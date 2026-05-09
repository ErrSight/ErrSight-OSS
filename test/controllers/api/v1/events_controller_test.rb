require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  VALID_KEY  = "elp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  PAUSED_KEY = "elp_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  def post_event(payload, api_key: VALID_KEY, headers: {})
    post api_v1_events_path,
         params: payload.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "X-API-Key" => api_key }.merge(headers)
  end

  # ── Authentication ────────────────────────────────────────────────────────────

  test "missing API key returns 401" do
    post api_v1_events_path,
         params: { message: "test", level: "error" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
    assert_equal "Invalid or missing API key", response.parsed_body["error"]
  end

  test "invalid API key returns 401" do
    post_event({ message: "test", level: "error" }, api_key: "elp_invalid")
    assert_response :unauthorized
  end

  test "Authorization Bearer header is accepted" do
    post api_v1_events_path,
         params: { message: "test", level: "error" }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "Authorization" => "Bearer #{VALID_KEY}"
         }
    assert_response :accepted
  end

  # ── Single event ─────────────────────────────────────────────────────────────

  test "POST /api/v1/events with valid payload returns 202 accepted" do
    post_event({ message: "Something failed", level: "error", environment: "production" })
    assert_response :accepted
    assert_equal "accepted", response.parsed_body["status"]
    assert_equal 1, response.parsed_body["queued"]
  end

  test "POST /api/v1/events enqueues ProcessEventJob" do
    assert_enqueued_with(job: ProcessEventJob) do
      post_event({ message: "test error", level: "error" })
    end
  end

  test "level defaults to info when unknown level given" do
    assert_enqueued_jobs 1 do
      post_event({ message: "test", level: "verbose" })
    end
  end

  test "environment defaults to production when blank" do
    assert_enqueued_jobs 1 do
      post_event({ message: "test", level: "info" })
    end
    assert_response :accepted
  end

  test "timestamp field is accepted as occurred_at" do
    ts = 5.minutes.ago.iso8601
    post_event({ message: "test", level: "debug", timestamp: ts })
    assert_response :accepted
  end

  # ── Batch ────────────────────────────────────────────────────────────────────

  test "POST /api/v1/events with array payload queues all events" do
    batch = 3.times.map { |i| { message: "Error #{i}", level: "error" } }
    post_event(batch)
    assert_response :accepted
    assert_equal 3, response.parsed_body["queued"]
    assert_enqueued_jobs 1, only: ProcessEventJob
  end

  test "batched ProcessEventJob carries an array of all events in the request" do
    batch = 3.times.map { |i| { message: "Error #{i}", level: "error" } }
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) { args[1].is_a?(Array) && args[1].length == 3 }
    ) do
      post_event(batch)
    end
  end

  test "batch exceeding MAX_BATCH_SIZE returns 422" do
    batch = 101.times.map { { message: "x", level: "info" } }
    post_event(batch)
    assert_response :unprocessable_entity
    assert_match "Batch size exceeds", response.parsed_body["error"]
  end

  # ── Ingestion paused ──────────────────────────────────────────────────────────

  test "returns 429 with INGESTION_PAUSED when project is admin/manually paused" do
    post_event({ message: "test", level: "info" }, api_key: PAUSED_KEY)
    assert_response :too_many_requests
    assert_equal "INGESTION_PAUSED", response.parsed_body["code"]
    assert_match(/paused/i, response.parsed_body["error"])
  end

  # ── Rate limit ───────────────────────────────────────────────────────────────

  test "returns 429 and RATE_LIMIT_EXCEEDED when project rate limit is exceeded" do
    projects(:alpha).update!(rate_limit_per_minute: 2)
    IngestionRateLimiter.check!(projects(:alpha), count: 2)

    assert_no_enqueued_jobs only: ProcessEventJob do
      post_event({ message: "hit the ceiling", level: "error" })
    end

    assert_response :too_many_requests
    assert_equal "RATE_LIMIT_EXCEEDED", response.parsed_body["code"]
    assert response.headers["Retry-After"].to_i >= 1
    assert_equal "2", response.headers["X-RateLimit-Limit"]
  end

  test "zero rate_limit_per_minute disables rate limiting" do
    projects(:alpha).update!(rate_limit_per_minute: 0)
    200.times { IngestionRateLimiter.check!(projects(:alpha), count: 1) }
    post_event({ message: "still ok", level: "error" })
    assert_response :accepted
  end

  # ── Payload size ─────────────────────────────────────────────────────────────

  test "returns 413 when Content-Length exceeds the limit" do
    post api_v1_events_path,
         params: ("x" * 10).to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-API-Key" => VALID_KEY,
           "CONTENT_LENGTH" => (513 * 1024).to_s
         }
    assert_response :content_too_large
    assert_equal "PAYLOAD_TOO_LARGE", response.parsed_body["code"]
  end

  # Regression: chunked Transfer-Encoding (or any client that omits
  # Content-Length) must not be able to smuggle a >MAX_PAYLOAD_SIZE body
  # past the header guard. parse_payload reads MAX+1 bytes and rejects when
  # the body actually exceeds the cap.
  test "parse_payload rejects oversized body even when Content-Length is absent (chunked bypass)" do
    over = Api::V1::EventsController::MAX_PAYLOAD_SIZE + 1024
    raw  = "\"#{'x' * over}\""

    fake_request  = ActionDispatch::TestRequest.create("rack.input" => StringIO.new(raw))
    fake_request.env.delete("CONTENT_LENGTH")
    fake_response = ActionDispatch::TestResponse.create

    controller = Api::V1::EventsController.new
    controller.set_request!(fake_request)
    controller.set_response!(fake_response)

    assert_nil controller.send(:parse_payload)
    assert_equal 413, fake_response.status
    assert_equal "PAYLOAD_TOO_LARGE", JSON.parse(fake_response.body)["code"]
  end

  # ── Invalid JSON ──────────────────────────────────────────────────────────────

  test "invalid JSON returns 400" do
    post api_v1_events_path,
         params: '{"message":"boom","api_key":"should-not-echo",',
         headers: { "CONTENT_TYPE" => "application/json", "X-API-Key" => VALID_KEY }
    assert_response :bad_request
    assert_equal "Invalid JSON payload", response.parsed_body["error"]
    assert_equal "INVALID_JSON", response.parsed_body["code"]
    refute_includes response.body, "should-not-echo"
  end

  # ── Custom fingerprint override ──────────────────────────────────────────────

  test "custom string fingerprint is hashed and passed through to the job" do
    expected = Digest::SHA256.hexdigest("custom-group-key")[0, 32]
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) { args[1].first["fingerprint"] == expected }
    ) do
      post_event({ message: "a", level: "error", fingerprint: "custom-group-key" })
    end
  end

  test "array fingerprint is joined and hashed" do
    expected = Digest::SHA256.hexdigest("UserError|login")[0, 32]
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) { args[1].first["fingerprint"] == expected }
    ) do
      post_event({ message: "a", level: "error", fingerprint: [ "UserError", "login" ] })
    end
  end

  test "blank fingerprint falls back to server-side computed fingerprint" do
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) { args[1].first["fingerprint"].nil? }
    ) do
      post_event({ message: "a", level: "error", fingerprint: "" })
    end
  end

  # ── Enrichment fields ────────────────────────────────────────────────────────

  test "user context is flattened to user_identifier for aggregation" do
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) {
        args[1].first["user_context"] == { "id" => "42", "email" => "u@example.com", "username" => "alice" } &&
        args[1].first["user_identifier"] == "42"
      }
    ) do
      post_event({
        message: "a", level: "error",
        user: { id: 42, email: "u@example.com", username: "alice" }
      })
    end
  end

  test "release, breadcrumbs, and tags are passed through" do
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) {
        args[1].first["release"] == "v1.2.3" &&
        args[1].first["tags"] == { "component" => "auth", "region" => "us-east" } &&
        args[1].first["breadcrumbs"].size == 2
      }
    ) do
      post_event({
        message: "a", level: "error",
        release: "v1.2.3",
        tags: { component: "auth", region: "us-east" },
        breadcrumbs: [
          { category: "nav", message: "user clicked login" },
          { category: "http", message: "GET /me 401" }
        ]
      })
    end
  end

  test "breadcrumbs over 50 are truncated" do
    crumbs = 60.times.map { |i| { category: "c", message: "m#{i}" } }
    assert_enqueued_with(
      job: ProcessEventJob,
      args: ->(args) { args[1].first["breadcrumbs"].size == 50 }
    ) do
      post_event({ message: "a", level: "error", breadcrumbs: crumbs })
    end
  end
end

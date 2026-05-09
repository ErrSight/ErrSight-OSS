require "test_helper"

class Api::V1::EventsReadControllerTest < ActionDispatch::IntegrationTest
  WRITE_KEY = "elp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  setup do
    @project  = projects(:alpha)
    @read_key = @project.api_keys.create!(name: "Read", scope: :read).token
  end

  def headers(token)
    { "X-API-Key" => token }
  end

  test "GET /api/v1/events with read key returns list of kept events" do
    get api_v1_events_path, headers: headers(@read_key)
    assert_response :ok
    data = response.parsed_body["data"]
    assert data.is_a?(Array)
    assert data.any? { |e| e["fingerprint"] == "abc123abc123abc1" }
    assert data.none? { |e| e["fingerprint"] == "jkl012jkl012jkl0" }, "discarded events must not appear"
  end

  test "GET /api/v1/events with write key is forbidden" do
    get api_v1_events_path, headers: headers(WRITE_KEY)
    assert_response :forbidden
    assert_match "lacks required scope", response.parsed_body["error"]
  end

  test "GET /api/v1/events without any key returns 401" do
    get api_v1_events_path
    assert_response :unauthorized
  end

  test "POST /api/v1/events with read-scoped key returns 403" do
    post api_v1_events_path,
         params: { message: "x", level: "error" }.to_json,
         headers: headers(@read_key).merge("CONTENT_TYPE" => "application/json")
    assert_response :forbidden
    assert_match "lacks required scope", response.parsed_body["error"]
  end

  test "GET /api/v1/events filters by fingerprint" do
    get api_v1_events_path, params: { fingerprint: "abc123abc123abc1" }, headers: headers(@read_key)
    data = response.parsed_body["data"]
    assert data.all? { |e| e["fingerprint"] == "abc123abc123abc1" }
  end

  test "GET /api/v1/events/:id returns full event detail" do
    event = events(:error_event)
    get api_v1_event_path(event), headers: headers(@read_key)
    assert_response :ok
    detail = response.parsed_body["data"]
    assert_equal event.id, detail["id"]
    assert detail.key?("backtrace")
    assert detail.key?("metadata")
  end

  test "GET /api/v1/events/:id 404s for discarded events" do
    discarded = events(:discarded_event)
    get api_v1_event_path(discarded), headers: headers(@read_key)
    assert_response :not_found
  end

  test "GET /api/v1/issues/:fingerprint returns aggregate issue data" do
    get api_v1_issue_path(fingerprint: "abc123abc123abc1"), headers: headers(@read_key)
    assert_response :ok
    data = response.parsed_body["data"]
    assert_equal "abc123abc123abc1", data["fingerprint"]
    assert data["occurrences"] >= 1
  end

  test "GET /api/v1/issues/:fingerprint returns 404 for unknown fingerprint" do
    get api_v1_issue_path(fingerprint: "doesnotexist"), headers: headers(@read_key)
    assert_response :not_found
  end

  test "revoked key is rejected" do
    ApiKey.find_by(token: @read_key).revoke!
    get api_v1_events_path, headers: headers(@read_key)
    assert_response :unauthorized
  end

  test "last_used_at is updated on successful auth" do
    key = ApiKey.find_by(token: @read_key)
    assert_nil key.last_used_at
    get api_v1_events_path, headers: headers(@read_key)
    assert_not_nil key.reload.last_used_at
  end
end

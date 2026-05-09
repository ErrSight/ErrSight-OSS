require "test_helper"

class SendWebhookAlertJobTest < ActiveJob::TestCase
  include StubHelper

  setup do
    @event    = events(:error_event)
    @project  = @event.project
    @endpoint = @project.webhook_endpoints.create!(url: "https://example.com/hook")
  end

  test "does nothing when no endpoints exist" do
    @endpoint.destroy
    captured = capture_http do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_empty captured
  end

  # Mute-rule coverage is now exercised in ProcessEventJobTest — the mute
  # check was lifted into ingestion so this job no longer queries MuteRule.

  test "sends HMAC-signed POST to active endpoint" do
    captured = capture_http(success: true) do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_equal 1, captured.length
    request = captured.first
    assert_match(/\Asha256=[a-f0-9]{64}\z/, request[:signature])
    assert request[:timestamp].present?

    expected = OpenSSL::HMAC.hexdigest("SHA256", @endpoint.secret, "#{request[:timestamp]}.#{request[:body]}")
    assert_equal "sha256=#{expected}", request[:signature]
  end

  test "records last_delivered_at on success" do
    capture_http(success: true) do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert @endpoint.reload.last_delivered_at.present?
    assert_equal 0, @endpoint.failure_count
  end

  test "increments failure_count on non-2xx response" do
    capture_http(success: false) do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_equal 1, @endpoint.reload.failure_count
  end

  test "disables endpoint after repeated failures" do
    @endpoint.update_columns(failure_count: SendWebhookAlertJob::MAX_FAILURES_BEFORE_DISABLE - 1)
    capture_http(success: false) do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_not @endpoint.reload.active?
  end

  test "skips delivery when alert rules exist but none match" do
    @project.alert_rules.create!(
      name: "fatals only", rule_type: :every_event,
      level_threshold: Event.levels[:fatal], count_threshold: 1, window_seconds: 3600
    )
    captured = capture_http do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_empty captured
  end

  test "regression still respects alert rules" do
    @project.alert_rules.create!(
      name: "fatals only", rule_type: :every_event,
      level_threshold: Event.levels[:fatal], count_threshold: 1, window_seconds: 3600
    )
    @event.update!(is_regression: true)
    captured = capture_http do
      SendWebhookAlertJob.perform_now(@event.id)
    end
    assert_empty captured
  end

  test "logs only endpoint host on delivery failure" do
    @endpoint.update!(url: "https://example.com/hook?token=super-secret")

    factory = ->(*_args) do
      http = Object.new
      http.define_singleton_method(:use_ssl=)      { |_| }
      http.define_singleton_method(:open_timeout=) { |_| }
      http.define_singleton_method(:read_timeout=) { |_| }
      http.define_singleton_method(:ipaddr=)       { |_| }
      http.define_singleton_method(:request) { |_req| raise Net::ReadTimeout }
      http
    end

    logs = capture_logs do
      stub_method(Net::HTTP, :new, factory) do
        SendWebhookAlertJob.perform_now(@event.id)
      end
    end

    assert_includes logs, "host=example.com"
    refute_includes logs, "super-secret"
    refute_includes logs, "/hook?token=super-secret"
  end

  private

  class FakeResponse
    attr_reader :code, :body
    def initialize(success)
      @success = success
      @code    = success ? "200" : "500"
      @body    = ""
    end

    def is_a?(klass)
      return @success if klass == Net::HTTPSuccess
      super
    end
  end

  # Stubs Net::HTTP.new so each invocation returns a fresh fake that captures
  # the outgoing request. Uses stub_method (singleton scoped) instead of the
  # prior class_eval monkey-patch — avoids corrupting Net::HTTP#request if the
  # test suite is ever run with thread-parallelism instead of process-parallelism.
  def capture_http(success: true)
    captured = []
    fake_response = FakeResponse.new(success)

    factory = ->(*_args) do
      http = Object.new
      http.define_singleton_method(:use_ssl=)      { |_| }
      http.define_singleton_method(:open_timeout=) { |_| }
      http.define_singleton_method(:read_timeout=) { |_| }
      http.define_singleton_method(:ipaddr=)       { |_| }
      http.define_singleton_method(:request) do |req|
        captured << {
          body:      req.body,
          signature: req["X-ErrSight-Signature"],
          timestamp: req["X-ErrSight-Timestamp"]
        }
        fake_response
      end
      http
    end

    stub_method(Net::HTTP, :new, factory) { yield }
    captured
  end

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = Logger::INFO
    Rails.logger = ActiveSupport::TaggedLogging.new(logger)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end

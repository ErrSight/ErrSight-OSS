require "test_helper"

class SlackNotifierTest < ActiveSupport::TestCase
  include StubHelper

  # The rejection tests never stub HTTP — they rely on the allowlist short-circuit
  # returning false before any socket is opened. If the allowlist is removed in a
  # future refactor, these tests will either hang or raise a real network error,
  # which is itself the failure signal.

  test "returns false and logs when webhook_url is blank" do
    assert_equal false, SlackNotifier.post(nil, { text: "x" })
    assert_equal false, SlackNotifier.post("", { text: "x" })
  end

  test "refuses CNAME bypass (hooks.slack.com.attacker.com)" do
    result = SlackNotifier.post("https://hooks.slack.com.attacker.com/services/X", { text: "x" })
    assert_equal false, result
  end

  test "refuses subdomain prefix bypass (attacker.hooks.slack.com)" do
    result = SlackNotifier.post("https://attacker.hooks.slack.com/services/X", { text: "x" })
    assert_equal false, result
  end

  test "refuses literal private IP" do
    result = SlackNotifier.post("https://169.254.169.254/latest/meta-data/", { text: "x" })
    assert_equal false, result
  end

  test "refuses http (non-TLS) even to hooks.slack.com" do
    result = SlackNotifier.post("http://hooks.slack.com/services/X", { text: "x" })
    assert_equal false, result
  end

  test "refuses malformed URL" do
    result = SlackNotifier.post("not a url", { text: "x" })
    assert_equal false, result
  end

  test "refuses host with embedded credentials pointing elsewhere" do
    result = SlackNotifier.post("https://hooks.slack.com@attacker.com/x", { text: "x" })
    assert_equal false, result
  end

  test "accepts valid hooks.slack.com URL and issues POST" do
    captured = nil
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:request) do |req|
      captured = { path: req.path, body: req.body, content_type: req["Content-Type"] }
      fake_success = Object.new
      fake_success.define_singleton_method(:is_a?) { |k| k == Net::HTTPSuccess }
      fake_success.define_singleton_method(:code) { "200" }
      fake_success.define_singleton_method(:body) { "ok" }
      fake_success
    end

    stub_method(Net::HTTP, :new, fake_http) do
      result = SlackNotifier.post("https://hooks.slack.com/services/T000/B000/XYZ", { text: "hello" })
      assert_equal true, result
    end

    assert_equal "/services/T000/B000/XYZ", captured[:path]
    assert_equal "application/json", captured[:content_type]
    assert_equal({ "text" => "hello" }, JSON.parse(captured[:body]))
  end

  test "accepts uppercase host (case-insensitive match)" do
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:request) do |_req|
      fake_success = Object.new
      fake_success.define_singleton_method(:is_a?) { |k| k == Net::HTTPSuccess }
      fake_success.define_singleton_method(:code) { "200" }
      fake_success.define_singleton_method(:body) { "ok" }
      fake_success
    end

    stub_method(Net::HTTP, :new, fake_http) do
      result = SlackNotifier.post("https://Hooks.Slack.COM/services/T/B/X", { text: "hi" })
      assert_equal true, result
    end
  end

  test "does not log the secret webhook path" do
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:request) do |_req|
      fake_success = Object.new
      fake_success.define_singleton_method(:is_a?) { |k| k == Net::HTTPSuccess }
      fake_success.define_singleton_method(:code) { "200" }
      fake_success.define_singleton_method(:body) { "ok" }
      fake_success
    end

    logs = capture_logs do
      stub_method(Net::HTTP, :new, fake_http) do
        SlackNotifier.post("https://hooks.slack.com/services/T000/B000/VERYSECRET", { text: "hello" })
      end
    end

    assert_includes logs, "host=hooks.slack.com"
    refute_includes logs, "/services/T000/B000/VERYSECRET"
    refute_includes logs, "VERYSECRET"
  end

  private

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

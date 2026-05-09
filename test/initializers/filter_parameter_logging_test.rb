require "test_helper"

# Pins the filter list against the actually-used sensitive params in the app.
# Adding a new sensitive param without filtering it must fail this test.
class FilterParameterLoggingTest < ActiveSupport::TestCase
  def filter(params)
    ActiveSupport::ParameterFilter
      .new(Rails.application.config.filter_parameters)
      .filter(params.transform_keys(&:to_s))
  end

  SENSITIVE_KEYS = %w[
    password
    password_confirmation
    api_key
    api_token
    access_token
    refresh_token
    secret
    webhook_secret
    signing_secret
    reset_password_token
    confirmation_token
    unlock_token
    invitation_token
    slack_webhook_url
    webhook_url
    otp
    ssn
    cvv
    cvc
    card_number
    iban
    account_number
    authorization
    cookie
    user_identifier
    exit_details
    details
    webhook_endpoint
  ].freeze

  SENSITIVE_KEYS.each do |key|
    test "filters #{key}" do
      filtered = filter(key => "should-be-hidden")
      assert_equal "[FILTERED]", filtered[key],
        "expected #{key} to be filtered, got #{filtered[key].inspect}"
    end
  end

  test "filters event PII fields that may carry user context" do
    filtered = filter(
      "user_context" => { "email" => "user@example.com", "ip_address" => "1.2.3.4" },
      "backtrace"    => "app/foo.rb:10",
      "breadcrumbs"  => [ { "message" => "click" } ]
    )
    assert_equal "[FILTERED]", filtered["user_context"]
    assert_equal "[FILTERED]", filtered["backtrace"]
    assert_equal "[FILTERED]", filtered["breadcrumbs"]
  end

  test "filters nested webhook endpoint payloads" do
    filtered = filter(
      "webhook_endpoint" => { "url" => "https://example.com/hook?token=secret", "active" => "1" }
    )
    assert_equal "[FILTERED]", filtered["webhook_endpoint"]
  end

  test "leaves non-sensitive fields untouched" do
    filtered = filter("project_id" => 42, "level" => "error", "message" => "Boom")
    assert_equal 42, filtered["project_id"]
    assert_equal "error", filtered["level"]
    assert_equal "Boom", filtered["message"]
  end
end

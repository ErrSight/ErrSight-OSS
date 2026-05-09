require "test_helper"

class LogrageTest < ActiveSupport::TestCase
  EventStub = Struct.new(:payload)

  def custom_options_for(payload)
    Rails.application.config.lograge.custom_options.call(EventStub.new(payload))
  end

  test "omits params for ingestion requests" do
    options = custom_options_for(
      controller: "Api::V1::EventsController",
      action: "create",
      request_id: "req-1",
      filtered_parameters: {
        "controller" => "api/v1/events",
        "action" => "create",
        "message" => "customer secret",
        "metadata" => { "token" => "abc123" }
      }
    )

    refute options.key?(:params)
    assert_equal "req-1", options[:request_id]
  end

  test "keeps filtered params for non-sensitive actions" do
    options = custom_options_for(
      controller: "ProjectsController",
      action: "show",
      filtered_parameters: {
        "controller" => "projects",
        "action" => "show",
        "id" => "42",
        "password" => "[FILTERED]"
      }
    )

    assert_equal({ "id" => "42", "password" => "[FILTERED]" }, options[:params])
  end
end

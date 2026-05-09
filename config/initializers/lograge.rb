Rails.application.configure do
  sensitive_param_actions = {
    "Api::V1::EventsController" => %w[create],
    "Webhooks::DodoController" => %w[create]
  }.freeze

  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_options = lambda do |event|
    payload = event.payload
    filtered_params = payload[:filtered_parameters]&.except("controller", "action", "format", "_method")
    if sensitive_param_actions.fetch(payload[:controller].to_s, []).include?(payload[:action].to_s)
      filtered_params = nil
    end

    {
      user_id: payload[:user_id],
      request_id: payload[:request_id],
      params: filtered_params.presence
    }.compact
  end

  config.lograge.ignore_actions = [ "RailsHealthController#show" ]
end

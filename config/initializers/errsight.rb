# Self-instrumentation. The community-edition app can forward its own errors
# and log lines to either this same instance (point ERRSIGHT_HOST at the host
# you serve from) or any upstream ErrSight. Leave ERRSIGHT_API_KEY unset to
# disable.
if ENV["ERRSIGHT_API_KEY"].present?
  Errsight.configure do |config|
    config.api_key     = ENV["ERRSIGHT_API_KEY"]
    config.environment = Rails.env
    config.min_level   = :error
    config.host        = ENV["ERRSIGHT_HOST"] if ENV["ERRSIGHT_HOST"].present?
  end
else
  Errsight.configure { |config| config.enabled = false } if defined?(Errsight)
end

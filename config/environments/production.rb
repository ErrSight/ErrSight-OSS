require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Container filesystems are typically ephemeral — any local-disk upload is lost on deploy
  # or container restart. No upload feature exists today, but ACTIVE_STORAGE_SERVICE
  # should be flipped to :amazon / :gcs (configured in config/storage.yml) before
  # the first attachment ships. Default stays :local so dev/CI parity isn't broken.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue

  # Database-backed Rails.cache shared across Puma workers and app replicas.
  # Without this, every Rails.cache.write(..., unless_exist: true) used for alert
  # debouncing and cleanup gating is per-worker — so the moment
  # WEB_CONCURRENCY > 1, each worker thinks it's "first" and recipients
  # get duplicate alerts. Settings live in config/cache.yml.
  config.cache_store = :solid_cache_store

  # Email delivery via SMTP. Settings are pulled from env so any provider works
  # — Mailgun, SendGrid, Amazon SES, Postmark, your own Postfix relay. With
  # SMTP_ADDRESS unset, delivery will fail at send time; if your install
  # doesn't need email at all, remove :confirmable from app/models/user.rb
  # so users can register without email verification.
  #
  # raise_delivery_errors = true so an SMTP 5xx surfaces as a job failure —
  # visible in SolidQueue and retried via each mailer job's own retry_on
  # budget. False would silently swallow errors and lose alerts invisibly.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address:              ENV["SMTP_ADDRESS"],
    port:                 ENV.fetch("SMTP_PORT", 587).to_i,
    domain:               ENV["SMTP_DOMAIN"].presence,
    user_name:            ENV["SMTP_USERNAME"].presence,
    password:             ENV["SMTP_PASSWORD"].presence,
    authentication:       :plain,
    enable_starttls_auto: true
  }.compact
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    protocol: "https"
  }

  # Absolute asset URLs so image_tag in mailer templates renders the logo.
  config.action_mailer.asset_host = "https://#{ENV.fetch("APP_HOST", "localhost")}"

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Regex is fully anchored — Rails matches hosts with Regexp#match?, which is
  # unanchored, so `/.*\.errsight\.com/` would also match `foo.errsight.com.attacker.tld`.
  config.hosts = [
    ENV.fetch("APP_HOST", "errsight.com"),
    /\A(?:.+\.)?errsight\.com\z/
  ]

  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

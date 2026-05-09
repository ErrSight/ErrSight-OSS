# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }
  config.action_mailer.asset_host = "http://example.com"

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Use inline adapter so ActiveJob jobs run synchronously in tests
  config.active_job.queue_adapter = :test
end

# Cloudflare Turnstile is force-disabled in the test environment regardless of
# whatever keys may bleed in from a local .env, so registration tests don't
# need to mint real challenge tokens. Tests that want to exercise the gate
# stub CloudflareTurnstile.enabled?/verify directly.
ENV.delete("CLOUDFLARE_TURNSTILE_SITE_KEY")
ENV.delete("CLOUDFLARE_TURNSTILE_SECRET_KEY")

# config/initializers/devise.rb registers the Google/GitHub OmniAuth
# strategies only when their CLIENT_ID/CLIENT_SECRET env vars are present, and
# the sign-in/sign-up views gate the provider buttons on the same vars. The
# system tests in test/system/oauth_sign_in_test.rb drive the real OmniAuth
# request phase (clicking "Continue with Google/GitHub"), which requires the
# strategies to be mounted in the Rack middleware. Supply dummy credentials so
# the providers register in test. This file is loaded before the initializers,
# and `||=` preserves any real values a developer set locally. OmniAuth's
# test_mode short-circuits the request phase before any network call, so these
# placeholder secrets are never sent anywhere.
ENV["GOOGLE_CLIENT_ID"]     ||= "test-google-client-id"
ENV["GOOGLE_CLIENT_SECRET"] ||= "test-google-client-secret"
ENV["GITHUB_CLIENT_ID"]     ||= "test-github-client-id"
ENV["GITHUB_CLIENT_SECRET"] ||= "test-github-client-secret"

# Bullet in tests: opt-in via BULLET=true. Off by default so the suite stays
# quiet for everyday runs; turn on locally or in a dedicated CI step to scan
# for new N+1 regressions.
if ENV["BULLET"]
  Rails.application.config.after_initialize do
    Bullet.enable        = true
    Bullet.bullet_logger = true
    Bullet.raise         = true

    # Counter-cache hints (`.size` triggers a COUNT) are noisier than they're
    # worth pre-launch — they're at most 1 extra COUNT per request, not an
    # N+1 fan-out. We focus Bullet on real eager-loading misses for now.
    Bullet.counter_cache_enable = false
  end
end

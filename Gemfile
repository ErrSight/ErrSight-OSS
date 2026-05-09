source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Authentication. Google + GitHub OAuth providers are auto-disabled when their
# *_CLIENT_ID/*_CLIENT_SECRET env vars are blank — self-host operators who only
# want email/password can leave those vars unset.
gem "devise"
gem "omniauth-google-oauth2"
gem "omniauth-github"
gem "omniauth-rails_csrf_protection"

# Authorization
gem "pundit"

# Admin panel
gem "activeadmin"
gem "ransack"

# Web UI for Solid Queue (pending/scheduled/failed/finished jobs, retry, discard).
# Mounted at /jobs behind the existing authenticate_admin! guard. Job arguments
# are visible here, including event payloads with PII — keep admin-only.
gem "mission_control-jobs"

# Pagination
gem "pagy", "~> 9.0"

# Rate limiting
gem "rack-attack"

# CORS — allow browser-based JS/React SDKs to POST to the ingestion API
gem "rack-cors"

# Fast JSON parsing
gem "oj"

# Structured logging
gem "lograge"

# Soft delete
gem "discard"

# CSS framework
gem "tailwindcss-rails"

# Compile active_admin.scss → active_admin.css for Propshaft
gem "dartsass-rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapter for Active Job
gem "solid_queue"

# Database-backed Action Cable adapter (production)
gem "solid_cable"

# Database-backed Rails.cache (shared across Puma workers and replicas).
# In-process MemoryStore would silently fail dedup primitives (alert debounce,
# cleanup gating) the moment we scale beyond WEB_CONCURRENCY=1 — each worker
# would think it's "first" within its own process. solid_cache backs cache
# writes with a Postgres table, so write(..., unless_exist: true) is atomic
# across the whole cluster.
gem "solid_cache"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Self-instrumentation — the OSS build can monitor its own errors and
# log lines by configuring `config.host` to point at this instance (or any
# upstream ErrSight). See config/initializers/errsight.rb.
gem "errsight", "~> 0.2.2"

group :development, :test do
  # Loads .env into ENV for all rails commands (console, dbconsole, db:migrate, etc.)
  gem "dotenv-rails"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # N+1 query detection — runs as Rack middleware in development and as a
  # listener in tests; misuses surface in the Rails log and (in dev) as a
  # browser footer notification.
  gem "bullet"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview outgoing mail in the browser instead of sending it
  gem "letter_opener"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Code coverage reporting — opt-in via COVERAGE=true so it doesn't slow
  # the default `bin/rails test` loop.
  gem "simplecov", require: false
end

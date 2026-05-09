# Logs a warning at boot if the events table is not a TimescaleDB hypertable
# with a compression policy. Silent compression drift is hard to notice —
# this surfaces it as a boot-time log line visible in Railway/stdout.
#
# Runs only in production. Failures are swallowed so transient DB issues
# during boot cannot crash the app.

Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next if ENV["SKIP_TIMESCALE_CHECK"].present?
  next if defined?(Rails::Console) || $PROGRAM_NAME.end_with?("rake")

  begin
    connection = ActiveRecord::Base.connection

    hypertable_active = connection.select_value(<<~SQL).present?
      SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'
    SQL

    unless hypertable_active
      Rails.logger.error("[TimescaleDB] extension is NOT installed — events is a plain Postgres table. Time-series performance and compression are disabled.")
      next
    end

    is_hypertable = connection.select_value(<<~SQL).present?
      SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'events'
    SQL

    unless is_hypertable
      Rails.logger.error("[TimescaleDB] events table is NOT a hypertable — run the TimescaleDB migration on this database.")
      next
    end

    has_compression_policy = connection.select_value(<<~SQL).present?
      SELECT 1
      FROM timescaledb_information.jobs
      WHERE proc_name = 'policy_compression'
        AND hypertable_name = 'events'
    SQL

    unless has_compression_policy
      Rails.logger.warn("[TimescaleDB] events hypertable has no compression policy — storage may grow unchecked.")
      next
    end

    Rails.logger.info("[TimescaleDB] events hypertable and compression policy are active.")
  rescue StandardError => e
    Rails.logger.warn("[TimescaleDB] health check failed error=#{e.class}")
  end
end

# Idempotently converges the `events` table to its intended TimescaleDB shape:
# a hypertable partitioned on occurred_at, columnar compression, and a 7-day
# compression policy. Mirrors the SQL documented in the README's TimescaleDB
# section and in lib/tasks/timescale.rake.
#
# Why this exists: Rails' default :ruby schema format (db/schema.rb) cannot
# represent create_hypertable / compression DDL. So on a FRESH database
# `db:prepare` takes the schema-LOAD path, which leaves `events` a plain table
# with no hypertable and no compression. Run `bin/rails timescale:ensure_hypertable`
# (or call TimescaleHypertable.ensure!) to converge the table, whether the DB
# came up via schema load or via migrations.
#
# Safe to run on every boot:
#   * no-ops when timescaledb is absent (CI / local plain Postgres),
#   * no-ops when `events` is already a hypertable with compression set up,
#   * never raises — a degraded database must not crash the web container.
# config/initializers/timescaledb_health_check.rb logs the resulting state.
class TimescaleHypertable
  HYPERTABLE = "events".freeze
  COMPRESSION_INTERVAL = "7 days".freeze

  class << self
    # Returns one of:
    #   :extension_unavailable  timescaledb is not (and cannot be) installed
    #   :configured             ran some DDL to reach the desired state
    #   :already_configured     nothing to do, already correct
    #   :error                  something raised; logged and swallowed
    def ensure!
      return :extension_unavailable unless ensure_extension!

      did_work = false

      unless hypertable?
        create_hypertable!
        did_work = true
      end

      if tsl_licensed?
        unless compression_configured?
          enable_compression!
          did_work = true
        end
        unless compression_policy?
          add_compression_policy!
          did_work = true
        end
      else
        Rails.logger.warn(
          "[TimescaleHypertable] TimescaleDB is Apache-licensed; compression is a " \
          "Community/TSL feature. events is a hypertable but will not be compressed."
        )
      end

      state = did_work ? :configured : :already_configured
      Rails.logger.info("[TimescaleHypertable] events #{state}")
      state
    rescue StandardError => e
      Rails.logger.error("[TimescaleHypertable] ensure failed error=#{e.class}: #{e.message}")
      :error
    end

    def installed?
      connection.select_value(
        "SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'"
      ).present?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def available?
      connection.select_value(
        "SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb'"
      ).present?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def hypertable?
      connection.select_value(<<~SQL.squish).present?
        SELECT 1 FROM timescaledb_information.hypertables
        WHERE hypertable_name = '#{HYPERTABLE}'
      SQL
    rescue ActiveRecord::StatementInvalid
      false
    end

    def compression_configured?
      connection.select_value(<<~SQL.squish).present?
        SELECT 1 FROM timescaledb_information.compression_settings
        WHERE hypertable_name = '#{HYPERTABLE}'
      SQL
    rescue ActiveRecord::StatementInvalid
      false
    end

    def compression_policy?
      connection.select_value(<<~SQL.squish).present?
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression' AND hypertable_name = '#{HYPERTABLE}'
      SQL
    rescue ActiveRecord::StatementInvalid
      false
    end

    def tsl_licensed?
      return false unless installed?

      license = connection.select_value("SHOW timescaledb.license").to_s
      license == "timescale" || license == "timescale-community"
    rescue StandardError
      false
    end

    private

    # Returns true if timescaledb is installed (enabling it first if the build
    # offers it). Returns false on plain Postgres, where the whole ensure! no-ops.
    def ensure_extension!
      return true if installed?
      return false unless available?

      connection.execute("CREATE EXTENSION IF NOT EXISTS timescaledb")
      installed?
    end

    def create_hypertable!
      connection.execute(<<~SQL.squish)
        SELECT create_hypertable('#{HYPERTABLE}', 'occurred_at',
          if_not_exists => TRUE,
          migrate_data  => TRUE)
      SQL
    end

    def enable_compression!
      connection.execute(<<~SQL.squish)
        ALTER TABLE #{HYPERTABLE} SET (
          timescaledb.compress,
          timescaledb.compress_segmentby = 'project_id',
          timescaledb.compress_orderby   = 'occurred_at DESC, id'
        )
      SQL
    end

    def add_compression_policy!
      connection.execute(
        "SELECT add_compression_policy('#{HYPERTABLE}', INTERVAL '#{COMPRESSION_INTERVAL}')"
      )
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end

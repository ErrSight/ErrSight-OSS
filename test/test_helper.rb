ENV["RAILS_ENV"] ||= "test"

# SimpleCov must be required BEFORE the app loads or coverage misses any
# file Rails autoloads at boot. Opt-in via COVERAGE=true so the default
# `bin/rails test` loop stays fast.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter %w[/test/ /config/ /db/ /vendor/ /bin/]
    # Each Minitest worker is a forked process; tag results so SimpleCov merges
    # them into a single report at the end of the suite.
    command_name "Minitest:#{$$}"
    # No-backsliding gate. Baseline at the time of introduction was ~74% line /
    # 65% branch — these floors leave a few points of headroom but make a real
    # drop in coverage fail the build.
    minimum_coverage line: 70, branch: 60
  end
end

require_relative "../config/environment"
require "rails/test_help"

# TimescaleDB hypertables with columnstore enabled reject
# `ALTER TABLE ... DISABLE TRIGGER ALL` and `ALTER TABLE ... VALIDATE CONSTRAINT`,
# which Rails uses during fixture loading. Replace:
#   1. disable_referential_integrity    → SET session_replication_role = replica
#   2. check_all_foreign_keys_valid!    → skip FK constraints on hypertables
# Both require superuser — the `postgres` container default satisfies that.
module TimescaleFixtureIntegrity
  def disable_referential_integrity
    previous = select_value("SHOW session_replication_role")
    execute("SET session_replication_role = 'replica'")
    yield
  ensure
    execute("SET session_replication_role = #{quote(previous || 'origin')}")
  end

  def check_all_foreign_keys_valid!
    hypertables = begin
      select_values("SELECT hypertable_name FROM timescaledb_information.hypertables")
    rescue ActiveRecord::StatementInvalid
      []
    end

    skip_list = hypertables.map { |t| quote(t) }.join(",")
    hypertable_filter = skip_list.empty? ? "" : "AND table_name NOT IN (#{skip_list})"

    sql = <<~SQL
      do $$
        declare r record;
      BEGIN
      FOR r IN (
        SELECT FORMAT(
          'UPDATE pg_catalog.pg_constraint SET convalidated=false WHERE conname = ''%1$I'' AND connamespace::regnamespace = ''%2$I''::regnamespace; ALTER TABLE %2$I.%3$I VALIDATE CONSTRAINT %1$I;',
          constraint_name,
          table_schema,
          table_name
        ) AS constraint_check
        FROM information_schema.table_constraints
        WHERE constraint_type = 'FOREIGN KEY'
          AND table_schema NOT IN ('_timescaledb_internal', '_timescaledb_catalog', '_timescaledb_config', '_timescaledb_cache')
          #{hypertable_filter}
      )
        LOOP
          EXECUTE (r.constraint_check);
        END LOOP;
      END;
      $$;
    SQL

    transaction(requires_new: true) { execute(sql) }
  end
end
ActiveRecord::ConnectionAdapters::PostgreSQL::ReferentialIntegrity.prepend(TimescaleFixtureIntegrity)

# Minitest 6 removed Object#stub. Provide a lightweight replacement.
module StubHelper
  # Temporarily replaces obj.method_name with a stub that returns return_value_or_proc.
  # If a Proc/lambda is given it is called with the original arguments.
  def stub_method(obj, method_name, return_value_or_proc, &block)
    original_method = obj.method(method_name) rescue nil
    obj.define_singleton_method(method_name) do |*args, **kwargs, &blk|
      return_value_or_proc.respond_to?(:call) ? return_value_or_proc.call(*args, **kwargs, &blk) : return_value_or_proc
    end
    block.call
  ensure
    obj.singleton_class.send(:undef_method, method_name) rescue nil
    obj.define_singleton_method(method_name, original_method) if original_method
  end
end

module TimescaleTestSupport
  module_function

  # Rails loads schema.rb for parallel worker DBs (and for a fresh `db:test:prepare`).
  # schema.rb only records `enable_extension "timescaledb"` — it does NOT re-run the
  # hypertable migration, so the events table in each worker DB is a plain table.
  # This restores the hypertable + compression setup so TimescaleStats-dependent
  # tests see the same structure they'd see in development/production.
  def ensure_events_hypertable!
    conn = ActiveRecord::Base.connection
    return unless conn.select_value("SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'")

    already = conn.select_value(
      "SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'events'"
    )
    return if already

    conn.execute <<~SQL.squish
      SELECT create_hypertable('events', 'occurred_at',
        if_not_exists => TRUE,
        migrate_data  => TRUE)
    SQL
    conn.execute <<~SQL.squish
      ALTER TABLE events SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'project_id',
        timescaledb.compress_orderby   = 'occurred_at DESC, id'
      )
    SQL
  end
end

module ActiveSupport
  class TestCase
    TimescaleTestSupport.ensure_events_hypertable!

    parallelize(workers: :number_of_processors)
    parallelize_setup do |worker|
      TimescaleTestSupport.ensure_events_hypertable!
      # Each parallel worker is a forked process; SimpleCov needs a unique
      # command_name per worker so its results get merged into one report.
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" if defined?(SimpleCov)
    end
    parallelize_teardown { |_worker| SimpleCov.result if defined?(SimpleCov) }

    fixtures :all

    setup do
      IngestionRateLimiter.reset!
      # Fixtures load via raw SQL and bypass the after_create_commit
      # callback that maintains issue aggregates. Run the rebuild here so
      # tests that exercise grouped_by_fingerprint or similar see the
      # right denormalized state. Idempotent and cheap on the small
      # fixture set; the work happens inside the per-test transaction
      # which rolls back, so we re-rebuild each test — acceptable
      # given the tiny dataset.
      Issue.rebuild_all_aggregates! if Event.exists?
    end
  end
end

# Devise helpers available in all integration tests
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end

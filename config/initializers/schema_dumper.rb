# Local dev runs a TimescaleDB-HA Docker image that auto-installs the
# `timescaledb_toolkit` extension on first connect. CI uses the plain
# `timescaledb:latest-pg17` image, which doesn't ship the toolkit. The app
# doesn't use it (see migration 20260505120000) — it only ends up in the
# DB because of the HA image's init scripts. Without this filter, every
# `db:migrate` that someone runs locally re-adds `enable_extension
# "timescaledb_toolkit"` to db/schema.rb, then breaks CI's
# `db:test:load_schema` with "extension is not available".
#
# Filter the extension out of the schema dump. Only affects what gets
# written to db/schema.rb; the runtime DB is untouched.
module ErrSight
  module SchemaDumperExtensionFilter
    EXCLUDED = %w[timescaledb_toolkit].freeze

    def extensions(stream)
      original = @connection.extensions
      @connection.define_singleton_method(:extensions) { original - EXCLUDED }
      super
    ensure
      @connection.singleton_class.send(:remove_method, :extensions)
    end
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  # The PG adapter has its own SchemaDumper subclass that overrides
  # `extensions` directly (does not call super) — prepending the
  # adapter-specific class is what actually intercepts the call.
  require "active_record/connection_adapters/postgresql/schema_dumper"
  ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(
    ErrSight::SchemaDumperExtensionFilter
  )
end

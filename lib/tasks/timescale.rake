namespace :timescale do
  desc "Print TimescaleDB hypertable + compression stats for events"
  task stats: :environment do
    stats = TimescaleStats.hypertable

    unless stats[:available]
      puts "TimescaleDB extension not available on this database."
      exit 1
    end

    puts "events hypertable"
    puts "-" * 60
    puts "Total chunks          : #{stats[:total_chunks]}"
    puts "Compressed chunks     : #{stats[:compressed_chunks]}"
    puts "Uncompressed (hot)    : #{stats[:uncompressed_chunks]}"
    puts "Size on disk          : #{format_bytes(stats[:total_bytes_on_disk])}"
    puts "Compressed-region raw : #{format_bytes(stats[:before_bytes])}"
    puts "Compressed-region on disk : #{format_bytes(stats[:after_bytes])}"
    puts "Storage saved         : #{format_bytes(stats[:bytes_saved])}"
    puts "Compression ratio     : #{stats[:ratio] ? "#{stats[:ratio]}x" : '—'}"
    puts
    puts "Per-chunk breakdown"
    puts "-" * 60

    rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
      SELECT chunk_name,
             range_start::date AS starts,
             range_end::date   AS ends,
             is_compressed,
             pg_total_relation_size(format('%I.%I', chunk_schema, chunk_name)::regclass) AS bytes
      FROM timescaledb_information.chunks
      WHERE hypertable_name = 'events'
      ORDER BY range_start
    SQL

    printf "%-28s %-12s %-12s %-12s %-10s\n", "chunk", "starts", "ends", "compressed", "size"
    rows.each do |r|
      printf "%-28s %-12s %-12s %-12s %-10s\n",
             r["chunk_name"],
             r["starts"],
             r["ends"],
             r["is_compressed"] ? "yes" : "no",
             format_bytes(r["bytes"].to_i)
    end
  end

  desc "Idempotently ensure events is a TimescaleDB hypertable with compression"
  task ensure_hypertable: :environment do
    # Converges the events table to its hypertable + compression shape. Needed
    # because db:prepare on a fresh DB loads db/schema.rb (which can't express
    # the hypertable) — and the squashed create_initial_schema leaves events a
    # plain table by design. Idempotent and safe on plain Postgres; see
    # app/services/timescale_hypertable.rb.
    result = TimescaleHypertable.ensure!
    puts "[timescale:ensure_hypertable] #{result}"
  end

  def format_bytes(n)
    ActionController::Base.helpers.number_to_human_size(n) || "0 B"
  end
end

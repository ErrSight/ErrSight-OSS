class TimescaleStats
  CACHE_TTL = 5.minutes
  HYPERTABLE = "events".freeze

  class << self
    def hypertable
      Rails.cache.fetch(cache_key(:hypertable), expires_in: CACHE_TTL) do
        fetch_hypertable
      end
    end

    def chunk_for(event)
      return nil unless installed?
      return nil if event.occurred_at.blank?

      Rails.cache.fetch(cache_key(:chunk, event.id), expires_in: CACHE_TTL) do
        fetch_chunk_for(event.occurred_at)
      end
    end

    def compressed?(event)
      chunk_for(event)&.dig(:is_compressed) == true
    end

    def installed?
      Rails.cache.fetch(cache_key(:installed), expires_in: CACHE_TTL) do
        connection.select_value(
          "SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'"
        ).present?
      end
    rescue ActiveRecord::StatementInvalid
      false
    end

    def clear_cache
      Rails.cache.delete_matched("#{cache_key_prefix}:*") if Rails.cache.respond_to?(:delete_matched)
    end

    private

    def fetch_hypertable
      return unavailable_stats unless installed?

      row = connection.select_one(<<~SQL.squish)
        SELECT
          (SELECT COUNT(*) FROM timescaledb_information.chunks
             WHERE hypertable_name = '#{HYPERTABLE}')                  AS total_chunks,
          (SELECT COUNT(*) FROM timescaledb_information.chunks
             WHERE hypertable_name = '#{HYPERTABLE}' AND is_compressed) AS compressed_chunks,
          hs.before_compression_total_bytes,
          hs.after_compression_total_bytes
        FROM hypertable_compression_stats('#{HYPERTABLE}') hs
      SQL

      return unavailable_stats if row.blank?

      before = row["before_compression_total_bytes"].to_i
      after  = row["after_compression_total_bytes"].to_i
      uncompressed = uncompressed_size

      {
        available:         true,
        total_chunks:      row["total_chunks"].to_i,
        compressed_chunks: row["compressed_chunks"].to_i,
        uncompressed_chunks: row["total_chunks"].to_i - row["compressed_chunks"].to_i,
        before_bytes:      before,
        after_bytes:       after,
        bytes_saved:       [ before - after, 0 ].max,
        ratio:             after.positive? ? (before.to_f / after).round(2) : nil,
        uncompressed_bytes: uncompressed,
        total_bytes_on_disk: after + uncompressed
      }
    rescue ActiveRecord::StatementInvalid
      unavailable_stats
    end

    def uncompressed_size
      connection.select_value(<<~SQL.squish).to_i
        SELECT COALESCE(SUM(pg_total_relation_size(format('%I.%I', chunk_schema, chunk_name)::regclass)), 0)
        FROM timescaledb_information.chunks
        WHERE hypertable_name = '#{HYPERTABLE}' AND NOT is_compressed
      SQL
    rescue ActiveRecord::StatementInvalid
      0
    end

    def fetch_chunk_for(occurred_at)
      row = connection.select_one(<<~SQL.squish, nil, [ occurred_at ])
        SELECT chunk_schema, chunk_name, range_start, range_end, is_compressed
        FROM timescaledb_information.chunks
        WHERE hypertable_name = '#{HYPERTABLE}'
          AND range_start <= $1
          AND range_end   >  $1
        LIMIT 1
      SQL
      return nil if row.blank?

      {
        chunk_schema:  row["chunk_schema"],
        chunk_name:    row["chunk_name"],
        full_name:     "#{row['chunk_schema']}.#{row['chunk_name']}",
        range_start:   row["range_start"],
        range_end:     row["range_end"],
        is_compressed: row["is_compressed"]
      }
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def unavailable_stats
      { available: false }
    end

    def connection
      ActiveRecord::Base.connection
    end

    def cache_key(*parts)
      [ cache_key_prefix, *parts ].join(":")
    end

    def cache_key_prefix
      "timescale_stats"
    end
  end
end

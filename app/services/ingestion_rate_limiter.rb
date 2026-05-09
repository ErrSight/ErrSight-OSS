class IngestionRateLimiter
  WINDOW = 60 # seconds (1-minute fixed window)

  class << self
    # Attempts to consume `count` tokens for the project's current minute window.
    # Returns a Result struct with :allowed, :remaining, :retry_after.
    # Shared across Puma workers and replicas via Postgres — a per-process cache
    # cannot enforce a real limit under multi-worker deployments.
    Result = Struct.new(:allowed, :limit, :count, :remaining, :retry_after, keyword_init: true)

    def check!(project, count: 1, now: Time.current)
      limit = project.rate_limit_per_minute.to_i
      return Result.new(allowed: true, limit: limit, count: 0, remaining: Float::INFINITY, retry_after: 0) if limit <= 0

      window_start = now.to_i - (now.to_i % WINDOW)
      key          = "project:#{project.id}"

      sql = <<~SQL.squish
        INSERT INTO rate_limit_windows (key, window_start, count, created_at, updated_at)
        SELECT $1::varchar, $2::bigint, $3::integer, NOW(), NOW()
        WHERE $3::integer <= $4::integer
        ON CONFLICT (key, window_start) DO UPDATE
          SET count = rate_limit_windows.count + EXCLUDED.count, updated_at = NOW()
          WHERE rate_limit_windows.count + EXCLUDED.count <= $4::integer
        RETURNING count
      SQL

      binds = [
        ActiveRecord::Relation::QueryAttribute.new("key", key, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new("window_start", window_start, ActiveRecord::Type::BigInteger.new),
        ActiveRecord::Relation::QueryAttribute.new("count", count, ActiveRecord::Type::Integer.new),
        ActiveRecord::Relation::QueryAttribute.new("limit", limit, ActiveRecord::Type::Integer.new)
      ]
      result = ActiveRecord::Base.connection.exec_query(sql, "IngestionRateLimiter", binds)
      row    = result.first

      if row
        new_count = row["count"].to_i
        Result.new(
          allowed: true, limit: limit, count: new_count,
          remaining: [ limit - new_count, 0 ].max, retry_after: 0
        )
      else
        current = RateLimitWindow.where(key: key, window_start: window_start).pick(:count).to_i
        retry_after = (window_start + WINDOW) - now.to_i
        Result.new(
          allowed: false, limit: limit, count: current,
          remaining: [ limit - current, 0 ].max,
          retry_after: [ retry_after, 1 ].max
        )
      end
    end

    def reset!
      RateLimitWindow.delete_all
    end
  end
end

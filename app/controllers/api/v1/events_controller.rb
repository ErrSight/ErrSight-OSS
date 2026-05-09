module Api
  module V1
    class EventsController < BaseController
      MAX_PAYLOAD_SIZE = 512.kilobytes
      MAX_BATCH_SIZE = 100
      ANSI_ESCAPE = /\e\[[0-9;]*[a-zA-Z]|\[[0-9;]*m/

      before_action :check_content_length
      before_action :check_ingestion_limits

      def create
        payload = parse_payload
        return unless payload

        events_data = normalize_payload(payload)

        if events_data.length > MAX_BATCH_SIZE
          return render json: { error: "Batch size exceeds limit of #{MAX_BATCH_SIZE}" }, status: :unprocessable_entity
        end

        rate = IngestionRateLimiter.check!(@project, count: events_data.length)
        unless rate.allowed
          response.headers["Retry-After"]       = rate.retry_after.to_s
          response.headers["X-RateLimit-Limit"] = rate.limit.to_s
          return render json: {
            error: "Rate limit exceeded — try again in #{rate.retry_after}s",
            code: "RATE_LIMIT_EXCEEDED",
            retry_after: rate.retry_after
          }, status: :too_many_requests
        end

        # One job per request, regardless of batch size. Reduces solid_queue_jobs
        # row churn by ~Nx for batched clients — the per-event idempotency,
        # validation, and alert-debounce semantics still run per-event inside
        # the job.
        ProcessEventJob.perform_later(@project.id, events_data)

        render json: {
          status: "accepted",
          queued: events_data.length
        }, status: :accepted
      end

      private

      # Cheap header-based reject. Header may be missing (chunked
      # Transfer-Encoding) or untrustworthy — parse_payload re-checks against
      # the actual bytes read so a lying / absent Content-Length cannot smuggle
      # a >MAX_PAYLOAD_SIZE body past us.
      def check_content_length
        declared = request.content_length
        return if declared.nil?
        return unless declared.to_i > MAX_PAYLOAD_SIZE
        render_payload_too_large
      end

      def render_payload_too_large
        render json: {
          error: "Payload too large (max #{MAX_PAYLOAD_SIZE / 1024}KB)",
          code: "PAYLOAD_TOO_LARGE"
        }, status: :content_too_large
      end

      def check_ingestion_limits
        return unless @project.drop_reason == "ingestion_paused"
        render json: {
          error: "Ingestion is paused for this project",
          code: "INGESTION_PAUSED"
        }, status: :too_many_requests
      end

      # Read one byte past the cap so an oversized body is *detected*, not
      # silently truncated. Without the +1, a chunked / Content-Length-absent
      # request bypasses check_content_length and we'd parse the first
      # MAX_PAYLOAD_SIZE bytes of a larger body — sometimes still valid JSON,
      # sometimes a 400 from a mid-string truncation. Either way, wrong.
      def parse_payload
        body = request.body.read(MAX_PAYLOAD_SIZE + 1)
        if body && body.bytesize > MAX_PAYLOAD_SIZE
          render_payload_too_large
          return nil
        end
        Oj.load(body, mode: :strict)
      rescue Oj::ParseError, JSON::ParserError
        render json: { error: "Invalid JSON payload", code: "INVALID_JSON" }, status: :bad_request
        nil
      end

      def normalize_payload(payload)
        # Accept single event or array of events
        events = payload.is_a?(Array) ? payload : [ payload ]
        events.map { |e| sanitize_event(e) }
      end

      def sanitize_event(data)
        backtrace = data["backtrace"].is_a?(Array) ? data["backtrace"].join("\n") : data["backtrace"].to_s
        user_ctx = sanitize_user_context(data["user"])
        {
          "level" => sanitize_level(data["level"]),
          "message" => strip_ansi(data["message"].to_s).truncate(10_000),
          "backtrace" => strip_ansi(backtrace),
          "environment" => data["environment"].to_s.presence || "production",
          "metadata" => sanitize_metadata(data["metadata"]),
          "occurred_at" => parse_timestamp(data["timestamp"] || data["occurred_at"]),
          "fingerprint" => sanitize_fingerprint(data["fingerprint"]),
          "user_context" => user_ctx,
          "user_identifier" => user_ctx["id"].presence || user_ctx["email"].presence || user_ctx["username"].presence,
          "release" => data["release"].to_s.strip.presence&.truncate(120),
          "breadcrumbs" => sanitize_breadcrumbs(data["breadcrumbs"]),
          "tags" => sanitize_tags(data["tags"]),
          "ingestion_id" => SecureRandom.uuid
        }
      end

      def sanitize_fingerprint(value)
        parts = value.is_a?(Array) ? value : [ value ]
        normalized = parts.map { |p| p.to_s.strip }.reject(&:blank?)
        return nil if normalized.empty?
        Digest::SHA256.hexdigest(normalized.join("|"))[0, 32]
      end

      def strip_ansi(str)
        str.gsub(ANSI_ESCAPE, "")
      end

      def sanitize_level(level)
        level = level.to_s.downcase
        Event.levels.key?(level) ? level : "info"
      end

      def sanitize_metadata(metadata)
        return {} unless metadata.is_a?(Hash)
        # Limit metadata to prevent abuse
        metadata.transform_keys(&:to_s).slice(*metadata.keys.first(50).map(&:to_s))
      end

      def sanitize_user_context(user)
        return {} unless user.is_a?(Hash)
        {
          "id" => user["id"].to_s.strip.presence&.truncate(120),
          "email" => user["email"].to_s.strip.presence&.truncate(200),
          "username" => user["username"].to_s.strip.presence&.truncate(120),
          "ip_address" => user["ip_address"].to_s.strip.presence&.truncate(64)
        }.compact
      end

      def sanitize_breadcrumbs(crumbs)
        return [] unless crumbs.is_a?(Array)
        crumbs.first(50).filter_map do |c|
          next unless c.is_a?(Hash)
          {
            "timestamp" => c["timestamp"].to_s.presence,
            "category" => c["category"].to_s.strip.presence&.truncate(60),
            "level" => sanitize_level(c["level"]),
            "message" => c["message"].to_s.truncate(500),
            "data" => (c["data"].is_a?(Hash) ? c["data"].transform_keys(&:to_s).slice(*c["data"].keys.first(20).map(&:to_s)) : {})
          }.compact
        end
      end

      def sanitize_tags(tags)
        return {} unless tags.is_a?(Hash)
        tags.first(30).to_h.transform_keys { |k| k.to_s.truncate(60) }
            .transform_values { |v| v.to_s.truncate(200) }
      end

      # Accept ISO-8601 / RFC-3339 timestamps, normalize to UTC, and clamp to a
      # narrow sane window. Unbounded timestamps let clients spray events across
      # the Timescale chunk history (catalog bloat) or into the far future.
      INGESTION_PAST_BOUND   = 7.days
      INGESTION_FUTURE_BOUND = 1.hour

      def parse_timestamp(ts)
        return Time.current if ts.blank?
        t = Time.zone.parse(ts.to_s) or return Time.current
        t = t.utc
        now = Time.current
        return Time.current if t < now - INGESTION_PAST_BOUND
        return Time.current if t > now + INGESTION_FUTURE_BOUND
        t
      rescue ArgumentError, TypeError
        Time.current
      end
    end
  end
end

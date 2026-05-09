class QueueHealth
  # Single point of truth for "is Solid Queue keeping up?" Backed by
  # SolidQueue's own tables — no external monitoring infra. Use this from
  # the recurring health-report job and from any future ops endpoints.
  #
  # The metric that actually matters is `oldest_ready_age_seconds`. If the
  # oldest ready execution is N seconds old, drain time is at least N. A
  # healthy queue keeps it under a second; sustained values >60s mean the
  # workers can't keep up with arrivals and customers will see stale
  # dashboards / late alerts.
  Snapshot = Struct.new(:backlog, :oldest_ready_age_seconds, :failed, keyword_init: true)

  class << self
    def snapshot(now: Time.current)
      Snapshot.new(
        backlog:                  ready_count,
        oldest_ready_age_seconds: oldest_ready_age_seconds(now: now),
        failed:                   failed_count
      )
    end

    private

    def ready_count
      SolidQueue::ReadyExecution.count
    end

    # The age of the oldest claimable job. Created_at is set when the
    # execution is promoted to ready, so this is the actual time-in-queue.
    # Returns 0 when the queue is empty.
    def oldest_ready_age_seconds(now:)
      oldest = SolidQueue::ReadyExecution.minimum(:created_at)
      return 0 unless oldest
      [ (now - oldest).to_i, 0 ].max
    end

    def failed_count
      SolidQueue::FailedExecution.count
    end
  end
end

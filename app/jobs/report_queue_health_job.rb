class ReportQueueHealthJob < ApplicationJob
  queue_as :maintenance

  # Thresholds picked to match the current single-worker Railway setup
  # (~150 jobs/sec drain rate). At 1k backlog the queue is roughly 7 seconds
  # behind — annoying but recoverable. At 10k+ or 5+ minutes lag, the queue
  # has stopped keeping up and the worker needs to be split out.
  WARN_BACKLOG    = 1_000
  CRIT_BACKLOG    = 10_000
  WARN_LAG_SECONDS = 60
  CRIT_LAG_SECONDS = 300

  discard_on ActiveJob::DeserializationError

  def perform
    snapshot = QueueHealth.snapshot
    log_snapshot(snapshot)
  end

  private

  def log_snapshot(s)
    line = "[QueueHealth] backlog=#{s.backlog} oldest_ready_age_s=#{s.oldest_ready_age_seconds} failed=#{s.failed}"
    case severity_for(s)
    when :error   then Rails.logger.error(line)
    when :warning then Rails.logger.warn(line)
    else               Rails.logger.info(line)
    end
  end

  # Severity reflects whichever signal is worse. Either dimension alone is
  # enough — a 50k backlog with 1s ages still means the worker is dying;
  # a 10-event backlog with a 10-minute oldest age means a single job is
  # wedged. Both are paging-worthy.
  def severity_for(s)
    return :error   if s.backlog >= CRIT_BACKLOG || s.oldest_ready_age_seconds >= CRIT_LAG_SECONDS
    return :warning if s.backlog >= WARN_BACKLOG || s.oldest_ready_age_seconds >= WARN_LAG_SECONDS
    nil
  end
end

class PruneEventsByRetentionJob < ApplicationJob
  queue_as :maintenance

  # Retention is operator-configurable in the community edition. Default
  # 30 days. Set RETENTION_DAYS=0 in the environment to disable pruning
  # (keep events forever — make sure you have the disk for it).
  def perform
    days = ENV.fetch("RETENTION_DAYS", 30).to_i
    return unless days.positive?

    cutoff = days.days.ago
    total_deleted = 0
    total_bytes   = 0

    Project.find_each do |project|
      count, bytes = EventRepository.prune_older_than!(project_id: project.id, cutoff: cutoff)
      next if count.zero?

      Project.where(id: project.id).update_all([
        "events_count = GREATEST(events_count - ?, 0), " \
        "storage_bytes = GREATEST(storage_bytes - ?, 0), " \
        "updated_at = NOW()",
        count, bytes
      ])

      total_deleted += count
      total_bytes   += bytes
    end

    if total_deleted.positive?
      Rails.logger.info "[PruneEventsByRetentionJob] retention=#{days}d deleted=#{total_deleted} bytes_freed=#{total_bytes}"
    end
  end
end

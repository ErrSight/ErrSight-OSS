class PurgeDiscardedOrganizationsJob < ApplicationJob
  queue_as :maintenance

  def perform
    cutoff = Organization::RETENTION_WINDOW.ago

    Organization.discarded.where("discarded_at < ?", cutoff).find_each do |org|
      Rails.logger.info "[PurgeDiscardedOrganizationsJob] Destroying organization #{org.id} (discarded_at=#{org.discarded_at})"
      purge_events_for(org)
      org.destroy
    end
  end

  private

  # Blow away the events table via delete_all so we don't instantiate every row
  # (orgs can have millions of events). No callbacks on Event we care about in
  # this context — counters get dropped along with the org anyway.
  def purge_events_for(org)
    project_ids = org.projects.pluck(:id)
    return if project_ids.empty?
    Event.where(project_id: project_ids).delete_all
  end
end

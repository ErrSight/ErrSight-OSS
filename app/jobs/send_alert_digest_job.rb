class SendAlertDigestJob < ApplicationJob
  queue_as :alerts

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform
    cutoff = 1.hour.ago

    AlertPreference.where(digest_frequency: :hourly, email_enabled: true).includes(membership: :user).find_each do |preference|
      membership = preference.membership
      organization = membership.organization
      project = preference.project

      # For org-wide preferences (project_id nil), send digest per project
      projects = project ? [ project ] : organization.projects

      projects.each do |proj|
        events = EventRepository.digest_for(project: proj, since: cutoff, min_level: preference.min_level)
        next unless events.any?

        AlertMailer.digest_alert(membership.user, events, proj, "hour").deliver_later
      end
    end

    deliver_slack_digests(cutoff)
  end

  private

  def deliver_slack_digests(cutoff)
    Organization.where.not(slack_webhook_url: [ nil, "" ]).find_each do |organization|
      slack_prefs = AlertPreference
        .joins(:membership)
        .where(memberships: { organization_id: organization.id })
        .where(digest_frequency: :hourly, slack_enabled: true)

      next if slack_prefs.empty?

      organization.projects.find_each do |project|
        relevant = slack_prefs.select { |p| p.project_id.nil? || p.project_id == project.id }
        next if relevant.empty?

        min_level = relevant.map(&:min_level).min

        events = EventRepository.digest_for(project: project, since: cutoff, min_level: min_level)
        next unless events.any?

        # Atomically claim the right to send this hour's digest for (org, project).
        # Retries within the same hour bucket see the claim and skip. Release the
        # claim on failure so the outer retry can reclaim and resend.
        cache_key = "slack_digest:org:#{organization.id}:project:#{project.id}:hour:#{Time.current.beginning_of_hour.to_i}"
        next unless Rails.cache.write(cache_key, true, expires_in: 3.hours, unless_exist: true)
        begin
          SlackNotifier.post(organization.slack_webhook_url, SlackNotifier.digest_payload(events.to_a, project))
        rescue StandardError
          Rails.cache.delete(cache_key)
          raise
        end
      end
    end
  end
end

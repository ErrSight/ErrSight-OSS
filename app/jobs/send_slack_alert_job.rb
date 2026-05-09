class SendSlackAlertJob < ApplicationJob
  queue_as :alerts

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 10.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  def perform(event_id)
    event = EventRepository.find(event_id)
    return unless event

    project = event.project
    organization = project.organization
    return unless organization&.slack_configured?
    return unless alert_rule_matches?(project, event)

    payload = SlackNotifier.event_payload(event, project)

    organization.memberships.includes(:alert_preferences).find_each do |membership|
      preference = membership.alert_preferences.detect { |p| p.project_id == project.id } ||
                   membership.alert_preferences.detect { |p| p.project_id.nil? }

      next unless preference&.should_alert_for?(event.level, channel: :slack)
      next unless preference.immediate?

      SlackNotifier.post(organization.slack_webhook_url, payload)
      # Org webhook posts once per org — break after first matching member
      break
    end
  end

  private

  def alert_rule_matches?(project, event)
    rules = project.alert_rules.active.to_a
    return true if rules.empty?
    rules.any? { |rule| rule.matches?(event) }
  end
end

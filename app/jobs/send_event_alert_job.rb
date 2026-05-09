class SendEventAlertJob < ApplicationJob
  queue_as :alerts

  # 5 attempts with polynomial backoff (~3s, 18s, 83s, 258s, 625s) keeps the
  # job alive through a typical Resend incident without dead-lettering alerts.
  # Production config now lets mail-delivery errors raise so they consume this
  # budget rather than being swallowed silently — the cache-key release below
  # undoes the "already claimed" marker on each failure so the retry is
  # actually able to resend.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(event_id)
    event = EventRepository.find(event_id)
    return unless event

    project = event.project
    organization = project.organization
    return unless organization
    return unless alert_rule_matches?(project, event)

    organization.memberships.includes(:user, :alert_preferences).find_each do |membership|
      # .detect walks the preloaded alert_preferences association in memory;
      # .find_by would re-issue SQL per membership and defeat the include.
      preference = membership.alert_preferences.detect { |p| p.project_id == project.id } ||
                   membership.alert_preferences.detect { |p| p.project_id.nil? }

      next unless preference&.should_alert_for?(event.level, channel: :email)

      case preference.digest_frequency
      when "immediate"
        # Atomically claim the right to send for this (event, membership) pair.
        # write(..., unless_exist: true) returns true only if this worker won
        # the race — closes the read-then-write TOCTOU that could double-send
        # alerts on concurrent retries. On enqueue failure we release the claim
        # so the outer retry can try again (preserving at-least-once).
        cache_key = "alert_delivered:event:#{event.id}:membership:#{membership.id}"
        next unless Rails.cache.write(cache_key, true, expires_in: 24.hours, unless_exist: true)
        begin
          AlertMailer.error_alert(membership.user, event, project).deliver_later
        rescue StandardError
          Rails.cache.delete(cache_key)
          raise
        end
      end
      # Hourly digests are handled by SendAlertDigestJob
    end
  end

  private

  def alert_rule_matches?(project, event)
    rules = project.alert_rules.active.to_a
    return true if rules.empty?
    rules.any? { |rule| rule.matches?(event) }
  end
end

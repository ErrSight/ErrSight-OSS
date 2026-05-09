class SendWeeklyDigestsJob < ApplicationJob
  queue_as :alerts

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform
    Organization.kept.find_each do |organization|
      stats = WeeklyDigestStats.new(organization)
      next if stats.empty?

      organization.memberships
        .weekly_digest_recipients
        .includes(:user)
        .find_each do |membership|
          next unless membership.user&.active_for_authentication?
          next unless membership.organization_id == organization.id

          # Claim this week's digest for the membership so a retry (triggered by
          # a later org raising in WeeklyDigestStats) doesn't resend to members
          # already processed in the failed attempt. Released on a failed send so
          # a genuine delivery error can still be retried.
          cache_key = "weekly_digest:membership:#{membership.id}:week:#{Time.current.beginning_of_week.to_i}"
          next unless Rails.cache.write(cache_key, true, expires_in: 8.days, unless_exist: true)

          begin
            DigestMailer.weekly(membership, stats).deliver_now
          rescue => e
            Rails.cache.delete(cache_key)
            Rails.error.report(
              e,
              context: { membership_id: membership.id, organization_id: organization.id },
              handled: true
            )
          end
        end
    end
  end
end

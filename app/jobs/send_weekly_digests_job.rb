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

          begin
            DigestMailer.weekly(membership, stats).deliver_now
          rescue => e
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

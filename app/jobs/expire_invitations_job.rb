class ExpireInvitationsJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = Invitation.pending.where("expires_at < ?", Time.current).update_all(status: :expired)
    Rails.logger.info "[ExpireInvitationsJob] Marked #{expired_count} invitations as expired" if expired_count > 0
  end
end

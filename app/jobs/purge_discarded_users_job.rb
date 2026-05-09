class PurgeDiscardedUsersJob < ApplicationJob
  queue_as :maintenance

  def perform
    cutoff = User::RETENTION_WINDOW.ago

    User.discarded.where("discarded_at < ?", cutoff).find_each do |user|
      Rails.logger.info "[PurgeDiscardedUsersJob] Destroying user #{user.id} (discarded_at=#{user.discarded_at})"
      user.destroy
    end
  end
end

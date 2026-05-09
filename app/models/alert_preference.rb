class AlertPreference < ApplicationRecord
  belongs_to :membership
  belongs_to :project, optional: true

  enum :digest_frequency, { immediate: 0, hourly: 1 }

  validates :membership_id, uniqueness: { scope: :project_id }

  # Event levels in the app: debug=0, info=1, warning=2, error=3, fatal=4
  def should_alert_for?(level, channel: :email)
    return false unless channel_enabled?(channel)
    event_level = Event.levels[level.to_s] || level.to_i
    event_level >= min_level
  end

  def channel_enabled?(channel)
    case channel.to_sym
    when :email then email_enabled?
    when :slack then slack_enabled?
    else false
    end
  end
end

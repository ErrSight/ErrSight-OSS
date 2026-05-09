class AlertRule < ApplicationRecord
  belongs_to :project

  enum :rule_type, { every_event: 0, first_occurrence: 1, threshold: 2 }

  validates :name, presence: true
  validates :level_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 4 }
  validates :count_threshold, numericality: { greater_than: 0 }
  MAX_WINDOW_SECONDS = 30.days.to_i

  validates :window_seconds, numericality: { greater_than: 0, less_than_or_equal_to: MAX_WINDOW_SECONDS }

  scope :active, -> { where(active: true) }

  def matches?(event)
    return false unless active?
    return false if event.level_before_type_cast < level_threshold

    case rule_type
    when "every_event"
      true
    when "first_occurrence"
      first_occurrence_for?(event)
    when "threshold"
      over_threshold_for?(event)
    else
      false
    end
  end

  private

  def first_occurrence_for?(event)
    EventRepository.first_occurrence?(project: project, fingerprint: event.fingerprint, except_id: event.id)
  end

  def over_threshold_for?(event)
    since = Time.current - window_seconds.seconds
    count = EventRepository.count_in_window(project: project, fingerprint: event.fingerprint, since: since)
    count >= count_threshold
  end
end

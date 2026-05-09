require "test_helper"

class AlertRuleTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
    @event = events(:error_event)
  end

  test "every_event rule matches any event above level_threshold" do
    rule = @project.alert_rules.create!(
      name: "all errors", rule_type: :every_event,
      level_threshold: Event.levels[:error], count_threshold: 1, window_seconds: 3600
    )
    assert rule.matches?(@event)
  end

  test "rule does not match when event level is below threshold" do
    warning = @project.events.create!(
      level: "warning", message: "warn", environment: "production",
      fingerprint: "warn-fp", occurred_at: Time.current, size_bytes: 100
    )
    rule = @project.alert_rules.create!(
      name: "fatals", rule_type: :every_event,
      level_threshold: Event.levels[:fatal], count_threshold: 1, window_seconds: 3600
    )
    assert_not rule.matches?(warning)
  end

  test "first_occurrence matches only when no other events share fingerprint" do
    rule = @project.alert_rules.create!(
      name: "first", rule_type: :first_occurrence,
      level_threshold: 0, count_threshold: 1, window_seconds: 3600
    )
    fresh = @project.events.create!(
      level: "error", message: "new", environment: "production",
      fingerprint: "new-fp-once", occurred_at: Time.current, size_bytes: 100
    )
    assert rule.matches?(fresh)

    dup = @project.events.create!(
      level: "error", message: "new", environment: "production",
      fingerprint: "new-fp-once", occurred_at: Time.current, size_bytes: 100
    )
    assert_not rule.matches?(dup)
  end

  test "threshold matches when count within window reaches threshold" do
    rule = @project.alert_rules.create!(
      name: "spike", rule_type: :threshold,
      level_threshold: 0, count_threshold: 2, window_seconds: 3600
    )
    2.times do
      @project.events.create!(
        level: "error", message: "dup", environment: "production",
        fingerprint: "spike-fp", occurred_at: Time.current, size_bytes: 100
      )
    end
    triggering = @project.events.where(fingerprint: "spike-fp").last
    assert rule.matches?(triggering)
  end

  test "inactive rule never matches" do
    rule = @project.alert_rules.create!(
      name: "off", rule_type: :every_event,
      level_threshold: 0, count_threshold: 1, window_seconds: 3600, active: false
    )
    assert_not rule.matches?(@event)
  end
end

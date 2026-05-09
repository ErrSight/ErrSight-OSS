require "test_helper"

class SendSlackAlertJobTest < ActiveJob::TestCase
  include StubHelper

  setup do
    @event        = events(:error_event)
    @project      = @event.project
    @organization = @project.organization
    @organization.update!(slack_webhook_url: "https://hooks.slack.com/services/T0/B0/XYZ")
    @membership   = memberships(:regular_admin)
  end

  # Capture Slack posts so no real HTTP is attempted.
  def capture_slack_posts(&block)
    calls = []
    stub_method(SlackNotifier, :post, ->(url, payload) {
      calls << { url: url, payload: payload }
      true
    }, &block)
    calls
  end

  test "does nothing when organization has no slack_webhook_url" do
    @organization.update!(slack_webhook_url: nil)
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "does nothing when no membership has a matching slack preference" do
    # No AlertPreference exists — default behavior should be no-op
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "does nothing when preference has slack_enabled: false" do
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: true, slack_enabled: false,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "does nothing when preference min_level is above event level" do
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: false, slack_enabled: true,
      min_level: Event.levels[:fatal], digest_frequency: :immediate
    )
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "does nothing when preference is not immediate (digest frequency)" do
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: false, slack_enabled: true,
      min_level: Event.levels[:warning], digest_frequency: :hourly
    )
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "posts to Slack when matching immediate preference exists" do
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: false, slack_enabled: true,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_equal 1, calls.length
    assert_equal @organization.slack_webhook_url, calls.first[:url]
    assert_kind_of Hash, calls.first[:payload]
  end

  test "posts only once per org regardless of how many members match" do
    # Add additional members with their own matching preferences.
    other_user = User.create!(
      email: "second-admin@example.com",
      password: "password1234",
      name: "Second Admin",
      confirmed_at: Time.current
    )
    other_membership = Membership.create!(organization: @organization, user: other_user, role: :admin)

    [ @membership, other_membership ].each do |m|
      AlertPreference.create!(
        membership: m, project: nil,
        email_enabled: false, slack_enabled: true,
        min_level: Event.levels[:warning], digest_frequency: :immediate
      )
    end

    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_equal 1, calls.length
  end

  test "skips delivery when alert rules exist but none match" do
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: false, slack_enabled: true,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )
    @project.alert_rules.create!(
      name: "fatals only", rule_type: :every_event,
      level_threshold: Event.levels[:fatal], count_threshold: 1, window_seconds: 3600
    )

    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_empty calls
  end

  test "project-specific preference takes precedence over org-wide" do
    # Org-wide disallows Slack; project-specific allows it.
    AlertPreference.create!(
      membership: @membership, project: nil,
      email_enabled: true, slack_enabled: false,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )
    AlertPreference.create!(
      membership: @membership, project: @project,
      email_enabled: false, slack_enabled: true,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )

    calls = capture_slack_posts { SendSlackAlertJob.perform_now(@event.id) }
    assert_equal 1, calls.length
  end

  test "returns silently when event does not exist" do
    calls = capture_slack_posts { SendSlackAlertJob.perform_now(999_999) }
    assert_empty calls
  end
end

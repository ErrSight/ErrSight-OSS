require "test_helper"

class SendWeeklyDigestsJobTest < ActiveJob::TestCase
  include StubHelper

  setup do
    ActionMailer::Base.deliveries.clear

    @org_a       = organizations(:regular_org)
    @org_b       = organizations(:admin_org)
    @recipient_a = memberships(:regular_admin)
    @recipient_b = memberships(:admin_admin)

    @org_a_message = "Org A unique boom #{SecureRandom.hex(4)}"
    @org_b_message = "Org B unique kaboom #{SecureRandom.hex(4)}"

    seed_event(projects(:alpha),         @org_a_message, 1.day.ago)
    seed_event(projects(:admin_project), @org_b_message, 2.days.ago)
  end

  test "each org's recipient only receives their own org's stats" do
    SendWeeklyDigestsJob.perform_now

    by_recipient = ActionMailer::Base.deliveries.group_by { |m| m.to.first }
    a_emails = by_recipient[@recipient_a.user.email] || []
    b_emails = by_recipient[@recipient_b.user.email] || []

    assert_equal 1, a_emails.size, "expected exactly one email for org A's recipient"
    assert_equal 1, b_emails.size, "expected exactly one email for org B's recipient"

    a_email = a_emails.first
    b_email = b_emails.first

    assert_includes a_email.subject,      @org_a.name
    refute_includes a_email.subject,      @org_b.name
    assert_includes a_email.body.encoded, @org_a_message
    refute_includes a_email.body.encoded, @org_b_message
    refute_includes a_email.body.encoded, projects(:admin_project).name

    assert_includes b_email.subject,      @org_b.name
    refute_includes b_email.subject,      @org_a.name
    assert_includes b_email.body.encoded, @org_b_message
    refute_includes b_email.body.encoded, @org_a_message
    refute_includes b_email.body.encoded, projects(:alpha).name
  end

  test "delivers to exactly the opted-in recipients of orgs with activity" do
    SendWeeklyDigestsJob.perform_now

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }.sort
    expected   = [ @recipient_a.user.email, @recipient_b.user.email ].sort
    assert_equal expected, recipients
  end

  test "skips memberships whose user is not active for authentication" do
    @recipient_b.user.discard!

    SendWeeklyDigestsJob.perform_now

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }
    refute_includes recipients, @recipient_b.user.email
    assert_includes recipients, @recipient_a.user.email
  end

  test "a single failing send does not block other recipients in the same org" do
    second_user = User.create!(
      email: "second-#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      name: "Second Org A Member",
      confirmed_at: Time.current
    )
    second_membership = Membership.create!(
      organization: @org_a,
      user: second_user,
      role: :member,
      weekly_digest_enabled: true
    )

    failing_membership_id = @recipient_a.id
    original_weekly = DigestMailer.method(:weekly)
    DigestMailer.define_singleton_method(:weekly) do |membership, stats|
      raise StandardError, "smtp boom" if membership.id == failing_membership_id
      original_weekly.call(membership, stats)
    end

    reported = []
    stub_method(Rails.error, :report, ->(error, **opts) { reported << [ error, opts ] }) do
      SendWeeklyDigestsJob.perform_now
    end

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }
    refute_includes recipients, @recipient_a.user.email,    "failing recipient must not receive the email"
    assert_includes recipients, second_membership.user.email, "second recipient in same org must still receive the email"
    assert_includes recipients, @recipient_b.user.email,      "recipients in other orgs must still receive the email"

    assert_equal 1, reported.size
    err, opts = reported.first
    assert_kind_of StandardError, err
    assert_equal failing_membership_id, opts.dig(:context, :membership_id)
    assert_equal @org_a.id,             opts.dig(:context, :organization_id)
  ensure
    DigestMailer.singleton_class.remove_method(:weekly) if DigestMailer.singleton_class.method_defined?(:weekly)
  end

  test "skips organizations with no activity" do
    Event.where(project: projects(:admin_project)).destroy_all

    SendWeeklyDigestsJob.perform_now

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }
    assert_includes recipients, @recipient_a.user.email
    refute_includes recipients, @recipient_b.user.email
  end

  test "skips memberships with weekly digest disabled" do
    @recipient_b.update!(weekly_digest_enabled: false)

    SendWeeklyDigestsJob.perform_now

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }
    refute_includes recipients, @recipient_b.user.email
    assert_includes recipients, @recipient_a.user.email
  end

  test "skips discarded organizations entirely" do
    @org_b.discard!

    SendWeeklyDigestsJob.perform_now

    recipients = ActionMailer::Base.deliveries.map { |m| m.to.first }
    refute_includes recipients, @recipient_b.user.email
  end

  private

  def seed_event(project, message, occurred_at)
    Event.create!(
      project:     project,
      level:       :error,
      message:     message,
      environment: "production",
      occurred_at: occurred_at,
      size_bytes:  100,
      discarded:   false,
      metadata:    {}
    )
  end
end

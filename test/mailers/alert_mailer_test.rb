require "test_helper"

class AlertMailerTest < ActionMailer::TestCase
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    @event   = @project.events.create!(
      level: :error, message: "Database down", environment: "production",
      fingerprint: "fp-mailer", occurred_at: Time.current, size_bytes: 100
    )
  end

  test "error_alert is addressed to the user" do
    mail = AlertMailer.error_alert(@user, @event, @project)
    assert_equal [ @user.email ], mail.to
    assert_match @project.name, mail.subject
    assert_match "Error", mail.subject
    assert_match "Database down", mail.subject
  end

  test "error_alert body includes event url" do
    mail = AlertMailer.error_alert(@user, @event, @project)
    assert_match "/projects/#{@project.id}/events/", mail.body.encoded
  end

  test "error_alert subject strips CRLF from event message" do
    @event.update!(message: "Database\r\ndown\nBcc: attacker@example.com")
    mail = AlertMailer.error_alert(@user, @event, @project)
    assert_no_match(/[\r\n]/, mail.subject)
    assert_match "Database down", mail.subject
  end

  test "digest_alert subject reflects event count and period" do
    events = [ @event ]
    mail = AlertMailer.digest_alert(@user, events, @project, "hourly")
    assert_equal [ @user.email ], mail.to
    assert_match "1 new errors", mail.subject
    assert_match "hourly", mail.subject
  end

  test "quota_reached for events uses monthly-event label" do
    mail = AlertMailer.quota_reached(@user, @project.organization, "events")
    assert_equal [ @user.email ], mail.to
    assert_match "Monthly event", mail.subject
  end

  test "quota_reached for storage uses storage label" do
    mail = AlertMailer.quota_reached(@user, @project.organization, "storage")
    assert_match "Storage", mail.subject
  end
end

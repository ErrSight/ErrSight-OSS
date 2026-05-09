require "test_helper"

class AdminNotificationMailerTest < ActionMailer::TestCase
  include StubHelper

  test "new_user_signup is addressed to the admin recipient" do
    user = User.create!(email: "signup1@example.com", name: "Signed Up", password: "password123")

    mail = AdminNotificationMailer.new_user_signup(user)

    assert_equal [ AdminNotificationMailer.recipient ], mail.to
    assert_match user.email, mail.subject
    assert_match "New signup", mail.subject
  end

  test "new_user_signup body contains user email, name, and signup method" do
    user = User.create!(email: "signup2@example.com", name: "Email User", password: "password123")

    mail = AdminNotificationMailer.new_user_signup(user)

    [ mail.text_part.decoded, mail.html_part.decoded ].each do |body|
      assert_match user.email, body
      assert_match "Email User", body
      assert_match "Email + password", body
    end
  end

  test "new_user_signup labels OAuth signups with the provider" do
    user = User.create!(
      email: "oauth@example.com",
      name: "OAuth User",
      password: "password123",
      provider: "google_oauth2",
      uid: "abc-123"
    )

    mail = AdminNotificationMailer.new_user_signup(user)

    assert_match "OAuth (google_oauth2)", mail.text_part.decoded
    assert_match "OAuth (google_oauth2)", mail.html_part.decoded
  end

  test "recipient is overridable via ADMIN_NOTIFICATION_EMAIL env var" do
    ENV["ADMIN_NOTIFICATION_EMAIL"] = "ops@example.com"
    assert_equal "ops@example.com", AdminNotificationMailer.recipient
  ensure
    ENV.delete("ADMIN_NOTIFICATION_EMAIL")
  end

  test "signup_notification_mode defaults to per_signup" do
    ENV.delete("ADMIN_SIGNUP_NOTIFICATIONS")
    assert_equal AdminNotificationMailer::MODE_PER_SIGNUP, AdminNotificationMailer.signup_notification_mode
  end
end

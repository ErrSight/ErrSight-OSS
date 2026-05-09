class AdminNotificationMailer < ApplicationMailer
  # Per-signup mode fires one email per new user. Digest mode short-circuits
  # the per-signup callback so a future scheduled job can roll up signups
  # into a daily summary. Disabled silences both paths (used in staging /
  # noisy test scenarios).
  MODE_PER_SIGNUP = "per_signup".freeze
  MODE_DIGEST     = "digest".freeze
  MODE_DISABLED   = "disabled".freeze

  def self.signup_notification_mode
    ENV.fetch("ADMIN_SIGNUP_NOTIFICATIONS", MODE_PER_SIGNUP)
  end

  def self.recipient
    ENV.fetch("ADMIN_NOTIFICATION_EMAIL", "support@errsight.com")
  end

  def new_user_signup(user)
    @user          = user
    @signup_method = user.provider.present? ? "OAuth (#{user.provider})" : "Email + password"
    @signup_time   = user.created_at
    @admin_url     = admin_user_url(user) rescue nil

    mail(
      to: self.class.recipient,
      subject: "[ErrSight Admin] New signup: #{user.email}"
    )
  end
end

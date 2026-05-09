class User < ApplicationRecord
  include Discard::Model

  RETENTION_WINDOW = 90.days

  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable
  #
  # Self-host note: :confirmable requires working SMTP (see config/environments
  # for mailer settings). If your deployment can't deliver email, remove
  # :confirmable from this list — confirmation will be skipped at signup.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable,
         :omniauthable, omniauth_providers: [ :google_oauth2, :github ]

  has_many :projects, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :owned_organizations, class_name: "Organization", foreign_key: :owner_id, dependent: :nullify
  has_many :saved_filters, dependent: :destroy

  attr_accessor :organization_name

  RESERVED_EMAIL_DOMAINS = %w[example.com example.net example.org].freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, on: :create
  validate :email_domain_not_reserved

  def self.from_omniauth(auth)
    provider = auth.provider.to_s
    uid      = auth.uid.to_s
    email    = auth.info.email.presence || "#{provider}-#{uid}@oauth.errsight.local"
    email    = email.downcase

    user = find_by(provider: provider, uid: uid)
    user ||= find_or_initialize_by(email: email)

    user.provider = provider
    user.uid      = uid
    user.name     = auth.info.name.presence || user.name.presence || email.split("@").first
    user.password = Devise.friendly_token[0, 20] if user.encrypted_password.blank?

    # OAuth providers have already verified the user's email — skip our own
    # confirmation email for both brand-new OAuth signups and any legacy
    # unconfirmed rows they collide with.
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!) && user.confirmed_at.blank?

    user.save!
    user
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[email name admin created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "projects" ]
  end

  after_discard do
    projects.update_all(ingestion_paused: true)
    solo_owned_organizations.each(&:discard!)
  end

  after_undiscard { projects.update_all(ingestion_paused: false) }

  # Fires after the full registration transaction commits (so org-creation
  # rollback also drops the notification). Gated by ADMIN_SIGNUP_NOTIFICATIONS:
  # `per_signup` (default) sends one email per signup; `digest` short-circuits
  # so a future scheduled job can roll signups into a daily summary; any other
  # value (e.g. `disabled`) silences both paths.
  after_create_commit :notify_admin_of_signup

  def active_for_authentication?
    super && !discarded?
  end

  def inactive_message
    discarded? ? :account_deleted : super
  end

  def admin?
    admin
  end

  def accessible_projects
    Project.where(organization_id: organizations.kept.select(:id))
  end

  def primary_organization
    organizations.kept.first
  end

  # Organizations this user owns where they are the only member. These cascade
  # on account deletion. Shared orgs are blocked at the controller — the user
  # must remove other members first.
  def solo_owned_organizations
    owned_organizations.kept.select { |org| org.memberships.count <= 1 }
  end

  # Orgs the user owns that still have other members. Used as an account-
  # deletion guard.
  def shared_owned_organizations
    owned_organizations.kept.select { |org| org.memberships.count > 1 }
  end

  # Devise 5.0 ships with deliver_now, which sends the confirmation email
  # synchronously inside the registration transaction. If a later step
  # rolls the transaction back (e.g. organization creation fails), the
  # email has already been sent and the user is left with a confirmation
  # link for an account that no longer exists. Using deliver_later under
  # Rails 8.1's enqueue_after_transaction_commit: :all defers the enqueue
  # until after the transaction commits and drops it on rollback.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  private

  def notify_admin_of_signup
    return unless AdminNotificationMailer.signup_notification_mode == AdminNotificationMailer::MODE_PER_SIGNUP

    AdminNotificationMailer.new_user_signup(self).deliver_later
  rescue => e
    Rails.logger.warn "[AdminNotificationMailer] failed to enqueue new-user notification user=#{id} error=#{e.class}: #{e.message}"
  end

  # Test env relies on example.com fixtures and seed users; prod/staging reject
  # them so a real signup can't squat on RFC 2606 reserved domains.
  def email_domain_not_reserved
    return if Rails.env.test?
    return if email.blank?
    domain = email.to_s.split("@", 2).last.to_s.downcase
    errors.add(:email, "domain is not allowed") if RESERVED_EMAIL_DOMAINS.include?(domain)
  end
end

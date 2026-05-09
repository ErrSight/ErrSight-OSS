class Invitation < ApplicationRecord
  belongs_to :organization
  belongs_to :invited_by, class_name: "User"

  # Namespace for pg_advisory_xact_lock(int, int). Using the two-int form
  # partitions our advisory lock keyspace so another code path picking an
  # org-id-sized int can't collide with invite serialization. Derived once
  # from a stable string so the value is reviewable rather than magic.
  ADVISORY_LOCK_NAMESPACE = Zlib.crc32("errsight:invite") % 2**31

  def self.acquire_org_lock!(organization_id)
    # Both args are Integers we fully control (one is a constant, the other is
    # explicitly coerced), but parameterize anyway so Brakeman is happy and
    # the call site reads like a normal query.
    sanitized = sanitize_sql_array([
      "SELECT pg_advisory_xact_lock(?, ?)",
      ADVISORY_LOCK_NAMESPACE,
      Integer(organization_id) % (2**31)
    ])
    connection.execute(sanitized)
  end

  enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3 }
  enum :role, { admin: 0, member: 1, viewer: 2 }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :email, uniqueness: {
    scope: :organization_id,
    conditions: -> { where(status: :pending) },
    message: "has already been invited to this organization"
  }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create
  before_validation :normalize_email

  scope :not_expired, -> { where("expires_at > ?", Time.current) }

  # Pending, unexpired invitation matching a given address (case-insensitive,
  # to mirror Invitation#accept!'s email check). Used by the sign-in / onboarding
  # gate so an invitee is always recognized as invited — even when their session
  # has lost the invitation_token (cross-browser confirmation, OAuth redirect, etc).
  def self.pending_for_email(email)
    return none if email.blank?
    pending.not_expired.where("LOWER(email) = ?", email.to_s.downcase)
  end

  def expired?
    expires_at < Time.current
  end

  def accept!(user)
    transaction do
      # Serialize concurrent invitation acceptances for this org so the member-
      # limit check and the insert happen atomically — without this, N invitees
      # accepting simultaneously all pass can_invite? and all get memberships.
      self.class.acquire_org_lock!(organization_id)

      raise InvitationLimitExceeded unless organization.can_invite?

      update!(status: :accepted, accepted_at: Time.current)
      organization.memberships.create!(user: user, role: role)
    end
  end

  class InvitationLimitExceeded < StandardError; end

  def decline!
    update!(status: :declined)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[email role status created_at expires_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[organization invited_by]
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiry
    self.expires_at ||= 7.days.from_now
  end

  # Normalize on write so the uniqueness validator, the existing-user lookup
  # in InvitationsController#show, and the pending_for_email scope all compare
  # the same canonical form. User emails are already downcased by Devise
  # (case_insensitive_keys) and User.from_omniauth, so this also lets
  # User.find_by(email: @invitation.email) hit the matching user record.
  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end
end

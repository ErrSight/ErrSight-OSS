class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  has_many :alert_preferences, dependent: :destroy

  enum :role, { admin: 0, member: 1, viewer: 2 }

  DIGEST_UNSUBSCRIBE_PURPOSE = "digest_unsubscribe".freeze

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :organization_id, message: "is already a member of this organization" }

  scope :admins, -> { where(role: :admin) }
  scope :members_and_above, -> { where(role: [ :admin, :member ]) }
  scope :weekly_digest_recipients, -> { where(weekly_digest_enabled: true) }

  def digest_unsubscribe_token
    Rails.application.message_verifier(DIGEST_UNSUBSCRIBE_PURPOSE).generate(id)
  end

  def self.find_by_digest_unsubscribe_token(token)
    id = Rails.application.message_verifier(DIGEST_UNSUBSCRIBE_PURPOSE).verify(token.to_s)
    find_by(id: id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[role created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[organization user]
  end
end

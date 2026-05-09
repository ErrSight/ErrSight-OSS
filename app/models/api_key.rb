class ApiKey < ApplicationRecord
  SCOPE_PREFIX = { "write" => "elp_", "read" => "elr_" }.freeze

  belongs_to :project

  enum :scope, { write: 0, read: 1 }, prefix: true

  validates :name,  presence: true, length: { maximum: 80 }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :active, -> { where(revoked_at: nil) }

  def self.find_active_by_token(token)
    return nil if token.blank?
    active.find_by(token: token)
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    return if revoked?
    update!(revoked_at: Time.current)
  end

  def touch_last_used!
    update_columns(last_used_at: Time.current)
  end

  private

  def generate_token
    return if token.present?
    prefix = SCOPE_PREFIX[scope.to_s] || SCOPE_PREFIX["write"]
    self.token = "#{prefix}#{SecureRandom.hex(24)}"
  end
end

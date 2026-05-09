class Project < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  has_many :events, dependent: :delete_all
  has_many :alert_preferences, dependent: :destroy
  has_many :mute_rules, dependent: :delete_all
  has_many :alert_rules, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy
  has_many :issues, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true
  validates :api_key, presence: true, uniqueness: true
  validates :slug, uniqueness: true, allow_blank: true
  validates :rate_limit_per_minute, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :generate_api_key, on: :create
  before_validation :generate_slug, on: :create
  after_create :ensure_default_api_key

  scope :for_user, ->(user) { where(user: user) }

  def self.ransackable_attributes(auth_object = nil)
    %w[name slug ingestion_paused events_count storage_bytes created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user events]
  end

  def to_param
    id.to_s
  end

  # Returns the first tripped limit, or nil. Used by ingestion jobs to decide
  # whether to drop an event and to report *why* so ingestion loss is
  # observable rather than silent. In the OSS build the only reason is
  # an explicitly paused project (manual or admin pause); per-minute rate
  # limiting is enforced separately by IngestionRateLimiter.
  def drop_reason
    ingestion_paused? ? "ingestion_paused" : nil
  end

  def default_api_key
    api_keys.active.find_by(token: api_key) || api_keys.active.scope_write.order(:created_at).first
  end

  def rotate_default_api_key!
    transaction do
      new_token = "elp_#{SecureRandom.hex(24)}"
      existing = api_keys.find_by(token: api_key)
      update!(api_key: new_token)
      if existing
        existing.update!(token: new_token)
      else
        api_keys.create!(name: "Default", scope: :write, token: new_token)
      end
    end
  end

  private

  def generate_api_key
    self.api_key ||= "elp_#{SecureRandom.hex(24)}"
  end

  def ensure_default_api_key
    return if api_keys.exists?
    api_keys.create!(name: "Default", scope: :write, token: api_key)
  end

  def generate_slug
    return if name.blank? || slug.present?
    base = name.downcase.gsub(/[^a-z0-9]/, "-").squeeze("-").gsub(/\A[-0-9]+/, "").gsub(/-\z/, "")
    base = "project" if base.blank?
    candidate = base
    counter = 1
    while Project.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end
end

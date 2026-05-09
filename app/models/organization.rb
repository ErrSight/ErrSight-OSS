class Organization < ApplicationRecord
  include Discard::Model

  belongs_to :owner, class_name: "User"
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :projects, dependent: :destroy
  has_many :invitations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :slack_webhook_url,
            format: { with: %r{\Ahttps://hooks\.slack\.com/\S+\z}, message: "must be a Slack incoming webhook URL" },
            allow_blank: true

  before_validation :generate_slug, on: :create

  after_discard   { projects.update_all(ingestion_paused: true) }
  after_undiscard { projects.update_all(ingestion_paused: false) }

  # Wrap the whole discard in a transaction so an after_discard callback
  # failure (projects.update_all) rolls back the discarded_at write,
  # preventing a half-discarded org that still accepts ingestion.
  def discard
    self.class.transaction { super }
  end

  def discard!
    self.class.transaction { super }
  end

  def membership_for(user)
    memberships.find_by(user: user)
  end

  def slack_configured?
    slack_webhook_url.present?
  end

  def can_invite?
    true
  end

  def deletable?
    true
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name slug created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[owner memberships projects]
  end

  private

  def generate_slug
    return if name.blank? || slug.present?
    base = name.downcase.gsub(/[^a-z0-9]/, "-").squeeze("-").gsub(/\A[-0-9]+/, "").gsub(/-\z/, "")
    base = "org" if base.blank?
    candidate = base
    counter = 1
    while Organization.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug = candidate
  end
end

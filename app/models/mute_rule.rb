class MuteRule < ApplicationRecord
  belongs_to :project

  validates :fingerprint, presence: true, uniqueness: { scope: :project_id }

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.active_fingerprints_for(project_id)
    active.where(project_id: project_id).pluck(:fingerprint)
  end

  def self.muted?(project_id, fingerprint)
    active.exists?(project_id: project_id, fingerprint: fingerprint)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end

class SavedFilter < ApplicationRecord
  belongs_to :user

  ALLOWED_KEYS = %w[q level environment release tag_key tag_value project_id resolved range].freeze

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :user_id }
  before_validation :sanitize_filters

  def to_params
    filters.slice(*ALLOWED_KEYS)
  end

  private

  def sanitize_filters
    self.filters = (filters || {}).stringify_keys.slice(*ALLOWED_KEYS)
                                  .transform_values { |v| v.to_s.presence }.compact
  end
end

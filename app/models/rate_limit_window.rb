class RateLimitWindow < ApplicationRecord
  validates :key,          presence: true
  validates :window_start, presence: true
  validates :count,        numericality: { greater_than_or_equal_to: 0 }
end

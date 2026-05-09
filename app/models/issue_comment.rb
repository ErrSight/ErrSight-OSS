class IssueComment < ApplicationRecord
  belongs_to :issue
  belongs_to :user, optional: true

  validates :body, presence: true, length: { maximum: 5_000 }

  scope :chronological, -> { order(:created_at) }
end

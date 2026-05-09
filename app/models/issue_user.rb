class IssueUser < ApplicationRecord
  # Membership row: "user X has been seen as user_identifier on this
  # issue's events." The size of this set per-issue is what the
  # affected_users_count column on issues tracks. Maintained by
  # Issue.maintain_aggregates_for_event! via INSERT ... ON CONFLICT
  # DO NOTHING RETURNING — only counted as "new" when the insert
  # actually wrote a row.
  belongs_to :issue
end

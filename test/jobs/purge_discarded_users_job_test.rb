require "test_helper"

class PurgeDiscardedUsersJobTest < ActiveJob::TestCase
  test "destroys users discarded more than 90 days ago" do
    user = users(:regular)
    # In production, PurgeDiscardedOrganizationsJob runs 30 min before this job
    # and has already hard-deleted the user's solo-owned orgs. Simulate that
    # here so owned_organizations.dependent :nullify doesn't trip the NOT NULL
    # owner_id constraint.
    user.owned_organizations.find_each(&:destroy)
    user.update!(discarded_at: 91.days.ago)

    assert_difference -> { User.with_discarded.count }, -1 do
      PurgeDiscardedUsersJob.new.perform
    end

    assert_nil User.with_discarded.find_by(id: user.id)
  end

  test "keeps users discarded within the 90-day window" do
    user = users(:regular)
    user.update!(discarded_at: 89.days.ago)

    assert_no_difference -> { User.with_discarded.count } do
      PurgeDiscardedUsersJob.new.perform
    end

    assert_not_nil User.with_discarded.find_by(id: user.id)
  end

  test "does not touch kept users" do
    user = users(:admin)
    assert_nil user.discarded_at

    PurgeDiscardedUsersJob.new.perform

    assert_not_nil User.find_by(id: user.id)
  end
end

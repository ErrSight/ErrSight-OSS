require "test_helper"

class PurgeDiscardedOrganizationsJobTest < ActiveJob::TestCase
  test "destroys organizations discarded more than 90 days ago" do
    org = organizations(:regular_org)
    org.update!(discarded_at: 91.days.ago)

    assert_difference -> { Organization.with_discarded.count }, -1 do
      PurgeDiscardedOrganizationsJob.new.perform
    end

    assert_nil Organization.with_discarded.find_by(id: org.id)
  end

  test "keeps organizations discarded within the 90-day window" do
    org = organizations(:regular_org)
    org.update!(discarded_at: 89.days.ago)

    assert_no_difference -> { Organization.with_discarded.count } do
      PurgeDiscardedOrganizationsJob.new.perform
    end

    assert_not_nil Organization.with_discarded.find_by(id: org.id)
  end

  test "does not touch kept organizations" do
    org = organizations(:admin_org)
    assert_nil org.discarded_at

    PurgeDiscardedOrganizationsJob.new.perform

    assert_not_nil Organization.find_by(id: org.id)
  end
end

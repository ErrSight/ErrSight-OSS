require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    org = Organization.new(name: "Acme", slug: "acme", owner: users(:regular))
    assert org.valid?
  end

  test "invalid without name" do
    org = Organization.new(slug: "acme", owner: users(:regular))
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "invalid with duplicate slug" do
    Organization.create!(name: "First", slug: "shared", owner: users(:regular))
    dup = Organization.new(name: "Second", slug: "shared", owner: users(:regular))
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "auto-generates slug from name on create" do
    org = Organization.create!(name: "My Cool Org", owner: users(:regular))
    assert_equal "my-cool-org", org.slug
  end

  test "slug-collision counter" do
    Organization.create!(name: "Acme", slug: "acme", owner: users(:regular))
    second = Organization.create!(name: "Acme", owner: users(:regular))
    assert_equal "acme-1", second.slug
  end

  test "validates slack_webhook_url format" do
    org = organizations(:regular_org)
    org.slack_webhook_url = "not-a-slack-url"
    assert_not org.valid?
    assert_includes org.errors[:slack_webhook_url], "must be a Slack incoming webhook URL"
  end

  test "slack_configured? reflects webhook presence" do
    org = organizations(:regular_org)
    assert_not org.slack_configured?
    org.update!(slack_webhook_url: "https://hooks.slack.com/services/T00/B00/abc")
    assert org.slack_configured?
  end

  test "can_invite? is always true (no member cap in OSS)" do
    assert organizations(:regular_org).can_invite?
  end

  test "deletable? is always true (no subscription gate)" do
    assert organizations(:regular_org).deletable?
  end

  test "membership_for returns the user's membership row" do
    org = organizations(:team_org)
    user = users(:team_owner)
    membership = org.memberships.find_or_create_by!(user: user) { |m| m.role = :admin }
    assert_equal membership, org.membership_for(user)
  end

  test "discarded orgs are excluded from kept scope" do
    org = organizations(:regular_org)
    org.discard!
    assert_not Organization.kept.exists?(id: org.id)
  end

  test "after_discard pauses the org's projects" do
    org = organizations(:regular_org)
    project = org.projects.create!(
      name: "Test", user: users(:regular), api_key: "elp_#{SecureRandom.hex(24)}"
    )
    assert_not project.ingestion_paused?
    org.discard!
    assert project.reload.ingestion_paused?
  end

  test "after_undiscard un-pauses the org's projects" do
    org = organizations(:regular_org)
    org.projects.create!(
      name: "Test", user: users(:regular), api_key: "elp_#{SecureRandom.hex(24)}"
    )
    org.discard!
    org.undiscard
    assert org.projects.none?(&:ingestion_paused?)
  end
end

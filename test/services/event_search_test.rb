require "test_helper"

class EventSearchTest < ActiveSupport::TestCase
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
  end

  test "scopes to user's accessible projects only" do
    search = EventSearch.new(@user, {})
    ids    = search.relation.pluck(:project_id).uniq
    assert ids.all? { |id| @user.accessible_projects.pluck(:id).include?(id) }
  end

  test "filters by level" do
    search = EventSearch.new(@user, { level: "error" })
    search.relation.each { |e| assert_equal "error", e.level }
  end

  test "filters by keyword (ILIKE on message)" do
    @project.events.create!(level: "error", message: "Unique needle here",
                            environment: "production", fingerprint: "needle-fp",
                            occurred_at: Time.current, size_bytes: 100)
    search = EventSearch.new(@user, { q: "needle" })
    assert search.relation.any? { |e| e.message.include?("needle") }
  end

  test "filters by range" do
    old = @project.events.create!(level: "error", message: "old", environment: "production",
                                  fingerprint: "old-fp", occurred_at: 10.days.ago, size_bytes: 100)
    search = EventSearch.new(@user, { range: "24h" })
    assert_not_includes search.relation, old
  end

  test "project_id filter falls back to all accessible when unauthorized id given" do
    other = projects(:admin_project)
    search = EventSearch.new(@user, { project_id: other.id })
    assert_not_includes search.scoped_project_ids, other.id
  end

  # ── cross-org scoping ────────────────────────────────────────────────────────

  test "never returns events from projects outside the user's organizations" do
    other_project = projects(:admin_project)
    other_event = other_project.events.create!(
      level: "error", message: "cross-org secret", environment: "production",
      fingerprint: "other-fp", occurred_at: Time.current, size_bytes: 100
    )

    search = EventSearch.new(@user, {})

    assert_not_includes search.relation.pluck(:id), other_event.id
  end

  test "providing a project_id from another org does not leak that org's events" do
    other_project = projects(:admin_project)
    other_event = other_project.events.create!(
      level: "error", message: "forbidden payload", environment: "production",
      fingerprint: "xorg-fp", occurred_at: Time.current, size_bytes: 100
    )

    search = EventSearch.new(@user, { project_id: other_project.id })

    ids = search.relation.pluck(:id)
    assert_not_includes ids, other_event.id
  end

  test "member-role user sees only their org's events" do
    member = users(:member_user)                    # member of team_org
    own_project = projects(:team_project)
    own_event = own_project.events.create!(
      level: "error", message: "own org event", environment: "production",
      fingerprint: "own-fp", occurred_at: Time.current, size_bytes: 100
    )
    other_project = projects(:admin_project)
    other_event = other_project.events.create!(
      level: "error", message: "other org event", environment: "production",
      fingerprint: "other-fp", occurred_at: Time.current, size_bytes: 100
    )

    search = EventSearch.new(member, {})
    ids = search.relation.pluck(:id)

    assert_includes ids, own_event.id
    assert_not_includes ids, other_event.id
  end
end

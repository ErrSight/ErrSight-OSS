require "test_helper"

class EventPolicyTest < ActiveSupport::TestCase
  def policy(user, record)
    EventPolicy.new(user, record)
  end

  def scope(user)
    EventPolicy::Scope.new(user, Event).resolve
  end

  setup do
    @owner  = users(:regular)
    @admin  = users(:admin)
    @other  = users(:over_limit)
    @member = users(:member_user)
    @viewer = users(:viewer_user)
    @event  = events(:error_event)           # belongs to projects(:alpha) → owned by @owner
  end

  # ── index? ────────────────────────────────────────────────────────────────────

  test "index? is always true" do
    assert policy(@owner, Event).index?
    assert policy(@other, Event).index?
    assert policy(@admin, Event).index?
  end

  # ── show? ─────────────────────────────────────────────────────────────────────

  test "show? is true for the project owner" do
    assert policy(@owner, @event).show?
  end

  test "show? is true for admin" do
    assert policy(@admin, @event).show?
  end

  test "show? is false for other users" do
    assert_not policy(@other, @event).show?
  end

  # ── resolve? / unresolve? ────────────────────────────────────────────────────

  test "resolve? is true for project owner" do
    assert policy(@owner, @event).resolve?
  end

  test "resolve? is false for unrelated user" do
    assert_not policy(@other, @event).resolve?
  end

  test "unresolve? is true for project owner" do
    assert policy(@owner, @event).unresolve?
  end

  test "unresolve? is false for unrelated user" do
    assert_not policy(@other, @event).unresolve?
  end

  # ── destroy? ─────────────────────────────────────────────────────────────────

  test "destroy? is true for project owner" do
    assert policy(@owner, @event).destroy?
  end

  test "destroy? is true for admin" do
    assert policy(@admin, @event).destroy?
  end

  test "destroy? is false for unrelated user" do
    assert_not policy(@other, @event).destroy?
  end

  # ── Scope ────────────────────────────────────────────────────────────────────

  test "scope returns events from the user's own projects only" do
    result = scope(@owner)
    assert_includes result, @event
    # admin_project events should not be visible to @owner
    admin_events = projects(:admin_project).events
    admin_events.each do |e|
      assert_not_includes result, e
    end
  end

  test "scope returns all events for admin" do
    result = scope(@admin)
    assert_includes result, @event
  end

  # ── Role boundaries: member / viewer (evaluated against a team_org event) ──

  def team_event
    @team_event ||= projects(:team_project).events.create!(
      level: :error, message: "team event", environment: "production",
      fingerprint: "team-fp", occurred_at: 1.hour.ago, size_bytes: 100
    )
  end

  test "member can view, resolve, and unresolve events" do
    assert policy(@member, team_event).show?
    assert policy(@member, team_event).resolve?
    assert policy(@member, team_event).unresolve?
  end

  test "member cannot destroy events (admin-only)" do
    assert_not policy(@member, team_event).destroy?
  end

  test "viewer can view but cannot resolve, unresolve, or destroy events" do
    assert policy(@viewer, team_event).show?
    assert_not policy(@viewer, team_event).resolve?
    assert_not policy(@viewer, team_event).unresolve?
    assert_not policy(@viewer, team_event).destroy?
  end
end

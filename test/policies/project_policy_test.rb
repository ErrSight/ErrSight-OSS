require "test_helper"

class ProjectPolicyTest < ActiveSupport::TestCase
  def policy(user, record)
    ProjectPolicy.new(user, record)
  end

  def scope(user)
    ProjectPolicy::Scope.new(user, Project).resolve
  end

  setup do
    @owner  = users(:regular)
    @admin  = users(:admin)
    @other  = users(:over_limit)
    @member = users(:member_user)
    @viewer = users(:viewer_user)
    @project = projects(:alpha)            # owned by @owner (regular_org)
    @team_project = projects(:team_project) # team_org — has member/viewer memberships
  end

  # ── index? ────────────────────────────────────────────────────────────────────

  test "index? is true for any user" do
    assert policy(@owner, Project).index?
    assert policy(@other, Project).index?
    assert policy(@admin, Project).index?
  end

  # ── show? ─────────────────────────────────────────────────────────────────────

  test "show? is true for the owner" do
    assert policy(@owner, @project).show?
  end

  test "show? is true for admin" do
    assert policy(@admin, @project).show?
  end

  test "show? is false for another regular user" do
    assert_not policy(@other, @project).show?
  end

  # ── create? / new? ───────────────────────────────────────────────────────────

  test "create? is true for any authenticated user" do
    assert policy(@owner, Project).create?
    assert policy(@other, Project).create?
  end

  test "new? delegates to create?" do
    assert policy(@owner, Project.new).new?
  end

  test "create? denies a viewer-role member of the target org" do
    assert_not policy(@viewer, @team_project).create?
  end

  test "create? allows a member-role member of the target org" do
    assert policy(@member, @team_project).create?
  end

  # ── update? / edit? ──────────────────────────────────────────────────────────

  test "update? is true for the owner" do
    assert policy(@owner, @project).update?
  end

  test "update? is true for admin" do
    assert policy(@admin, @project).update?
  end

  test "update? is false for other users" do
    assert_not policy(@other, @project).update?
  end

  test "edit? delegates to update?" do
    assert policy(@owner, @project).edit?
    assert_not policy(@other, @project).edit?
  end

  # ── destroy? ─────────────────────────────────────────────────────────────────

  test "destroy? is true for the owner" do
    assert policy(@owner, @project).destroy?
  end

  test "destroy? is true for admin" do
    assert policy(@admin, @project).destroy?
  end

  test "destroy? is false for other users" do
    assert_not policy(@other, @project).destroy?
  end

  # ── rotate_api_key? ──────────────────────────────────────────────────────────

  test "rotate_api_key? is true for owner" do
    assert policy(@owner, @project).rotate_api_key?
  end

  test "rotate_api_key? is false for other users" do
    assert_not policy(@other, @project).rotate_api_key?
  end

  # ── Scope ────────────────────────────────────────────────────────────────────

  test "scope returns only the user's own projects for regular users" do
    result = scope(@owner)
    assert_includes result, projects(:alpha)
    assert_includes result, projects(:beta)
    assert_not_includes result, projects(:admin_project)
  end

  test "scope returns all projects for admins" do
    result = scope(@admin)
    assert_includes result, projects(:alpha)
    assert_includes result, projects(:admin_project)
  end

  # ── Role boundaries: member / viewer (evaluated against team_project) ───────

  test "member can view but cannot update or destroy" do
    assert policy(@member, @team_project).show?
    assert_not policy(@member, @team_project).update?
    assert_not policy(@member, @team_project).destroy?
    assert_not policy(@member, @team_project).rotate_api_key?
  end

  test "viewer can view but cannot mutate or trigger write actions" do
    assert policy(@viewer, @team_project).show?
    assert_not policy(@viewer, @team_project).update?
    assert_not policy(@viewer, @team_project).destroy?
    assert_not policy(@viewer, @team_project).rotate_api_key?
    assert_not policy(@viewer, @team_project).resolve_events?
    assert_not policy(@viewer, @team_project).mute_events?
  end

  test "member can resolve, mute, comment, and triage" do
    assert policy(@member, @team_project).resolve_events?
    assert policy(@member, @team_project).mute_events?
    assert policy(@member, @team_project).comment?
    assert policy(@member, @team_project).triage_issues?
  end
end

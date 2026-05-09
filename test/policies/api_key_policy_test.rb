require "test_helper"

class ApiKeyPolicyTest < ActiveSupport::TestCase
  def policy(user, record)
    ApiKeyPolicy.new(user, record)
  end

  setup do
    @admin_in_org  = users(:team_owner)
    @member        = users(:member_user)
    @viewer        = users(:viewer_user)
    @site_admin    = users(:admin)
    @api_key       = projects(:team_project).api_keys.first || projects(:team_project).api_keys.create!(name: "k", scope: :write)
  end

  test "index? allows any org member (admin, member, viewer)" do
    assert policy(@admin_in_org, @api_key).index?
    assert policy(@member,       @api_key).index?
    assert policy(@viewer,       @api_key).index?
  end

  test "index? rejects users outside the org" do
    outsider = users(:over_limit)
    assert_not policy(outsider, @api_key).index?
  end

  test "index? allows site admin" do
    assert policy(@site_admin, @api_key).index?
  end

  test "create? requires org admin — member cannot create" do
    assert policy(@admin_in_org, @api_key).create?
    assert_not policy(@member, @api_key).create?
  end

  test "create? — viewer cannot create" do
    assert_not policy(@viewer, @api_key).create?
  end

  test "destroy? requires org admin — viewer cannot destroy" do
    assert policy(@admin_in_org, @api_key).destroy?
    assert_not policy(@viewer, @api_key).destroy?
    assert_not policy(@member, @api_key).destroy?
  end
end

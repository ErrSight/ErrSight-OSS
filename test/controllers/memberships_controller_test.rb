require "test_helper"

class MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:team_owner)
    @member   = users(:member_user)
    @viewer   = users(:viewer_user)
    @outsider = users(:over_limit)
    @org      = organizations(:team_org)
    @member_membership = memberships(:team_member)
    @viewer_membership = memberships(:team_viewer)
  end

  # ── index ────────────────────────────────────────────────────────────────────

  test "unauthenticated users are redirected" do
    get organization_memberships_path(@org)
    assert_redirected_to new_user_session_path
  end

  test "non-member cannot see org memberships" do
    sign_in @outsider
    get organization_memberships_path(@org)
    assert_redirected_to authenticated_root_path
    assert_match "Organization not found", flash[:alert]
  end

  test "viewer can view memberships index" do
    sign_in @viewer
    get organization_memberships_path(@org)
    assert_response :success
  end

  test "admin can view memberships index" do
    sign_in @admin
    get organization_memberships_path(@org)
    assert_response :success
  end

  # ── update ────────────────────────────────────────────────────────────────────

  test "viewer cannot change member role" do
    sign_in @viewer
    patch organization_membership_path(@org, @member_membership),
          params: { membership: { role: "viewer" } }
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
    assert_equal "member", @member_membership.reload.role
  end

  test "member cannot change another member's role" do
    sign_in @member
    patch organization_membership_path(@org, @viewer_membership),
          params: { membership: { role: "admin" } }
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
    assert_equal "viewer", @viewer_membership.reload.role
  end

  test "admin can promote a viewer to member" do
    sign_in @admin
    patch organization_membership_path(@org, @viewer_membership),
          params: { membership: { role: "member" } }
    assert_redirected_to organization_memberships_path(@org)
    assert_equal "member", @viewer_membership.reload.role
  end

  test "update rejects invalid role" do
    sign_in @admin
    patch organization_membership_path(@org, @viewer_membership),
          params: { membership: { role: "superuser" } }
    assert_response :bad_request
    assert_equal "viewer", @viewer_membership.reload.role
  end

  # ── destroy ───────────────────────────────────────────────────────────────────

  test "viewer cannot remove another member" do
    sign_in @viewer
    assert_no_difference -> { @org.memberships.count } do
      delete organization_membership_path(@org, @member_membership)
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "admin can remove a member" do
    sign_in @admin
    assert_difference -> { @org.memberships.count }, -1 do
      delete organization_membership_path(@org, @member_membership)
    end
    assert_redirected_to organization_memberships_path(@org)
  end

  test "last admin cannot be removed" do
    sign_in @admin
    admin_membership = memberships(:team_owner_admin)
    assert_no_difference -> { @org.memberships.count } do
      delete organization_membership_path(@org, admin_membership)
    end
    assert_response :redirect
  end

  # ── owner protection ─────────────────────────────────────────────────────────
  #
  # The org's owner_id and the billing customer point at the owner; org and
  # project visibility are membership-based. Removing or demoting the owner's
  # membership leaves them as billing customer + owner_id but locks them out
  # of normal access. Block both paths even when there's a *second* admin
  # who could otherwise destroy/demote without tripping `last_admin?`.

  def with_second_admin
    second_admin = User.create!(email: "second_admin@example.com", name: "Second Admin",
                                password: "password123",
                                confirmed_at: Time.current)
    Membership.create!(organization: @org, user: second_admin, role: :admin)
    yield second_admin
  end

  test "second admin cannot remove the owner's membership" do
    with_second_admin do |second_admin|
      sign_in second_admin
      owner_membership = memberships(:team_owner_admin)

      assert_no_difference -> { @org.memberships.count } do
        delete organization_membership_path(@org, owner_membership)
      end
      assert_response :redirect
      assert_match(/not authorized/i, flash[:alert])
    end
  end

  test "second admin cannot demote the owner's role" do
    with_second_admin do |second_admin|
      sign_in second_admin
      owner_membership = memberships(:team_owner_admin)

      patch organization_membership_path(@org, owner_membership),
            params: { membership: { role: "viewer" } }
      assert_response :redirect
      assert_match(/not authorized/i, flash[:alert])
      assert_equal "admin", owner_membership.reload.role
    end
  end

  test "owner row in the team list shows no role select and no remove button" do
    with_second_admin do |second_admin|
      sign_in second_admin
      get organization_memberships_path(@org)
      assert_response :success

      owner_membership = memberships(:team_owner_admin)
      # No form (PATCH or DELETE) targeting the owner's membership.
      assert_no_match(%r{action="/organizations/#{@org.id}/memberships/#{owner_membership.id}"}, response.body)
      # Owner badge is rendered so it's clear why the row has no actions.
      assert_match(/>Owner</, response.body)
    end
  end

  # ── update_weekly_digest ─────────────────────────────────────────────────────

  test "user can toggle their own weekly digest preference" do
    sign_in @member
    own_membership = @member.memberships.find_by(organization: @org)
    assert_not_nil own_membership

    patch toggle_weekly_digest_path(own_membership), params: { weekly_digest_enabled: "1" }
    assert_redirected_to edit_user_registration_path
    assert_equal true, own_membership.reload.weekly_digest_enabled

    patch toggle_weekly_digest_path(own_membership), params: { weekly_digest_enabled: "0" }
    assert_redirected_to edit_user_registration_path
    assert_equal false, own_membership.reload.weekly_digest_enabled
  end

  test "unauthenticated user cannot toggle weekly digest" do
    patch toggle_weekly_digest_path(@member_membership), params: { weekly_digest_enabled: "1" }
    assert_redirected_to new_user_session_path
  end

  test "user cannot toggle another user's weekly digest (IDOR)" do
    sign_in @outsider
    other_membership = @member_membership
    original = other_membership.weekly_digest_enabled

    patch toggle_weekly_digest_path(other_membership), params: { weekly_digest_enabled: "1" }
    assert_response :not_found

    assert_equal original, other_membership.reload.weekly_digest_enabled
  end
end

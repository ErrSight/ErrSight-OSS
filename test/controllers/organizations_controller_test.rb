require "test_helper"

class OrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:regular)
    @org  = organizations(:regular_org)
    sign_in @user
  end

  test "DELETE /organizations/:id is not a defined route" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        organization_path(@org), method: :delete
      )
    end
  end

  test "discarded organization is hidden from the policy scope" do
    @org.discard!
    get organization_path(@org)
    assert_redirected_to authenticated_root_path
    assert_match "not found", flash[:alert]
  end

  # ── activate (org switcher) ─────────────────────────────────────────────────

  test "POST /organizations/:id/activate sets the current organization in session" do
    second = Organization.create!(name: "Second Co", owner: @user)
    Membership.create!(organization: second, user: @user, role: :admin)

    post activate_organization_path(second)

    assert_equal second.id, session[:current_organization_id]
    # Switching always lands on the dashboard so the page re-renders in the
    # newly active org's context (not the page belonging to the previous org).
    assert_redirected_to dashboard_path
    assert_match "Switched to Second Co", flash[:notice]
  end

  test "POST /organizations/:id/activate refuses an org the user is not a member of" do
    foreign = organizations(:admin_org)
    post activate_organization_path(foreign)

    assert_nil session[:current_organization_id]
    assert_redirected_to authenticated_root_path
    assert_match(/not found/i, flash[:alert])
  end

  test "GET /projects/new defaults the org dropdown to the current_organization" do
    second = Organization.create!(name: "Second Co", owner: @user)
    Membership.create!(organization: second, user: @user, role: :admin)
    post activate_organization_path(second)  # switch to Second Co

    get new_project_path
    assert_response :success
    assert_select "select[name='project[organization_id]']" do
      assert_select "option[selected='selected'][value=?]", second.id.to_s
    end
  end

  test "sidebar shows the org switcher (and account menu) whenever the user has an org" do
    # Single-org user: the switcher is present — it doubles as the account menu
    # (account settings / sign out now live in its popover).
    get organization_path(@org)
    assert_response :success
    assert_match(/Switch organization/, response.body)

    # Second org: switcher still present, and its popover lists the other org.
    second = Organization.create!(name: "Second Co", owner: @user)
    Membership.create!(organization: second, user: @user, role: :admin)
    get organization_path(@org)
    assert_response :success
    assert_match(/Switch organization/, response.body)
    assert_match(/Second Co/, response.body)
  end

  # Regression: organizations#new sets @organization to an UNSAVED record (id
  # nil). The sidebar org switcher builds an org-scoped link from the active
  # org, so it must fall back to the persisted current_organization here rather
  # than raise UrlGenerationError on a nil :organization_id.
  test "GET /organizations/new renders even though @organization is unsaved" do
    get new_organization_path
    assert_response :success
    assert_match(/Switch organization/, response.body)
  end
end

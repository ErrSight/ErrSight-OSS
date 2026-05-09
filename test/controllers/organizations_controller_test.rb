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
    assert_redirected_to organization_path(second)
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

  test "sidebar shows the org switcher only when the user has multiple orgs" do
    # Single-org user: no switcher.
    get organization_path(@org)
    assert_response :success
    assert_no_match(/Switch organization/, response.body)

    # Add a second org and the switcher should appear.
    second = Organization.create!(name: "Second Co", owner: @user)
    Membership.create!(organization: second, user: @user, role: :admin)
    get organization_path(@org)
    assert_response :success
    assert_match(/Switch organization/, response.body)
  end
end

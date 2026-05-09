require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "GET /dashboard redirects to sign-in when not authenticated" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET /dashboard succeeds for authenticated user" do
    sign_in users(:regular)
    get dashboard_path
    assert_response :success
  end

  test "GET /dashboard shows the user's projects" do
    sign_in users(:regular)
    get dashboard_path
    assert_response :success
    assert_select "body"
  end

  test "GET /dashboard redirects user with no organization to org-create" do
    sign_in users(:incomplete)
    get dashboard_path
    assert_redirected_to new_organization_path
  end

  test "authenticated root redirects to dashboard" do
    sign_in users(:regular)
    get authenticated_root_path
    assert_response :success
  end

  # The org switcher only feels real if the dashboard's project list actually
  # filters when you flip it. Set up two orgs with one project each, switch,
  # and assert the visible project list narrows.
  test "dashboard projects scope to the current_organization chosen via the switcher" do
    user = users(:regular)
    org_a = organizations(:regular_org)
    org_b = Organization.create!(name: "Sister Co", owner: user, plan: "free")
    Membership.create!(organization: org_b, user: user, role: :admin)

    project_a = Project.create!(organization: org_a, name: "Alpha App", api_key: "elp_#{SecureRandom.hex(24)}", user: user)
    project_b = Project.create!(organization: org_b, name: "Sister App", api_key: "elp_#{SecureRandom.hex(24)}", user: user)

    sign_in user

    # Default: current_organization falls back to first owned, which is org_a.
    get dashboard_path
    assert_response :success
    assert_match project_a.name, response.body
    assert_no_match project_b.name, response.body

    # Flip the switcher to org_b — the dashboard should now show org_b's project.
    post activate_organization_path(org_b)
    get dashboard_path
    assert_response :success
    assert_match project_b.name, response.body
    assert_no_match project_a.name, response.body
  end
end

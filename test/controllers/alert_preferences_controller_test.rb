require "test_helper"

class AlertPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:team_owner)
    @viewer   = users(:viewer_user)
    @outsider = users(:over_limit)
    @org      = organizations(:team_org)
  end

  test "unauthenticated user is redirected" do
    get edit_alert_preference_path(@org)
    assert_redirected_to new_user_session_path
  end

  test "non-member cannot edit preferences for another org" do
    sign_in @outsider
    get edit_alert_preference_path(@org)
    assert_redirected_to authenticated_root_path
    assert_match "Organization not found", flash[:alert]
  end

  test "viewer (member of org) can view edit form" do
    sign_in @viewer
    get edit_alert_preference_path(@org)
    assert_response :success
  end

  test "admin updates org-wide preference" do
    sign_in @admin
    patch alert_preference_path(@org),
          params: { alert_preference: { email_enabled: "0", min_level: 4 } }
    assert_redirected_to edit_alert_preference_path(@org)

    pref = memberships(:team_owner_admin).alert_preferences.find_by(project_id: nil)
    assert_not pref.email_enabled
    assert_equal 4, pref.min_level
  end

  test "update for a project the user owns creates a project-scoped preference" do
    sign_in @admin
    project = projects(:team_project)
    assert_difference -> { memberships(:team_owner_admin).alert_preferences.count }, 1 do
      patch alert_preference_path(@org),
            params: {
              alert_preference: {
                project_id:    project.id,
                email_enabled: "1",
                min_level:     3
              }
            }
    end
    assert_redirected_to edit_alert_preference_path(@org)
  end

  test "cannot create preference for a project from another organization (IDOR)" do
    sign_in @admin
    foreign_project = projects(:alpha) # belongs to regular_org, not team_org

    assert_no_difference -> { memberships(:team_owner_admin).alert_preferences.count } do
      patch alert_preference_path(@org),
            params: {
              alert_preference: {
                project_id:    foreign_project.id,
                email_enabled: "1",
                min_level:     3
              }
            }
    end

    assert_redirected_to edit_alert_preference_path(@org)
    assert_match "Project not found", flash[:alert]
    assert_nil memberships(:team_owner_admin).alert_preferences.find_by(project_id: foreign_project.id)
  end
end

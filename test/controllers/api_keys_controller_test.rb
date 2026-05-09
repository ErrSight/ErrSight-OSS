require "test_helper"

class ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin   = users(:team_owner)       # admin of team_org
    @member  = users(:member_user)
    @viewer  = users(:viewer_user)
    @other   = users(:over_limit)       # no membership in team_org
    @project = projects(:team_project)  # in team_org
  end

  test "unauthenticated users are redirected to sign-in" do
    get project_api_keys_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "cross-org user is redirected to projects index" do
    sign_in @other
    get project_api_keys_path(@project)
    assert_redirected_to projects_path
  end

  test "viewer can list keys (index)" do
    sign_in @viewer
    get project_api_keys_path(@project)
    assert_response :success
  end

  test "member cannot create API key (org_admin? required)" do
    sign_in @member
    assert_no_difference -> { @project.api_keys.count } do
      post project_api_keys_path(@project), params: { api_key: { name: "new", scope: "read" } }
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "viewer cannot create API key" do
    sign_in @viewer
    assert_no_difference -> { @project.api_keys.count } do
      post project_api_keys_path(@project), params: { api_key: { name: "new", scope: "read" } }
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "admin can create API key" do
    sign_in @admin
    assert_difference -> { @project.api_keys.count }, 1 do
      post project_api_keys_path(@project), params: { api_key: { name: "new-key", scope: "read" } }
    end
    assert_redirected_to project_api_keys_path(@project)
  end

  test "destroy requires admin — viewer forbidden" do
    sign_in @viewer
    key = @project.api_keys.create!(name: "ephemeral", scope: :read)
    delete project_api_key_path(@project, key)
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
    assert_nil key.reload.revoked_at
  end

  test "cannot destroy the project's default ingestion key" do
    sign_in @admin
    default_key = @project.default_api_key
    assert default_key, "expected a default key to exist"
    delete project_api_key_path(@project, default_key)
    assert_redirected_to project_api_keys_path(@project)
    assert_nil default_key.reload.revoked_at
    assert_match "Cannot revoke the default", flash[:alert]
  end

  test "admin can revoke a non-default key" do
    sign_in @admin
    key = @project.api_keys.create!(name: "secondary", scope: :read)
    delete project_api_key_path(@project, key)
    assert_redirected_to project_api_keys_path(@project)
    assert key.reload.revoked?
  end
end

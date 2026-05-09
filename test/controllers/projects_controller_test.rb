require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    organizations(:regular_org).memberships.find_or_create_by!(user: @user) { |m| m.role = :admin }
    sign_in @user
  end

  # ── index ────────────────────────────────────────────────────────────────────

  test "GET /projects lists the user's projects" do
    get projects_path
    assert_response :success
  end

  test "GET /projects redirects when not signed in" do
    sign_out @user
    get projects_path
    assert_redirected_to new_user_session_path
  end

  # ── show ─────────────────────────────────────────────────────────────────────

  test "GET /projects/:id shows own project" do
    get project_path(@project)
    assert_response :success
  end

  test "GET /projects/:id redirects when accessing another user's project" do
    get project_path(projects(:admin_project))
    assert_redirected_to projects_path
  end

  # ── new / create ─────────────────────────────────────────────────────────────

  test "GET /projects/new renders form" do
    get new_project_path
    assert_response :success
  end

  test "POST /projects creates a project in the chosen org and redirects to it" do
    org = organizations(:regular_org)
    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "Brand New App", organization_id: org.id } }
    end
    new_project = Project.order(:created_at).last
    assert_equal org.id, new_project.organization_id
    assert_redirected_to project_path(new_project)
    assert_match "created in", flash[:notice]
  end

  test "POST /projects with blank name re-renders new with error" do
    org = organizations(:regular_org)
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "", organization_id: org.id } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /projects without organization_id re-renders new with an error and creates nothing" do
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "Where Does This Land" } }
    end
    assert_response :unprocessable_entity
    assert_match(/organization/i, response.body)
  end

  test "POST /projects rejects an organization_id the user is not a member of" do
    foreign_org = organizations(:admin_org)
    assert_no_difference "Project.count" do
      post projects_path, params: { project: { name: "Trespass", organization_id: foreign_org.id } }
    end
    assert_response :unprocessable_entity
  end

  test "GET /projects/new pre-selects organization from query param" do
    get new_project_path(organization_id: organizations(:regular_org).id)
    assert_response :success
  end

  test "multi-org user sees an organization dropdown on the new form" do
    second_org = Organization.create!(name: "Second Co", owner: @user)
    Membership.create!(organization: second_org, user: @user, role: :admin)

    get new_project_path
    assert_response :success
    assert_select "select[name='project[organization_id]']" do
      assert_select "option", text: "Regular Org"
      assert_select "option", text: "Second Co"
    end
  end

  test "single-org user sees a hidden organization_id, no dropdown" do
    get new_project_path
    assert_response :success
    assert_select "select[name='project[organization_id]']", count: 0
    assert_select "input[type='hidden'][name='project[organization_id]']", count: 1
  end

  # ── edit / update ─────────────────────────────────────────────────────────────

  test "GET /projects/:id/edit renders edit form" do
    get edit_project_path(@project)
    assert_response :success
  end

  test "PATCH /projects/:id updates name and redirects" do
    patch project_path(@project), params: { project: { name: "Updated Name" } }
    assert_redirected_to project_path(@project.reload)
    assert_equal "Updated Name", @project.reload.name
  end

  test "PATCH /projects/:id with blank name re-renders edit" do
    patch project_path(@project), params: { project: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "PATCH /projects/:id cannot update another user's project" do
    patch project_path(projects(:admin_project)), params: { project: { name: "Hijacked" } }
    assert_redirected_to projects_path
  end

  test "PATCH /projects/:id allows updating rate_limit_per_minute" do
    patch project_path(@project), params: { project: { rate_limit_per_minute: 250 } }
    assert_redirected_to project_path(@project.reload)
    assert_equal 250, @project.reload.rate_limit_per_minute
  end

  test "PATCH /projects/:id accepts 0 to disable rate limiting" do
    patch project_path(@project), params: { project: { rate_limit_per_minute: 0 } }
    assert_redirected_to project_path(@project.reload)
    assert_equal 0, @project.reload.rate_limit_per_minute
  end

  test "PATCH /projects/:id rejects negative rate_limit_per_minute" do
    original = @project.rate_limit_per_minute
    patch project_path(@project), params: { project: { rate_limit_per_minute: -1 } }
    assert_response :unprocessable_entity
    assert_equal original, @project.reload.rate_limit_per_minute
  end

  test "PATCH /projects/:id rejects blank rate_limit_per_minute" do
    original = @project.rate_limit_per_minute
    patch project_path(@project), params: { project: { rate_limit_per_minute: "" } }
    assert_response :unprocessable_entity
    assert_equal original, @project.reload.rate_limit_per_minute
  end

  # ── destroy ──────────────────────────────────────────────────────────────────

  test "DELETE /projects/:id destroys the project" do
    assert_difference "Project.count", -1 do
      delete project_path(@project)
    end
    assert_redirected_to projects_path
  end

  test "DELETE /projects/:id cannot destroy another user's project" do
    assert_no_difference "Project.count" do
      delete project_path(projects(:admin_project))
    end
    assert_redirected_to projects_path
  end

  # ── rotate_api_key ────────────────────────────────────────────────────────────

  test "POST /projects/:id/rotate_api_key generates a new key" do
    old_key = @project.api_key
    post rotate_api_key_project_path(@project)
    assert_not_equal old_key, @project.reload.api_key
    assert_match(/\Aelp_[a-f0-9]{48}\z/, @project.reload.api_key)
    assert_redirected_to project_path(@project)
  end

  test "POST /projects/:id/rotate_api_key cannot rotate another user's key" do
    old_key = projects(:admin_project).api_key
    post rotate_api_key_project_path(projects(:admin_project))
    assert_equal old_key, projects(:admin_project).reload.api_key
  end

  # ── time_series ──────────────────────────────────────────────────────────────

  test "GET /projects/:id/time_series returns JSON for own project" do
    get time_series_project_path(@project)
    assert_response :success
    assert_equal "application/json", response.media_type
  end

  test "GET /projects/:id/time_series redirects when accessing another user's project" do
    get time_series_project_path(projects(:admin_project))
    assert_redirected_to projects_path
  end

  test "GET /projects/:id/time_series returns 404 JSON for out-of-scope project when requested as JSON" do
    get time_series_project_path(projects(:admin_project)), as: :json
    assert_response :not_found
  end
end

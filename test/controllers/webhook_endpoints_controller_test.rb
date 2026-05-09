require "test_helper"

class WebhookEndpointsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:team_owner)
    @member   = users(:member_user)
    @viewer   = users(:viewer_user)
    @outsider = users(:over_limit)
    @project  = projects(:team_project)
  end

  test "unauthenticated user redirected" do
    get project_webhook_endpoints_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "outsider cannot access another org's webhooks" do
    sign_in @outsider
    get project_webhook_endpoints_path(@project)
    assert_redirected_to projects_path
  end

  test "viewer can view index" do
    sign_in @viewer
    get project_webhook_endpoints_path(@project)
    assert_response :success
  end

  test "viewer cannot create" do
    sign_in @viewer
    assert_no_difference -> { @project.webhook_endpoints.count } do
      post project_webhook_endpoints_path(@project),
           params: { webhook_endpoint: { url: "https://hooks.example.com/x" } }
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "member cannot create (update? requires admin)" do
    sign_in @member
    assert_no_difference -> { @project.webhook_endpoints.count } do
      post project_webhook_endpoints_path(@project),
           params: { webhook_endpoint: { url: "https://hooks.example.com/x" } }
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "admin can create a webhook endpoint" do
    sign_in @admin
    assert_difference -> { @project.webhook_endpoints.count }, 1 do
      post project_webhook_endpoints_path(@project),
           params: { webhook_endpoint: { url: "https://hooks.example.com/new" } }
    end
    assert_redirected_to project_webhook_endpoints_path(@project)
  end

  test "admin can destroy webhook endpoint" do
    sign_in @admin
    endpoint = @project.webhook_endpoints.create!(url: "https://hooks.example.com/del")
    assert_difference -> { @project.webhook_endpoints.count }, -1 do
      delete project_webhook_endpoint_path(@project, endpoint)
    end
    assert_redirected_to project_webhook_endpoints_path(@project)
  end

  test "viewer cannot destroy webhook endpoint" do
    endpoint = @project.webhook_endpoints.create!(url: "https://hooks.example.com/del")
    sign_in @viewer
    assert_no_difference -> { @project.webhook_endpoints.count } do
      delete project_webhook_endpoint_path(@project, endpoint)
    end
    assert_response :redirect
  end
end

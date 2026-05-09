require "test_helper"

class DataErasuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    sign_in @user
  end

  test "GET new renders form for org admin" do
    get new_project_data_erasure_path(@project)
    assert_response :success
    assert_match "Erase user data", response.body
  end

  test "POST create deletes only events matching user_identifier" do
    keep = @project.events.create!(
      message: "keep", level: :error, occurred_at: 1.hour.ago,
      fingerprint: "keep-fp", user_identifier: "other@example.com"
    )
    erase = @project.events.create!(
      message: "erase", level: :error, occurred_at: 1.hour.ago,
      fingerprint: "erase-fp", user_identifier: "target@example.com"
    )

    post project_data_erasure_path(@project), params: { user_identifier: "target@example.com" }
    assert_redirected_to project_path(@project)
    assert_nil Event.find_by(id: erase.id)
    assert Event.exists?(keep.id)
  end

  test "POST create with missing identifier redirects back with alert" do
    post project_data_erasure_path(@project), params: { user_identifier: " " }
    assert_redirected_to new_project_data_erasure_path(@project)
    assert_match "Provide a user identifier", flash[:alert]
  end

  test "POST create with no matching events redirects back with alert" do
    post project_data_erasure_path(@project), params: { user_identifier: "nobody@example.com" }
    assert_redirected_to new_project_data_erasure_path(@project)
    assert_match "No events found", flash[:alert]
  end

  test "cannot erase on another org's project" do
    post project_data_erasure_path(projects(:admin_project)), params: { user_identifier: "x" }
    assert_redirected_to projects_path
  end
end

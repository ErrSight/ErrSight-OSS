require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "GET / renders landing page without authentication" do
    get root_path
    assert_response :success
  end

  test "GET / redirects authenticated users to the dashboard" do
    user = users(:regular)
    organizations(:regular_org).memberships.find_or_create_by!(user: user) { |m| m.role = :admin }
    sign_in user
    get root_path
    assert_response :redirect
  end

  test "GET /docs renders without authentication" do
    get docs_path
    assert_response :success
  end

  test "GET /integrations renders without authentication" do
    get integrations_path
    assert_response :success
  end

  test "GET /support renders without authentication" do
    get support_path
    assert_response :success
  end

  test "GET /privacy renders without authentication" do
    get privacy_path
    assert_response :success
  end

  test "GET /terms renders without authentication" do
    get terms_path
    assert_response :success
  end
end

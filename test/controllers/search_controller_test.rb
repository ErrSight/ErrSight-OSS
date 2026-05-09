require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:regular)
    sign_in @user
  end

  test "GET /search returns success" do
    get search_path
    assert_response :success
  end

  test "GET /search with filters returns success" do
    get search_path(q: "needle", level: "error", range: "24h")
    assert_response :success
  end

  test "POST /saved_filters creates named filter" do
    assert_difference "SavedFilter.count", 1 do
      post saved_filters_path, params: { name: "Errors 24h", filters: { level: "error", range: "24h" } }
    end
    assert_redirected_to search_path(level: "error", range: "24h")
  end

  test "DELETE /saved_filters/:id removes filter" do
    sf = @user.saved_filters.create!(name: "tmp", filters: { level: "error" })
    assert_difference "SavedFilter.count", -1 do
      delete saved_filter_path(sf)
    end
  end

  test "user cannot delete another user's saved filter" do
    other_user = users(:admin)
    other = other_user.saved_filters.create!(name: "other", filters: { level: "error" })
    assert_no_difference "SavedFilter.count" do
      delete saved_filter_path(other)
    end
  end
end

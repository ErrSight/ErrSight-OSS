require "test_helper"

class SavedFiltersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:regular)
  end

  test "unauthenticated users cannot create" do
    post saved_filters_path, params: { name: "fav", filters: { level: "error" } }
    assert_redirected_to new_user_session_path
  end

  test "creates a saved filter for the current user" do
    sign_in @user
    assert_difference -> { @user.saved_filters.count }, 1 do
      post saved_filters_path, params: {
        name: "Errors this week",
        filters: { level: "error", range: "7d" }
      }
    end
    filter = @user.saved_filters.order(:created_at).last
    assert_equal({ "level" => "error", "range" => "7d" }, filter.filters)
  end

  test "rejects keys outside ALLOWED_KEYS (mass-assignment protection)" do
    sign_in @user
    post saved_filters_path, params: {
      name: "bad",
      filters: { level: "error", malicious_key: "injection", user_id: 9999 }
    }
    filter = @user.saved_filters.order(:created_at).last
    assert_not_includes filter.filters.keys, "malicious_key"
    assert_not_includes filter.filters.keys, "user_id"
    assert_includes filter.filters.keys, "level"
  end

  test "destroy only affects current user's filters (no cross-user IDOR)" do
    sign_in @user
    mine = @user.saved_filters.create!(name: "mine", filters: { level: "error" })
    others_user = users(:admin)
    theirs = others_user.saved_filters.create!(name: "theirs", filters: { level: "error" })

    delete saved_filter_path(theirs)
    assert_redirected_to search_path
    assert SavedFilter.exists?(theirs.id), "other user's filter must not be deleted"
    assert SavedFilter.exists?(mine.id)

    delete saved_filter_path(mine)
    assert_not SavedFilter.exists?(mine.id)
  end
end

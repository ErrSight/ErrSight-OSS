require "test_helper"

class SavedFilterTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular)
  end

  test "strips unknown keys from filters" do
    sf = @user.saved_filters.create!(name: "Prod errors",
                                     filters: { "level" => "error", "malicious" => "drop" })
    assert_equal "error", sf.filters["level"]
    assert_nil sf.filters["malicious"]
  end

  test "rejects duplicate names per user" do
    @user.saved_filters.create!(name: "Dup", filters: { level: "error" })
    dup = @user.saved_filters.build(name: "Dup", filters: { level: "error" })
    assert_not dup.valid?
  end

  test "to_params returns only allowed keys" do
    sf = @user.saved_filters.create!(name: "Any", filters: { level: "error", project_id: "1" })
    params = sf.to_params
    assert_equal %w[level project_id].sort, params.keys.sort
  end
end

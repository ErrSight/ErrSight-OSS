require "test_helper"

class ItemsQueryTest < ActiveSupport::TestCase
  test "parses key:value tokens and free keyword" do
    q = ItemsQuery.parse("level:error env:prod is:unresolved checkout timeout")
    assert_equal %w[error], q.levels
    assert_equal %w[prod], q.environments
    assert_equal %w[unresolved], q.statuses
    assert_equal "checkout timeout", q.keyword
  end

  test "ignores unknown keys, folding them into the keyword" do
    q = ItemsQuery.parse("bogus:thing real text")
    assert_empty q.tokens
    assert_equal "bogus:thing real text", q.keyword
  end

  test "normalises the warn alias to warning" do
    assert_equal %w[warning], ItemsQuery.parse("level:warn").levels
  end

  test "empty? is true for a blank query" do
    assert ItemsQuery.parse("").empty?
    assert ItemsQuery.parse(nil).empty?
    assert_not ItemsQuery.parse("is:muted").empty?
  end

  test "chips expose key, value, raw and a tone" do
    chips = ItemsQuery.parse("level:error env:prod is:unresolved assigned:me").chips
    assert_equal "is-level",  chips[0][:tone]
    assert_equal "is-env",    chips[1][:tone]
    assert_equal "is-status", chips[2][:tone]
    assert_equal "is-status", chips[3][:tone]
    assert_equal "level:error", chips[0][:raw]
  end

  test "toggle adds a missing token and removes a present one" do
    assert_equal "level:error env:prod", ItemsQuery.parse("level:error").toggle("env", "prod")
    assert_equal "level:error",          ItemsQuery.parse("level:error env:prod").toggle("env", "prod")
  end

  test "round-trips through to_s" do
    assert_equal "level:error is:unresolved boom", ItemsQuery.parse("level:error is:unresolved boom").to_s
  end
end

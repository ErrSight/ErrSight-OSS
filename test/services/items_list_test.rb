require "test_helper"
require "ostruct"

class ItemsListTest < ActiveSupport::TestCase
  setup { @user = users(:regular) }

  # Mirrors the OpenStruct shape returned by EventRepository.grouped_by_fingerprint.
  def group(attrs = {})
    OpenStruct.new({
      fingerprint: "fp", last_environment: "production", last_message: "Boom",
      severity: 3, occurrences: 10, affected_users: 2,
      all_resolved: false, any_resolved: false, muted: false,
      last_seen: Time.current, first_seen: Time.current
    }.merge(attrs))
  end

  def build(groups, **opts)
    ItemsList.new(groups: groups, issues: {}, query: ItemsQuery.parse(opts.delete(:q).to_s), user: @user, **opts)
  end

  test "default sort is last seen, newest first" do
    older = group(fingerprint: "a", last_seen: 2.hours.ago)
    newer = group(fingerprint: "b", last_seen: 1.minute.ago)
    assert_equal %w[b a], build([ older, newer ]).rows.map(&:fingerprint)
  end

  test "sorts by events ascending when asked" do
    big   = group(fingerprint: "big", occurrences: 100)
    small = group(fingerprint: "small", occurrences: 2)
    assert_equal %w[small big], build([ big, small ], sort: "events", dir: "asc").rows.map(&:fingerprint)
  end

  test "filters by level token" do
    err  = group(fingerprint: "e", severity: 3)
    warn = group(fingerprint: "w", severity: 2)
    assert_equal %w[w], build([ err, warn ], q: "level:warning").rows.map(&:fingerprint)
  end

  test "unresolved view hides resolved and muted groups" do
    open = group(fingerprint: "o", all_resolved: false)
    done = group(fingerprint: "d", all_resolved: true)
    mute = group(fingerprint: "m", muted: true)
    assert_equal %w[o], build([ open, done, mute ], view: "unresolved").rows.map(&:fingerprint)
  end

  test "paginates in memory" do
    groups = 30.times.map { |i| group(fingerprint: "fp#{i}", last_seen: i.minutes.ago) }
    list = build(groups, per: 25, page: 2)
    assert_equal 5, list.rows.size
    assert_equal 30, list.total
    assert_equal 2, list.pager[:pages]
    assert_equal 26, list.pager[:from]
  end

  test "saved-view counts ignore the active view" do
    open = group(fingerprint: "o", all_resolved: false)
    done = group(fingerprint: "d", all_resolved: true)
    list = build([ open, done ], view: "unresolved")
    assert_equal 1, list.saved_views.find { |v| v[:id] == "unresolved" }[:count]
  end

  test "level facet counts over the view-scoped set" do
    list = build([ group(fingerprint: "e", severity: 3), group(fingerprint: "w", severity: 2) ], view: "all")
    levels = list.facets[:level]
    assert_equal 1, levels.find { |f| f[:id] == "error" }[:count]
    assert_equal 1, levels.find { |f| f[:id] == "warning" }[:count]
  end
end

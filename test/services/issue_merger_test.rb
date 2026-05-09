require "test_helper"

class IssueMergerTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "merges duplicates into the oldest issue and repoints events + aggregates" do
    canonical = Issue.create!(project: @project, fingerprint: "fp-keep",
                              first_seen_at: 10.days.ago, last_seen_at: 9.days.ago,
                              occurrences_count: 1, severity: 3)
    dup = Issue.create!(project: @project, fingerprint: "fp-dup",
                        first_seen_at: 2.days.ago, last_seen_at: 1.day.ago,
                        occurrences_count: 1, severity: 4)
    @project.events.create!(level: "error", message: "keep ev", environment: "production",
                            fingerprint: "fp-keep", occurred_at: 9.days.ago, size_bytes: 100, user_identifier: "u1")
    @project.events.create!(level: "fatal", message: "dup ev", environment: "staging",
                            fingerprint: "fp-dup", occurred_at: 1.day.ago, size_bytes: 100, user_identifier: "u2")

    result = IssueMerger.call(project: @project, fingerprints: [ "fp-keep", "fp-dup" ])

    assert_equal 2, result.merged_count
    assert_equal "fp-keep", result.canonical_fingerprint # earliest first_seen_at wins
    assert_equal 1, result.events_moved

    assert_nil Issue.find_by(project: @project, fingerprint: "fp-dup")
    assert_equal 0, @project.events.where(fingerprint: "fp-dup").count
    assert_equal 2, @project.events.where(fingerprint: "fp-keep").count

    canonical.reload
    assert_equal 2, canonical.occurrences_count
    assert_equal 2, canonical.affected_users_count # u1 + u2 unioned
    assert_equal 4, canonical.severity             # max(error=3, fatal=4)
  end

  test "moves comments from merged issues onto the canonical" do
    canonical = Issue.create!(project: @project, fingerprint: "fp-keep2", first_seen_at: 5.days.ago)
    dup       = Issue.create!(project: @project, fingerprint: "fp-dup2", first_seen_at: 1.day.ago)
    @project.events.create!(level: "error", message: "k", environment: "production",
                            fingerprint: "fp-keep2", occurred_at: 5.days.ago, size_bytes: 100)
    @project.events.create!(level: "error", message: "d", environment: "production",
                            fingerprint: "fp-dup2", occurred_at: 1.day.ago, size_bytes: 100)
    comment = dup.comments.create!(body: "looking into this", user: users(:regular))

    IssueMerger.call(project: @project, fingerprints: [ "fp-keep2", "fp-dup2" ])

    assert_equal canonical.id, comment.reload.issue_id
  end

  test "inherits assignment from a merged issue when the canonical is unassigned" do
    canonical = Issue.create!(project: @project, fingerprint: "fp-k3", first_seen_at: 5.days.ago)
    Issue.create!(project: @project, fingerprint: "fp-d3", first_seen_at: 1.day.ago,
                  assigned_to_id: users(:regular).id)
    @project.events.create!(level: "error", message: "k", environment: "production",
                            fingerprint: "fp-k3", occurred_at: 5.days.ago, size_bytes: 100)
    @project.events.create!(level: "error", message: "d", environment: "production",
                            fingerprint: "fp-d3", occurred_at: 1.day.ago, size_bytes: 100)

    IssueMerger.call(project: @project, fingerprints: [ "fp-k3", "fp-d3" ])

    assert_equal users(:regular).id, canonical.reload.assigned_to_id
  end

  test "returns nil when fewer than two real issues resolve" do
    assert_nil IssueMerger.call(project: @project, fingerprints: [ "only-one" ])

    Issue.create!(project: @project, fingerprint: "solo", first_seen_at: 1.day.ago)
    assert_nil IssueMerger.call(project: @project, fingerprints: [ "solo", "ghost-fp" ])
  end
end

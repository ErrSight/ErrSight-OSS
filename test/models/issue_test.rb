require "test_helper"

class IssueTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "unique per (project, fingerprint)" do
    Issue.create!(project: @project, fingerprint: "uniq-fp")
    dup = Issue.new(project: @project, fingerprint: "uniq-fp")
    assert_not dup.valid?
  end

  test "rejects invalid external_url" do
    issue = Issue.new(project: @project, fingerprint: "fp", external_url: "notaurl")
    assert_not issue.valid?
  end

  test "accepts http(s) external_url" do
    issue = Issue.new(project: @project, fingerprint: "fp", external_url: "https://github.com/x/y/issues/1")
    assert issue.valid?
  end

  test "find_or_init_by! returns existing record when already present" do
    Issue.create!(project: @project, fingerprint: "xx")
    assert_no_difference "Issue.count" do
      Issue.find_or_init_by!(@project, "xx")
    end
  end

  test "reconcile_aggregates_for_fingerprints! is a no-op with empty input" do
    assert_nothing_raised do
      Issue.reconcile_aggregates_for_fingerprints!(project_id: @project.id, fingerprints: [])
      Issue.reconcile_aggregates_for_fingerprints!(project_id: @project.id, fingerprints: nil)
    end
  end

  test "reconcile_aggregates_for_fingerprints! zeros an issue whose events are all gone" do
    event = @project.events.create!(
      level: :error, message: "bye", fingerprint: "fp-rec-zero",
      occurred_at: 1.hour.ago, size_bytes: 100, user_identifier: "u1"
    )
    issue = Issue.find_by!(project: @project, fingerprint: "fp-rec-zero")
    assert_equal 1, issue.occurrences_count
    assert_equal 1, issue.affected_users_count

    # Bypass the after_commit callback so the issues row stays stale,
    # mimicking what delete_all does in the hard-delete paths.
    Event.where(id: event.id).delete_all

    Issue.reconcile_aggregates_for_fingerprints!(
      project_id: @project.id, fingerprints: [ "fp-rec-zero" ]
    )

    issue.reload
    assert_equal 0, issue.occurrences_count
    assert_equal 0, issue.resolved_count
    assert_equal 0, issue.affected_users_count
    refute issue.issue_users.exists?
  end

  test "reconcile_aggregates_for_fingerprints! recomputes from remaining events" do
    @project.events.create!(
      level: :info, message: "old low", fingerprint: "fp-rec-mix",
      occurred_at: 3.hours.ago, size_bytes: 50, user_identifier: "u1"
    )
    keeper = @project.events.create!(
      level: :error, message: "new high", fingerprint: "fp-rec-mix",
      occurred_at: 10.minutes.ago, environment: "production",
      size_bytes: 80, user_identifier: "u2"
    )
    old_low = @project.events.where(fingerprint: "fp-rec-mix").where.not(id: keeper.id).first
    Event.where(id: old_low.id).delete_all

    Issue.reconcile_aggregates_for_fingerprints!(
      project_id: @project.id, fingerprints: [ "fp-rec-mix" ]
    )

    issue = Issue.find_by!(project: @project, fingerprint: "fp-rec-mix")
    assert_equal 1, issue.occurrences_count
    assert_equal Event.levels[:error], issue.severity
    assert_equal "new high", issue.last_message
    assert_equal "production", issue.last_environment
    assert_equal 1, issue.affected_users_count
    assert issue.issue_users.exists?(user_identifier: "u2")
    refute issue.issue_users.exists?(user_identifier: "u1")
  end
end

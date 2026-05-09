require "test_helper"

class EventTest < ActiveSupport::TestCase
  include StubHelper

  # ── Validations ──────────────────────────────────────────────────────────────

  test "valid with required attributes" do
    event = projects(:alpha).events.build(message: "Test error", level: :error)
    assert event.valid?
  end

  test "invalid without message" do
    event = projects(:alpha).events.build(message: "", level: :error)
    assert_not event.valid?
    assert event.errors[:message].any?
  end

  test "invalid without level" do
    event = projects(:alpha).events.build(message: "Test")
    event.level = nil
    assert_not event.valid?
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  test "sets occurred_at to current time when blank" do
    event = projects(:alpha).events.build(message: "Test", level: :info)
    freeze_time do
      event.valid?
      assert_in_delta Time.current.to_i, event.occurred_at.to_i, 1
    end
  end

  test "does not overwrite an explicit occurred_at" do
    past = 3.days.ago
    event = projects(:alpha).events.build(message: "Test", level: :info, occurred_at: past)
    event.valid?
    assert_in_delta past.to_i, event.occurred_at.to_i, 1
  end

  test "sets fingerprint automatically before validation" do
    event = projects(:alpha).events.build(message: "NilClass error at line 42", level: :error)
    event.valid?
    assert_match(/\A[0-9a-f]{32}\z/, event.fingerprint)
  end

  test "same message and backtrace produce the same fingerprint" do
    attrs = { message: "Identical error", level: :error, backtrace: "app/foo.rb:10" }
    e1 = projects(:alpha).events.build(attrs)
    e2 = projects(:alpha).events.build(attrs)
    e1.valid?
    e2.valid?
    assert_equal e1.fingerprint, e2.fingerprint
  end

  test "different messages produce different fingerprints" do
    e1 = projects(:alpha).events.build(message: "Error A", level: :error)
    e2 = projects(:alpha).events.build(message: "Error B", level: :error)
    e1.valid?
    e2.valid?
    assert_not_equal e1.fingerprint, e2.fingerprint
  end

  test "legacy fingerprint is byte-identical to the pre-v2 hash" do
    # Guard against accidental drift: any change to the legacy hash format
    # would invalidate every fingerprint already in the database, scattering
    # existing issues into "new" issues with no occurrences. This test
    # pins the exact hash for a known input.
    e = projects(:alpha).events.build(
      message:   "ActiveRecord::RecordNotFound",
      backtrace: "/app/app/models/user.rb:42:in 'find'",
      level:     :error
    )
    e.valid?
    expected = Digest::SHA256.hexdigest(
      "ActiveRecord::RecordNotFound|/app/app/models/user.rb:42:in 'find'"
    )[0, 32]
    assert_equal expected, e.fingerprint
  end

  test "v2 fingerprint uses exception_class + top in_app frame when present" do
    e = projects(:alpha).events.build(
      message:  "User 42 not found",
      level:    :error,
      metadata: {
        "exception_class" => "ActiveRecord::RecordNotFound",
        "exception_frames" => [
          { "filename" => "/gems/activerecord/relation.rb", "function" => "first", "in_app" => false },
          { "filename" => "app/controllers/users_controller.rb", "function" => "show", "in_app" => true },
          { "filename" => "app/models/user.rb", "function" => "find_by_id", "in_app" => true }
        ]
      }
    )
    e.valid?
    expected = Digest::SHA256.hexdigest(
      "v2|ActiveRecord::RecordNotFound|app/controllers/users_controller.rb|show"
    )[0, 32]
    assert_equal expected, e.fingerprint
  end

  test "v2 fingerprint groups same-site errors with varying messages" do
    # The whole point of the v2 hash: "User 42 not found" and "User 99
    # not found" are the same crash, not two different issues.
    base_metadata = {
      "exception_class" => "ActiveRecord::RecordNotFound",
      "exception_frames" => [
        { "filename" => "app/controllers/users_controller.rb", "function" => "show", "in_app" => true }
      ]
    }
    e1 = projects(:alpha).events.build(message: "User 42 not found", level: :error, metadata: base_metadata)
    e2 = projects(:alpha).events.build(message: "User 99 not found", level: :error, metadata: base_metadata)
    e1.valid?
    e2.valid?
    assert_equal e1.fingerprint, e2.fingerprint
  end

  test "v2 fingerprint splits same-message errors at different sites" do
    # And the converse: identical messages at unrelated code sites should
    # NOT collide — the legacy hash got this wrong.
    e1 = projects(:alpha).events.build(
      message: "undefined method `foo'", level: :error,
      metadata: {
        "exception_class"  => "NoMethodError",
        "exception_frames" => [ { "filename" => "app/models/post.rb", "function" => "publish", "in_app" => true } ]
      }
    )
    e2 = projects(:alpha).events.build(
      message: "undefined method `foo'", level: :error,
      metadata: {
        "exception_class"  => "NoMethodError",
        "exception_frames" => [ { "filename" => "app/models/comment.rb", "function" => "approve", "in_app" => true } ]
      }
    )
    e1.valid?
    e2.valid?
    assert_not_equal e1.fingerprint, e2.fingerprint
  end

  test "v2 path falls through when no in_app frame is present" do
    # All-framework stack: nothing actionable to fingerprint on. Fall back
    # to the legacy hash so we still produce some fingerprint.
    e = projects(:alpha).events.build(
      message: "boom", level: :error, backtrace: "/gems/foo/bar.rb:1:in 'bar'",
      metadata: {
        "exception_class"  => "RuntimeError",
        "exception_frames" => [ { "filename" => "/gems/foo/bar.rb", "function" => "bar", "in_app" => false } ]
      }
    )
    e.valid?
    legacy_expected = Digest::SHA256.hexdigest("boom|/gems/foo/bar.rb:1:in 'bar'")[0, 32]
    assert_equal legacy_expected, e.fingerprint
  end

  # ── Enum ─────────────────────────────────────────────────────────────────────

  test "level enum has correct integer mappings" do
    assert_equal 0, Event.levels[:debug]
    assert_equal 1, Event.levels[:info]
    assert_equal 2, Event.levels[:warning]
    assert_equal 3, Event.levels[:error]
    assert_equal 4, Event.levels[:fatal]
  end

  # ── resolve! / unresolve! ────────────────────────────────────────────────────

  test "resolve! marks event as resolved" do
    event = events(:error_event)
    assert_not event.resolved?
    event.resolve!
    assert event.reload.resolved?
  end

  test "unresolve! marks event as unresolved" do
    event = events(:resolved_event)
    assert event.resolved?
    event.unresolve!
    assert_not event.reload.resolved?
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  test "unresolved scope excludes resolved events" do
    scope = projects(:alpha).events.unresolved
    assert_includes scope, events(:error_event)
    assert_not_includes scope, events(:resolved_event)
  end

  test "resolved scope excludes unresolved events" do
    scope = projects(:alpha).events.resolved
    assert_includes scope, events(:resolved_event)
    assert_not_includes scope, events(:error_event)
  end

  test "for_environment filters by environment" do
    staging = projects(:alpha).events.for_environment("staging")
    assert_includes staging, events(:staging_event)
    assert_not_includes staging, events(:error_event)
  end

  test "for_environment is a no-op when blank" do
    all_count = projects(:alpha).events.kept.count
    assert_equal all_count, projects(:alpha).events.kept.for_environment("").count
  end

  test "for_level filters by level" do
    errors = projects(:alpha).events.for_level("error")
    assert_includes errors, events(:error_event)
    assert_not_includes errors, events(:resolved_event)
  end

  test "for_keyword matches message case-insensitively" do
    matches = projects(:alpha).events.for_keyword("something went wrong")
    assert_includes matches, events(:error_event)
    assert_not_includes matches, events(:resolved_event)
  end

  test "recent scope orders by occurred_at descending" do
    occurred_ats = projects(:alpha).events.kept.recent.pluck(:occurred_at)
    assert_equal occurred_ats.sort.reverse, occurred_ats
  end

  test "kept scope excludes discarded events" do
    kept = projects(:alpha).events.kept
    assert_not_includes kept, events(:discarded_event)
    assert_includes kept, events(:error_event)
  end

  # ── estimated_size_bytes ─────────────────────────────────────────────────────

  test "estimated_size_bytes returns a positive integer" do
    event = projects(:alpha).events.build(
      message: "Some message", level: :info, backtrace: "app/foo.rb:5",
      metadata: { key: "value" }
    )
    event.valid?
    assert event.estimated_size_bytes > 0
  end

  # ── grouped_by_fingerprint ────────────────────────────────────────────────────

  test "grouped_by_fingerprint returns one row per unique fingerprint" do
    groups = Event.grouped_by_fingerprint(projects(:alpha).id)
    fingerprints = groups.map(&:fingerprint)
    assert_equal fingerprints.uniq.length, fingerprints.length
  end

  test "grouped_by_fingerprint counts occurrences correctly" do
    project = projects(:alpha)
    fp = "unique000000000a"
    2.times { project.events.create!(message: "Dup error", level: :error, fingerprint: fp) }

    groups = Event.grouped_by_fingerprint(project.id)
    group  = groups.find { |g| g.fingerprint == fp }
    assert group
    assert_equal 2, group.occurrences
  end

  test "grouped_by_fingerprint filters by environment" do
    groups = Event.grouped_by_fingerprint(projects(:alpha).id, environment: "staging")
    assert groups.all? { |g|
      projects(:alpha).events.where(fingerprint: g.fingerprint, environment: "staging").exists?
    }
  end

  test "grouped_by_fingerprint excludes discarded events" do
    groups = Event.grouped_by_fingerprint(projects(:alpha).id)
    discarded_fp = events(:discarded_event).fingerprint
    assert_nil groups.find { |g| g.fingerprint == discarded_fp }
  end

  test "grouped_by_fingerprint returns the actually-most-recent message, not the lexicographically largest" do
    # Regression for the original-audit MAX(message) bug. With MAX(message)
    # the group's "last_message" was whatever string sorted highest in the
    # alphabet, not the most recent occurrence. Verify the array_agg
    # ordering produces the chronologically-correct message.
    project = projects(:alpha)
    fp = "msgordertest0001"
    project.events.create!(
      message: "Zzz earlier (sorts high)", level: :error, fingerprint: fp,
      occurred_at: 1.hour.ago
    )
    project.events.create!(
      message: "Aaa latest (sorts low)", level: :error, fingerprint: fp,
      occurred_at: 1.minute.ago
    )

    groups = Event.grouped_by_fingerprint(project.id)
    group = groups.find { |g| g.fingerprint == fp }
    assert group, "test fingerprint not found"
    assert_equal "Aaa latest (sorts low)", group.last_message
  end

  # ── Issue aggregate maintenance (after_create_commit) ───────────────────────

  test "after_create_commit materializes Issue with correct first/last/occurrence aggregate" do
    project = projects(:alpha)
    fp = "agg_maintenance_001"
    t1 = 2.hours.ago
    t2 = 1.hour.ago
    t3 = 5.minutes.ago

    project.events.create!(message: "first",  level: :error, fingerprint: fp, occurred_at: t1)
    project.events.create!(message: "middle", level: :error, fingerprint: fp, occurred_at: t2)
    project.events.create!(message: "latest", level: :fatal, fingerprint: fp, occurred_at: t3)

    issue = Issue.find_by!(project_id: project.id, fingerprint: fp)
    assert_equal 3,        issue.occurrences_count
    assert_in_delta t1.to_f, issue.first_seen_at.to_f, 1.0
    assert_in_delta t3.to_f, issue.last_seen_at.to_f,  1.0
    assert_equal "latest", issue.last_message,              "should reflect the most recent message"
    assert_equal Event.levels[:fatal], issue.severity, "severity is highest level ever seen"
  end

  test "backdated event does not move last_seen_at backwards" do
    project = projects(:alpha)
    fp = "agg_backdate_002"

    # Latest first.
    project.events.create!(message: "latest", level: :error, fingerprint: fp, occurred_at: 5.minutes.ago)
    # Then a backdated retry.
    project.events.create!(message: "retry-of-old", level: :error, fingerprint: fp, occurred_at: 2.hours.ago)

    issue = Issue.find_by!(project_id: project.id, fingerprint: fp)
    assert_equal 2, issue.occurrences_count
    # last_seen and last_message stay pinned to the actually-most-recent occurrence.
    assert_equal "latest", issue.last_message
    # first_seen moves earlier to capture the backdated event.
    assert_in_delta 2.hours.ago.to_f, issue.first_seen_at.to_f, 1.0
  end

  test "affected_users_count counts unique user_identifiers, not duplicates" do
    project = projects(:alpha)
    fp = "agg_users_003"

    project.events.create!(message: "x", level: :error, fingerprint: fp, occurred_at: Time.current, user_identifier: "u-1")
    project.events.create!(message: "x", level: :error, fingerprint: fp, occurred_at: Time.current, user_identifier: "u-2")
    project.events.create!(message: "x", level: :error, fingerprint: fp, occurred_at: Time.current, user_identifier: "u-1") # duplicate user

    issue = Issue.find_by!(project_id: project.id, fingerprint: fp)
    assert_equal 3, issue.occurrences_count
    assert_equal 2, issue.affected_users_count, "two distinct users despite three events"
  end

  test "resolve_group flips issue.resolved_count to occurrences_count" do
    project = projects(:alpha)
    fp = "agg_resolve_004"
    3.times { project.events.create!(message: "x", level: :error, fingerprint: fp, occurred_at: Time.current) }

    EventRepository.resolve_group(project: project, fingerprint: fp)
    issue = Issue.find_by!(project_id: project.id, fingerprint: fp)
    assert_equal 3, issue.resolved_count
    assert issue.all_resolved?
    assert issue.any_resolved?

    EventRepository.unresolve_group(project: project, fingerprint: fp)
    assert_equal 0, issue.reload.resolved_count
    refute issue.any_resolved?
  end

  test "Issue.rebuild_all_aggregates! is idempotent and self-correcting" do
    project = projects(:alpha)
    fp = "agg_rebuild_005"
    project.events.create!(message: "x", level: :error, fingerprint: fp, occurred_at: 1.hour.ago)
    project.events.create!(message: "y", level: :error, fingerprint: fp, occurred_at: 5.minutes.ago)

    issue = Issue.find_by!(project_id: project.id, fingerprint: fp)
    # Simulate drift: counters out of sync with reality.
    issue.update_columns(occurrences_count: 999, last_message: "wrong", affected_users_count: 50)

    Issue.rebuild_all_aggregates!

    issue.reload
    assert_equal 2, issue.occurrences_count
    assert_equal "y", issue.last_message
    assert_equal 0,  issue.affected_users_count, "no user_identifier on these events"

    # Running again must produce identical state (idempotent).
    before = issue.attributes.except("updated_at")
    Issue.rebuild_all_aggregates!
    after = issue.reload.attributes.except("updated_at")
    assert_equal before, after, "rebuild should be idempotent"
  end

  # ── TimescaleDB integration ──────────────────────────────────────────────────

  test "chunk_info delegates to TimescaleStats.chunk_for" do
    event = events(:error_event)
    sentinel = { chunk_name: "_hyper_1_test_chunk", is_compressed: false }
    captured = nil
    stub_method(TimescaleStats, :chunk_for, ->(e) { captured = e; sentinel }) do
      assert_equal sentinel, event.chunk_info
    end
    assert_equal event, captured
  end

  test "chunk_info returns a real chunk hash for a persisted event" do
    event = events(:error_event)
    TimescaleStats.clear_cache
    info = event.chunk_info
    assert info.is_a?(Hash)
    assert info[:chunk_name].present?
    assert info[:range_start] <= event.occurred_at
    assert info[:range_end]   >  event.occurred_at
  end

  test "compressed? delegates to TimescaleStats.compressed?" do
    event = events(:error_event)
    stub_method(TimescaleStats, :compressed?, true) do
      assert_equal true, event.compressed?
    end
    stub_method(TimescaleStats, :compressed?, false) do
      assert_equal false, event.compressed?
    end
  end

  test "compressed? is false for a freshly-inserted event (chunk too young to compress)" do
    event = events(:error_event)
    TimescaleStats.clear_cache
    assert_equal false, event.compressed?
  end
end

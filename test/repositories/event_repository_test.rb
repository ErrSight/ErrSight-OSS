require "test_helper"

class EventRepositoryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
    @org     = @project.organization
  end

  # -- Writes ----------------------------------------------------------------

  test "build_for returns unsaved event with size_bytes set" do
    event = EventRepository.build_for(
      project: @project,
      attributes: { level: :error, message: "boom", fingerprint: "fp-build" }
    )
    assert_nil event.id
    assert_operator event.size_bytes, :>, 0
  end

  test "persist_new! saves event and accumulates storage bytes" do
    @project.update!(events_count: 0, storage_bytes: 0)
    event = EventRepository.build_for(
      project: @project,
      attributes: { level: :error, message: "x", fingerprint: "fp-persist" }
    )

    EventRepository.persist_new!(event)

    assert event.persisted?
    @project.reload
    # events_count is informational; ProcessEventJob doesn't increment it.
    assert_equal 0, @project.events_count
    assert_operator @project.storage_bytes, :>, 0
  end

  test "persist_new! marks prior resolved events as regression" do
    @project.events.create!(
      level: :error, message: "first", fingerprint: "fp-regression",
      occurred_at: 1.day.ago, resolved: true, size_bytes: 100
    )

    new_event = EventRepository.build_for(
      project: @project,
      attributes: { level: :error, message: "again", fingerprint: "fp-regression" }
    )
    EventRepository.persist_new!(new_event)

    assert new_event.is_regression?
    # All prior events in the group flipped back to unresolved:
    assert_equal 0, @project.events.where(fingerprint: "fp-regression", resolved: true).count
  end

  test "resolve_group and unresolve_group flip the whole fingerprint group" do
    3.times do |i|
      @project.events.create!(
        level: :error, message: "g#{i}", fingerprint: "fp-group",
        occurred_at: i.hours.ago, resolved: false, size_bytes: 100
      )
    end

    EventRepository.resolve_group(project: @project, fingerprint: "fp-group")
    assert_equal 3, @project.events.where(fingerprint: "fp-group", resolved: true).count

    EventRepository.unresolve_group(project: @project, fingerprint: "fp-group")
    assert_equal 0, @project.events.where(fingerprint: "fp-group", resolved: true).count
  end

  test "prune_older_than! deletes and returns [count, bytes]" do
    @project.events.create!(
      level: :error, message: "old", fingerprint: "fp-old",
      occurred_at: 10.days.ago, size_bytes: 500
    )
    @project.events.create!(
      level: :error, message: "fresh", fingerprint: "fp-fresh",
      occurred_at: 1.day.ago, size_bytes: 100
    )

    count, bytes = EventRepository.prune_older_than!(
      project_id: @project.id,
      cutoff: 3.days.ago
    )

    assert_equal 1, count
    assert_equal 500, bytes
    assert @project.events.where(fingerprint: "fp-fresh").exists?
    refute @project.events.where(fingerprint: "fp-old").exists?
  end

  test "delete_oldest_for_project! removes N oldest kept events" do
    5.times do |i|
      @project.events.create!(
        level: :error, message: "o#{i}", fingerprint: "fp-oldest-#{i}",
        occurred_at: (10 - i).days.ago, size_bytes: 50
      )
    end

    count, bytes = EventRepository.delete_oldest_for_project!(
      project_id: @project.id,
      limit: 2
    )

    assert_equal 2, count
    assert_equal 100, bytes
  end

  test "erase_by_user_identifier! removes events for that user and returns stats" do
    @project.events.create!(
      level: :error, message: "mine", fingerprint: "fp-user-a",
      occurred_at: 1.hour.ago, user_identifier: "user-a", size_bytes: 100
    )
    @project.events.create!(
      level: :error, message: "mine 2", fingerprint: "fp-user-a",
      occurred_at: 2.hours.ago, user_identifier: "user-a", size_bytes: 200
    )
    @project.events.create!(
      level: :error, message: "other", fingerprint: "fp-other",
      occurred_at: 1.hour.ago, user_identifier: "user-b", size_bytes: 100
    )

    count, bytes = EventRepository.erase_by_user_identifier!(
      project_id: @project.id,
      user_identifier: "user-a"
    )

    assert_equal 2, count
    assert_equal 300, bytes
    assert @project.events.where(user_identifier: "user-b").exists?
  end

  # -- Reads -----------------------------------------------------------------

  test "find returns event by id or nil" do
    event = @project.events.create!(
      level: :error, message: "findable", fingerprint: "fp-find",
      occurred_at: 1.hour.ago, size_bytes: 100
    )

    assert_equal event.id, EventRepository.find(event.id)&.id
    assert_nil EventRepository.find(-1)
  end

  test "kept_for excludes discarded events" do
    discarded = events(:discarded_event)
    refute_includes EventRepository.kept_for(@project).pluck(:id), discarded.id
  end

  test "filtered composes scopes correctly" do
    scope = EventRepository.filtered(
      project: @project,
      environment: "production",
      level: "error"
    )
    ids = scope.pluck(:id)
    assert_includes ids, events(:error_event).id
    refute_includes ids, events(:staging_event).id
    refute_includes ids, events(:discarded_event).id
  end

  test "filtered applies resolved boolean" do
    resolved_scope   = EventRepository.filtered(project: @project, resolved: true).pluck(:id)
    unresolved_scope = EventRepository.filtered(project: @project, resolved: false).pluck(:id)
    assert_includes resolved_scope,   events(:resolved_event).id
    refute_includes unresolved_scope, events(:resolved_event).id
  end

  test "digest_for returns events above cutoff and level" do
    @project.events.create!(
      level: :error, message: "recent high", fingerprint: "fp-d1",
      occurred_at: 10.minutes.ago, size_bytes: 100
    )
    @project.events.create!(
      level: :info, message: "recent low", fingerprint: "fp-d2",
      occurred_at: 10.minutes.ago, size_bytes: 100
    )
    @project.events.create!(
      level: :error, message: "old high", fingerprint: "fp-d3",
      occurred_at: 2.hours.ago, size_bytes: 100
    )

    msgs = EventRepository.digest_for(
      project: @project, since: 1.hour.ago, min_level: Event.levels[:error]
    ).pluck(:message)

    assert_includes msgs, "recent high"
    refute_includes msgs, "recent low"
    refute_includes msgs, "old high"
  end

  test "exists_for_fingerprint? and first_occurrence? behave correctly" do
    a = @project.events.create!(
      level: :error, message: "a", fingerprint: "fp-fo",
      occurred_at: 1.hour.ago, size_bytes: 100
    )

    assert EventRepository.exists_for_fingerprint?(project: @project, fingerprint: "fp-fo")
    refute EventRepository.exists_for_fingerprint?(project: @project, fingerprint: "nope")

    assert EventRepository.first_occurrence?(project: @project, fingerprint: "fp-fo", except_id: a.id)
    @project.events.create!(
      level: :error, message: "b", fingerprint: "fp-fo",
      occurred_at: 30.minutes.ago, size_bytes: 100
    )
    refute EventRepository.first_occurrence?(project: @project, fingerprint: "fp-fo", except_id: a.id)
  end

  test "count_in_window counts events within a time window for a fingerprint" do
    @project.events.create!(
      level: :error, message: "in window", fingerprint: "fp-win",
      occurred_at: 5.minutes.ago, size_bytes: 100
    )
    @project.events.create!(
      level: :error, message: "out of window", fingerprint: "fp-win",
      occurred_at: 2.hours.ago, size_bytes: 100
    )

    assert_equal 1, EventRepository.count_in_window(
      project: @project, fingerprint: "fp-win", since: 1.hour.ago
    )
  end

  test "issue_summary aggregates fingerprint stats" do
    @project.events.create!(
      level: :error, message: "first", fingerprint: "fp-summary",
      occurred_at: 3.hours.ago, user_identifier: "u1", size_bytes: 100
    )
    @project.events.create!(
      level: :fatal, message: "latest", fingerprint: "fp-summary",
      occurred_at: 5.minutes.ago, user_identifier: "u2", size_bytes: 100
    )

    summary = EventRepository.issue_summary(project: @project, fingerprint: "fp-summary")
    assert_equal 2, summary[:occurrences]
    assert_equal 2, summary[:affected_users]
    assert_equal "latest", summary[:last_message]
    assert_equal "fatal",  summary[:level]
    refute summary[:all_resolved]
  end

  test "environments_for and releases_for return distinct values" do
    @project.events.create!(
      level: :error, message: "rel", fingerprint: "fp-rel",
      occurred_at: 1.hour.ago, environment: "staging", release: "v1.0.0", size_bytes: 100
    )

    envs = EventRepository.environments_for(@project)
    assert_includes envs, "production"
    assert_includes envs, "staging"

    rels = EventRepository.releases_for(@project)
    assert_includes rels, "v1.0.0"
  end

  test "monthly_usage_rows returns rows grouped by month" do
    rows = EventRepository.monthly_usage_rows(project: @project).to_a
    assert rows.all? { |r| r.respond_to?(:month) && r.respond_to?(:cnt) && r.respond_to?(:bytes) }
  end

  test "time_series_counts groups by bucket and level" do
    now   = Time.current
    start = 2.hours.ago
    rows  = EventRepository.time_series_counts(
      project:      @project,
      start_time:   start,
      end_time:     now,
      bucket_unit: "hour"
    )
    assert rows.all? { |bucket, level, count| bucket.is_a?(Time) && level.is_a?(Integer) && count.is_a?(Integer) }
  end

  test "time_series_counts rejects invalid bucket_unit" do
    assert_raises(ArgumentError) do
      EventRepository.time_series_counts(
        project: @project, start_time: 1.hour.ago, end_time: Time.current,
        bucket_unit: "minute"
      )
    end
  end

  # Guards the dashboard's recent-events feed against an N+1 on event.project.
  # Without preloading, rendering 10 events from 10 distinct projects fires
  # 10 extra SELECTs as the view calls event.project.name/slug.
  test "recent_across_projects preloads :project to avoid N+1 in the dashboard view" do
    events = EventRepository.recent_across_projects(projects: Project.all, limit: 10)
    events.each do |event|
      assert event.association(:project).loaded?,
        "expected event##{event.id}.project to be eager-loaded"
    end
  end
end

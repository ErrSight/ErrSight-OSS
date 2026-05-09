require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    @event   = events(:error_event)
    sign_in @user
  end

  # ── index ────────────────────────────────────────────────────────────────────

  test "GET /projects/:id/events returns success" do
    get project_events_path(@project)
    assert_response :success
  end

  test "GET /projects/:id/events filters by environment" do
    get project_events_path(@project, environment: "staging")
    assert_response :success
  end

  test "GET /projects/:id/events filters by level" do
    get project_events_path(@project, level: "error")
    assert_response :success
  end

  test "GET /projects/:id/events cannot access another user's project" do
    get project_events_path(projects(:admin_project))
    assert_redirected_to projects_path
  end

  test "GET /projects/:id/events shows only unresolved by default" do
    get project_events_path(@project)
    assert_response :success
  end

  test "GET /projects/:id/events?resolved=true shows resolved events" do
    get project_events_path(@project, resolved: "true")
    assert_response :success
  end

  # ── groups ───────────────────────────────────────────────────────────────────

  test "GET /projects/:id/events/groups returns success" do
    get groups_project_events_path(@project)
    assert_response :success
  end

  test "GET /projects/:id/events/groups filters by environment" do
    get groups_project_events_path(@project, environment: "production")
    assert_response :success
  end

  # ── logs ─────────────────────────────────────────────────────────────────────

  test "GET /projects/:id/events/logs returns success" do
    get logs_project_events_path(@project)
    assert_response :success
  end

  test "GET /projects/:id/events/logs with keyword returns success" do
    get logs_project_events_path(@project, q: "something")
    assert_response :success
  end

  # ── show ─────────────────────────────────────────────────────────────────────

  test "GET /projects/:project_id/events/:id shows event" do
    get project_event_path(@project, @event)
    assert_response :success
  end

  # ── resolve ──────────────────────────────────────────────────────────────────

  test "PATCH /events/:id/resolve marks event resolved and redirects" do
    assert_not @event.resolved?
    patch resolve_project_event_path(@project, @event)
    assert @event.reload.resolved?
    assert_redirected_to project_events_path(@project)
  end

  test "PATCH /events/:id/resolve cannot resolve event belonging to another user" do
    other_event = events(:error_event)
    sign_out @user
    sign_in users(:admin)
    # admin_project event — use admin
    sign_out users(:admin)
    sign_in users(:regular)
    # regular user cannot access admin's project events
    get project_events_path(projects(:admin_project))
    assert_redirected_to projects_path
  end

  # ── unresolve ────────────────────────────────────────────────────────────────

  test "PATCH /events/:id/unresolve marks event unresolved and redirects" do
    event = events(:resolved_event)
    assert event.resolved?
    patch unresolve_project_event_path(@project, event)
    assert_not event.reload.resolved?
    assert_redirected_to project_events_path(@project)
  end

  # ── bulk resolve by fingerprint ──────────────────────────────────────────────

  test "PATCH resolve_group resolves all kept events with the given fingerprint" do
    fp = @event.fingerprint
    @project.events.create!(
      level: "error", message: "dup", environment: "production",
      fingerprint: fp, occurred_at: Time.current, size_bytes: 100
    )

    patch resolve_group_project_events_path(@project, fingerprint: fp)
    assert_redirected_to groups_project_events_path(@project)
    assert_equal 2, @project.events.where(fingerprint: fp, resolved: true).count
  end

  test "PATCH unresolve_group reopens all events with the given fingerprint" do
    event = events(:resolved_event)
    patch unresolve_group_project_events_path(@project, fingerprint: event.fingerprint)
    assert_redirected_to groups_project_events_path(@project)
    assert_not event.reload.resolved?
  end

  test "resolve_group with blank fingerprint is a no-op" do
    before = @project.events.where(resolved: true).count
    patch resolve_group_project_events_path(@project, fingerprint: "")
    assert_equal before, @project.events.where(resolved: true).count
  end

  test "resolve_group cannot affect events of another user's project" do
    patch resolve_group_project_events_path(projects(:admin_project), fingerprint: "anything")
    assert_redirected_to projects_path
  end

  # ── mute/unmute ──────────────────────────────────────────────────────────────

  test "POST mute_group creates a mute rule for the fingerprint" do
    fp = @event.fingerprint
    assert_difference "MuteRule.count", 1 do
      post mute_group_project_events_path(@project, fingerprint: fp)
    end
    assert MuteRule.muted?(@project.id, fp)
    assert_redirected_to groups_project_events_path(@project)
  end

  test "POST mute_group is idempotent for the same fingerprint" do
    fp = @event.fingerprint
    post mute_group_project_events_path(@project, fingerprint: fp)
    assert_no_difference "MuteRule.count" do
      post mute_group_project_events_path(@project, fingerprint: fp)
    end
  end

  test "DELETE unmute_group removes the mute rule" do
    fp = @event.fingerprint
    @project.mute_rules.create!(fingerprint: fp)
    assert_difference "MuteRule.count", -1 do
      delete unmute_group_project_events_path(@project, fingerprint: fp)
    end
    assert_not MuteRule.muted?(@project.id, fp)
  end

  test "grouped_by_fingerprint hides muted groups by default" do
    @project.mute_rules.create!(fingerprint: @event.fingerprint, hide_from_issues: true)
    groups = Event.grouped_by_fingerprint(@project.id)
    assert_not_includes groups.map(&:fingerprint), @event.fingerprint
  end

  test "grouped_by_fingerprint includes muted groups when include_muted: true" do
    @project.mute_rules.create!(fingerprint: @event.fingerprint, hide_from_issues: true)
    groups = Event.grouped_by_fingerprint(@project.id, include_muted: true)
    muted = groups.find { |g| g.fingerprint == @event.fingerprint }
    assert muted
    assert muted.muted
  end

  test "grouped_by_fingerprint counts distinct affected users" do
    fp = @event.fingerprint
    @event.update!(user_identifier: "user-1")
    @project.events.create!(level: "error", message: "dup", environment: "production",
                            fingerprint: fp, occurred_at: Time.current, size_bytes: 100,
                            user_identifier: "user-2")
    @project.events.create!(level: "error", message: "dup", environment: "production",
                            fingerprint: fp, occurred_at: Time.current, size_bytes: 100,
                            user_identifier: "user-1")

    group = Event.grouped_by_fingerprint(@project.id).find { |g| g.fingerprint == fp }
    assert_equal 2, group.affected_users
  end

  test "events index filters by release" do
    @event.update!(release: "v2.0.0")
    other = @project.events.create!(level: "error", message: "other", environment: "production",
                                    fingerprint: "other", occurred_at: Time.current, size_bytes: 100,
                                    release: "v1.0.0")
    get project_events_path(@project, release: "v2.0.0")
    assert_response :success
    assert_includes response.body, @event.message
    assert_not_includes response.body, other.message
  end

  test "events index filters by tag key/value" do
    @event.update!(tags: { "component" => "auth" })
    other = @project.events.create!(level: "error", message: "billing-error", environment: "production",
                                    fingerprint: "fp-billing", occurred_at: Time.current, size_bytes: 100,
                                    tags: { "component" => "billing" })
    get project_events_path(@project, tag_key: "component", tag_value: "auth")
    assert_response :success
    assert_includes response.body, @event.message
    assert_not_includes response.body, other.message
  end

  # ── destroy ──────────────────────────────────────────────────────────────────

  test "DELETE /events/:id soft-deletes the event" do
    assert_no_difference "Event.count" do
      delete project_event_path(@project, @event)
    end
    assert @event.reload.discarded?
    assert_redirected_to project_events_path(@project)
  end

  test "soft-deleted events are excluded from kept scope" do
    delete project_event_path(@project, @event)
    assert_not_includes @project.events.kept, @event
  end

  # ── authentication ────────────────────────────────────────────────────────────

  test "all event routes require authentication" do
    sign_out @user
    get project_events_path(@project)
    assert_redirected_to new_user_session_path
  end
end

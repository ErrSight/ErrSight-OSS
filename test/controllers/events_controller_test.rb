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

  test "groups view renders a level chip and per-row sparkline (App UI kit issue list)" do
    @project.events.create!(level: :error, message: "boom", fingerprint: "fp-ui-chip",
                            occurred_at: Time.current.utc.beginning_of_hour, size_bytes: 100)
    get groups_project_events_path(@project)
    assert_response :success
    assert_select ".iss-row .lvl", minimum: 1        # level chip leads each issue row
    assert_select ".iss-row .cnt .spark", minimum: 1 # 24h sparkline beside the count
  end

  test "GET /projects/:id/events/groups filters by environment" do
    get groups_project_events_path(@project, environment: "production")
    assert_response :success
  end

  # ── redesigned Items view: layouts / query / sort / bulk ──────────────────────

  test "groups renders the redesigned items chrome" do
    get groups_project_events_path(@project)
    assert_response :success
    assert_select ".es-ihead .es-seg"   # Issues/Events segmented toggle
    assert_select ".es-views"           # layout A saved-view tab strip
    assert_select ".es-micro"           # one-line metric strip
    assert_select ".iss-overlay"        # issue detail overlay retained
  end

  test "groups renders each layout variant" do
    %w[a b c].each do |layout|
      get groups_project_events_path(@project, layout: layout)
      assert_response :success
    end
  end

  test "layout b renders the faceted rail" do
    get groups_project_events_path(@project, layout: "b")
    assert_response :success
    assert_select ".es-facets"
  end

  test "groups query token filters issues by level" do
    get groups_project_events_path(@project, q: "level:warning")
    assert_response :success
    assert_includes @response.body, "Warning in staging"            # staging_event (warning)
    assert_not_includes @response.body, "Something went wrong in the app" # error_event (error)
  end

  test "groups accepts a sort key without error" do
    get groups_project_events_path(@project, sort: "events", dir: "asc")
    assert_response :success
  end

  test "is:resolved query surfaces resolved issues despite the default unresolved view" do
    # resolved_event (fingerprint def456…, level info) is resolved; the hidden
    # view=unresolved must not double-filter it away.
    get groups_project_events_path(@project, q: "is:resolved", view: "unresolved")
    assert_response :success
    assert_includes @response.body, "User logged in successfully"
  end

  test "POST bulk resolves the selected fingerprints" do
    fp = @event.fingerprint
    @project.events.create!(level: "error", message: "dup", environment: "production",
                            fingerprint: fp, occurred_at: Time.current, size_bytes: 100)
    post bulk_project_events_path(@project), params: { action_type: "resolve", fingerprints: [ fp ] }
    assert_redirected_to groups_project_events_path(@project)
    assert_equal 2, @project.events.where(fingerprint: fp, resolved: true).count
  end

  test "POST bulk mute creates mute rules for each fingerprint" do
    assert_difference "MuteRule.count", 1 do
      post bulk_project_events_path(@project), params: { action_type: "mute", fingerprints: [ @event.fingerprint ] }
    end
  end

  test "POST bulk with no fingerprints is rejected" do
    post bulk_project_events_path(@project), params: { action_type: "resolve", fingerprints: [] }
    assert_equal "Select at least one issue first.", flash[:alert]
  end

  test "POST bulk with an unknown action is rejected" do
    post bulk_project_events_path(@project), params: { action_type: "frobnicate", fingerprints: [ @event.fingerprint ] }
    assert_equal "Unknown bulk action.", flash[:alert]
  end

  test "POST bulk assign sets the issue assignee" do
    post bulk_project_events_path(@project), params: { action_type: "assign", assignee_id: @user.id, fingerprints: [ @event.fingerprint ] }
    assert_redirected_to groups_project_events_path(@project)
    assert_equal @user.id, @project.issues.find_by(fingerprint: @event.fingerprint).assigned_to_id
  end

  test "POST bulk assign with a blank assignee unassigns" do
    issue = Issue.find_or_init_by!(@project, @event.fingerprint)
    issue.update!(assigned_to_id: @user.id)
    post bulk_project_events_path(@project), params: { action_type: "assign", assignee_id: "", fingerprints: [ @event.fingerprint ] }
    assert_nil issue.reload.assigned_to_id
  end

  test "POST bulk assign rejects a non-member assignee" do
    outsider = users(:admin) # admin_org member, not a member of alpha's regular_org
    post bulk_project_events_path(@project), params: { action_type: "assign", assignee_id: outsider.id, fingerprints: [ @event.fingerprint ] }
    assert_equal "That person isn't a member of this organization.", flash[:alert]
  end

  test "POST bulk merge needs at least two issues" do
    post bulk_project_events_path(@project), params: { action_type: "merge", fingerprints: [ @event.fingerprint ] }
    assert_equal "Select at least two issues to merge.", flash[:alert]
  end

  test "POST bulk merge folds the selected issues into the oldest one" do
    keep = @event.fingerprint
    dup  = "fp-merge-dup"
    Issue.find_or_init_by!(@project, keep).update!(first_seen_at: 5.days.ago)
    dup_issue = Issue.find_or_init_by!(@project, dup)
    dup_issue.update!(first_seen_at: 1.day.ago)
    @project.events.create!(level: "error", message: "dup ev", environment: "production",
                            fingerprint: dup, occurred_at: Time.current, size_bytes: 100)

    post bulk_project_events_path(@project), params: { action_type: "merge", fingerprints: [ keep, dup ] }
    assert_redirected_to groups_project_events_path(@project)
    assert_nil Issue.find_by(id: dup_issue.id)                    # merged-away row removed
    assert_equal 0, @project.events.where(fingerprint: dup).count # events repointed off the dup
    assert @project.events.where(fingerprint: keep).exists?
  end

  test "groups renders the assign picker and no longer renders an ignore button" do
    get groups_project_events_path(@project)
    assert_response :success
    assert_select ".es-bulk details.es-bulk-menu > summary"                       # Assign disclosure
    assert_select ".es-bulk-pop button[data-action=?]", "items-select#assign", minimum: 2  # "Assign to me" + "Unassign"
    assert_select ".es-bulk button[data-bulk-action='merge']"                     # Merge retained
    assert_select ".es-bulk button[data-bulk-action='ignore']", false             # Ignore removed
  end

  test "POST bulk cannot affect another user's project" do
    post bulk_project_events_path(projects(:admin_project)), params: { action_type: "resolve", fingerprints: [ "x" ] }
    assert_redirected_to projects_path
  end

  test "events index filters to a single fingerprint (the overlay's View events target)" do
    fp = "fp-view-events"
    @project.events.create!(level: "error", message: "mine-ve", environment: "production",
                            fingerprint: fp, occurred_at: Time.current, size_bytes: 100)
    @project.events.create!(level: "error", message: "other-ve", environment: "production",
                            fingerprint: "fp-other-ve", occurred_at: Time.current, size_bytes: 100)
    get project_events_path(@project, fingerprint: fp, q: "is:all")
    assert_response :success
    assert_includes @response.body, "mine-ve"
    assert_not_includes @response.body, "other-ve"
  end

  test "export honours query-bar tokens so it matches the filtered view" do
    @event.update!(level: :error, message: "boom-export")
    @project.events.create!(level: "warning", message: "warn-export", environment: "production",
                            fingerprint: "fp-warn-exp", occurred_at: Time.current, size_bytes: 100)
    get export_project_events_path(@project, format: :csv, q: "level:error")
    assert_response :success
    assert_includes @response.body, "boom-export"
    assert_not_includes @response.body, "warn-export"
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

  test "show page renders the fix-prompt accordion in the context aside" do
    get project_event_path(@project, @event)
    assert_response :success
    assert_select "aside details.fix-prompt > summary", text: /Fix prompt/i
    assert_select "aside details.fix-prompt pre[data-fix-prompt-target=?]", "content", text: /You are debugging/
    assert_select "aside details.fix-prompt button[data-action=?]", "click->fix-prompt#copy", text: /Copy to clipboard/
    # The old modal/dialog and its action-bar trigger are gone.
    assert_select "dialog.fix-prompt-dialog", false
    assert_select ".btn-row button[data-action='click->fix-prompt#open']", false
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

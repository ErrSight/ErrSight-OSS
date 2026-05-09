class EventsController < ApplicationController
  require "csv"

  EXPORT_MAX = 10_000

  # Scoping is enforced by set_project (only finds projects owned by current_user),
  # so Pundit's policy_scope is intentionally not used here.
  skip_after_action :verify_policy_scoped

  before_action :set_project
  before_action :set_event, only: [ :show, :resolve, :unresolve, :destroy ]

  # Events mode of the unified Items view: the dense, single-line raw stream.
  # Still honours the legacy filter params (environment/level/release/resolved/
  # tag) so existing links and tests keep working; the query bar layers on top
  # via the `q` token string.
  def index
    authorize Event
    resolve_items_view
    @pagy, @events = pagy(filtered_events_scope.order(occurred_at: :desc), items: @per)
    @environments = EventRepository.environments_for(@project)
    @releases     = EventRepository.releases_for(@project)
    @metrics      = items_metrics
    @facets       = events_facets(environment: params[:environment].presence || @items_query.environments.first,
                                  level: params[:level].presence || @items_query.levels.first)
    @saved_views  = events_saved_views
  end

  # Issues mode of the unified Items view (default landing). Loads the full set
  # of fingerprint groups and lets ItemsList filter/sort/paginate them in
  # memory (see ItemsList for why that's appropriate at our scale).
  def groups
    authorize Event, :index?
    resolve_items_view

    all_groups = EventRepository.grouped_by_fingerprint(
      project_id: @project.id, environment: nil, include_muted: true
    )
    @issues_by_fingerprint = @project.issues
                                     .where(fingerprint: all_groups.map(&:fingerprint))
                                     .includes(:assigned_to)
                                     .index_by(&:fingerprint)
    @regressed_fingerprints = regressed_fingerprints(all_groups.map(&:fingerprint))
    @environments = EventRepository.environments_for(@project)
    @releases     = EventRepository.releases_for(@project)
    @assignable_users = assignable_users

    @list = ItemsList.new(
      groups:    all_groups,
      issues:    @issues_by_fingerprint,
      query:     @items_query,
      user:      current_user,
      regressed: @regressed_fingerprints,
      releases:  @releases,
      view:      @items_view,
      env_param: params[:environment],
      sort:      @sort_key,
      dir:       @sort_dir,
      page:      params[:page],
      per:       @per
    )
    @groups       = @list.rows
    @facets       = @list.facets
    @saved_views  = @list.saved_views
    @pager        = @list.pager
    @metrics      = items_metrics
    @spark_by_fingerprint = EventRepository.spark_series_for(
      project: @project, fingerprints: @groups.map(&:fingerprint)
    )
  end

  def logs
    authorize Event, :index?
    scope = EventRepository.filtered(
      project:     @project,
      environment: params[:environment],
      level:       params[:level],
      keyword:     params[:q]
    ).order(occurred_at: :desc)
    @pagy, @events = pagy(scope, items: 100)
    @environments = EventRepository.environments_for(@project)

    if request.xhr?
      render partial: "log_rows", locals: { events: @events, pagy: @pagy }
    end
  end

  def show
    authorize @event
    @similar_events = EventRepository.similar_for(
      project: @project, fingerprint: @event.fingerprint, except_id: @event.id, limit: 5
    )
    @similar_events_total = EventRepository.count_by_fingerprint(
      project: @project, fingerprint: @event.fingerprint
    )
    @muted = @event.fingerprint.present? &&
             @project.mute_rules.exists?(fingerprint: @event.fingerprint)
  end

  def resolve
    authorize @event
    EventRepository.mark_resolved!(@event)
    respond_to do |format|
      format.html { redirect_back fallback_location: project_events_path(@project), notice: "Event marked as resolved." }
      format.turbo_stream
    end
  end

  def unresolve
    authorize @event
    EventRepository.mark_unresolved!(@event)
    respond_to do |format|
      format.html { redirect_back fallback_location: project_events_path(@project), notice: "Event marked as unresolved." }
      format.turbo_stream
    end
  end

  def resolve_group
    authorize @project, :resolve_events?
    count = bulk_update_group(resolved: true)
    redirect_back fallback_location: groups_project_events_path(@project),
                  notice: "Resolved #{count} #{'event'.pluralize(count)} in this group."
  end

  def unresolve_group
    authorize @project, :resolve_events?
    count = bulk_update_group(resolved: false)
    redirect_back fallback_location: groups_project_events_path(@project),
                  notice: "Reopened #{count} #{'event'.pluralize(count)} in this group."
  end

  def mute_group
    authorize @project, :mute_events?
    fingerprint = params[:fingerprint].to_s
    return redirect_back(fallback_location: groups_project_events_path(@project), alert: "Missing fingerprint.") if fingerprint.blank?

    @project.mute_rules.find_or_create_by!(fingerprint: fingerprint) do |rule|
      rule.hide_from_issues = true
    end
    redirect_back fallback_location: groups_project_events_path(@project),
                  notice: "Muted. New events in this group will not trigger alerts."
  end

  def unmute_group
    authorize @project, :mute_events?
    fingerprint = params[:fingerprint].to_s
    @project.mute_rules.where(fingerprint: fingerprint).delete_all if fingerprint.present?
    redirect_back fallback_location: groups_project_events_path(@project, show_muted: true),
                  notice: "Unmuted."
  end

  # Bulk action bar on the Items view. Operates on the selected fingerprints
  # (issues). resolve/unresolve/mute loop the existing group machinery; assign
  # sets the issue assignee; merge folds the selected issues into one via
  # IssueMerger.
  def bulk
    authorize @project, :resolve_events?
    fingerprints = Array(params[:fingerprints]).map(&:to_s).reject(&:blank?).uniq
    action_type  = params[:action_type].to_s

    return back_with("Select at least one issue first.", alert: true) if fingerprints.empty?

    case action_type
    when "resolve"
      count = fingerprints.sum { |fp| EventRepository.resolve_group(project: @project, fingerprint: fp) }
      back_with "Resolved #{helpers.pluralize(count, 'event')} across #{helpers.pluralize(fingerprints.size, 'issue')}."
    when "unresolve"
      count = fingerprints.sum { |fp| EventRepository.unresolve_group(project: @project, fingerprint: fp) }
      back_with "Reopened #{helpers.pluralize(count, 'event')} across #{helpers.pluralize(fingerprints.size, 'issue')}."
    when "mute"
      authorize @project, :mute_events?
      fingerprints.each do |fp|
        @project.mute_rules.find_or_create_by!(fingerprint: fp) { |rule| rule.hide_from_issues = true }
      end
      back_with "Muted #{helpers.pluralize(fingerprints.size, 'issue')}."
    when "assign"
      bulk_assign(fingerprints)
    when "merge"
      bulk_merge(fingerprints)
    else
      back_with "Unknown bulk action.", alert: true
    end
  end

  def destroy
    authorize @event
    EventRepository.discard!(@event)
    respond_to do |format|
      format.html { redirect_to project_events_path(@project), notice: "Event deleted." }
      format.turbo_stream
    end
  end

  def export
    authorize Event, :index?
    # Honour the same filters as the list (legacy params + query-bar `q` tokens)
    # so an export matches what the user is looking at.
    scope = filtered_events_scope.order(occurred_at: :desc).limit(EXPORT_MAX)

    filename_base = "events-#{@project.slug.presence || @project.id}-#{Time.current.strftime('%Y%m%d-%H%M%S')}"

    respond_to do |format|
      format.csv  { stream_csv_export(scope, filename_base) }
      format.json { stream_json_export(scope, filename_base) }
    end
  end

  private

  # Batch size for streaming exports. Small enough that peak memory stays flat
  # across a 10k-row export, large enough that per-batch SQL overhead is trivial.
  EXPORT_BATCH_SIZE = 500

  # Streams rows one at a time so a 10k-row export doesn't materialize the
  # whole body in memory. We can't use find_each — it silently overrides the
  # scope's order with primary-key ASC, so a "newest first" export would come
  # back oldest first. Use keyset pagination on (occurred_at, id) DESC instead:
  # preserves the user-visible order AND keeps memory flat.
  def stream_csv_export(scope, filename_base)
    set_streaming_headers(type: "text/csv", filename: "#{filename_base}.csv")
    stream_response do |yielder|
      yielder << CSV.generate_line(%w[id occurred_at level message environment fingerprint release user_identifier resolved is_regression backtrace breadcrumbs])
      each_export_event(scope) do |e|
        yielder << CSV.generate_line([
          e.id, e.occurred_at&.iso8601, e.level, csv_safe(e.message), csv_safe(e.environment),
          csv_safe(e.fingerprint), csv_safe(e.release), csv_safe(e.user_identifier), e.resolved, e.is_regression,
          csv_safe(e.backtrace), Oj.dump(e.breadcrumbs, mode: :compat)
        ])
      end
    end
  end

  # Spreadsheet formula-injection guard. Event fields (message, user_identifier,
  # backtrace, etc.) are attacker-controlled via the ingest API; a value that
  # begins with =, +, -, @, tab, or CR is executed as a formula when the CSV is
  # opened in Excel / Sheets / LibreOffice. Prefix those with a single quote so
  # the cell is treated as literal text.
  def csv_safe(value)
    str = value.to_s
    str.match?(/\A[=+\-@\t\r]/) ? "'#{str}" : str
  end

  def stream_json_export(scope, filename_base)
    set_streaming_headers(type: "application/json", filename: "#{filename_base}.json")
    stream_response do |yielder|
      yielder << "["
      first = true
      each_export_event(scope) do |e|
        yielder << "," unless first
        first = false
        yielder << Oj.dump({
          id:              e.id,
          occurred_at:     e.occurred_at&.iso8601,
          level:           e.level,
          message:         e.message,
          environment:     e.environment,
          fingerprint:     e.fingerprint,
          release:         e.release,
          user_identifier: e.user_identifier,
          user_context:    e.user_context,
          tags:            e.tags,
          resolved:        e.resolved,
          is_regression:   e.is_regression,
          backtrace:       e.backtrace,
          breadcrumbs:     e.breadcrumbs
        }, mode: :compat)
      end
      yielder << "]"
    end
  end

  # Keyset-paginated iteration over `scope` in (occurred_at DESC, id DESC)
  # order, capped at EXPORT_MAX. Replaces find_each, which would silently
  # re-sort by primary-key ASC and break the export's advertised newest-first
  # ordering.
  def each_export_event(scope)
    base = scope.except(:order, :limit).order(occurred_at: :desc, id: :desc)
    cursor_at = nil
    cursor_id = nil
    yielded   = 0

    while yielded < EXPORT_MAX
      page = base
      if cursor_at
        page = page.where(
          "events.occurred_at < :at OR (events.occurred_at = :at AND events.id < :id)",
          at: cursor_at, id: cursor_id
        )
      end

      rows = page.limit([ EXPORT_BATCH_SIZE, EXPORT_MAX - yielded ].min).to_a
      break if rows.empty?

      rows.each do |row|
        yield row
        yielded += 1
      end

      break if rows.size < EXPORT_BATCH_SIZE
      cursor_at = rows.last.occurred_at
      cursor_id = rows.last.id
    end
  end

  # Wraps the yielder block with two guarantees:
  #   1. with_connection — ensures the AR connection used to iterate batches
  #      is explicitly returned to the pool when the Enumerator finishes OR
  #      is abandoned (client disconnect, GC).
  #   2. Rescues client-disconnect errors so they don't bubble up as 500s in
  #      logs — the response is already half-written at that point anyway.
  def stream_response(&block)
    self.response_body = Enumerator.new do |yielder|
      ActiveRecord::Base.connection_pool.with_connection do
        block.call(yielder)
      end
    rescue Errno::EPIPE, IOError => e
      Rails.logger.info("[EventsController] export stream aborted: #{e.class}")
    end
  end

  def set_streaming_headers(type:, filename:)
    response.headers["Content-Type"]        = type
    response.headers["Content-Disposition"] = %(attachment; filename="#{filename}")
    response.headers["X-Accel-Buffering"]   = "no"
    response.headers["Cache-Control"]       = "no-cache"
    response.headers.delete("Content-Length")
  end


  def back_with(message, alert: false)
    key = alert ? :alert : :notice
    redirect_back fallback_location: groups_project_events_path(@project), key => message
  end

  # Users selectable as assignees: the project's organization members. Mirrors
  # IssuesController#show so the bulk picker and the detail overlay agree.
  def assignable_users
    @project.organization&.memberships&.includes(:user)&.map(&:user)&.compact || []
  end

  # Bulk-assigns (or unassigns) the selected issues. A blank assignee_id means
  # "unassign"; a present one must belong to the project's organization. Issue
  # rows are materialized on demand so a fingerprint that has events but no
  # aggregate row yet can still be assigned.
  def bulk_assign(fingerprints)
    authorize @project, :triage_issues?
    raw = params[:assignee_id].to_s
    if raw.present? && !@project.organization&.memberships&.exists?(user_id: raw)
      return back_with("That person isn't a member of this organization.", alert: true)
    end

    assignee_id = raw.presence
    fingerprints.each { |fp| Issue.find_or_init_by!(@project, fp).update!(assigned_to_id: assignee_id) }

    if assignee_id
      user = User.find_by(id: assignee_id)
      name = user&.name.presence || user&.email || "user"
      back_with "Assigned #{helpers.pluralize(fingerprints.size, 'issue')} to #{name}."
    else
      back_with "Unassigned #{helpers.pluralize(fingerprints.size, 'issue')}."
    end
  end

  # Merges the selected issues into one canonical issue by re-pointing their
  # existing events (see IssueMerger for semantics + the future-events caveat).
  def bulk_merge(fingerprints)
    authorize @project, :triage_issues?
    return back_with("Select at least two issues to merge.", alert: true) if fingerprints.size < 2

    result = IssueMerger.call(project: @project, fingerprints: fingerprints)
    return back_with("Select at least two issues to merge.", alert: true) unless result

    back_with "Merged #{helpers.pluralize(result.merged_count, 'issue')} into \"#{result.canonical_label}\" " \
              "(#{helpers.pluralize(result.events_moved, 'event')} moved)."
  end

  # Resolves the shared Items view state from params, falling back to cookies so
  # the layout / columns / page-size choices stick per browser (URL param wins
  # and re-persists). Sets @items_query, @items_layout, @visible_cols,
  # @sort_key, @sort_dir, @per, @items_view.
  def resolve_items_view
    @items_query  = ItemsQuery.parse(params[:q])
    @items_layout = resolve_layout
    @visible_cols = resolve_cols
    @per          = resolve_per
    @sort_key     = ItemsList::SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : "last_seen"
    @sort_dir     = params[:dir].to_s == "asc" ? "asc" : "desc"
    # An explicit `is:` status token in the query wins over the saved view, so
    # the two never double-filter status into an empty result (the query bar
    # carries the view as a hidden field, which would otherwise re-apply it).
    # Otherwise honour an explicit ?view=, defaulting to the starred "Unresolved".
    @items_view =
      if @items_query.statuses.any?
        "all"
      elsif params.key?(:view)
        params[:view].presence
      else
        "unresolved"
      end
    @items_counts = { issues: @project.issues.count, events: @project.events_count.to_i }
  end

  def resolve_layout
    raw = params[:layout].to_s.downcase[0]
    if %w[a b c].include?(raw)
      cookies[:items_layout] = { value: raw, expires: 1.year }
      raw
    else
      stored = cookies[:items_layout].to_s
      %w[a b c].include?(stored) ? stored : "a"
    end
  end

  def resolve_cols
    if params.key?(:cols)
      value = params[:cols].to_s
      cookies[:items_cols] = { value: value, expires: 1.year }
      value.split(",").map(&:strip).reject(&:blank?).to_set
    elsif cookies[:items_cols].present?
      cookies[:items_cols].to_s.split(",").map(&:strip).reject(&:blank?).to_set
    else
      ItemsHelper::DEFAULT_COLS.to_set
    end
  end

  def resolve_per
    if params.key?(:per)
      value = ItemsList::PER_OPTIONS.include?(params[:per].to_i) ? params[:per].to_i : ItemsList::PER_DEFAULT
      cookies[:items_per] = { value: value, expires: 1.year }
      value
    elsif cookies[:items_per].present? && ItemsList::PER_OPTIONS.include?(cookies[:items_per].to_i)
      cookies[:items_per].to_i
    else
      ItemsList::PER_DEFAULT
    end
  end

  # Raw-events scope shared by the Events list and the export, so an export
  # matches the on-screen subset. Merges legacy params with query-bar `q` tokens
  # (event-level tokens: level / env / release / keyword / is:resolved). Issue-only
  # tokens (assigned:, is:muted, is:regression) have no raw-event equivalent and
  # are ignored here.
  def filtered_events_scope
    query = ItemsQuery.parse(params[:q])
    EventRepository.filtered(
      project:     @project,
      environment: params[:environment].presence || query.environments.first,
      level:       params[:level].presence       || query.levels.first,
      fingerprint: params[:fingerprint],
      release:     params[:release].presence      || query.releases.first,
      tag_key:     params[:tag_key],
      tag_value:   params[:tag_value],
      keyword:     params[:keyword].presence      || query.keyword,
      resolved:    resolved_filter_for_events(query)
    )
  end

  # Raw events default to unresolved (preserves the existing index behaviour);
  # is:resolved surfaces resolved events, is:all drops the resolved filter.
  def resolved_filter_for_events(query = @items_query)
    if params.key?(:resolved)
      params[:resolved] == "true"
    elsif query.statuses.include?("resolved")
      true
    elsif query.statuses.include?("all")
      nil
    else
      false
    end
  end

  # Fingerprints (within the loaded set) that have at least one regression event.
  # One bounded `WHERE fingerprint IN (...)` query — cheap even on the hypertable.
  def regressed_fingerprints(fingerprints)
    return Set.new if fingerprints.blank?

    @project.events.kept
            .where(is_regression: true, fingerprint: fingerprints)
            .distinct.pluck(:fingerprint).to_set
  rescue StandardError => e
    Rails.logger.warn("[items] regression lookup failed: #{e.class}: #{e.message}")
    Set.new
  end

  # The one-line metric strip. events/24h, distinct users/24h, and the average
  # ingest rate are real; p95 latency is not tracked by ErrSight yet (rendered
  # as "—"). TODO: surface real p95 if/when request timing is captured.
  def items_metrics
    since  = 24.hours.ago
    recent = @project.events.kept.where("occurred_at >= ?", since)
    events_24h = recent.count
    {
      events_24h:     events_24h,
      users_24h:      recent.where.not(user_identifier: [ nil, "" ]).distinct.count(:user_identifier),
      ingest_per_sec: events_24h.positive? ? (events_24h / 86_400.0) : 0.0,
      last_event_at:  @project.events.kept.maximum(:occurred_at)
    }
  end

  # Facet rail data for Events mode: filter options without per-issue counts
  # (computing them would mean scanning the events hypertable). Assignee is
  # omitted since raw events have no assignment.
  def events_facets(environment:, level:)
    {
      level:    Event.levels.keys.map { |l| { id: l, name: l, count: nil, dot: ItemsHelper::LEVEL_DOTS[l], active: l == level || @items_query.has_token?("level", l) } },
      status:   [
        { id: "unresolved", name: "unresolved", count: nil, active: resolved_filter_for_events == false },
        { id: "resolved",   name: "resolved",   count: nil, active: resolved_filter_for_events == true }
      ],
      env:      Array(@environments).map { |e| { id: e, name: e, count: nil, active: e == environment || @items_query.has_token?("env", e) } },
      release:  Array(@releases).map { |r| { id: r, name: r, count: nil, active: @items_query.has_token?("release", r) } },
      assignee: []
    }
  end

  # Saved-view presets in Events mode act as token shortcuts; counts are omitted
  # (they would require scanning the events table).
  def events_saved_views
    [
      { id: "unresolved",  name: "Unresolved",     star: true, count: nil, active: resolved_filter_for_events == false },
      { id: "resolved",    name: "Resolved",       count: nil, active: resolved_filter_for_events == true },
      { id: "regressions", name: "Regressions",    count: nil, active: @items_query.has_token?("is", "regression") }
    ]
  end

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  def set_event
    @event = EventRepository.find_kept_for_project!(project: @project, id: params[:id])
  end

  def bulk_update_group(resolved:)
    fingerprint = params[:fingerprint].to_s
    return 0 if fingerprint.blank?
    if resolved
      EventRepository.resolve_group(project: @project, fingerprint: fingerprint)
    else
      EventRepository.unresolve_group(project: @project, fingerprint: fingerprint)
    end
  end
end

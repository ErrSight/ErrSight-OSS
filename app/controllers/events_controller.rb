class EventsController < ApplicationController
  require "csv"

  EXPORT_MAX = 10_000

  # Scoping is enforced by set_project (only finds projects owned by current_user),
  # so Pundit's policy_scope is intentionally not used here.
  skip_after_action :verify_policy_scoped

  before_action :set_project
  before_action :set_event, only: [ :show, :resolve, :unresolve, :destroy ]

  def index
    authorize Event
    scope = EventRepository.filtered(
      project:     @project,
      environment: params[:environment],
      level:       params[:level],
      fingerprint: params[:fingerprint],
      release:     params[:release],
      tag_key:     params[:tag_key],
      tag_value:   params[:tag_value],
      resolved:    params[:resolved] == "true"
    )
    @pagy, @events = pagy(scope.order(occurred_at: :desc), items: 50)
    @environments = EventRepository.environments_for(@project)
    @releases     = EventRepository.releases_for(@project)
  end

  def groups
    authorize Event, :index?
    @show_muted = params[:show_muted] == "true"
    @groups = EventRepository.grouped_by_fingerprint(
      project_id:    @project.id,
      environment:   params[:environment],
      include_muted: @show_muted
    )
    @environments = EventRepository.environments_for(@project)
    @issues_by_fingerprint = @project.issues
                                     .where(fingerprint: @groups.map(&:fingerprint))
                                     .includes(:assigned_to)
                                     .index_by(&:fingerprint)
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
    scope = EventRepository.filtered(
      project:     @project,
      environment: params[:environment],
      level:       params[:level],
      fingerprint: params[:fingerprint],
      release:     params[:release]
    ).order(occurred_at: :desc).limit(EXPORT_MAX)

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
          e.id, e.occurred_at&.iso8601, e.level, e.message, e.environment,
          e.fingerprint, e.release, e.user_identifier, e.resolved, e.is_regression,
          e.backtrace, Oj.dump(e.breadcrumbs, mode: :compat)
        ])
      end
    end
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

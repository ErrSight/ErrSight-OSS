# In-memory pipeline for the redesigned Issues list.
#
# `EventsController#groups` loads the full set of fingerprint groups (denormalised
# Issue aggregates, already one row per fingerprint) plus the matching Issue
# records. This object then filters, sorts, paginates, and derives facet +
# saved-view counts entirely in Ruby. That keeps the redesign a UI-layer change:
# no new ORDER/LIMIT/OFFSET or COUNT queries against the events hypertable.
# At ErrSight's scale a project's distinct fingerprints number in the tens to
# low hundreds, so working the array in memory is cheap.
class ItemsList
  PER_DEFAULT = 25
  PER_OPTIONS = [ 25, 50, 100 ].freeze

  # Occurrences threshold for the "High frequency" saved view.
  HIGH_FREQUENCY = 1_000

  # group attribute -> comparable sort key
  SORTS = {
    "last_seen"  => ->(g) { g.last_seen  || Time.at(0) },
    "first_seen" => ->(g) { g.first_seen || Time.at(0) },
    "events"     => ->(g) { g.occurrences.to_i },
    "users"      => ->(g) { g.affected_users.to_i },
    "severity"   => ->(g) { g.severity.to_i }
  }.freeze

  # Saved-view presets. Each predicate gets (group, issue) and the user id.
  SAVED_VIEWS = [
    { id: "unresolved",  name: "Unresolved",     star: true },
    { id: "assigned",    name: "Assigned to me" },
    { id: "highfreq",    name: "High frequency" },
    { id: "regressions", name: "Regressions" },
    { id: "new24",       name: "New today" },
    { id: "muted",       name: "Muted" }
  ].freeze

  def initialize(groups:, issues:, query:, user:, regressed: Set.new, releases: [],
                 view: nil, env_param: nil, sort: "last_seen", dir: "desc",
                 page: 1, per: PER_DEFAULT)
    @groups    = Array(groups)
    @issues    = issues || {}
    @query     = query
    @user      = user
    @regressed = regressed || Set.new
    @releases  = Array(releases)
    @view      = view.presence
    @env_param = env_param.presence
    @sort      = SORTS.key?(sort.to_s) ? sort.to_s : "last_seen"
    @dir       = dir.to_s == "asc" ? "asc" : "desc"
    @page      = [ page.to_i, 1 ].max
    @per       = PER_OPTIONS.include?(per.to_i) ? per.to_i : PER_DEFAULT
  end

  # The page of rows to render.
  def rows
    @rows ||= begin
      slice_start = (@page - 1) * @per
      sorted.slice(slice_start, @per) || []
    end
  end

  def total
    filtered.size
  end

  def fingerprints
    rows.map(&:fingerprint)
  end

  # Saved-view presets with live counts (computed over the env-scoped base set,
  # independent of the active view + query so the numbers stay stable).
  def saved_views
    base = env_scoped
    SAVED_VIEWS.map do |v|
      {
        id:     v[:id],
        name:   v[:name],
        star:   v[:star] || false,
        count:  base.count { |g| view_match?(v[:id], g) },
        active: @view == v[:id]
      }
    end
  end

  # Facet groups for the rail (layout B). Counts are over the view-scoped base
  # (so they reflect the active saved view) but ignore the ad-hoc query tokens.
  def facets
    base = view_scoped
    {
      level:    level_facet(base),
      status:   status_facet(base),
      env:      env_facet(base),
      release:  release_facet,
      assignee: assignee_facet(base)
    }
  end

  def pager
    count = total
    pages = [ (count.to_f / @per).ceil, 1 ].max
    page  = [ @page, pages ].min
    from  = count.zero? ? 0 : (page - 1) * @per + 1
    to    = [ page * @per, count ].min
    {
      count: count, page: page, pages: pages, per: @per, per_options: PER_OPTIONS,
      from: from, to: to, prev: (page > 1 ? page - 1 : nil), next: (page < pages ? page + 1 : nil)
    }
  end

  def sort_key = @sort
  def sort_dir = @dir

  private

  # Groups after the (legacy + token) environment filter only.
  def env_scoped
    envs = ([ @env_param ] + @query.environments).compact.map(&:to_s).uniq
    return @groups if envs.empty?

    @groups.select { |g| envs.include?(g.last_environment.to_s) }
  end

  # env_scoped + the active saved view.
  def view_scoped
    base = env_scoped
    return base unless @view

    base.select { |g| view_match?(@view, g) }
  end

  # view_scoped + every query token + free keyword.
  def filtered
    @filtered ||= view_scoped.select { |g| matches_query?(g) }
  end

  def sorted
    @sorted ||= begin
      key = SORTS[@sort]
      arr = filtered.sort_by { |g| key.call(g) }
      @dir == "asc" ? arr : arr.reverse
    end
  end

  # ---- query-token matching -------------------------------------------------

  def matches_query?(group)
    lv = @query.levels
    return false if lv.any? && !lv.include?(level_name(group))

    envs = @query.environments
    return false if envs.any? && !envs.include?(group.last_environment.to_s)

    statuses = @query.statuses
    return false if statuses.any? && statuses.none? { |s| status_match?(s, group) }

    @query.assignees.each do |a|
      return false unless assignee_match?(a, group)
    end

    if (kw = @query.keyword)
      hay = "#{group.last_message} #{group.fingerprint}".downcase
      return false unless hay.include?(kw.downcase)
    end

    # release:/browser:/has: have no in-memory backing on grouped issues; they
    # are honoured on the raw Events view instead. TODO: denormalise release /
    # browser onto the issues aggregate to filter them here too.
    true
  end

  def status_match?(status, group)
    case status
    when "unresolved" then !group.all_resolved
    when "resolved"   then group.all_resolved
    when "muted"      then !!group.muted
    when "regression" then @regressed.include?(group.fingerprint)
    when "ignored"    then false # TODO: no ignore state on issues yet
    else true
    end
  end

  def assignee_match?(value, group)
    issue = @issues[group.fingerprint]
    case value.downcase
    when "me"   then @user && issue&.assigned_to_id == @user.id
    when "none" then issue&.assigned_to_id.nil?
    else issue&.assigned_to&.email.to_s.casecmp?(value)
    end
  end

  # ---- saved-view predicates ------------------------------------------------

  def view_match?(view_id, group)
    issue = @issues[group.fingerprint]
    case view_id
    when "unresolved"  then !group.all_resolved && !group.muted
    when "assigned"    then @user && issue&.assigned_to_id == @user.id
    when "highfreq"    then group.occurrences.to_i >= HIGH_FREQUENCY
    when "regressions" then @regressed.include?(group.fingerprint)
    when "new24"       then group.first_seen.present? && group.first_seen >= 24.hours.ago
    when "muted"       then !!group.muted
    else true
    end
  end

  # ---- facet builders -------------------------------------------------------

  def level_facet(base)
    colors = { "fatal" => "var(--fatal)", "error" => "var(--err)",
               "warning" => "var(--warn)", "info" => "var(--info)", "debug" => "var(--fg-dimmer)" }
    %w[fatal error warning info debug].filter_map do |name|
      count = base.count { |g| level_name(g) == name }
      next if count.zero?

      { id: name, name: name, count: count, dot: colors[name], active: @query.has_token?("level", name) }
    end
  end

  def status_facet(base)
    [
      { id: "unresolved", name: "unresolved", count: base.count { |g| !g.all_resolved } },
      { id: "resolved",   name: "resolved",   count: base.count(&:all_resolved) },
      { id: "regression", name: "regression", count: base.count { |g| @regressed.include?(g.fingerprint) } },
      { id: "muted",      name: "muted",      count: base.count { |g| !!g.muted } }
    ].map { |f| f.merge(active: @query.has_token?("is", f[:id])) }
  end

  def env_facet(base)
    base.group_by { |g| g.last_environment.to_s }
        .reject { |env, _| env.blank? }
        .map { |env, gs| { id: env, name: env, count: gs.size, active: @query.has_token?("env", env) } }
        .sort_by { |f| -f[:count] }
  end

  # Releases have no per-issue aggregate, so the facet lists the project's known
  # releases without counts; the filter only narrows the raw Events view.
  def release_facet
    Array(@releases).map { |r| { id: r, name: r, count: nil, active: @query.has_token?("release", r) } }
  end

  def assignee_facet(base)
    rows = []
    if @user
      mine = base.count { |g| @issues[g.fingerprint]&.assigned_to_id == @user.id }
      rows << { id: "me", name: (@user.name.presence || @user.email), count: mine, active: @query.has_token?("assigned", "me") }
    end
    rows << { id: "none", name: "unassigned",
              count: base.count { |g| @issues[g.fingerprint]&.assigned_to_id.nil? },
              active: @query.has_token?("assigned", "none") }
    rows
  end

  def level_name(group)
    Event.levels.key(group.severity.to_i) || "info"
  end
end

# View helpers for the redesigned Items (Issues / Events) view: URL building
# that preserves the current filter state, column visibility, sort state, and
# the small level/format helpers the dense rows need.
#
# Reads effective state from controller ivars set in EventsController:
#   @items_query (ItemsQuery), @items_layout, @visible_cols (Set),
#   @sort_key, @sort_dir, @items_view.
module ItemsHelper
  # Optional, toggleable columns on the Issues table (checkbox / level / issue
  # are always present). `width` feeds the CSS grid template var.
  ISSUE_COLUMNS = [
    { id: "env",       label: "Environment", width: "72px"  },
    { id: "spark",     label: "Occurrences", width: "104px" },
    { id: "events",    label: "Events",      width: "70px"  },
    { id: "users",     label: "Users",       width: "56px"  },
    { id: "last_seen", label: "Last seen",   width: "98px"  },
    { id: "assignee",  label: "Assignee",    width: "44px"  }
  ].freeze

  DEFAULT_COLS = ISSUE_COLUMNS.map { |c| c[:id] }.freeze

  LEVEL_DOTS = {
    "fatal" => "var(--fatal)", "error" => "var(--err)", "warning" => "var(--warn)",
    "info" => "var(--info)", "debug" => "var(--fg-dimmer)"
  }.freeze

  # Sort options surfaced in the header sort menu (key => label).
  SORT_OPTIONS = [
    [ "last_seen",  "Last seen" ],
    [ "events",     "Events" ],
    [ "users",      "Users impacted" ],
    [ "first_seen", "First seen" ],
    [ "severity",   "Severity" ]
  ].freeze

  # Facet group -> query token key.
  FACET_TOKEN = { level: "level", status: "is", env: "env", release: "release", assignee: "assigned" }.freeze

  # Build a URL on the current Items route (groups OR index) with `overrides`
  # merged into the existing query string. Pagination resets on any filter
  # change unless the caller passes :page explicitly. Pass a key as nil/"" to
  # drop it.
  def items_url(overrides = {})
    overrides = overrides.symbolize_keys
    merged = request.query_parameters.symbolize_keys.merge(overrides)
    merged.delete(:page) unless overrides.key?(:page)
    merged = merged.reject { |_, v| v.nil? || v.to_s.empty? }
    query = merged.to_query
    query.present? ? "#{request.path}?#{query}" : request.path
  end

  # Toggle a `key:value` token in the query bar (used by facet + suggestion links).
  def items_toggle_url(key, value)
    items_url(q: @items_query.toggle(key, value).presence)
  end

  # Sort header link: first click sorts the column descending, a second click on
  # the active column flips to ascending.
  def items_sort_url(key)
    dir = (@sort_key == key.to_s && @sort_dir == "desc") ? "asc" : "desc"
    items_url(sort: key, dir: dir)
  end

  def items_sorted?(key)
    @sort_key == key.to_s
  end

  def items_sort_arrow(key)
    return "" unless items_sorted?(key)

    @sort_dir == "asc" ? "▲" : "▼"
  end

  def items_visible_cols
    @visible_cols || DEFAULT_COLS.to_set
  end

  def items_col?(id)
    items_visible_cols.include?(id.to_s)
  end

  def items_toggle_col_url(id)
    set = items_visible_cols.dup
    set.include?(id.to_s) ? set.delete(id.to_s) : set.add(id.to_s)
    items_url(cols: set.to_a.join(","))
  end

  # CSS grid-template-columns for the Issues table, reflecting visible columns.
  def items_issue_grid
    widths = ISSUE_COLUMNS.select { |c| items_col?(c[:id]) }.map { |c| c[:width] }
    ([ "34px", "76px", "minmax(0,1fr)" ] + widths).join(" ")
  end

  def items_level_name(severity)
    Event.levels.key(severity.to_i) || "info"
  end

  def items_level_dot(level)
    LEVEL_DOTS[level.to_s] || "var(--fg-dimmer)"
  end

  # Splits "ExceptionClass: message" into [class, rest] so the dense issue row
  # can lead with the error type. Falls back to the whole string as the type.
  def items_split_message(message)
    klass, rest = message.to_s.split(/:\s/, 2)
    [ klass.to_s.strip, rest.to_s.strip ]
  end

  # Compact count for the segmented toggle ("1.2k").
  def items_count_label(count)
    n = count.to_i
    return n.to_s if n < 1000

    "#{(n / 1000.0).round(1)}k".sub(".0k", "k")
  end

  # Href for a saved-view preset, per mode.
  def items_saved_view_href(mode, view)
    if mode == :issues
      items_url(view: view[:active] ? "all" : view[:id])
    else
      case view[:id]
      when "resolved"   then items_url(resolved: "true")
      when "unresolved" then items_url(resolved: "false")
      else items_url(q: @items_query.toggle("is", view[:id] == "regressions" ? "regression" : view[:id]).presence)
      end
    end
  end

  # Href for a facet row (toggles the matching query token).
  def items_facet_href(group_key, facet)
    items_toggle_url(FACET_TOKEN[group_key.to_sym] || group_key.to_s, facet[:id])
  end

  # Hidden inputs that carry the current Items state through a GET form submit
  # (query bar, rows-per-page) so submitting one control doesn't drop the rest.
  def items_hidden_state_fields(except: [])
    except = Array(except).map(&:to_s)
    state = {
      q:           @items_query&.to_s,
      layout:      @items_layout,
      view:        @items_view,
      sort:        @sort_key,
      dir:         @sort_dir,
      cols:        items_visible_cols.to_a.join(","),
      per:         @per,
      environment: params[:environment],
      resolved:    params[:resolved],
      fingerprint: params[:fingerprint]
    }
    safe_join(
      state.filter_map do |key, value|
        hidden_field_tag(key, value) if value.present? && except.exclude?(key.to_s)
      end
    )
  end

  # Buckets rows into time bands for the layout-C grouped stream.
  def items_time_buckets(rows, mode)
    now     = Time.current
    bands   = { "Last hour" => [], "Earlier today" => [], "This week" => [], "Older" => [] }
    rows.each do |row|
      t = mode == :issues ? row.last_seen : row.occurred_at
      if t.nil?            then bands["Older"] << row
      elsif t >= 1.hour.ago         then bands["Last hour"] << row
      elsif t >= now.beginning_of_day then bands["Earlier today"] << row
      elsif t >= 7.days.ago         then bands["This week"] << row
      else                              bands["Older"] << row
      end
    end
    bands.to_a
  end

  # Short relative time ("12s", "4m", "3h", "2d") for the dense last-seen cell.
  def items_short_ago(time)
    return "—" unless time.respond_to?(:to_time)

    secs = (Time.current - time).to_i
    return "now" if secs < 5
    return "#{secs}s" if secs < 60
    mins = secs / 60
    return "#{mins}m" if mins < 60
    hrs = mins / 60
    return "#{hrs}h" if hrs < 24
    "#{hrs / 24}d"
  end
end

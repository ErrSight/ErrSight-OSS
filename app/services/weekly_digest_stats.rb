class WeeklyDigestStats
  attr_reader :organization, :project_ids, :now, :week_start, :prev_week_start

  def initialize(organization, now: Time.current)
    @organization    = organization
    @project_ids     = organization.projects.pluck(:id)
    @now             = now
    @week_start      = 1.week.ago(now)
    @prev_week_start = 2.weeks.ago(now)
  end

  def empty?
    # Events are the source of truth for "did anything happen this week."
    # Used to also check `new_issue_count.zero?`, but with the issues
    # aggregate table, Issue rows linger after their events are pruned —
    # a project whose events were all deleted would erroneously look
    # active. Event count is the definitive signal.
    total_events_this_week.zero?
  end

  def total_events_this_week
    @total_events_this_week ||= events_between(week_start, now)
  end

  def total_events_prev_week
    @total_events_prev_week ||= events_between(prev_week_start, week_start)
  end

  def delta_pct
    prev = total_events_prev_week
    return nil if prev.zero?
    (((total_events_this_week - prev) / prev.to_f) * 100).round
  end

  def new_issue_count
    # "New issues this week" = issues whose first event arrived in the
    # week. Used to be Issue.created_at, which worked when Issue rows
    # were created lazily on first view; with aggregate maintenance,
    # Issues are created on first event so created_at is now ≈
    # first_seen_at except in edge cases. Use first_seen_at directly
    # — it's the actual semantic intent and survives the lazy-vs-eager
    # creation change.
    @new_issue_count ||= Issue
      .where(project_id: project_ids)
      .where(first_seen_at: week_start..now)
      .count
  end

  def regression_count
    @regression_count ||= event_scope(week_start, now)
      .where(is_regression: true)
      .count
  end

  # Returns an array of hashes { project:, issue:, event_count:, last_message:, last_level: }
  def top_issues(limit: 5)
    return [] if project_ids.empty?

    rows = event_scope(week_start, now)
      .group(:project_id, :fingerprint)
      .select(
        "project_id",
        "fingerprint",
        "COUNT(*) AS event_count",
        "MAX(occurred_at) AS last_seen",
        "(array_agg(message ORDER BY occurred_at DESC))[1] AS last_message",
        "(array_agg(level   ORDER BY occurred_at DESC))[1] AS last_level"
      )
      .order("event_count DESC, last_seen DESC")
      .limit(limit)

    projects_by_id = organization.projects.index_by(&:id)
    issues_by_key  = Issue
      .where(project_id: project_ids, fingerprint: rows.map(&:fingerprint))
      .index_by { |i| [ i.project_id, i.fingerprint ] }

    rows.map do |row|
      project = projects_by_id[row.project_id]
      issue   = issues_by_key[[ row.project_id, row.fingerprint ]]
      {
        project:      project,
        issue:        issue,
        fingerprint:  row.fingerprint,
        event_count:  row.event_count.to_i,
        last_message: row.last_message.to_s,
        last_level:   row.last_level.to_i
      }
    end
  end

  private

  def events_between(from, to)
    event_scope(from, to).count
  end

  def event_scope(from, to)
    return Event.none if project_ids.empty?
    Event
      .where(project_id: project_ids)
      .where(discarded: false)
      .where(occurred_at: from...to)
  end
end

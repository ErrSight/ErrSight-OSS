class Issue < ApplicationRecord
  belongs_to :project
  belongs_to :assigned_to, class_name: "User", optional: true
  has_many   :comments,    class_name: "IssueComment", dependent: :destroy
  has_many   :issue_users, dependent: :delete_all

  validates :fingerprint, presence: true, uniqueness: { scope: :project_id }
  validates :external_url,
            format: { with: %r{\Ahttps?://\S+\z}, message: "must be an http(s) URL" },
            allow_blank: true

  def self.find_or_init_by!(project, fingerprint)
    find_or_create_by!(project: project, fingerprint: fingerprint)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent callers racing on the same (project_id, fingerprint) — the
    # unique index catches the duplicate; return whichever row won.
    find_by!(project: project, fingerprint: fingerprint)
  end

  # Derived booleans matching what the old GROUP BY produced. Kept as
  # methods (not columns) because they're cheap and would otherwise need
  # their own maintenance path.
  def any_resolved?
    resolved_count.to_i > 0
  end

  def all_resolved?
    occurrences_count.to_i > 0 && resolved_count.to_i >= occurrences_count.to_i
  end

  # Maintains the denormalized aggregate columns when a new event lands.
  # This used to be computed via GROUP BY across the events hypertable on
  # every issues-page render — multi-second at scale. Now the page is a
  # single indexed scan against a small table; we pay the maintenance
  # cost (one UPSERT + maybe one issue_users INSERT) per event instead.
  #
  # Concurrency-safe: the UPSERT uses Postgres's row-level lock during
  # the ON CONFLICT UPDATE, so two threads inserting events for the same
  # fingerprint serialize correctly. GREATEST/LEAST/CASE inside SET
  # guard against backdated events (e.g. retried jobs with stale
  # occurred_at) clobbering newer data.
  def self.maintain_aggregates_for_event!(event)
    return unless event.fingerprint.present? && event.project_id

    occurred = event.occurred_at || Time.current
    level    = Event.levels[event.level.to_s] || 0
    resolved = event.resolved? ? 1 : 0

    issue_id = upsert_aggregates_sql!(
      project_id:       event.project_id,
      fingerprint:      event.fingerprint,
      occurred_at:      occurred,
      level:            level,
      message:          event.message.to_s,
      environment:      event.environment.to_s,
      resolved_increment: resolved
    )

    if event.user_identifier.present?
      record_unique_user!(issue_id: issue_id, user_identifier: event.user_identifier, first_seen_at: occurred)
    end

    issue_id
  end

  # Atomically applies a resolved-flag flip across all events for a
  # fingerprint. Called from EventRepository.resolve_group /
  # .unresolve_group after the bulk update on events. Without this the
  # any_resolved? / all_resolved? badges would lie until the next event
  # arrived.
  def self.set_resolved_count!(project_id:, fingerprint:, resolved_count:)
    where(project_id: project_id, fingerprint: fingerprint)
      .update_all(resolved_count: resolved_count, updated_at: Time.current)
  end

  # Rebuild aggregates from scratch by scanning the events table. Used:
  #
  #   1. Tests — fixture events are inserted via raw SQL, bypassing the
  #      after_create_commit callback, so issues need to be materialized
  #      after fixture load.
  #   2. Reconciliation — over time, retention pruning deletes events
  #      without decrementing counters, so aggregates drift upward. A
  #      periodic job runs this to bring them back in line with reality.
  #   3. Backfill — same SQL is in the original add_aggregates_to_issues
  #      migration. Centralized here so future schema changes update one
  #      copy instead of two.
  #
  # Idempotent: re-running produces the same final state regardless of
  # how stale the issues table was.
  def self.rebuild_all_aggregates!
    rebuild_issue_rows!
    rebuild_aggregate_columns!
    rebuild_issue_users!
    rebuild_affected_users_count!
  end

  # Per-project version for incremental reconciliation. The "all" version
  # is fine for tests; in production we'd want to scope to one project at
  # a time so a stuck rebuild on one project doesn't block others.
  def self.rebuild_aggregates_for_project!(project_id)
    rebuild_issue_rows!(project_id: project_id)
    rebuild_aggregate_columns!(project_id: project_id)
    rebuild_issue_users!(project_id: project_id)
    rebuild_affected_users_count!(project_id: project_id)
  end

  class << self
    private

    # Builds an "AND <qualifier>.project_id = <id>" snippet for inlining
    # into the rebuild SQL. Inlined rather than parameterized because the
    # SQL is otherwise template-only and we want it to match the exact
    # text the migration's backfill ran (audit-friendly).
    def project_id_filter(qualifier:, project_id:)
      return "" unless project_id
      "AND #{qualifier}.project_id = #{Integer(project_id)}"
    end

    def rebuild_issue_rows!(project_id: nil)
      connection.execute <<~SQL
        INSERT INTO issues (project_id, fingerprint, created_at, updated_at)
        SELECT DISTINCT e.project_id, e.fingerprint, NOW(), NOW()
        FROM events e
        WHERE e.discarded_at IS NULL
          AND e.fingerprint IS NOT NULL
          #{project_id_filter(qualifier: 'e', project_id: project_id)}
          AND NOT EXISTS (
            SELECT 1 FROM issues i
            WHERE i.project_id = e.project_id
              AND i.fingerprint = e.fingerprint
          )
      SQL
    end

    def rebuild_aggregate_columns!(project_id: nil)
      connection.execute <<~SQL
        UPDATE issues i SET
          last_seen_at      = agg.last_seen,
          first_seen_at     = agg.first_seen,
          occurrences_count = agg.occurrences,
          severity          = agg.severity,
          last_message      = agg.last_message,
          last_environment  = agg.last_environment,
          resolved_count    = agg.resolved_count
        FROM (
          SELECT
            project_id,
            fingerprint,
            MAX(occurred_at)                                       AS last_seen,
            MIN(occurred_at)                                       AS first_seen,
            COUNT(*)                                               AS occurrences,
            MAX(level)                                             AS severity,
            (array_agg(message     ORDER BY occurred_at DESC))[1]  AS last_message,
            (array_agg(environment ORDER BY occurred_at DESC))[1]  AS last_environment,
            COUNT(*) FILTER (WHERE resolved = TRUE)                AS resolved_count
          FROM events e
          WHERE e.discarded_at IS NULL
            AND e.fingerprint IS NOT NULL
            #{project_id_filter(qualifier: 'e', project_id: project_id)}
          GROUP BY project_id, fingerprint
        ) agg
        WHERE i.project_id = agg.project_id
          AND i.fingerprint = agg.fingerprint
      SQL
    end

    def rebuild_issue_users!(project_id: nil)
      connection.execute <<~SQL
        INSERT INTO issue_users (issue_id, user_identifier, first_seen_at)
        SELECT i.id, agg.user_identifier, agg.first_seen
        FROM (
          SELECT project_id, fingerprint, user_identifier, MIN(occurred_at) AS first_seen
          FROM events e
          WHERE e.discarded_at IS NULL
            AND e.fingerprint IS NOT NULL
            AND e.user_identifier IS NOT NULL
            AND e.user_identifier <> ''
            #{project_id_filter(qualifier: 'e', project_id: project_id)}
          GROUP BY project_id, fingerprint, user_identifier
        ) agg
        JOIN issues i
          ON i.project_id = agg.project_id
          AND i.fingerprint = agg.fingerprint
        ON CONFLICT (issue_id, user_identifier) DO NOTHING
      SQL
    end

    def rebuild_affected_users_count!(project_id: nil)
      # LEFT JOIN so issues with no users get reset to 0. The previous
      # version inner-joined against a "GROUP BY issue_users" subquery,
      # which silently skipped issues that had drift counters but no
      # actual user rows. The drift then persisted across rebuilds.
      where_clause = project_id ? "WHERE i2.project_id = #{Integer(project_id)}" : ""
      connection.execute <<~SQL
        UPDATE issues i SET
          affected_users_count = sub.cnt
        FROM (
          SELECT i2.id AS issue_id, COALESCE(COUNT(iu.id), 0) AS cnt
          FROM issues i2
          LEFT JOIN issue_users iu ON iu.issue_id = i2.id
          #{where_clause}
          GROUP BY i2.id
        ) sub
        WHERE i.id = sub.issue_id
      SQL
    end

    def upsert_aggregates_sql!(project_id:, fingerprint:, occurred_at:, level:, message:, environment:, resolved_increment:)
      sql = <<~SQL
        INSERT INTO issues (
          project_id, fingerprint,
          last_seen_at, first_seen_at,
          occurrences_count, severity,
          last_message, last_environment,
          resolved_count,
          created_at, updated_at
        ) VALUES (
          $1, $2,
          $3, $3,
          1, $4,
          $5, $6,
          $7,
          NOW(), NOW()
        )
        ON CONFLICT (project_id, fingerprint) DO UPDATE SET
          occurrences_count = issues.occurrences_count + 1,
          last_seen_at      = GREATEST(issues.last_seen_at,  EXCLUDED.last_seen_at),
          first_seen_at     = LEAST   (issues.first_seen_at, EXCLUDED.first_seen_at),
          severity          = GREATEST(issues.severity,      EXCLUDED.severity),
          last_message      = CASE
                                WHEN EXCLUDED.last_seen_at >= issues.last_seen_at
                                THEN EXCLUDED.last_message
                                ELSE issues.last_message
                              END,
          last_environment  = CASE
                                WHEN EXCLUDED.last_seen_at >= issues.last_seen_at
                                THEN EXCLUDED.last_environment
                                ELSE issues.last_environment
                              END,
          resolved_count    = issues.resolved_count + EXCLUDED.resolved_count,
          updated_at        = NOW()
        RETURNING id
      SQL

      result = connection.exec_query(sql, "Issue Upsert", [
        project_id, fingerprint, occurred_at, level, message, environment, resolved_increment
      ])
      result.first&.fetch("id")
    end

    def record_unique_user!(issue_id:, user_identifier:, first_seen_at:)
      sql = <<~SQL
        INSERT INTO issue_users (issue_id, user_identifier, first_seen_at)
        VALUES ($1, $2, $3)
        ON CONFLICT (issue_id, user_identifier) DO NOTHING
        RETURNING id
      SQL

      result = connection.exec_query(sql, "Issue User Insert", [
        issue_id, user_identifier.to_s.first(200), first_seen_at
      ])
      # If a row was actually inserted (not a conflict), this user is new
      # to this issue; bump the count atomically.
      if result.any?
        connection.exec_update(
          "UPDATE issues SET affected_users_count = affected_users_count + 1, updated_at = NOW() WHERE id = $1",
          "Issue Affected Users Increment",
          [ issue_id ]
        )
      end
    end
  end
end

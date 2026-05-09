class EventRepository
  # Single entry point for all reads/writes against the events store.
  # Today backed by ActiveRecord on Postgres+TimescaleDB; designed so a future
  # ClickHouse migration changes only this file, not callers.

  class << self
    # -- Writes ----------------------------------------------------------------

    def build_for(project:, attributes:)
      event = project.events.build(attributes)
      event.size_bytes = event.estimated_size_bytes
      event
    end

    def persist_new!(event)
      ApplicationRecord.transaction do
        event.is_regression = regression?(event.project, event.fingerprint)
        event.save!

        if event.is_regression?
          mark_group_unresolved(
            project_id: event.project_id,
            fingerprint: event.fingerprint,
            except_id: event.id
          )
        end

        # Issue aggregate maintenance is handled by an after_create_commit
        # on Event itself, so direct Event.create! paths (tests, admin
        # tooling) stay coherent without going through the repository.

        # Track storage_bytes here so the dashboard / project show / projects
        # index can display real numbers without COUNT/SUMing the events
        # hypertable on every request. events_count is a separate counter
        # maintained out-of-band — keeping it out of the hot ingest path
        # avoids a per-event UPDATE on the projects row from every batch.
        Project.where(id: event.project_id).update_all([
          "storage_bytes = storage_bytes + ?, " \
          "updated_at    = NOW()",
          event.size_bytes.to_i
        ])
      end
      event
    end

    def mark_resolved!(event)
      event.resolve!
    end

    def mark_unresolved!(event)
      event.unresolve!
    end

    def resolve_group(project:, fingerprint:)
      affected = kept_for(project).where(fingerprint: fingerprint)
                                  .update_all(resolved: true, updated_at: Time.current)
      # Sync the issue aggregate so the any_resolved? badge reflects the
      # bulk flip immediately. Setting equal to occurrences_count makes
      # all_resolved? true, which matches BOOL_AND(resolved) the old
      # GROUP BY produced when every event flipped.
      Issue.where(project_id: project.id, fingerprint: fingerprint).update_all(
        "resolved_count = occurrences_count, updated_at = NOW()"
      )
      affected
    end

    def unresolve_group(project:, fingerprint:)
      affected = kept_for(project).where(fingerprint: fingerprint)
                                  .update_all(resolved: false, updated_at: Time.current)
      Issue.set_resolved_count!(project_id: project.id, fingerprint: fingerprint, resolved_count: 0)
      affected
    end

    def discard!(event)
      event.discard
    end

    # Hard-deletes events older than cutoff for a single project, batching for
    # predictable memory use. Capped at max_batches per call so a backlog can't
    # pin a maintenance worker indefinitely — the recurring job will pick up
    # remaining rows on the next run. Returns [deleted_count, freed_bytes].
    MAX_PRUNE_BATCHES_PER_RUN = 50

    def prune_older_than!(project_id:, cutoff:, batch_size: 1_000, max_batches: MAX_PRUNE_BATCHES_PER_RUN)
      total_deleted = 0
      total_bytes   = 0
      touched_fingerprints = Set.new

      max_batches.times do
        batch = Event.where(project_id: project_id)
                     .where("occurred_at < ?", cutoff)
                     .limit(batch_size)
                     .pluck(:id, :size_bytes, :fingerprint)
        break if batch.empty?

        ids   = batch.map { |row| row[0] }
        freed = batch.sum { |row| row[1].to_i }
        batch.each { |row| touched_fingerprints << row[2] if row[2].present? }
        Event.where(id: ids).delete_all

        total_deleted += batch.length
        total_bytes   += freed
      end

      Issue.reconcile_aggregates_for_fingerprints!(
        project_id: project_id, fingerprints: touched_fingerprints
      )

      [ total_deleted, total_bytes ]
    end

    # Hard-deletes the oldest N kept events for a project. Returns freed_bytes
    # (caller is responsible for updating project counters).
    def delete_oldest_for_project!(project_id:, limit:)
      rows = Event.kept.where(project_id: project_id)
                       .order(:occurred_at).limit(limit)
                       .pluck(:id, :size_bytes, :fingerprint)
      return [ 0, 0 ] if rows.empty?

      ids          = rows.map { |row| row[0] }
      freed        = rows.sum { |row| row[1].to_i }
      fingerprints = rows.map { |row| row[2] }.compact.uniq
      Event.where(id: ids).delete_all

      Issue.reconcile_aggregates_for_fingerprints!(
        project_id: project_id, fingerprints: fingerprints
      )

      [ ids.length, freed ]
    end

    # GDPR erasure for a specific user_identifier within a project.
    # Returns [erased_count, freed_bytes].
    def erase_by_user_identifier!(project_id:, user_identifier:)
      scope = Event.where(project_id: project_id, user_identifier: user_identifier)
      rows  = scope.pluck(:id, :size_bytes, :fingerprint)
      return [ 0, 0 ] if rows.empty?

      ids          = rows.map { |row| row[0] }
      bytes        = rows.sum { |row| row[1].to_i }
      fingerprints = rows.map { |row| row[2] }.compact.uniq
      Event.where(id: ids).delete_all

      Issue.reconcile_aggregates_for_fingerprints!(
        project_id: project_id, fingerprints: fingerprints
      )

      [ ids.length, bytes ]
    end

    # -- Reads: individual records --------------------------------------------

    def find(id)
      Event.find_by(id: id)
    end

    def find_kept_for_project!(project:, id:)
      project.events.kept.find(id)
    end

    # -- Reads: base scopes (returned as AR relations) ------------------------

    def kept_for(project)
      project.events.kept
    end

    def kept_for_project_ids(project_ids)
      Event.kept.where(project_id: project_ids)
    end

    def for_fingerprint(project:, fingerprint:)
      kept_for(project).for_fingerprint(fingerprint)
    end

    # -- Reads: filtered list (index pages, API list) -------------------------

    def filtered(project:, environment: nil, level: nil, fingerprint: nil,
                 release: nil, tag_key: nil, tag_value: nil, keyword: nil,
                 resolved: nil, since: nil, before: nil)
      scope = kept_for(project)
               .for_environment(environment)
               .for_level(level)
               .for_fingerprint(fingerprint)
               .for_release(release)
               .for_tag(tag_key, tag_value)
      scope = scope.for_keyword(keyword) if keyword.present?
      scope = apply_resolved_filter(scope, resolved)
      scope = scope.where("occurred_at >= ?", since)  if since
      scope = scope.where("occurred_at < ?",  before) if before
      scope
    end

    # Events for a project more recent than cutoff, at or above a given level.
    # Used by alert digest jobs.
    def digest_for(project:, since:, min_level:)
      kept_for(project).where("occurred_at > ?", since)
                       .where("level >= ?", min_level)
                       .order(occurred_at: :desc)
    end

    def recent_across_projects(projects:, limit:)
      Event.kept.where(project: projects)
                .includes(:project)
                .order(occurred_at: :desc)
                .limit(limit)
    end

    def similar_for(project:, fingerprint:, except_id:, limit:)
      scope = for_fingerprint(project: project, fingerprint: fingerprint)
      scope = scope.where.not(id: except_id) if except_id
      scope.order(occurred_at: :desc).limit(limit)
    end

    def list_for_issue(project:, fingerprint:, limit:)
      for_fingerprint(project: project, fingerprint: fingerprint)
        .order(occurred_at: :desc).limit(limit)
    end

    # -- Reads: fingerprint / grouping ----------------------------------------

    def exists_for_fingerprint?(project:, fingerprint:)
      project.events.where(fingerprint: fingerprint).exists?
    end

    def first_occurrence?(project:, fingerprint:, except_id:)
      project.events.where(fingerprint: fingerprint).where.not(id: except_id).none?
    end

    def count_in_window(project:, fingerprint:, since:)
      project.events.where(fingerprint: fingerprint)
             .where("occurred_at >= ?", since).count
    end

    def grouped_by_fingerprint(project_id:, environment: nil, include_muted: false)
      Event.grouped_by_fingerprint(project_id,
                                   environment: environment,
                                   include_muted: include_muted)
    end

    def count_by_fingerprint(project:, fingerprint:)
      for_fingerprint(project: project, fingerprint: fingerprint).count
    end

    def unresolved_count_at_levels(project:, levels:)
      kept_for(project).unresolved.where(level: levels).count
    end

    def issue_summary(project:, fingerprint:)
      events = for_fingerprint(project: project, fingerprint: fingerprint)
      return nil if events.none?

      last  = events.order(occurred_at: :desc).first
      first = events.order(occurred_at: :asc).first

      {
        occurrences:    events.count,
        affected_users: events.where.not(user_identifier: nil).distinct.count(:user_identifier),
        first_seen:     first&.occurred_at,
        last_seen:      last&.occurred_at,
        last_message:   last&.message,
        level:          last&.level,
        all_resolved:   events.unresolved.none?
      }
    end

    # -- Reads: distinct values for filter UIs --------------------------------

    def environments_for(project)
      kept_for(project).distinct.pluck(:environment).compact.sort
    end

    def releases_for(project)
      kept_for(project).where.not(release: [ nil, "" ])
                       .distinct.pluck(:release).sort
    end

    def releases_for_project_ids(project_ids)
      Event.kept.where(project_id: project_ids)
                .where.not(release: [ nil, "" ])
                .distinct.pluck(:release).sort
    end

    # -- Aggregates -----------------------------------------------------------

    def total_count_kept(project:)
      kept_for(project).count
    end

    def total_bytes_kept(project:)
      kept_for(project).sum(:size_bytes)
    end

    def monthly_usage_rows(project:)
      kept_for(project)
        .select("DATE_TRUNC('month', occurred_at)::date AS month, " \
                "COUNT(*) AS cnt, " \
                "COALESCE(SUM(size_bytes), 0) AS bytes")
        .group("DATE_TRUNC('month', occurred_at)::date")
    end

    # Returns array of [bucket_at (UTC Time), level (int), count].
    # bucket_unit must be "hour" or "day".
    def time_series_counts(project:, start_time:, end_time:,
                           fingerprint: nil, environment: nil, bucket_unit:)
      unless %w[hour day].include?(bucket_unit)
        raise ArgumentError, "bucket_unit must be 'hour' or 'day'"
      end

      scope = kept_for(project).where(occurred_at: start_time..end_time)
      scope = scope.where(fingerprint: fingerprint) if fingerprint
      scope = scope.where(environment: environment) if environment

      # Bucket at UTC regardless of DB session TZ — otherwise bucket_start on
      # the Ruby side won't line up with DATE_TRUNC on the DB side.
      trunc_sql = "DATE_TRUNC('#{bucket_unit}', occurred_at AT TIME ZONE 'UTC')"
      level_sql = Arel.sql("events.level")
      scope.group(Arel.sql(trunc_sql), level_sql)
           .pluck(Arel.sql(trunc_sql), level_sql, Arel.sql("COUNT(*)"))
           .map { |bucket_at, level, count| [ bucket_at.utc, level.to_i, count.to_i ] }
    end

    # -- Private --------------------------------------------------------------

    private

    def regression?(project, fingerprint)
      return false if fingerprint.blank?
      # Discarded events were admin-dismissed as noise; they shouldn't count
      # toward regression detection or the "all prior resolved" check would
      # trip on soft-deleted history.
      prior = project.events.kept.where(fingerprint: fingerprint)
      return false unless prior.exists?
      !prior.where(resolved: false).exists?
    end

    def mark_group_unresolved(project_id:, fingerprint:, except_id:)
      Event.where(project_id: project_id, fingerprint: fingerprint, resolved: true)
           .where.not(id: except_id)
           .update_all(resolved: false, updated_at: Time.current)
    end

    def apply_resolved_filter(scope, resolved)
      case resolved
      when true,  "true"  then scope.resolved
      when false, "false" then scope.unresolved
      else scope
      end
    end
  end
end

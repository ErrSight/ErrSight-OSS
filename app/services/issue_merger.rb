# Merges several issues (identified by fingerprint) into one canonical issue
# by re-pointing their existing events onto the canonical fingerprint and
# folding in comments, assignment, and the affected-user set. This is the
# "clean up the duplicates I can see right now" operation behind the bulk
# Merge action.
#
# CAVEAT (surfaced in the bulk-merge flash): grouping happens at ingest time
# from the event's own fingerprint, so NEW events arriving with a merged-away
# fingerprint will spawn a fresh issue again. Making a merge "stick" for future
# events needs a fingerprint-alias consulted on the ingest path — deliberately
# out of scope here.
# TODO: fingerprint-alias table + ingest-path lookup so merges persist forward.
class IssueMerger
  Result = Struct.new(
    :merged_count, :canonical_label, :events_moved, :canonical_fingerprint,
    keyword_init: true
  )

  def self.call(project:, fingerprints:)
    new(project: project, fingerprints: fingerprints).call
  end

  def initialize(project:, fingerprints:)
    @project      = project
    @fingerprints = Array(fingerprints).map(&:to_s).reject(&:blank?).uniq
  end

  # Returns a Result on success, or nil when there aren't at least two real
  # issues to merge (caller turns that into a user-facing alert).
  def call
    return nil if @fingerprints.size < 2

    issues = @project.issues.where(fingerprint: @fingerprints).to_a
    return nil if issues.size < 2

    canonical = pick_canonical(issues)
    others    = issues - [ canonical ]
    other_ids = others.map(&:id)
    other_fps = others.map(&:fingerprint)
    events_moved = 0

    ActiveRecord::Base.transaction do
      # 1. Preserve comments: re-point them to the canonical issue before the
      #    source rows are destroyed.
      IssueComment.where(issue_id: other_ids).update_all(issue_id: canonical.id, updated_at: Time.current)

      # 2. Inherit assignment / external_url only where the canonical is blank,
      #    so a merge never clobbers an existing triage decision.
      inherit_metadata!(canonical, others)

      # 3. Re-point the events themselves (kept + discarded, for a consistent
      #    fingerprint) onto the canonical issue.
      events_moved = @project.events.where(fingerprint: other_fps)
                             .update_all(fingerprint: canonical.fingerprint, updated_at: Time.current)

      # 4. Drop the now-orphaned source artifacts. issue_users is delete_all'd
      #    explicitly because Issue.delete_all skips the dependent callback.
      @project.mute_rules.where(fingerprint: other_fps).delete_all
      IssueUser.where(issue_id: other_ids).delete_all
      Issue.where(id: other_ids).delete_all

      # 5. Rebuild the canonical aggregates + affected-user set from the
      #    combined events so counts and badges are correct immediately.
      rebuild_canonical!(canonical)
    end

    Result.new(
      merged_count:          issues.size,
      canonical_label:       canonical.last_message.to_s.truncate(60).presence || canonical.fingerprint,
      events_moved:          events_moved,
      canonical_fingerprint: canonical.fingerprint
    )
  end

  private

  # Canonical = the oldest issue (earliest first_seen_at) — the "original" the
  # duplicates split off from. Deterministic fingerprint tie-break so the
  # choice is stable across runs.
  def pick_canonical(issues)
    issues.min_by { |i| [ i.first_seen_at || Time.current, i.fingerprint ] }
  end

  def inherit_metadata!(canonical, others)
    updates = {}
    if canonical.assigned_to_id.nil?
      donor = others.find { |i| i.assigned_to_id.present? }
      updates[:assigned_to_id] = donor.assigned_to_id if donor
    end
    if canonical.external_url.blank?
      donor = others.find { |i| i.external_url.present? }
      updates[:external_url] = donor.external_url if donor
    end
    canonical.update_columns(updates.merge(updated_at: Time.current)) if updates.any?
  end

  # Recompute the canonical issue's denormalized aggregates from the events it
  # now owns. Mirrors Issue.reconcile_aggregates_for_fingerprints! but also
  # rebuilds issue_users (membership grows on merge, which reconcile alone
  # would miss, leaving affected_users_count too low).
  def rebuild_canonical!(canonical)
    fp     = canonical.fingerprint
    events = @project.events.kept.where(fingerprint: fp)
    recent = events.order(occurred_at: :desc).first

    canonical.issue_users.delete_all
    rows = events.where.not(user_identifier: [ nil, "" ])
                 .group(:user_identifier).minimum(:occurred_at)
                 .map { |uid, first| { issue_id: canonical.id, user_identifier: uid.to_s.first(200), first_seen_at: first } }
    IssueUser.insert_all(rows) if rows.any?

    canonical.update_columns(
      occurrences_count:    events.count,
      first_seen_at:        events.minimum(:occurred_at),
      last_seen_at:         events.maximum(:occurred_at),
      severity:             events.maximum(:level).to_i,
      resolved_count:       events.where(resolved: true).count,
      last_message:         recent&.message,
      last_environment:     recent&.environment,
      affected_users_count: rows.size,
      updated_at:           Time.current
    )
  end
end

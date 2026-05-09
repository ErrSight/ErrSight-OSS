require "ostruct"

class Event < ApplicationRecord
  include Discard::Model

  self.primary_key = :id

  belongs_to :project

  enum :level, { debug: 0, info: 1, warning: 2, error: 3, fatal: 4 }

  validates :message, presence: true
  validates :level, presence: true
  validates :occurred_at, presence: true

  before_validation :set_fingerprint, if: -> { fingerprint.blank? }
  before_validation :set_occurred_at, if: -> { occurred_at.blank? }

  # Maintain the denormalized issue aggregate on commit. Lives on the
  # model rather than EventRepository so direct Event.create! paths
  # (admin tooling, tests, future code) keep the issues table coherent.
  # after_create_commit fires once the outer transaction commits, which
  # is the moment the event becomes visible to other connections — the
  # right time to publish derived state.
  after_create_commit :maintain_issue_aggregates, unless: :discarded?

  scope :recent, -> { order(occurred_at: :desc) }
  scope :unresolved, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :for_environment, ->(env) { where(environment: env) if env.present? }
  scope :for_level, ->(lvl) { where(level: lvl) if lvl.present? }
  scope :for_fingerprint, ->(fp) { where(fingerprint: fp) if fp.present? }
  scope :for_keyword,     ->(q)  { where("message ILIKE ?", "%#{sanitize_sql_like(q)}%") if q.present? }
  scope :for_release,     ->(r)  { where(release: r) if r.present? }
  scope :for_tag,         ->(k, v) { where("tags @> ?", { k => v }.to_json) if k.present? && v.present? }

  def chunk_info
    TimescaleStats.chunk_for(self)
  end

  def compressed?
    TimescaleStats.compressed?(self)
  end

  def estimated_size_bytes
    # Rough estimate: message + backtrace + metadata serialized
    (message.to_s.bytesize +
      backtrace.to_s.bytesize +
      metadata.to_json.bytesize +
      environment.to_s.bytesize +
      fingerprint.to_s.bytesize + 200)
  end

  def resolve!
    update!(resolved: true)
  end

  def unresolve!
    update!(resolved: false)
  end

  # Group similar events by fingerprint for the error grouping view
  # Returns an array of OpenStruct objects with group data (not AR relation)
  def self.ransackable_attributes(auth_object = nil)
    %w[level environment resolved message occurred_at fingerprint created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "project" ]
  end

  # Reads from the denormalized aggregate columns on `issues` instead of
  # GROUP BYing the events hypertable. The previous query got slower
  # linearly with project event volume; this one is bounded by the
  # number of distinct fingerprints (typically dozens to hundreds, even
  # for large projects).
  #
  # Aggregates are maintained on event insert by
  # Issue.maintain_aggregates_for_event!, and on bulk resolve/unresolve
  # by EventRepository. They can drift downward when retention prunes
  # events; a periodic reconciliation job (deferred) rebuilds from
  # scratch when that becomes user-visible.
  #
  # Environment filter caveat: this filters on issue.last_environment
  # ("the env of the most recent occurrence"), not "every event in this
  # group with env=X". For a fingerprint that flips between staging and
  # prod, the issue appears under whichever env it most recently
  # occurred in. This matches what users intuit when they pick an
  # environment filter on the issues list.
  def self.grouped_by_fingerprint(project_id, environment: nil, include_muted: false)
    sql = <<~SQL
      SELECT
        i.fingerprint,
        i.last_seen_at         AS last_seen,
        i.first_seen_at        AS first_seen,
        i.occurrences_count    AS occurrences,
        i.affected_users_count AS affected_users,
        i.severity             AS severity,
        i.last_message         AS last_message,
        (i.resolved_count > 0)                         AS any_resolved,
        (i.occurrences_count > 0
          AND i.resolved_count >= i.occurrences_count) AS all_resolved,
        (m.id IS NOT NULL)     AS muted
      FROM issues i
      LEFT JOIN mute_rules m
        ON m.project_id = i.project_id
        AND m.fingerprint = i.fingerprint
        AND (m.expires_at IS NULL OR m.expires_at > :now)
      WHERE i.project_id = :project_id
        AND i.occurrences_count > 0
        #{environment.present? ? "AND i.last_environment = :environment" : ""}
        #{include_muted ? "" : "AND (m.id IS NULL OR m.hide_from_issues = FALSE)"}
      ORDER BY i.last_seen_at DESC NULLS LAST
    SQL

    result = connection.select_all(sanitize_sql([ sql, project_id: project_id, environment: environment, now: Time.current ]))
    result.map do |row|
      OpenStruct.new(
        fingerprint:    row["fingerprint"],
        last_seen:      row["last_seen"],
        first_seen:     row["first_seen"],
        occurrences:    row["occurrences"].to_i,
        affected_users: row["affected_users"].to_i,
        severity:       row["severity"].to_i,
        last_message:   row["last_message"],
        any_resolved:   row["any_resolved"],
        all_resolved:   row["all_resolved"],
        muted:          row["muted"]
      )
    end
  end

  private

  def maintain_issue_aggregates
    Issue.maintain_aggregates_for_event!(self)
  rescue StandardError => e
    # Issue maintenance must never block event ingestion. If the upsert
    # fails (lock timeout, schema drift, anything), log and move on —
    # the event itself is already committed and a future reconciliation
    # job will pick up the slack.
    Rails.logger.warn("[Event] Issue aggregate maintenance failed: #{e.class}: #{e.message}")
  end

  # Group events into issues. There are two paths, picked at insert time:
  #
  #   v2 (new SDK with structured frames):
  #     hash(exception_class | top_in_app_frame.filename | top_in_app_frame.function)
  #
  #     This is the right grouping. Two events of the same error class,
  #     in the same code location, group together — even if the message
  #     varies ("User 42 not found" vs "User 99 not found"). Two
  #     completely unrelated NoMethodErrors with identical messages but
  #     different stacks split — which is also right.
  #
  #   legacy (old SDK / no structured frames):
  #     hash(message-with-numbers-stripped | first_backtrace_line)
  #
  #     The original hash. False-merges errors with the same shape but
  #     different causes; false-splits the same error site when the
  #     message contains varying text. We keep this path because old SDKs
  #     still in production don't ship `exception_frames`, and we'd
  #     rather have noisy grouping than zero grouping for those events.
  #
  # The "v2|" / "v1|" prefix versions the hash so a future v3 can
  # coexist without colliding with grandfathered fingerprints.
  #
  # Migration discontinuity: an issue captured by the old SDK (legacy
  # hash) and the same crash from the new SDK (v2 hash) WILL appear as
  # two separate issues until the old SDK is rolled out. This is the
  # cost of upgrading grouping; document for users in the changelog.
  def set_fingerprint
    if (fp = fingerprint_from_frames)
      self.fingerprint = fp
    else
      self.fingerprint = legacy_fingerprint
    end
  end

  def fingerprint_from_frames
    return nil unless metadata.is_a?(Hash)
    frames = metadata["exception_frames"]
    return nil unless frames.is_a?(Array)
    top = frames.find { |f| f.is_a?(Hash) && f["in_app"] }
    return nil unless top
    exc_class = (metadata["exception_class"] || "Unknown").to_s
    raw = "v2|#{exc_class}|#{top['filename']}|#{top['function']}"
    Digest::SHA256.hexdigest(raw)[0, 32]
  end

  # The legacy hash MUST remain bit-identical to the pre-v2 implementation
  # so events captured by old SDKs continue to land in the same issues
  # they always did. No prefix; same separator; same number-stripping
  # regex. If you want to evolve this, version it as `legacy_fingerprint_v2`
  # and route the `set_fingerprint` decision through there.
  def legacy_fingerprint
    first_trace = backtrace.to_s.lines.first.to_s.strip
    raw = "#{message.to_s.gsub(/\d+/, 'N')}|#{first_trace}"
    Digest::SHA256.hexdigest(raw)[0, 32]
  end

  def set_occurred_at
    self.occurred_at = Time.current
  end
end

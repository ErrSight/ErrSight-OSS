module EventFramesHelper
  # Returns a normalized Array<Hash> of frames for the given event.
  #
  # Two sources, two fidelities:
  #
  #   1. metadata["exception_frames"] — shipped by errsight-ruby >= 0.2.0
  #      and other frame-aware SDKs. Contains structured frames with
  #      pre_context / context_line / post_context already attached for
  #      in_app frames. This is the high-fidelity path; in_app detection
  #      was done by the SDK using the host's project_root + Bundler
  #      paths so it's accurate.
  #
  #   2. event.backtrace string — the legacy path. We parse it best-effort
  #      with a regex and use a fuzzy heuristic for in_app. No source
  #      context. Older events captured before 0.2.0 will hit this path.
  #
  # Caller doesn't care which: both produce frames with symbol keys ready
  # for the partial. After every event has been re-captured (or after
  # enough time passes that legacy events fall off retention), we can
  # delete the fallback and the regex.
  def event_frames(event)
    structured = extract_structured_frames(event)
    return structured if structured.any?
    parse_backtrace_string(event.backtrace.to_s)
  end

  # Best-effort line-1 string for the issue header's "raised in <code>" hint.
  # Use the structured top frame when available — the SDK's filename is
  # already project-root-relative, which is much friendlier to read than
  # the absolute path that lives in the joined backtrace string.
  def event_first_frame_label(event, frames)
    top = frames.first
    if top
      label = top[:filename].to_s
      label += ":#{top[:lineno]}" if top[:lineno]
      label += " in #{top[:function]}" if top[:function].present?
      return label
    end
    event.backtrace.to_s.lines.first&.strip
  end

  # Returns the array under metadata["exception_causes"] when present, or
  # an empty array. Each entry is the raw hash from the SDK
  # (class/message/backtrace). View renders Class + Message; backtrace is
  # available for future "expand cause" UI but unused today.
  def event_causes(event)
    metadata = event.metadata
    return [] unless metadata.is_a?(Hash)
    raw = metadata["exception_causes"]
    raw.is_a?(Array) ? raw : []
  end

  # Builds the paste-ready "fix this error" prompt for the copy button on
  # the event detail page. Thin wrapper over FixPromptBuilder so the view
  # stays declarative; see that service for what the prompt contains and
  # which fields are deliberately omitted (end-user PII).
  def fix_prompt_for(event, project = nil)
    FixPromptBuilder.call(event, project: project)
  end

  # Lightweight SQL keyword highlight. We avoid pulling in a real
  # syntax-highlighter gem (Rouge, CodeRay) for one breadcrumb-list use
  # case — the goal is "readable at a glance," not "Sublime Text."
  # Escape first, then wrap matched keywords in spans, then mark the
  # result html_safe — order matters; never mark unescaped input safe.
  SQL_KEYWORDS = %w[
    SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE
    JOIN INNER LEFT RIGHT OUTER ON
    GROUP BY ORDER LIMIT OFFSET HAVING UNION DISTINCT AS
    AND OR NOT NULL IS LIKE IN EXISTS BETWEEN
    CREATE TABLE INDEX DROP ALTER ADD REFERENCES PRIMARY KEY FOREIGN
    BEGIN COMMIT ROLLBACK TRANSACTION
    CASE WHEN THEN ELSE END WITH RETURNING
  ].freeze
  SQL_KEYWORD_REGEX = /\b(#{SQL_KEYWORDS.join('|')})\b/i

  def highlight_sql(sql)
    return "" if sql.nil? || sql.empty?
    escaped = ERB::Util.html_escape(sql.to_s)
    escaped.gsub(SQL_KEYWORD_REGEX) { |m| %(<span class="sql-kw">#{m.upcase}</span>) }.html_safe
  end

  # Bucket query duration into a CSS class so eyes catch slow queries.
  # Thresholds tuned for typical Rails/Postgres workloads — adjust if a
  # customer's environment is consistently slower (e.g., heavy MongoDB).
  def sql_duration_class(ms)
    ms = ms.to_f
    return "dur-fast"      if ms < 10
    return "dur-norm"      if ms < 100
    return "dur-slow"      if ms < 500
    "dur-very-slow"
  end

  private

  def extract_structured_frames(event)
    metadata = event.metadata
    return [] unless metadata.is_a?(Hash)
    raw = metadata["exception_frames"]
    return [] unless raw.is_a?(Array)
    raw.filter_map { |f| normalize_structured_frame(f) }
  end

  # Frames arrive after a JSON round-trip so all keys are strings. View
  # code is easier to read with symbol-key access, so we normalize once
  # here. Defensive against partial frames (the SDK may add fields in
  # future versions; old fields may go missing).
  def normalize_structured_frame(frame)
    return nil unless frame.is_a?(Hash)
    out = {
      filename:     frame["filename"],
      abs_path:     frame["abs_path"],
      lineno:       frame["lineno"]&.to_i,
      function:     frame["function"],
      in_app:       !!frame["in_app"],
      pre_context:  Array(frame["pre_context"]),
      context_line: frame["context_line"],
      post_context: Array(frame["post_context"])
    }
    return nil if out[:filename].nil? || out[:filename].empty?
    out
  end

  # Same regex shape used by the SDK; relaxed slightly because we may be
  # parsing legacy lines from years-old events captured before the parser
  # was tightened up.
  LEGACY_FRAME_REGEX = %r{\A(?<file>.+?):(?<line>\d+)(?::in\s+['`"](?<fn>.+?)['"]?\s*)?\z}

  # Substrings that indicate "this frame is in a gem, not customer code."
  # The list is intentionally permissive — a false-negative on in_app
  # collapses a legitimate app frame into the framework group, which is
  # ugly but not broken; a false-positive shows source context for code
  # the user can't change, which is also ugly but not broken. Either way,
  # users with the new SDK get the precise classifier.
  LEGACY_GEM_PATH_HINTS = [
    "/gems/", "gems/", "/rubygems", "/ruby/",
    "activerecord", "activesupport", "actionpack",
    "actionview", "actionmailer", "railties",
    "actioncable", "activemodel", "activestorage", "activejob"
  ].freeze

  def parse_backtrace_string(str)
    return [] if str.empty?
    str.each_line.filter_map do |raw|
      line = raw.strip
      next nil if line.empty?
      m = LEGACY_FRAME_REGEX.match(line)
      file, lineno, fn = m ? [ m[:file], m[:line].to_i, m[:fn] ] : [ line, nil, nil ]
      {
        filename:     file,
        abs_path:     nil,
        lineno:       lineno,
        function:     fn,
        in_app:       legacy_in_app?(file),
        pre_context:  [],
        context_line: nil,
        post_context: []
      }
    end
  end

  def legacy_in_app?(file)
    return false if file.nil? || file.empty?
    return false if file.start_with?("<", "(")
    return false if LEGACY_GEM_PATH_HINTS.any? { |hint| file.include?(hint) }
    file.start_with?("app/", "lib/", "config/") ||
      file.match?(%r{\A[^/]*/?app/}) ||
      !file.start_with?("/")
  end
end

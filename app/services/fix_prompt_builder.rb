# Builds a paste-ready prompt that describes a captured error in enough
# detail for an AI coding assistant to propose a fix. This is pure
# templating — NO LLM is called here. The user copies the result and pastes
# it into the assistant of their choice (Claude Code, Cursor, ChatGPT, …),
# so ErrSight incurs no model cost.
#
# Privacy: this prompt is exported to a third-party tool, so it deliberately
# OMITS end-user PII. The identity of who hit the error (user_context email,
# username, IP) is irrelevant to fixing the code, and tags are skipped for
# the same reason. Only the error, its source context, the stack, the
# request path, and the breadcrumb trail are included.
#
# Frame extraction is delegated to EventFramesHelper#event_frames, the same
# normalization the event detail view uses — structured SDK frames (with
# source context) when available, a parsed backtrace string for legacy
# events. So legacy events still produce a structured stack, just without
# the source snippet.
class FixPromptBuilder
  include EventFramesHelper

  MAX_IN_APP_FRAMES = 18
  MAX_FRAMEWORK     = 6
  MAX_CAUSES        = 5
  MAX_BREADCRUMBS   = 8
  MAX_MESSAGE       = 600
  MAX_CAUSE_MESSAGE = 200
  MAX_CRUMB_MESSAGE = 160
  MAX_PROMPT_CHARS  = 8_000

  def self.call(event, project: nil)
    new(event, project: project).call
  end

  def initialize(event, project: nil)
    @event   = event
    @project = project || event.project
  end

  def call
    sections = [
      preamble,
      error_section,
      location_section,
      stack_section,
      causes_section,
      request_section,
      breadcrumbs_section,
      task_section
    ].compact

    sections.join("\n\n").strip.truncate(MAX_PROMPT_CHARS, omission: "\n\n[truncated]")
  end

  private

  attr_reader :event, :project

  def preamble
    "You are debugging a production error captured by ErrSight. Identify the " \
      "root cause and propose a minimal, correct fix."
  end

  # ---- error + meta ------------------------------------------------------

  def error_section
    [ "## Error", message_text, meta_line ].compact.join("\n")
  end

  def message_text
    msg   = event.message.to_s.strip
    klass = exception_class
    msg = "#{klass}: #{msg}" if klass.present? && !msg.start_with?(klass)
    msg.truncate(MAX_MESSAGE)
  end

  def meta_line
    parts = [ "Level: #{event.level}" ]
    parts << "Environment: #{event.environment}" if event.environment.present?
    parts << "Release: #{event.release}"         if event.release.present?
    stats = occurrence_stats
    parts << stats if stats.present?
    parts.join(" · ")
  end

  def occurrence_stats
    issue = issue_record
    return nil unless issue

    bits = []
    bits << "first seen #{issue.first_seen_at.to_date.iso8601}" if issue.first_seen_at
    bits << "#{issue.occurrences_count} occurrences"            if issue.occurrences_count.to_i.positive?
    bits << "#{issue.affected_users_count} users affected"      if issue.affected_users_count.to_i.positive?
    bits.presence&.join(" · ")
  end

  def issue_record
    return @issue_record if defined?(@issue_record)

    @issue_record =
      if project && event.fingerprint.present?
        Issue.find_by(project_id: project.id, fingerprint: event.fingerprint)
      end
  end

  # ---- where it failed (top frame + source snippet) ----------------------

  def location_section
    top = frames.find { |f| f[:in_app] } || frames.first
    return nil unless top

    header  = "## Where it failed\n#{frame_label(top)}"
    snippet = source_snippet(top)
    snippet ? "#{header}\n\n#{snippet}" : header
  end

  def source_snippet(frame)
    return nil if frame[:context_line].blank?

    pre  = Array(frame[:pre_context])
    post = Array(frame[:post_context])
    lineno = frame[:lineno].to_i
    return nil if lineno <= 0

    lines = []
    start = lineno - pre.size
    pre.each_with_index  { |code, i| lines << code_line(start + i, code, false) }
    lines << code_line(lineno, frame[:context_line], true)
    post.each_with_index { |code, i| lines << code_line(lineno + 1 + i, code, false) }
    lines.join("\n")
  end

  def code_line(no, code, marker)
    "#{marker ? '→' : ' '} #{no.to_s.rjust(4)}  #{code.to_s.truncate(200)}"
  end

  # ---- stack trace (in-app first) ----------------------------------------

  def stack_section
    return nil if frames.empty?

    in_app = frames.select { |f| f[:in_app] }
    lines  = [ "## Stack trace (your code first)" ]

    shown = in_app.any? ? in_app.first(MAX_IN_APP_FRAMES) : frames.first(MAX_FRAMEWORK)
    shown.each { |f| lines << frame_label(f) }
    omitted = frames.size - shown.size
    lines << omitted_note(omitted) if omitted.positive?

    lines.join("\n")
  end

  def omitted_note(count)
    "[#{count} more frame#{'s' unless count == 1} omitted]"
  end

  def frame_label(frame)
    label = frame[:filename].to_s
    label += ":#{frame[:lineno]}" if frame[:lineno]
    label += " in `#{frame[:function]}`" if frame[:function].present?
    label
  end

  # ---- cause chain -------------------------------------------------------

  def causes_section
    causes = event_causes(event)
    return nil if causes.empty?

    lines = [ "## Caused by" ]
    causes.first(MAX_CAUSES).each do |cause|
      klass = cause["class"].to_s.strip
      msg   = cause["message"].to_s.strip.truncate(MAX_CAUSE_MESSAGE)
      lines << [ klass.presence, msg.presence ].compact.join(": ")
    end
    lines.join("\n")
  end

  # ---- request -----------------------------------------------------------

  def request_section
    md = metadata
    # Path rides in metadata; the HTTP verb rides in tags (request_method)
    # for the Ruby SDK, with metadata fallbacks for other SDKs.
    path   = md.values_at("full_path", "path", "url").find(&:present?)
    method = [ tags["request_method"], md["method"], md["request_method"], md["http_method"] ].find(&:present?)
    return nil if path.blank? && method.blank?

    "## Request\n#{[ method, path ].compact.join(' ').strip}"
  end

  # ---- breadcrumbs -------------------------------------------------------

  def breadcrumbs_section
    crumbs = Array(event.breadcrumbs).last(MAX_BREADCRUMBS)
    return nil if crumbs.empty?

    lines = [ "## Recent breadcrumbs" ]
    crumbs.each do |crumb|
      next unless crumb.is_a?(Hash)

      label = [
        crumb_time(crumb["timestamp"]),
        crumb["level"].to_s.strip.presence,
        crumb["category"].to_s.strip.presence,
        crumb["message"].to_s.strip.truncate(MAX_CRUMB_MESSAGE).presence
      ].compact.join("  ")
      lines << label if label.present?
    end

    lines.size > 1 ? lines.join("\n") : nil
  end

  def crumb_time(timestamp)
    return nil if timestamp.blank?

    Time.parse(timestamp.to_s).strftime("%H:%M:%S")
  rescue ArgumentError, TypeError
    nil
  end

  # ---- task --------------------------------------------------------------

  def task_section
    "## Task\nExplain the root cause in 1-2 sentences, then give the smallest " \
      "code change that fixes it. Note any edge cases to verify."
  end

  # ---- shared ------------------------------------------------------------

  def frames
    @frames ||= event_frames(event)
  end

  def metadata
    event.metadata.is_a?(Hash) ? event.metadata : {}
  end

  def tags
    event.tags.is_a?(Hash) ? event.tags : {}
  end

  def exception_class
    metadata["exception_class"].to_s.strip.presence
  end
end

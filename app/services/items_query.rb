# Parses the Items view query bar into structured filters and renders it back
# into removable chips.
#
# The query string is a space-separated mix of `key:value` tokens and free
# keyword text, e.g.  `level:error env:prod is:unresolved checkout timeout`.
#
# Supported keys (mirror the suggestion vocabulary in the design):
#   level:     error | warning | fatal | info | debug
#   is:        unresolved | resolved | muted | ignored | regression
#   env:       <environment name>
#   assigned:  me | none | <email>
#   release:   <release>            (filters raw events; no-op on grouped issues)
#   browser:   <name>               (parsed, not yet indexed — TODO)
#   has:       assignee | link | comments
#
# Anything that is not a recognised `key:value` becomes free-text keyword,
# matched (ILIKE) against the event/issue message.
class ItemsQuery
  KEYS = %w[level is env assigned release browser has].freeze

  # Static vocabulary for the query-bar suggestions dropdown. Kept server-side
  # so the rendered chips and the Stimulus controller share one source of truth.
  SUGGESTIONS = [
    { key: "level",    values: %w[error warning fatal info debug],        desc: "severity of the event" },
    { key: "is",       values: %w[unresolved resolved muted ignored regression], desc: "resolution status" },
    { key: "env",      values: %w[production staging development],        desc: "deployment environment" },
    { key: "assigned", values: %w[me none],                               desc: "who owns it" },
    { key: "release",  values: [],                                        desc: "build / version" },
    { key: "browser",  values: %w[chrome safari firefox],                 desc: "client browser" },
    { key: "has",      values: %w[assignee link comments],                desc: "attribute present" }
  ].freeze

  Token = Struct.new(:key, :value)

  attr_reader :tokens, :keyword

  def self.parse(raw)
    new(raw)
  end

  def initialize(raw)
    @tokens = []
    words   = []
    raw.to_s.strip.split(/\s+/).each do |part|
      key, val = part.split(":", 2)
      if val && KEYS.include?(key.downcase) && val.strip.present?
        @tokens << Token.new(key.downcase, val.strip)
      else
        words << part
      end
    end
    @keyword = words.join(" ").presence
  end

  def empty?
    tokens.empty? && keyword.blank?
  end

  def values(key)
    tokens.select { |t| t.key == key.to_s }.map(&:value)
  end

  def has_token?(key, value)
    tokens.any? { |t| t.key == key.to_s && t.value.casecmp?(value.to_s) }
  end

  # `warn` is an accepted alias for the `warning` level enum.
  def levels
    values("level").map { |v| v.casecmp?("warn") ? "warning" : v.downcase }
  end

  def environments = values("env")
  def releases     = values("release")
  def statuses     = values("is").map(&:downcase)
  def assignees    = values("assigned")

  # Canonical query string: tokens first, then any free keyword.
  def to_s
    (tokens.map { |t| "#{t.key}:#{t.value}" } + Array(keyword)).join(" ")
  end

  # Returns a new query string with `key:value` toggled (added if absent,
  # removed if present). Used by facet / suggestion links so a click flips a
  # filter without the caller hand-assembling the string.
  def toggle(key, value)
    if has_token?(key, value)
      remaining = tokens.reject { |t| t.key == key.to_s && t.value.casecmp?(value.to_s) }
      (remaining.map { |t| "#{t.key}:#{t.value}" } + Array(keyword)).join(" ")
    else
      [ to_s, "#{key}:#{value}" ].reject(&:blank?).join(" ")
    end
  end

  # Chips for the query bar. `tone` drives the value colour (see items styles).
  def chips
    tokens.map do |t|
      { key: "#{t.key}:", value: t.value, raw: "#{t.key}:#{t.value}", tone: tone_for(t.key) }
    end
  end

  private

  def tone_for(key)
    case key
    when "level"          then "is-level"
    when "env"            then "is-env"
    when "is", "assigned" then "is-status"
    else ""
    end
  end
end

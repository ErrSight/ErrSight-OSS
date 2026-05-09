require "test_helper"

class FixPromptBuilderTest < ActiveSupport::TestCase
  # A structured event as shipped by errsight-ruby >= 0.2.0: exception_class
  # plus frames carrying source context for the in_app frame.
  def structured_event(overrides = {})
    metadata = {
      "exception_class" => "NoMethodError",
      "exception_frames" => [
        {
          "filename" => "app/services/payment.rb",
          "abs_path" => "/srv/app/services/payment.rb",
          "lineno" => 42,
          "function" => "process_payment",
          "in_app" => true,
          "pre_context" => [ "  def process_payment", "    if amount.nil?" ],
          "context_line" => "      raise TypeError, \"amount must be numeric\"",
          "post_context" => [ "    end", "  end" ]
        },
        {
          "filename" => "/gems/actionpack/lib/action_controller/metal.rb",
          "lineno" => 10,
          "function" => "dispatch",
          "in_app" => false
        }
      ]
    }
    projects(:alpha).events.build({
      message: "undefined method `name' for nil",
      level: :error,
      environment: "production",
      release: "v2.3.1",
      metadata: metadata
    }.merge(overrides))
  end

  # ── Core structure ──────────────────────────────────────────────────────────

  test "includes the standard sections in order" do
    prompt = FixPromptBuilder.call(structured_event)

    assert prompt.start_with?("You are debugging")
    assert_includes prompt, "## Error"
    assert_includes prompt, "## Where it failed"
    assert_includes prompt, "## Stack trace (your code first)"
    assert_includes prompt, "## Task"
    # Section ordering: Error precedes Stack precedes Task.
    assert prompt.index("## Error") < prompt.index("## Stack trace")
    assert prompt.index("## Stack trace") < prompt.index("## Task")
  end

  test "prefixes the exception class when the message omits it" do
    prompt = FixPromptBuilder.call(structured_event)
    assert_includes prompt, "NoMethodError: undefined method `name' for nil"
  end

  test "does not double-prefix when the message already starts with the class" do
    event  = structured_event(message: "NoMethodError: boom")
    prompt = FixPromptBuilder.call(event)
    refute_includes prompt, "NoMethodError: NoMethodError"
  end

  test "renders level, environment and release on the meta line" do
    prompt = FixPromptBuilder.call(structured_event)
    assert_includes prompt, "Level: error"
    assert_includes prompt, "Environment: production"
    assert_includes prompt, "Release: v2.3.1"
  end

  # ── Source snippet ──────────────────────────────────────────────────────────

  test "renders the source snippet with the failing line marked" do
    prompt = FixPromptBuilder.call(structured_event)

    assert_includes prompt, "app/services/payment.rb:42 in `process_payment`"
    # The context line is marked with an arrow and carries its line number.
    assert_match(/→\s+42\s+raise TypeError/, prompt)
    # Surrounding context is present and unmarked.
    assert_includes prompt, "  def process_payment"
  end

  test "truncates very long source lines" do
    long = "x" * 500
    event = structured_event
    event.metadata["exception_frames"][0]["context_line"] = long
    prompt = FixPromptBuilder.call(event)

    refute_includes prompt, long
  end

  # ── Stack trace ─────────────────────────────────────────────────────────────

  test "lists in-app frames and notes omitted frames" do
    prompt = FixPromptBuilder.call(structured_event)

    assert_includes prompt, "app/services/payment.rb:42 in `process_payment`"
    # The single framework frame is summarized, not listed.
    refute_includes prompt, "action_controller/metal.rb"
    assert_includes prompt, "[1 more frame omitted]"
  end

  test "caps the number of in-app frames shown" do
    frames = Array.new(40) do |i|
      { "filename" => "app/x#{i}.rb", "lineno" => i + 1, "function" => "m#{i}", "in_app" => true }
    end
    event  = structured_event(metadata: { "exception_frames" => frames })
    prompt = FixPromptBuilder.call(event)

    assert_includes prompt, "app/x0.rb:1 in `m0`"
    assert_includes prompt, "[22 more frames omitted]"
    assert_operator prompt.length, :<=, FixPromptBuilder::MAX_PROMPT_CHARS
  end

  # ── Legacy backtrace fallback ───────────────────────────────────────────────

  test "falls back to the parsed backtrace string for legacy events" do
    event = projects(:alpha).events.build(
      message: "PG::Error: deadlock detected",
      level: :error,
      backtrace: "app/models/order.rb:55:in `save'\n/gems/activerecord/lib/x.rb:10:in `call'"
    )
    prompt = FixPromptBuilder.call(event)

    assert_includes prompt, "## Stack trace (your code first)"
    assert_includes prompt, "app/models/order.rb:55 in `save`"
    # No structured source context exists, so no snippet arrow is rendered.
    refute_includes prompt, "→"
  end

  # ── Cause chain ─────────────────────────────────────────────────────────────

  test "renders the exception cause chain" do
    event = structured_event(metadata: {
      "exception_causes" => [
        { "class" => "StandardError", "message" => "upstream timeout", "backtrace" => "..." }
      ]
    })
    prompt = FixPromptBuilder.call(event)

    assert_includes prompt, "## Caused by"
    assert_includes prompt, "StandardError: upstream timeout"
  end

  # ── Request ─────────────────────────────────────────────────────────────────

  test "renders method from tags and path from metadata" do
    event = structured_event(
      metadata: { "full_path" => "/api/payments/123" },
      tags: { "request_method" => "POST" }
    )
    prompt = FixPromptBuilder.call(event)

    assert_includes prompt, "## Request"
    assert_includes prompt, "POST /api/payments/123"
  end

  # ── Breadcrumbs ─────────────────────────────────────────────────────────────

  test "renders recent breadcrumbs" do
    event = structured_event(breadcrumbs: [
      { "timestamp" => "2026-06-14T10:30:30Z", "level" => "info", "category" => "log", "message" => "Processing payment" }
    ])
    prompt = FixPromptBuilder.call(event)

    assert_includes prompt, "## Recent breadcrumbs"
    assert_includes prompt, "Processing payment"
  end

  # ── PII redaction (the privacy guarantee) ───────────────────────────────────

  test "never leaks end-user PII from user_context or tags" do
    event = structured_event(
      user_context: { "email" => "alice@example.com", "username" => "alice_jones", "ip_address" => "203.0.113.45" },
      tags: { "request_method" => "POST", "user_email" => "alice@example.com" },
      metadata: { "full_path" => "/checkout", "exception_class" => "NoMethodError" }
    )
    prompt = FixPromptBuilder.call(event)

    refute_includes prompt, "alice@example.com"
    refute_includes prompt, "alice_jones"
    refute_includes prompt, "203.0.113.45"
    # The non-PII request verb is still allowed through.
    assert_includes prompt, "POST /checkout"
  end

  # ── Occurrence stats (joins the Issue) ──────────────────────────────────────

  test "includes occurrence stats when a matching issue exists" do
    project = projects(:alpha)
    fp = "fixprompt000000000000000000000001"
    Issue.create!(
      project: project,
      fingerprint: fp,
      occurrences_count: 3104,
      affected_users_count: 88,
      first_seen_at: Time.utc(2026, 6, 10),
      last_seen_at: Time.current,
      severity: 3
    )
    event  = project.events.build(message: "Boom", level: :error, fingerprint: fp)
    prompt = FixPromptBuilder.call(event, project: project)

    assert_includes prompt, "3104 occurrences"
    assert_includes prompt, "88 users affected"
    assert_includes prompt, "first seen 2026-06-10"
  end

  test "omits occurrence stats when no issue is found" do
    event  = projects(:alpha).events.build(message: "Boom", level: :error, fingerprint: "nomatch_fp")
    prompt = FixPromptBuilder.call(event)

    refute_includes prompt, "occurrences"
    refute_includes prompt, "users affected"
  end

  # ── Truncation backstops ────────────────────────────────────────────────────

  test "truncates an oversized message" do
    event  = projects(:alpha).events.build(message: "y" * 2000, level: :error)
    prompt = FixPromptBuilder.call(event)

    refute_includes prompt, "y" * 1000
  end

  test "caps the overall prompt length" do
    crumbs = Array.new(8) { |i| { "timestamp" => "2026-06-14T10:30:0#{i}Z", "message" => "z" * 400, "category" => "log", "level" => "info" } }
    frames = Array.new(18) do |i|
      { "filename" => ("app/very/long/path/segment#{i}.rb" * 4), "lineno" => i, "function" => "m" * 80, "in_app" => true }
    end
    event = structured_event(metadata: { "exception_frames" => frames }, breadcrumbs: crumbs, message: "w" * 2000)
    prompt = FixPromptBuilder.call(event)

    assert_operator prompt.length, :<=, FixPromptBuilder::MAX_PROMPT_CHARS
  end
end

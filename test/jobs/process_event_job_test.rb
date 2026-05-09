require "test_helper"

class ProcessEventJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  def event_data(overrides = {})
    {
      "level"       => "error",
      "message"     => "Something went wrong",
      "environment" => "production",
      "backtrace"   => "app/foo.rb:10",
      "metadata"    => { "user" => "42" },
      "occurred_at" => 1.hour.ago.iso8601
    }.merge(overrides)
  end

  test "log_arguments is disabled so PII does not leak into Active Job logs" do
    assert_equal false, ProcessEventJob.log_arguments
  end

  test "creates an Event for the project" do
    project = projects(:admin_project)
    assert_difference "project.events.count", 1 do
      ProcessEventJob.new.perform(project.id, event_data)
    end
  end

  test "stores correct level on the event" do
    project = projects(:admin_project)
    ProcessEventJob.new.perform(project.id, event_data("level" => "fatal"))
    assert project.events.order(:created_at).last.fatal?
  end

  test "stores correct message on the event" do
    project = projects(:admin_project)
    ProcessEventJob.new.perform(project.id, event_data("message" => "DB connection failed"))
    assert_equal "DB connection failed", project.events.order(:created_at).last.message
  end

  # ── ingestion_id idempotency ─────────────────────────────────────────────────

  test "same ingestion_id processed twice creates only one event" do
    project = projects(:admin_project)
    data = event_data("ingestion_id" => "dup-ingestion-abc123")

    assert_difference "project.events.count", 1 do
      ProcessEventJob.new.perform(project.id, data)
      ProcessEventJob.new.perform(project.id, data)
    end
  end

  test "different ingestion_ids produce distinct events" do
    project = projects(:admin_project)

    assert_difference "project.events.count", 2 do
      ProcessEventJob.new.perform(project.id, event_data("ingestion_id" => "id-one"))
      ProcessEventJob.new.perform(project.id, event_data("ingestion_id" => "id-two"))
    end
  end

  test "missing ingestion_id does not dedupe (each call creates an event)" do
    project = projects(:admin_project)

    assert_difference "project.events.count", 2 do
      ProcessEventJob.new.perform(project.id, event_data)
      ProcessEventJob.new.perform(project.id, event_data)
    end
  end

  test "drops event when project has ingestion paused" do
    project = projects(:admin_project)
    project.update_column(:ingestion_paused, true)

    assert_no_difference "Event.count" do
      ProcessEventJob.new.perform(project.id, event_data)
    end
  end

  test "returns early when project does not exist" do
    assert_no_difference "Event.count" do
      ProcessEventJob.new.perform(999_999, event_data)
    end
  end

  test "defaults occurred_at to now when not provided" do
    project = projects(:admin_project)
    freeze_time do
      ProcessEventJob.new.perform(project.id, event_data.except("occurred_at"))
      event = project.events.order(:created_at).last
      assert_in_delta Time.current.to_i, event.occurred_at.to_i, 2
    end
  end

  # ── Regression detection ─────────────────────────────────────────────────────

  test "marks event as regression when prior events were all resolved" do
    project = projects(:admin_project)
    fp = "regression-fp-1"
    project.events.create!(level: "error", message: "prior", environment: "production",
                           fingerprint: fp, occurred_at: 1.day.ago, size_bytes: 100, resolved: true)

    ProcessEventJob.new.perform(project.id, event_data("fingerprint" => fp))
    event = project.events.where(fingerprint: fp).order(:created_at).last

    assert event.is_regression?
  end

  test "reopens previously resolved events on regression" do
    project = projects(:admin_project)
    fp = "regression-fp-2"
    prior = project.events.create!(level: "error", message: "prior", environment: "production",
                                   fingerprint: fp, occurred_at: 1.day.ago, size_bytes: 100, resolved: true)

    ProcessEventJob.new.perform(project.id, event_data("fingerprint" => fp))

    assert_not prior.reload.resolved?
  end

  test "does not mark as regression when a prior event is unresolved" do
    project = projects(:admin_project)
    fp = "regression-fp-3"
    project.events.create!(level: "error", message: "prior", environment: "production",
                           fingerprint: fp, occurred_at: 1.day.ago, size_bytes: 100, resolved: false)

    ProcessEventJob.new.perform(project.id, event_data("fingerprint" => fp))
    event = project.events.where(fingerprint: fp).order(:created_at).last

    assert_not event.is_regression?
  end

  test "does not mark the very first event as a regression" do
    project = projects(:admin_project)
    ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "brand-new-fp"))
    event = project.events.where(fingerprint: "brand-new-fp").last
    assert_not event.is_regression?
  end

  # ── Mute rule short-circuit ──────────────────────────────────────────────────

  test "enqueues alert jobs when no mute rule matches the fingerprint" do
    project = projects(:admin_project)
    assert_enqueued_with(job: SendEventAlertJob) do
      ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "unmuted-fp"))
    end
  end

  test "skips alert jobs when a mute rule matches the persisted fingerprint" do
    project = projects(:admin_project)
    project.mute_rules.create!(fingerprint: "muted-fp")

    assert_no_enqueued_jobs only: [ SendEventAlertJob, SendSlackAlertJob, SendWebhookAlertJob ] do
      ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "muted-fp"))
    end
  end

  test "expired mute rule does not block alert jobs" do
    project = projects(:admin_project)
    project.mute_rules.create!(fingerprint: "expired-fp", expires_at: 1.hour.ago)

    assert_enqueued_with(job: SendEventAlertJob) do
      ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "expired-fp"))
    end
  end

  # ── Broadcasts ───────────────────────────────────────────────────────────────

  test "broadcasts a structured JSON payload (no server-rendered HTML) on the project's logs stream" do
    project = projects(:admin_project)
    stream = ProjectLogsChannel.broadcasting_for(project)

    broadcasts = capture_broadcasts(stream) do
      ProcessEventJob.new.perform(
        project.id,
        event_data(
          "message"  => "Boom",
          "level"    => "error",
          "metadata" => { "request_id" => "abcdef1234567890", "email" => "bug@example.com", "full_path" => "/foo" }
        )
      )
    end

    assert_equal 1, broadcasts.size, "expected exactly one broadcast"
    payload = broadcasts.first

    assert_not payload.key?("html"), "broadcast must not carry server-rendered HTML"
    assert_equal "Boom",            payload["message"]
    assert_equal "error",           payload["level"]
    assert_equal "abcdef1234567890", payload["request_id"]
    assert_equal "bug@example.com",  payload["email"]
    assert_equal "/foo",             payload["full_path"]
  end

  # ── Batched payload ──────────────────────────────────────────────────────────

  test "perform accepts an array of events and persists each one" do
    project = projects(:admin_project)
    batch = [
      event_data("message" => "first",  "ingestion_id" => "batch-1"),
      event_data("message" => "second", "ingestion_id" => "batch-2"),
      event_data("message" => "third",  "ingestion_id" => "batch-3")
    ]

    assert_difference "project.events.count", 3 do
      ProcessEventJob.new.perform(project.id, batch)
    end
  end

  # Pins the in-flight-at-deploy compatibility shim. Removing the
  # `events_data = [events_data] if events_data.is_a?(Hash)` normalization
  # would silently break any ProcessEventJob already serialized from before
  # the batching change.
  test "perform still accepts a single hash for backward compatibility" do
    project = projects(:admin_project)
    assert_difference "project.events.count", 1 do
      ProcessEventJob.new.perform(project.id, event_data("ingestion_id" => "compat-1"))
    end
  end

  test "permanent validation error on one event in a batch does not drop its siblings" do
    project = projects(:admin_project)
    bad  = event_data("message" => "",   "ingestion_id" => "bad-1")
    good = event_data("message" => "ok", "ingestion_id" => "good-1")

    assert_difference "project.events.count", 1 do
      ProcessEventJob.new.perform(project.id, [ bad, good ])
    end
    assert project.events.exists?(ingestion_id: "good-1")
    assert_not project.events.exists?(ingestion_id: "bad-1")
  end

  # ── Alert debounce per (project, fingerprint) ────────────────────────────────

  # Default test cache is :null_store, where write(..., unless_exist:) always
  # returns true — that masks the debounce. Swap in a MemoryStore so the real
  # cache semantics are exercised.
  test "consecutive events with the same fingerprint enqueue alerts only once per debounce window" do
    project = projects(:admin_project)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      assert_enqueued_jobs 1, only: SendEventAlertJob do
        3.times do |i|
          ProcessEventJob.new.perform(
            project.id,
            event_data("fingerprint" => "spammy-fp", "ingestion_id" => "dbnc-#{i}")
          )
        end
      end
    ensure
      Rails.cache = original_cache
    end
  end

  test "different fingerprints debounce independently" do
    project = projects(:admin_project)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      assert_enqueued_jobs 2, only: SendEventAlertJob do
        ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "fp-a", "ingestion_id" => "a-1"))
        ProcessEventJob.new.perform(project.id, event_data("fingerprint" => "fp-b", "ingestion_id" => "b-1"))
      end
    ensure
      Rails.cache = original_cache
    end
  end

  # A regression is a state change (resolved → unresolved), not noise — it
  # must alert even if the same fingerprint had a recent alert.
  test "regression bypasses the alert debounce" do
    project = projects(:admin_project)
    fp = "regression-debounce-fp"
    project.events.create!(level: "error", message: "prior", environment: "production",
                           fingerprint: fp, occurred_at: 1.day.ago, size_bytes: 100, resolved: true)

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      Rails.cache.write("alert_debounce:project:#{project.id}:fingerprint:#{fp}", true, expires_in: 5.minutes)

      assert_enqueued_with(job: SendEventAlertJob) do
        ProcessEventJob.new.perform(
          project.id,
          event_data("fingerprint" => fp, "ingestion_id" => "regress-1")
        )
      end
    ensure
      Rails.cache = original_cache
    end
  end
end

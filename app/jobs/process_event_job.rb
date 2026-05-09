class ProcessEventJob < ApplicationJob
  queue_as :events

  # Event payloads contain user PII (email, IP, user_context). Without this,
  # the full hash is serialized into solid_queue_jobs.arguments and persists
  # there until the queue's retention sweep — a secondary PII store that
  # bypasses DataErasure.
  self.log_arguments = false

  # First-alert wins; subsequent events with the same (project, fingerprint)
  # are silenced for this window. Bursts on a single error stop spamming
  # email/Slack/webhooks while the dashboard still ingests every event.
  ALERT_DEBOUNCE_WINDOW = 5.minutes

  discard_on ActiveJob::DeserializationError
  # Permanent errors that won't recover by retrying — fail fast so the dead
  # job surfaces the root cause instead of being polluted by retry noise.
  discard_on ActiveRecord::RecordNotFound

  # Transient errors only. Connection blips, deadlocks, lock timeouts.
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::QueryCanceled, wait: :polynomially_longer, attempts: 3

  def perform(project_id, events_data)
    # In-flight jobs from before the batching change are serialized with a
    # single hash — accept either shape so a deploy mid-queue doesn't fail.
    events_data = [ events_data ] if events_data.is_a?(Hash)

    project = Project.find_by(id: project_id)
    return unless project

    # Events accepted by the API but the project got paused by the time the
    # job ran. Drop the batch silently.
    return if project.drop_reason

    events_data.each do |event_data|
      process_one(project, event_data)
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::NotNullViolation,
           ActiveRecord::ValueTooLong => e
      # One bad event in a batch must not drop its siblings. Permanent
      # validation errors are logged and skipped; transient errors propagate
      # so retry_on triggers a whole-batch retry (idempotency_id no-ops the
      # events that already persisted).
      Rails.logger.warn("[ProcessEventJob] discard event in batch error=#{e.class} project_id=#{project_id}")
    end
  end

  private

  def process_one(project, event_data)
    ingestion_id = event_data["ingestion_id"]

    event = persist_with_idempotency(project, event_data, ingestion_id)
    return unless event

    if alert_should_fire?(project, event)
      SendEventAlertJob.perform_later(event.id)
      SendSlackAlertJob.perform_later(event.id)
      SendWebhookAlertJob.perform_later(event.id)
    end
    broadcast_log_row(project, event)
    broadcast_dashboard_row(project, event)
  end

  # Gate the three Send*AlertJob enqueues on a per-(project, fingerprint)
  # claim. A spike on one fingerprint used to enqueue 3×N alert jobs; now it
  # enqueues 3 for the first event and 0 for the rest of the window.
  # Regressions always alert — they are state changes, not noise. Persisted
  # events always have a fingerprint (Event#set_fingerprint runs in
  # before_validation), so we don't need a blank-fingerprint fallback here.
  def alert_should_fire?(project, event)
    return false if MuteRule.muted?(project.id, event.fingerprint)
    return true  if event.is_regression?

    debounce_key = "alert_debounce:project:#{project.id}:fingerprint:#{event.fingerprint}"
    Rails.cache.write(debounce_key, true, expires_in: ALERT_DEBOUNCE_WINDOW, unless_exist: true)
  end

  def persist_with_idempotency(project, event_data, ingestion_id)
    ActiveRecord::Base.transaction do
      if ingestion_id.present?
        # Serialize concurrent retries of the same ingestion_id so the
        # exists?-then-insert window can't produce duplicates. TimescaleDB
        # disallows a pure (project_id, ingestion_id) unique index on the
        # events hypertable (must include the partitioning column), so we
        # lock at the app layer instead.
        lock_key = Zlib.crc32("errsight:ingest:#{project.id}:#{ingestion_id}") % 2**31
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key.to_i})")

        return nil if project.events.where(ingestion_id: ingestion_id).exists?
      end

      event = EventRepository.build_for(
        project: project,
        attributes: {
          level:           event_data["level"],
          message:         event_data["message"],
          backtrace:       event_data["backtrace"],
          environment:     event_data["environment"],
          metadata:        event_data["metadata"] || {},
          occurred_at:     event_data["occurred_at"] || Time.current,
          fingerprint:     event_data["fingerprint"],
          user_context:    event_data["user_context"] || {},
          user_identifier: event_data["user_identifier"],
          release:         event_data["release"],
          breadcrumbs:     event_data["breadcrumbs"] || [],
          tags:            event_data["tags"] || {},
          ingestion_id:    ingestion_id
        }
      )

      EventRepository.persist_new!(event)
      event
    end
  end

  def broadcast_log_row(project, event)
    metadata = event.metadata || {}
    ProjectLogsChannel.broadcast_to(project, {
      id:          event.id,
      level:       event.level,
      environment: event.environment,
      message:     event.message,
      ts_main:     event.occurred_at.strftime("%Y-%m-%d %H:%M:%S"),
      ts_ms:       event.occurred_at.strftime("%L"),
      request_id:  metadata["request_id"],
      email:       metadata["email"],
      user_id:     metadata["user_id"],
      full_path:   metadata["full_path"],
      url:         Rails.application.routes.url_helpers.project_event_path(project, event)
    })
  rescue StandardError => e
    Rails.logger.warn("[ProcessEventJob] broadcast failed error=#{e.class}")
  end

  def broadcast_dashboard_row(project, event)
    DashboardEventsChannel.broadcast_to(project.organization, {
      level:        event.level,
      message:      event.message,
      occurred_at:  event.occurred_at.strftime("%H:%M:%S.%L"),
      project_name: project.name,
      environment:  event.environment,
      url:          Rails.application.routes.url_helpers.project_event_path(project, event)
    })
  rescue StandardError => e
    Rails.logger.warn("[ProcessEventJob] dashboard broadcast failed error=#{e.class}")
  end
end

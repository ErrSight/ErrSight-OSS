# Initial schema for ErrSight Community Edition.
#
# This migration replaces the squashed history of the SaaS edition. A fresh
# install runs this once and lands at the schema.rb version below; future
# changes ship as additional migrations on top.
#
# TimescaleDB is intentionally not required here. The events table works on
# plain Postgres; convert it to a hypertable separately by enabling the
# extension and running `lib/tasks/timescale.rake` (see README).

class CreateInitialSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :action_mailbox_inbound_emails do |t|
      t.string  :message_id, null: false
      t.string  :message_checksum, null: false
      t.integer :status, default: 0, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :message_id, :message_checksum ], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
    end

    create_table :action_text_rich_texts do |t|
      t.string :name, null: false
      t.text   :body
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :record_type, :record_id, :name ], name: "index_action_text_rich_texts_uniqueness", unique: true
    end

    create_table :active_admin_comments do |t|
      t.string :namespace
      t.text   :body
      t.string :resource_type
      t.bigint :resource_id
      t.string :author_type
      t.bigint :author_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :author_type, :author_id ], name: "index_active_admin_comments_on_author"
      t.index [ :namespace ],                 name: "index_active_admin_comments_on_namespace"
      t.index [ :resource_type, :resource_id ], name: "index_active_admin_comments_on_resource"
    end

    create_table :active_storage_blobs do |t|
      t.string  :key, null: false
      t.string  :filename, null: false
      t.string  :content_type
      t.text    :metadata
      t.string  :service_name, null: false
      t.bigint  :byte_size, null: false
      t.string  :checksum
      t.datetime :created_at, null: false
      t.index [ :key ], name: "index_active_storage_blobs_on_key", unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string  :name, null: false
      t.string  :record_type, null: false
      t.bigint  :record_id, null: false
      t.bigint  :blob_id, null: false
      t.datetime :created_at, null: false
      t.index [ :blob_id ], name: "index_active_storage_attachments_on_blob_id"
      t.index [ :record_type, :record_id, :name, :blob_id ], name: "index_active_storage_attachments_uniqueness", unique: true
    end

    create_table :active_storage_variant_records do |t|
      t.bigint :blob_id, null: false
      t.string :variation_digest, null: false
      t.index [ :blob_id, :variation_digest ], name: "index_active_storage_variant_records_uniqueness", unique: true
    end

    create_table :users do |t|
      t.string  :email, default: "", null: false
      t.string  :encrypted_password, default: "", null: false
      t.string  :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.string  :name
      t.boolean :admin, default: false, null: false
      t.string  :provider
      t.string  :uid
      t.string  :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string  :unconfirmed_email
      t.datetime :discarded_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :confirmation_token ],   name: "index_users_on_confirmation_token", unique: true
      t.index [ :email ],                name: "index_users_on_email", unique: true
      t.index [ :provider, :uid ],       name: "index_users_on_provider_and_uid", unique: true
      t.index [ :reset_password_token ], name: "index_users_on_reset_password_token", unique: true
    end

    create_table :organizations do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.bigint  :owner_id, null: false
      t.string  :slack_webhook_url
      t.datetime :discarded_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :discarded_at ], name: "index_organizations_on_discarded_at"
      t.index [ :owner_id ],     name: "index_organizations_on_owner_id"
      t.index [ :slug ],         name: "index_organizations_on_slug", unique: true
    end

    create_table :memberships do |t|
      t.bigint  :user_id, null: false
      t.bigint  :organization_id, null: false
      t.integer :role, default: 0, null: false
      t.boolean :weekly_digest_enabled, default: true, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :organization_id, :user_id ], name: "index_memberships_on_organization_id_and_user_id", unique: true
      t.index [ :user_id ],                   name: "index_memberships_on_user_id"
    end

    create_table :invitations do |t|
      t.bigint  :organization_id, null: false
      t.bigint  :invited_by_id, null: false
      t.string  :email, null: false
      t.string  :token, null: false
      t.integer :role, default: 1, null: false
      t.integer :status, default: 0, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :email ],            name: "index_invitations_on_email"
      t.index [ :expires_at ],       name: "index_invitations_on_expires_at"
      t.index [ :organization_id, :email ], name: "index_invitations_on_org_email_pending", unique: true, where: "(status = 0)"
      t.index [ :token ],            name: "index_invitations_on_token", unique: true
    end

    create_table :projects do |t|
      t.string  :name, null: false
      t.string  :api_key, null: false
      t.string  :slug
      t.bigint  :user_id, null: false
      t.bigint  :organization_id, null: false
      t.boolean :ingestion_paused, default: false, null: false
      t.boolean :admin_paused, default: false, null: false
      t.integer :rate_limit_per_minute, default: 60, null: false
      t.integer :events_count, default: 0, null: false
      t.bigint  :storage_bytes, default: 0, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :api_key ],         name: "index_projects_on_api_key", unique: true
      t.index [ :organization_id ], name: "index_projects_on_organization_id"
      t.index [ :slug ],            name: "index_projects_on_slug", unique: true
      t.index [ :user_id ],         name: "index_projects_on_user_id"
    end

    create_table :api_keys do |t|
      t.bigint  :project_id, null: false
      t.string  :name, null: false
      t.string  :token, null: false
      t.integer :scope, default: 0, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :project_id, :name ], name: "index_api_keys_on_project_id_and_name", unique: true
      t.index [ :project_id ],        name: "index_api_keys_on_project_id"
      t.index [ :token ],             name: "index_api_keys_on_token", unique: true
    end

    # Composite primary key (id, occurred_at) is required by TimescaleDB
    # hypertable conversion (the partitioning column must be in the PK). Works
    # fine on plain Postgres too. id is bigserial so insert-side semantics
    # match a normal AR table.
    create_table :events, primary_key: %w[id occurred_at], id: false, force: :cascade do |t|
      t.bigserial :id, null: false
      t.bigint    :project_id, null: false
      t.integer   :level, default: 0, null: false
      t.text      :message, null: false
      t.text      :backtrace
      t.string    :environment, default: "production"
      t.string    :fingerprint
      t.string    :ingestion_id
      t.string    :release
      t.string    :user_identifier
      t.boolean   :resolved, default: false, null: false
      t.boolean   :is_regression, default: false, null: false
      t.boolean   :discarded, default: false, null: false
      t.integer   :size_bytes, default: 0, null: false
      t.jsonb     :metadata, default: {}
      t.jsonb     :user_context, default: {}, null: false
      t.jsonb     :tags, default: {}, null: false
      t.jsonb     :breadcrumbs, default: [], null: false
      t.timestamptz :occurred_at, null: false
      t.timestamptz :discarded_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
      t.index [ :discarded_at ],     name: "index_events_on_discarded_at"
      t.index [ :environment ],      name: "index_events_on_environment"
      t.index [ :fingerprint ],      name: "index_events_on_fingerprint"
      t.index [ :level ],            name: "index_events_on_level"
      t.index [ :message ],          name: "index_events_on_message_trgm", opclass: :gin_trgm_ops, using: :gin
      t.index [ :metadata ],         name: "index_events_on_metadata", using: :gin
      t.index [ :occurred_at ],      name: "index_events_on_occurred_at"
      t.index [ :project_id, :fingerprint, :resolved ],         name: "index_events_on_project_fingerprint_resolved"
      t.index [ :project_id, :fingerprint, :user_identifier ], name: "index_events_on_affected_users"
      t.index [ :project_id, :fingerprint ],                   name: "index_events_on_project_id_and_fingerprint"
      t.index [ :project_id, :ingestion_id ],                  name: "index_events_on_project_id_and_ingestion_id", where: "(ingestion_id IS NOT NULL)"
      t.index [ :project_id, :occurred_at ],                   name: "index_events_on_project_id_and_occurred_at"
      t.index [ :project_id ],       name: "index_events_on_project_id"
      t.index [ :release ],          name: "index_events_on_release"
      t.index [ :resolved ],         name: "index_events_on_resolved"
      t.index [ :size_bytes ],       name: "index_events_on_size_bytes"
      t.index [ :tags ],             name: "index_events_on_tags", using: :gin
      t.index [ :user_identifier ],  name: "index_events_on_user_identifier"
    end

    create_table :issues do |t|
      t.bigint  :project_id, null: false
      t.string  :fingerprint, null: false
      t.bigint  :assigned_to_id
      t.text    :last_message
      t.string  :last_environment
      t.timestamptz :first_seen_at
      t.timestamptz :last_seen_at
      t.bigint  :occurrences_count, default: 0, null: false
      t.bigint  :affected_users_count, default: 0, null: false
      t.bigint  :resolved_count, default: 0, null: false
      t.integer :severity, default: 0, null: false
      t.string  :external_url
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :assigned_to_id ],                     name: "index_issues_on_assigned_to_id"
      t.index [ :project_id, :fingerprint ],           name: "index_issues_on_project_id_and_fingerprint", unique: true
      t.index [ :project_id, :last_seen_at ],          name: "index_issues_on_project_and_last_seen", order: { last_seen_at: :desc }
      t.index [ :project_id ],                         name: "index_issues_on_project_id"
    end

    create_table :issue_users do |t|
      t.bigint :issue_id, null: false
      t.string :user_identifier, limit: 200, null: false
      t.timestamptz :first_seen_at, null: false
      t.index [ :issue_id, :user_identifier ], name: "index_issue_users_unique", unique: true
      t.index [ :issue_id ],                   name: "index_issue_users_on_issue_id"
    end

    create_table :issue_comments do |t|
      t.bigint :issue_id, null: false
      t.bigint :user_id
      t.text   :body, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :issue_id ], name: "index_issue_comments_on_issue_id"
      t.index [ :user_id ],  name: "index_issue_comments_on_user_id"
    end

    create_table :mute_rules do |t|
      t.bigint  :project_id, null: false
      t.string  :fingerprint, null: false
      t.boolean :hide_from_issues, default: true, null: false
      t.datetime :expires_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :project_id, :fingerprint ], name: "index_mute_rules_on_project_id_and_fingerprint", unique: true
      t.index [ :project_id ],               name: "index_mute_rules_on_project_id"
    end

    create_table :alert_preferences do |t|
      t.bigint  :membership_id, null: false
      t.bigint  :project_id
      t.boolean :email_enabled, default: true, null: false
      t.boolean :slack_enabled, default: false, null: false
      t.integer :min_level, default: 3, null: false
      t.integer :digest_frequency, default: 0, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :membership_id, :project_id ], name: "index_alert_preferences_on_membership_id_and_project_id", unique: true
      t.index [ :project_id ],                 name: "index_alert_preferences_on_project_id"
    end

    create_table :alert_rules do |t|
      t.bigint  :project_id, null: false
      t.string  :name, default: "", null: false
      t.integer :rule_type, default: 0, null: false
      t.integer :level_threshold, default: 3, null: false
      t.integer :count_threshold, default: 1, null: false
      t.integer :window_seconds, default: 3600, null: false
      t.boolean :active, default: true, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :project_id ], name: "index_alert_rules_on_project_id"
    end

    create_table :webhook_endpoints do |t|
      t.bigint  :project_id, null: false
      t.string  :url, null: false
      t.string  :secret, null: false
      t.boolean :active, default: true, null: false
      t.integer :failure_count, default: 0, null: false
      t.datetime :last_delivered_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :project_id ], name: "index_webhook_endpoints_on_project_id"
    end

    create_table :saved_filters do |t|
      t.bigint :user_id, null: false
      t.string :name, null: false
      t.jsonb  :filters, default: {}, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :user_id, :name ], name: "index_saved_filters_on_user_id_and_name", unique: true
      t.index [ :user_id ],        name: "index_saved_filters_on_user_id"
    end

    create_table :rate_limit_windows do |t|
      t.string  :key, null: false
      t.bigint  :window_start, null: false
      t.integer :count, default: 0, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :key, :window_start ], name: "index_rate_limit_windows_on_key_and_window", unique: true
      t.index [ :window_start ],       name: "index_rate_limit_windows_on_window_start"
    end

    # ============================================================
    # Solid Queue / Solid Cache / Solid Cable infrastructure tables
    # ============================================================

    create_table :solid_cable_messages do |t|
      t.binary :channel, null: false
      t.binary :payload, null: false
      t.bigint :channel_hash, null: false
      t.datetime :created_at, null: false
      t.index [ :channel ],      name: "index_solid_cable_messages_on_channel"
      t.index [ :channel_hash ], name: "index_solid_cable_messages_on_channel_hash"
      t.index [ :created_at ],   name: "index_solid_cable_messages_on_created_at"
    end

    create_table :solid_cache_entries do |t|
      t.binary  :key, null: false
      t.binary  :value, null: false
      t.bigint  :key_hash, null: false
      t.integer :byte_size, null: false
      t.datetime :created_at, null: false
      t.index [ :byte_size ],            name: "index_solid_cache_entries_on_byte_size"
      t.index [ :key_hash, :byte_size ], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index [ :key_hash ],             name: "index_solid_cache_entries_on_key_hash", unique: true
    end

    create_table :solid_queue_jobs do |t|
      t.string  :queue_name, null: false
      t.string  :class_name, null: false
      t.text    :arguments
      t.integer :priority, default: 0, null: false
      t.string  :active_job_id
      t.datetime :scheduled_at
      t.datetime :finished_at
      t.string  :concurrency_key
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :active_job_id ],            name: "index_solid_queue_jobs_on_active_job_id"
      t.index [ :class_name ],               name: "index_solid_queue_jobs_on_class_name"
      t.index [ :finished_at ],              name: "index_solid_queue_jobs_on_finished_at"
      t.index [ :queue_name, :finished_at ], name: "index_solid_queue_jobs_for_filtering"
      t.index [ :scheduled_at, :finished_at ], name: "index_solid_queue_jobs_for_alerting"
    end

    create_table :solid_queue_blocked_executions do |t|
      t.bigint  :job_id, null: false
      t.string  :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.string  :concurrency_key, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.index [ :concurrency_key, :priority, :job_id ], name: "index_solid_queue_blocked_executions_for_release"
      t.index [ :expires_at, :concurrency_key ],         name: "index_solid_queue_blocked_executions_for_maintenance"
      t.index [ :job_id ],                               name: "index_solid_queue_blocked_executions_on_job_id", unique: true
    end

    create_table :solid_queue_claimed_executions do |t|
      t.bigint :job_id, null: false
      t.bigint :process_id
      t.datetime :created_at, null: false
      t.index [ :job_id ],              name: "index_solid_queue_claimed_executions_on_job_id", unique: true
      t.index [ :process_id, :job_id ], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
    end

    create_table :solid_queue_failed_executions do |t|
      t.bigint :job_id, null: false
      t.text   :error
      t.datetime :created_at, null: false
      t.index [ :job_id ], name: "index_solid_queue_failed_executions_on_job_id", unique: true
    end

    create_table :solid_queue_pauses do |t|
      t.string :queue_name, null: false
      t.datetime :created_at, null: false
      t.index [ :queue_name ], name: "index_solid_queue_pauses_on_queue_name", unique: true
    end

    create_table :solid_queue_processes do |t|
      t.string  :kind, null: false
      t.datetime :last_heartbeat_at, null: false
      t.bigint  :supervisor_id
      t.integer :pid, null: false
      t.string  :hostname
      t.text    :metadata
      t.string  :name, null: false
      t.datetime :created_at, null: false
      t.index [ :last_heartbeat_at ],          name: "index_solid_queue_processes_on_last_heartbeat_at"
      t.index [ :name, :supervisor_id ],       name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
      t.index [ :supervisor_id ],              name: "index_solid_queue_processes_on_supervisor_id"
    end

    create_table :solid_queue_ready_executions do |t|
      t.bigint  :job_id, null: false
      t.string  :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.datetime :created_at, null: false
      t.index [ :job_id ],                            name: "index_solid_queue_ready_executions_on_job_id", unique: true
      t.index [ :priority, :job_id ],                 name: "index_solid_queue_poll_all"
      t.index [ :queue_name, :priority, :job_id ],    name: "index_solid_queue_poll_by_queue"
    end

    create_table :solid_queue_recurring_executions do |t|
      t.bigint :job_id, null: false
      t.string :task_key, null: false
      t.datetime :run_at, null: false
      t.datetime :created_at, null: false
      t.index [ :job_id ],            name: "index_solid_queue_recurring_executions_on_job_id", unique: true
      t.index [ :task_key, :run_at ], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
    end

    create_table :solid_queue_recurring_tasks do |t|
      t.string  :key, null: false
      t.string  :schedule, null: false
      t.string  :command, limit: 2048
      t.string  :class_name
      t.text    :arguments
      t.string  :queue_name
      t.integer :priority, default: 0
      t.boolean :static, default: true, null: false
      t.text    :description
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :key ],    name: "index_solid_queue_recurring_tasks_on_key", unique: true
      t.index [ :static ], name: "index_solid_queue_recurring_tasks_on_static"
    end

    create_table :solid_queue_scheduled_executions do |t|
      t.bigint  :job_id, null: false
      t.string  :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :created_at, null: false
      t.index [ :job_id ],                              name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
      t.index [ :scheduled_at, :priority, :job_id ],    name: "index_solid_queue_dispatch_all"
    end

    create_table :solid_queue_semaphores do |t|
      t.string  :key, null: false
      t.integer :value, default: 1, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :expires_at ],   name: "index_solid_queue_semaphores_on_expires_at"
      t.index [ :key, :value ],  name: "index_solid_queue_semaphores_on_key_and_value"
      t.index [ :key ],          name: "index_solid_queue_semaphores_on_key", unique: true
    end

    # ============================================================
    # Foreign keys
    # ============================================================

    add_foreign_key "active_storage_attachments",     "active_storage_blobs", column: "blob_id"
    add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
    add_foreign_key "alert_preferences",  "memberships",   on_delete: :cascade
    add_foreign_key "alert_preferences",  "projects",      on_delete: :cascade
    add_foreign_key "alert_rules",        "projects",      on_delete: :cascade
    add_foreign_key "api_keys",           "projects",      on_delete: :cascade
    add_foreign_key "events",             "projects",      on_delete: :cascade
    add_foreign_key "invitations",        "organizations", on_delete: :cascade
    add_foreign_key "invitations",        "users",         column: "invited_by_id"
    add_foreign_key "issue_comments",     "issues",        on_delete: :cascade
    add_foreign_key "issue_comments",     "users",         on_delete: :nullify
    add_foreign_key "issue_users",        "issues",        on_delete: :cascade
    add_foreign_key "issues",             "projects",      on_delete: :cascade
    add_foreign_key "issues",             "users",         column: "assigned_to_id", on_delete: :nullify
    add_foreign_key "memberships",        "organizations", on_delete: :cascade
    add_foreign_key "memberships",        "users",         on_delete: :cascade
    add_foreign_key "mute_rules",         "projects",      on_delete: :cascade
    add_foreign_key "organizations",      "users",         column: "owner_id"
    add_foreign_key "projects",           "organizations", on_delete: :cascade
    add_foreign_key "projects",           "users"
    add_foreign_key "saved_filters",      "users",         on_delete: :cascade
    add_foreign_key "webhook_endpoints",  "projects",      on_delete: :cascade

    add_foreign_key "solid_queue_blocked_executions",   "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_claimed_executions",   "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_failed_executions",    "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_ready_executions",     "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  end
end

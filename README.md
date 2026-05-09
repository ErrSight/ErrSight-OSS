# ErrSight OSS

Self-hostable error tracking and log management for any web app. Open-source
fork of [ErrSight](https://errsight.com), the SaaS — same product features
(ingestion, fingerprinting, real-time logs, alerts, multi-tenant orgs) with
billing, plan-based quotas, and third-party analytics stripped out.

```
┌─ your app ──────────┐    POST /api/v1/events    ┌─ ErrSight OSS ───────┐
│  errsight-ruby      │  ───────────────────────► │  Postgres + Solid    │
│  errsight-js        │                           │  Queue + Action      │
│  curl, anything     │                           │  Cable + ActiveAdmin │
└─────────────────────┘                           └──────────────────────┘
```

## Requirements

| Dependency  | Version  | Notes |
| ----------- | -------- | ----- |
| Ruby        | 3.2+     | Tested on 3.4.7 |
| Rails       | 8.1+     | |
| PostgreSQL  | 14+      | TimescaleDB extension is **optional** — see below |
| Node.js     | 18+      | Only needed if you regenerate front-end assets |

The bundled `docker-compose.yml` provides a TimescaleDB-flavored Postgres on
port 5432; switch to plain `postgres:17` in that file if you don't want the
extension. The schema works on either.

## Quickstart (Docker compose for the database)

```bash
git clone https://github.com/your-fork/errsight-community
cd errsight-community

cp .env.example .env
# Edit .env — at minimum, leave DATABASE_URL alone if you use docker-compose,
# or point it at your own Postgres.

docker compose up -d                  # boots Postgres on localhost:5432

bundle install

# Public signup is invite-only by default — bootstrap your first admin
# via env vars so the seed step creates an account you can sign in with.
# (See "Access model" below to enable open registration instead.)
ADMIN_EMAIL=you@example.com \
ADMIN_PASSWORD=somethingstrong \
bin/rails db:setup                    # creates DB, loads schema, seeds admin

bin/dev                               # web + tailwind watcher + queue worker
```

Open <http://localhost:3000> and sign in with the admin credentials you just
set. Create a project, copy its API key, and start sending events. Invite
teammates from the organization page.

## Configuration

All runtime configuration is environment-variable driven. See `.env.example`
for the full list with comments. The most relevant ones:

| Variable           | Default                          | Purpose |
| ------------------ | -------------------------------- | ------- |
| `DATABASE_URL`     | `postgres://...:5432/errsight_community_development` | Postgres connection |
| `APP_HOST`         | `errsight.local`                 | Used in mailer link generation |
| `RETENTION_DAYS`   | `30`                             | Days to keep events; `0` disables pruning |
| `SOLID_QUEUE_IN_PUMA` | `true`                        | Run the recurring scheduler inside Puma |
| `MAILER_FROM`      | `no-reply@errsight.local`        | "From" address on outgoing email |
| `SMTP_ADDRESS`     | unset                            | Required if `:confirmable` stays enabled |
| `SMTP_PORT`        | `587`                            | |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | unset             | |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | unset   | Optional — enables "Sign in with Google" |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | unset   | Optional — enables "Sign in with GitHub" |
| `ALLOW_PUBLIC_SIGNUP` | `false`                       | Default invite-only — set `true` to re-enable open registration |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | unset              | One-shot admin bootstrap via `bin/rails db:seed` |
| `ADMIN_NOTIFICATION_EMAIL` | `support@errsight.com`         | Where new-signup notifications are sent |
| `ADMIN_SIGNUP_NOTIFICATIONS` | `per_signup`                 | `per_signup` (default), `digest`, or `disabled` |
| `ERRSIGHT_API_KEY` / `ERRSIGHT_HOST` | unset          | Optional — point this instance at itself for self-instrumentation |

**Without SMTP**, Devise's `:confirmable` module can't send confirmation
emails and new accounts can't activate. Either set up SMTP or remove
`:confirmable` from `app/models/user.rb` so signups skip email verification.

## Access model

ErrSight OSS is **invite-only by default**. The public `/users/sign_up` form
is disabled and OAuth signups are blocked unless the email already has a
pending invitation. The first admin is bootstrapped via env vars (see "Admin
user" below); everyone else joins by invitation from an existing admin.

To re-enable open registration (small OSS communities, public dev groups),
set `ALLOW_PUBLIC_SIGNUP=true` in your environment. Invitees signing up via
an invitation link register regardless of this setting — only the public
signup form is gated.

## Sending events

```bash
curl -X POST http://localhost:3000/api/v1/events \
  -H "X-API-Key: elp_<your_project_api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "level":   "error",
    "message": "NoMethodError: undefined method `name'\'' for nil:NilClass",
    "environment": "production"
  }'
```

Or with the official Ruby gem:

```ruby
# Gemfile
gem "errsight"

# config/initializers/errsight.rb
Errsight.configure do |config|
  config.api_key     = ENV.fetch("ERRSIGHT_API_KEY")
  config.host        = ENV.fetch("ERRSIGHT_HOST", "https://errsight.example.com")
  config.environment = Rails.env
end
```

JS, REST, and React Native examples live in `/docs` once your instance is
running.

## TimescaleDB (optional)

The `events` table works fine on plain Postgres. If you want time-series
compression and chunked retention, enable Timescale once after `db:setup`:

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;

SELECT create_hypertable('events', 'occurred_at',
  if_not_exists => TRUE,
  migrate_data  => TRUE);

ALTER TABLE events SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'project_id',
  timescaledb.compress_orderby   = 'occurred_at DESC, id'
);

SELECT add_compression_policy('events', INTERVAL '7 days');
```

Inspect compression status any time with:

```bash
bin/rails timescale:stats
```

The admin dashboard's "TimescaleDB — events hypertable" panel will switch
from "extension not available" to per-chunk stats once it's enabled.

## Scheduled jobs

Recurring jobs run via Solid Queue's scheduler (or Mission Control's job UI
at `/jobs` for admins). Schedule lives in `config/recurring.yml`. The default
set:

| Job                              | Cadence              | What it does | Where to tune |
| -------------------------------- | -------------------- | ------------ | ------------- |
| `clear_solid_queue_finished_jobs` | every 5 min         | Trims `solid_queue_jobs` rows so the table doesn't grow unbounded | Lengthen the window if you want longer job history visible in `/jobs` |
| `report_queue_health`            | every minute         | Logs queue depth / latency / dead-letter counts | Drop the cadence if log volume is a concern |
| `send_alert_digest`              | every hour at :00    | Per-membership digest of events captured in the last hour | Change to a less frequent cadence for noisy projects |
| `send_weekly_digests`            | every Monday at 13:00 | "What broke last week" summary, opt-out per membership | Adjust the day/time for your team |
| `expire_invitations`             | daily at 3am         | Drops pending invitations older than the configured window | Edit `Invitation#expires_at` window directly |
| `purge_discarded_organizations`  | daily at 4am         | Hard-deletes orgs soft-deleted past `Organization::RETENTION_WINDOW` | Edit the constant in the model to change the grace |
| `purge_discarded_users`          | daily at 4:30am      | Hard-deletes users soft-deleted past `User::RETENTION_WINDOW` | Same — edit the model constant |
| `prune_events_by_retention`      | daily at 4:15am      | Deletes events older than `RETENTION_DAYS` env var | Set `RETENTION_DAYS=0` to disable, or change the number |

Edit the schedule lines in `config/recurring.yml` and restart the worker (or
restart `bin/dev`). Solid Queue will re-read the file.

## Admin user

Bootstrap one admin via env vars on first install:

```bash
ADMIN_EMAIL=you@example.com \
ADMIN_PASSWORD=somethingstrong \
bin/rails db:seed
```

The admin can then visit `/admin` (ActiveAdmin) for the operator panel —
users, orgs, projects, events, invitations — and `/jobs` for Mission Control.

If you don't set the env vars, `db:seed` is a no-op. With invite-only as
the default, you'll then have no way in — either set the env vars and re-run
`db:seed`, or temporarily set `ALLOW_PUBLIC_SIGNUP=true` to register the
first user through the sign-up form.

## Running tests

```bash
bin/rails db:test:prepare
bin/rails test           # unit + functional
bin/rails test:system    # browser-driven specs
```

`test/fixtures/` carries the per-model fixture data. Coverage is opt-in via
`COVERAGE=true bin/rails test`.

## Updating

```bash
git pull
bundle install
bin/rails db:migrate
bin/rails restart        # or kamal redeploy / docker compose up --build -d
```

The schema is squashed into one initial migration as of `2026_05_07`.
Subsequent schema changes ship as additional migrations on top.

## Architecture (one paragraph)

`User` belongs to one or more `Organization`s through `Membership`. Each org
owns `Project`s. Projects have an `ApiKey` (`elp_*` for write, `elr_*` for
read) that the SDKs / curl pass via `X-API-Key`. The `api/v1/events#create`
endpoint validates payload size, applies a per-project rate limit (Postgres-
backed `rate_limit_windows`), and enqueues a `ProcessEventJob`. The job
persists events with idempotency-id deduplication (advisory lock, since
TimescaleDB hypertables can't have a non-time-partitioning unique index),
maintains the denormalized `issues` aggregates, and broadcasts to two
Action Cable channels (`ProjectLogsChannel`, `DashboardEventsChannel`).
Alerts (email, Slack, webhook) fire from the same job behind a 5-minute
per-(project, fingerprint) debounce.

## License

AGPLv3 — see `LICENSE` for the full text. Fork, modify, redeploy.

The "ErrSight" name and logo (including the wordmark and mark image assets)
are © Jijo Bose and are **not** covered by the AGPLv3 grant. The license
covers the source code only; the name and logo are reserved. If you fork
this project, swap out the name and logo assets before redistributing or
operating a public instance.

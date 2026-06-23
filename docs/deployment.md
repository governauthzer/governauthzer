---
title: Deployment
nav_order: 4
has_children: true
---

# Deployment
{: .no_toc }

Running governauthzer in production: configuration, secrets, TLS, and bootstrap.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

governauthzer is self-hosted OSS. Infrastructure choices (where Postgres lives, which
SMTP provider, which secret manager) are yours; the app follows 12-factor conventions —
everything is environment variables.

## Prerequisites

- **PostgreSQL** 13+ (16+ recommended). Uses `gen_random_uuid()`; no extensions needed.
- The Solid stack (Queue / Cache / Cable) runs **on Postgres** — production uses four
  databases (`primary` / `cache` / `queue` / `cable`).
- Ruby per [`.ruby-version`](https://github.com/governauthzer/governauthzer/blob/main/.ruby-version).

## Environment variables

### Required in production

The app **fails to boot** without `SECRET_KEY_BASE` and the three encryption keys.

| Variable | Purpose |
| --- | --- |
| `SECRET_KEY_BASE` | Signs/encrypts session cookies and other signed data. Generate with `bin/rails secret`. governauthzer uses ENV keys in production, not Rails credentials, so this must be provided. |
| `GOVERNAUTHZER_ENCRYPTION_PRIMARY_KEY` | Active Record Encryption primary key |
| `GOVERNAUTHZER_ENCRYPTION_DETERMINISTIC_KEY` | deterministic encryption key |
| `GOVERNAUTHZER_ENCRYPTION_KEY_DERIVATION_SALT` | key-derivation salt |

### Strongly recommended

| Variable | Default | Purpose |
| --- | --- | --- |
| `GOVERNAUTHZER_HOST` | `http://localhost:3000` | Base URL for generated links and emails. Set to your public URL. |
| `GOVERNAUTHZER_EVENT_SOURCE` | `https://governauthzer.dev` | CloudEvents `source` identifying this instance. Set to your instance URL. |
| `GOVERNAUTHZER_SCHEMA_HOST` | `https://governauthzer.dev/schemas` | Registry host the outbound `dataschema` URLs point at. Defaults to the canonical project registry; override only if you mirror the JSON Schemas yourself. |
| `GOVERNAUTHZER_DATABASE_USER` | `governauthzer` (owner) | DB role the app connects as. Set to the restricted runtime role for [audit protection](audit-log-protection.md). |
| `GOVERNAUTHZER_DATABASE_PASSWORD` | — | password for that role |
| `FORCE_SSL` | `true` | Enforce HTTPS (redirect + HSTS + secure cookies). Set `false` only behind upstream TLS — logs a loud warning. |
| `ASSUME_SSL` | `false` | Set `true` behind a TLS-terminating proxy that doesn't forward `X-Forwarded-Proto` (avoids a redirect loop). |
| `MAIL_FROM` | app default | `From:` address on notification emails. |

### Optional

| Variable | Default | Purpose |
| --- | --- | --- |
| `RATE_LIMIT_SAFELIST` | — | Comma-separated CIDRs exempt from Rack::Attack throttling. |
| `SENTRY_DSN` | — | Enables Sentry error tracking. No DSN ⇒ the SDK is a no-op (nothing leaves the box). |
| `SENTRY_ENVIRONMENT` | `Rails.env` | Sentry environment tag. |
| `SENTRY_SEND_PII` | `false` | Opt-in PII in Sentry events (off by default for an identity app). |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.0` | Sentry performance tracing sample rate. |
| `GOVERNAUTHZER_RELEASE` | — | Release identifier reported to Sentry. |
| `SKIP_DB_PREPARE` | `false` | Set `true` to stop the container entrypoint auto-migrating on boot — required when serving under the restricted DB role (it can't run DDL). Run migrations as the owner separately. |

Operational tuning (`RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `JOB_CONCURRENCY`,
`SOLID_QUEUE_IN_PUMA`, `PORT`, `RAILS_LOG_LEVEL`) follows the Rails 8 defaults.

## Encryption keys

Generate three fresh keys (pure crypto — this subcommand does **not** load Rails, so it
works before keys are configured):

```sh
bin/governauthzer generate-encryption-keys
```

It prints ready-to-paste `KEY=value` lines. Store them in your secret manager and inject
as environment variables. **Losing these keys means losing access to all encrypted
data** (currently the OIDC client secrets) — back them up.

## Database & audit-log protection

1. Create the database(s) and run migrations **as the owner role**.
2. Apply Postgres role separation so the audit log is append-only at the database
   layer, not merely in app code.

The runbook is its own page: **[Audit-log protection](audit-log-protection.md)**.

> The container entrypoint runs `db:prepare` on server start by default — convenient
> for single-role installs. For a **role-separated** deploy, set `SKIP_DB_PREPARE=true`
> and run `bin/rails db:migrate` as the **owner** role at release time; the restricted
> runtime role cannot run DDL.

## TLS

`FORCE_SSL` defaults to `true`: Bearer tokens and session cookies over plain HTTP are
trivially MITM'd. Behind a TLS-terminating proxy/load balancer, set `ASSUME_SSL=true`
so the app trusts the upstream and doesn't redirect-loop. The `/up` health probe is
always reachable over HTTP. Disabling enforcement (`FORCE_SSL=false`) is allowed for
upstream-TLS-only deploys but logs a loud boot warning.

## Bootstrap the first operator

There's no admin UI to create the first operator (by design — every other user comes
from HRIS). Seed it from the shell:

```sh
# 1. Create the first operator (idempotent for the self-app + operator role):
bin/governauthzer seed-admin --email you@example.com --name "Your Name"

# 2. Issue a one-time, 10-minute login URL (break-glass, also used for bootstrap):
bin/governauthzer emergency-login --user you@example.com --reason "bootstrap"
```

Open the printed URL to sign in, then configure your first OIDC provider in
**Admin → OIDC providers**. After that, operators arrive through HRIS like everyone
else (their OIDC identity is linked by an operator in the admin UI).

## Email

Notifications (review requests, approvals, denials) go through Action Mailer, sent
asynchronously via Solid Queue (an SMTP outage never blocks approve/revoke). Configure
`config.action_mailer.smtp_settings` for your provider in
`config/environments/production.rb` — any SMTP provider works (SES, Postmark, Mailgun,
corporate Exchange). `MAIL_FROM` sets the `From:` address. In development, mail is
captured by `letter_opener_web` at `/letter_opener`.

## Background jobs

Solid Queue runs the recurring sweepers in production (`config/recurring.yml`):

| Job | Cadence | Does |
| --- | --- | --- |
| `Sync::OrphanedSweeper` | hourly | promotes past-grace orphaned users to terminated |
| `Users::ActivationSweeper` | hourly | flips `pending_start` users to `active` on their start date |
| `Accesses::ExpirySweeper` | hourly | revokes time-bounded grants past `expires_at` |

Run a Solid Queue worker (e.g. `SOLID_QUEUE_IN_PUMA=true` to run it inside Puma, or a
separate `bin/jobs` process).

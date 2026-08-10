# Changelog

Notable changes per release. Format follows [Keep a Changelog](https://keepachangelog.com/);
versions follow [Semantic Versioning](https://semver.org/).

Every release so far is a pre-release: expect breaking changes, and read the upgrade
notes before moving between versions.

Record what you ship under `## Unreleased` as you make the change. The release
workflow dates that section and turns it into the release notes.

## Unreleased

## 0.5.0 — 2026-07-17

### Changed

- Outgoing SMTP is configured through environment variables (`SMTP_HOST`, `SMTP_PORT`,
  `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_TLS`) instead of `production.rb`. With `SMTP_HOST`
  unset, mail stays off as before.

### Fixed

- The image builds again: the encryption-key check no longer fires during asset
  precompilation, where secrets are absent by design.
- `db/grants.sql` runs against all four databases. The audit-log lockdown applies itself
  only where the audit table exists, instead of aborting on the cache, queue and cable
  databases.

## 0.4.0 — 2026-07-06

### Changed

- Audit events raised through the API name the token that made the call.
- Documented API token security and the rate limits.

## 0.3.0 — 2026-07-03

### Changed

- Snapshot sync issues fewer queries.
- API errors say what was wrong.
- Removed dead code and scaffold leftovers.

## 0.2.0 — 2026-07-02

### Changed

- **Breaking.** End-user portal events are recorded under the `web-ui` audit channel,
  split out from `admin-ui`. Anything filtering audit events by channel needs updating.
  This went out unflagged at the time and is recorded here after the fact.

### Added

- A sweeper that recovers webhook deliveries stuck mid-flight.

### Fixed

- Sign-in through OIDC lands non-operators on a page they can see.

## 0.1.0 — 2026-07-01

First public preview. Request, approve and audit access, with an append-only audit log,
OIDC sign-in, a management API for the identity axis, and signed CloudEvents webhooks
plus a reconciliation API for fulfillment.

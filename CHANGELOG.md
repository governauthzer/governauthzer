# Changelog

Notable changes per release. Format follows [Keep a Changelog](https://keepachangelog.com/);
versions follow [Semantic Versioning](https://semver.org/).

Record what you ship under `## Unreleased`. The release workflow dates that section and
turns it into the release notes.

## Unreleased

### Added

- Published images at `ghcr.io/governauthzer/governauthzer`, for amd64 and arm64 — deploy a
  release without building it.
- A worked Kamal deployment: `config/deploy.production.yml`, reading its values from a
  `.env.production` you keep out of git.
- Deploying a destination migrates as the database owner, applies `db/grants.sql`, and stops
  if the audit log did not come out append-only.
- The operator dashboard shows the running version.

### Fixed

- Two approvers deciding the same request at the same moment can no longer both approve
  it, which granted the access twice and recorded the approval twice.
- Approving or denying a request that was just withdrawn says so instead of failing with
  a server error.

## 0.5.0 — 2026-07-17

### Changed

- SMTP is configured with environment variables. `SMTP_HOST` unset keeps mail off.

### Fixed

- The image builds again: the encryption-key check no longer fires during asset
  precompilation.
- `db/grants.sql` runs against all four databases.

## 0.4.0 — 2026-07-06

### Changed

- Audit events name the API token that made the call.
- Documented API token security.

## 0.3.0 — 2026-07-03

### Changed

- Faster snapshot sync.
- Clearer API errors.
- Leaner internals.

## 0.2.0 — 2026-07-02

### Changed

- **Breaking.** End-user portal events moved to the `web-ui` audit channel. Recorded after
  the fact — it went out unflagged.

### Added

- A sweeper that recovers stuck webhook deliveries.

### Fixed

- OIDC sign-in lands non-operators on a page they can see.

## 0.1.0 — 2026-07-01

First public preview.

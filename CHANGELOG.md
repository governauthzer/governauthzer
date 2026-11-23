# Changelog

What changed, one line each. How it works and why lives in the
[docs](https://governauthzer.github.io/governauthzer). Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow
[Semantic Versioning](https://semver.org/).

Record what you ship under `## Unreleased`. The release workflow dates that section and
turns it into the release notes.

## Unreleased

### Added

- Published images at `ghcr.io/governauthzer/governauthzer`, for amd64 and arm64.
- A worked Kamal deployment, configured through an env file kept out of git.
- Deploying migrates as the database owner and applies `db/grants.sql`.
- The operator dashboard shows the running version.
- Documented backup, restore and upgrades.
- Email is configured in UI
- Notifications can also be posted to a messenger channel through an incoming webhook

### Changed

- A webhook endpoint must be an `http://` or `https://` address.
- The CloudEvents `source` now identifies your deployment instead of the project.
- Email is off until an operator switches it on, and no notification is queued while
  it is off.

### Removed

- The SMTP environment variables.

### Fixed

- Two approvers can no longer both approve the same request.
- Approving or denying a withdrawn request no longer errors.

### Security

- Ruby 4.0.10, Rails 8.1.4.1 and current dependencies, with no known advisories.
- OmniAuth does not build callback URLs from request headers.
- The emergency-login token moved out of the URL path.
- Sentry no longer records outbound request URLs, which could carry a messenger webhook's secret.
- The API docs page serves its script from the app itself, under a policy that blocks
  loading anything from elsewhere.
- Webhook signing secrets are encrypted at rest.

## 0.5.0 — 2026-07-17

### Changed

- SMTP is configured with environment variables.

### Fixed

- The Docker image builds again.
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

- **Breaking.** End-user portal events moved to the `web-ui` audit channel.

### Added

- A sweeper that recovers stuck webhook deliveries.

### Fixed

- OIDC sign-in lands non-operators on a page they can see.

## 0.1.0 — 2026-07-01

First public preview.

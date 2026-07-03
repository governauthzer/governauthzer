---
title: Webhooks & CloudEvents
nav_order: 7
---

# Webhooks & CloudEvents
{: .no_toc }

The outbound contract a provisioner consumes — signed events out, reconciliation back.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

## Model

When a decision changes who should have access, governauthzer emits a
[CloudEvent](https://cloudevents.io) (CNCF spec v1.0) to every matching webhook
subscription. A consumer — the recommended Baton bridge, your own handler, or a manual
task runner — applies it to the target system and (optionally) reports back.

The outbound contract is **access-grain only**. Exactly two actionable event kinds
exist, each mapping 1:1 to a connector call:

| CloudEvent `type` | Internal event | Meaning | Schema |
| --- | --- | --- | --- |
| `com.governauthzer.access.approved` | `access.approved` | **Add** this grant | [`access.approved/1.json`](/schemas/access.approved/1.json) |
| `com.governauthzer.access.revoked` | `access.revoked` | **Remove** this grant | [`access.revoked/1.json`](/schemas/access.revoked/1.json) |

Coarse user-lifecycle events (`user.terminated`, `user.suspended`) are **not**
published — a connector can't act on "user terminated", only on "remove this specific
grant". A termination decomposes into N × `access.revoked`. The audit log stays rich;
the outbound contract stays narrow.

The self/operator application (governauthzer itself) is never provisioned externally,
so its grants are never published.

## Envelope

Events are delivered in CloudEvents **structured mode**: a single JSON object,
`Content-Type: application/cloudevents+json; charset=utf-8`.

| Attribute | Value |
| --- | --- |
| `specversion` | `1.0` (the CloudEvents spec — a separate axis from our payload version) |
| `id` | the originating `AuditEvent` id (UUID). Stable across retries → use it for **idempotency** and to **correlate** reconciliation. |
| `source` | the producing instance (`GOVERNAUTHZER_EVENT_SOURCE`) |
| `type` | `com.governauthzer.access.approved` / `...revoked` |
| `time` | RFC 3339 timestamp of the decision |
| `subject` | `access/<access_id>` |
| `datacontenttype` | `application/json` |
| `dataschema` | versioned URL of the JSON Schema for `data` (see [Versioning](#versioning)) |
| `data` | the payload — described by `dataschema` |

### Example (`access.approved`)

```json
{
  "specversion": "1.0",
  "id": "7c3e1b2a-9d4f-4a10-8c55-0a1b2c3d4e5f",
  "source": "https://acme.governauthzer.example",
  "type": "com.governauthzer.access.approved",
  "time": "2026-06-22T10:15:00Z",
  "subject": "access/0f8b8c1e-3a2d-4c1a-9b7e-1d2c3b4a5f60",
  "datacontenttype": "application/json",
  "dataschema": "https://governauthzer.dev/schemas/access.approved/1.json",
  "data": {
    "access_id": "0f8b8c1e-3a2d-4c1a-9b7e-1d2c3b4a5f60",
    "user":        { "id": "a1b2c3d4-e5f6-4711-8899-aabbccddeeff", "email": "ada@example.com", "name": "Ada Lovelace" },
    "role":        { "id": "11112222-3333-4444-5555-666677778888", "slug": "slack-admin", "name": "Slack Admin" },
    "application": { "id": "99990000-1111-2222-3333-444455556666", "slug": "slack", "name": "Slack" }
  }
}
```

`access.revoked` is identical in shape and may additionally carry an informational
`reason` (e.g. `"grant_expired"`).

## The `data` payload

Described authoritatively by the JSON Schemas. The user identity contract is
deliberate:

- `user.id` — **immutable**. KEY YOUR PERSISTENT user → target-account mapping on this.
- `user.email` — the conventional cross-system match key, but **mutable**; use it only
  for the *first* resolution, never as the persistent key.
- We do **not** send `external_identities` (HRIS namespace — the wrong identity space
  for target provisioning) nor any target-account id (that would be target *state* in
  the decision plane). Resolving our user → a target account is the bridge's job,
  exactly like resolving `role.slug` → a target entitlement.

Adding identifiers later is additive (non-breaking — see [Versioning](#versioning)), so
the payload stays minimal until a real bridge for a non-email-keyed system needs more.

## Signing & verification

Every delivery carries an HMAC-SHA256 signature (Stripe-style: it covers
`"<timestamp>.<body>"` so you can reject replays by checking timestamp freshness too).
The shared secret is the subscription's `signing_secret`.

| Header | Value |
| --- | --- |
| `X-Governauthzer-Event-Id` | the CloudEvent `id` (= AuditEvent id) |
| `X-Governauthzer-Timestamp` | unix seconds, the value signed |
| `X-Governauthzer-Signature` | `sha256=<hex HMAC-SHA256(secret, "<timestamp>.<body>")>` |

Verify (Ruby):

```ruby
expected = "sha256=" + OpenSSL::HMAC.hexdigest(
  "SHA256", signing_secret, "#{request.headers['X-Governauthzer-Timestamp']}.#{raw_body}"
)
abort "bad signature" unless Rack::Utils.secure_compare(expected, request.headers["X-Governauthzer-Signature"])
abort "stale"         if (Time.now.to_i - request.headers["X-Governauthzer-Timestamp"].to_i).abs > 300
```

Always HMAC over the **raw request body** before any JSON parsing.

## Delivery semantics

- **At-least-once.** The same event may arrive more than once (retries, network
  ambiguity). Deduplicate on the CloudEvent `id` — it is stable across all attempts.
- **Retries.** A non-2xx response or network error is retried with exponential backoff
  (`2^attempt` minutes, capped at 6 h) up to **8 attempts**, after which the delivery
  is marked `dead`. Delivery state (`pending` / `delivered` / `failed` / `dead`,
  attempts, last response code) is visible per subscription in the admin UI.
- **Idempotent fan-out.** One audit event produces at most one delivery row per
  subscription (unique constraint), so a re-projection never double-sends.

Respond **2xx** as soon as you've durably accepted the event; do the slow target-system
work asynchronously.

## Subscriptions

Create subscriptions in the admin UI (**Admin → Webhooks**):

- `endpoint_url` — where events POST.
- `signing_secret` — generated for you; shown on the subscription page; rotatable.
- `event_types[]` — filter (empty = all published types).
- `application_ids[]` — filter (empty = all apps). Routes events to the right consumer;
  the single-bridge reference deployment leaves both filters empty.

## Reconciliation

Fulfillment is the bridge's job; governauthzer is **never** the system of record for
target state. To close the loop, a bridge reports back whether it applied the change:

```
POST /api/v1/applications/:application_id/reconciliations
Authorization: Bearer <reconcile-scoped token>
Content-Type: application/json

{ "event_id": "<the CloudEvent id you received>", "status": "applied", "detail": "optional" }
```

- `status` is `applied` or `failed`.
- `event_id` is the CloudEvent `id` you received (= the AuditEvent id).
- The token must be **`reconcile`-scoped** (see [API → Token scopes](api.md#token-scopes)).
  Besides reconciliation it can read `GET /api/v1/grants` and post
  `POST /api/v1/drift-reports` (the [drift-detection loop](fulfillment.md#drift-detection)),
  but nothing else in the management API.

Core resolves `event_id` → the role/application (validating the role belongs to
`:application_id`) → the access. If the access still exists (a grant) its
`provisioning_status` is stamped `applied` / `failed`, surfaced on the user's page in
the admin UI. If the access is gone (a revoke destroyed the row) the report is recorded
audit-only. Either way an `access.provisioning_reported` audit event is written.

A grant with no matching subscription stays `not_required` — standalone core is honest
about not pretending an unconnected app was provisioned.

## Versioning

The event **kind** (`type`) is stable forever. The payload **shape** version lives in
`dataschema` — a dereferenceable, version-pinned URL hosted on this site:

```
<schema-host>/<internal-event>/<version>.json
```

The host defaults to the canonical project registry
(`https://governauthzer.dev/schemas`) and is overridable per deployment via
`GOVERNAUTHZER_SCHEMA_HOST` — consumers should always dereference whatever URL the
event actually carries, not assume the default.

**Evolution policy:**

- **Additive** changes (new optional fields) do **not** bump the version — that's why
  consumers MUST ignore unknown properties, and why the schemas don't set
  `additionalProperties: false`.
- Only a **breaking** change (remove / rename / retype / semantic shift) gets a new
  `dataschema` URL (`.../2.json`), while `type` stays the same so a `type`-router keeps
  matching.
- `specversion` (the CloudEvents spec itself) is a third, independent axis we don't
  version.

v1 is the only version, and will be for a long time. The convention is locked now; the
dual-emit / deprecation machinery is deliberately deferred until the first real breaking
change against a real consumer.

---
title: Fulfillment
nav_order: 5
---

# Fulfillment
{: .no_toc }

How access decisions actually reach your target systems.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

governauthzer **decides** who should have access; **fulfillment** is making the target
system match that decision. The core ships the *contract* — signed events out, a
reconciliation callback back — **not the connectors themselves**. That's deliberate: you're
never locked into one vendor's connector catalog, and you pick how each application is
fulfilled.

```mermaid
flowchart TD
  G["governauthzer — decision plane"]
  G -->|"signed event"| M1["1 · Webhook handler / Baton bridge"]
  G -->|"signed event"| M2["2 · Audited manual task"]
  G --> M3["3 · No subscription (standalone)"]
  M1 --> T1["Apps with an API<br/>Slack, GitHub, AWS, …"]
  M2 --> T2["Apps with no API"]
  M3 --> T3["status stays not_required"]
  M1 -.->|"reconcile applied/failed"| G
  M2 -.->|"reconcile applied/failed"| G
```

Every approved grant and every revoke is published as an `access.approved` /
`access.revoked` [CloudEvent](webhooks.md) to each matching webhook subscription. What
consumes it is your choice — and you can mix modes across applications.

## Mode 1 — a webhook handler (apps with an API)

For any target system with an API, run a small service that receives the signed
CloudEvent and calls that API to add/remove the grant. Two flavors:

- **Your own handler.** A few lines in whatever language you like: verify the HMAC
  signature, branch on `type` (`access.approved` / `access.revoked`), call the target's
  API, return `2xx`. Best when you want full control or the target isn't covered by an
  off-the-shelf connector.
- **A Baton bridge.** Rather than write a connector per system, stand on
  [Baton](https://github.com/conductorone/baton-sdk) — ConductorOne's open-source
  (Apache-2.0) connector framework, which already implements `grant` / `revoke` for many
  SaaS targets. The recommended pattern is a thin bridge that translates governauthzer's
  events into Baton connector calls. (The bridge is a separate component, not bundled in
  core.)

Either way, the handler maps **our** identifiers to the target's:

- *our `user`* → a target account — key your persistent mapping on the immutable
  `user.id`; use `user.email` only for the first match.
- *our `role.slug`* → a target entitlement / group.

That mapping is the connector's job — governauthzer is the system of record for *intent*,
never for target *state*. See [Webhooks → The `data` payload](webhooks.md#the-data-payload).

## Mode 2 — an audited manual task (apps with no API)

Roughly 40% of enterprise apps can't be auto-integrated. Instead of pretending a connector
exists, close the loop honestly: a handler (or a person watching a queue) receives the
event, **does the change by hand**, and reports the outcome back through
[reconciliation](#the-reconciliation-loop). The grant's status moves to `applied` (or
`failed`), visible to operators on the user's page. The audit trail stays complete either
way.

## Mode 3 — standalone (no fulfillment)

governauthzer runs perfectly well with **no** subscription at all — as the record of
*intent* plus the audit trail, while provisioning happens out of band. A grant that
matches no subscription keeps `provisioning_status: not_required`: the core is honest about
not having provisioned an unconnected app, rather than showing a misleading "pending".

## The reconciliation loop

Fulfillment is the consumer's job, so governauthzer never assumes a change took — the
consumer **reports back**:

```
POST /api/v1/applications/:application_id/reconciliations
{ "event_id": "<the CloudEvent id you received>", "status": "applied" }
```

- The grant's `provisioning_status` becomes `applied` / `failed`, surfaced in the admin UI
  on the user's page.
- A grant actively sent to ≥1 subscriber sits at `pending` until a report arrives.
- A *failed revoke* has no access row to flag (the row was destroyed on revoke), so it's
  recorded audit-only today — stale-access alerting is a future addition.

Full request/response shape: [Webhooks → Reconciliation](webhooks.md#reconciliation).

## Two directions, two secrets

| Direction | Mechanism |
| --- | --- |
| **core → consumer** (events out) | **HMAC-SHA256** signature on every delivery (the subscription's `signing_secret`). |
| **consumer → core** (reconcile back) | a **`reconcile`-scoped [API token](admin-guide.md#api-tokens)** — it can *only* post reconciliation, nothing else. |

## Setting it up

1. **Create a webhook subscription** (Admin → Webhooks): endpoint URL, copy the signing
   secret, optionally filter by event type and application. See
   [Admin guide → Webhooks](admin-guide.md#webhooks).
2. **Mint a `reconcile` API token** (Admin → API tokens) for the consumer to report back.
   See [Admin guide → API tokens](admin-guide.md#api-tokens).
3. **Run your consumer** — handler, Baton bridge, or manual-task runner. Verify signatures,
   apply, reconcile.

The full technical contract — envelope, signing, retries, delivery semantics, versioning —
is in **[Webhooks & CloudEvents](webhooks.md)**.

## What governauthzer does *not* do

- Hold your target systems' credentials.
- Claim to know a target's live state (it owns intent, not state).
- Ship the connectors — fulfillment is the open plane, on your side of the line.

---
title: Home
layout: home
nav_order: 1
---

# governauthzer
{: .fs-9 }

Govern access. Bring any provisioner — or use ours.
{: .fs-6 .fw-300 }

governauthzer is a **decision-plane IGA** (Identity Governance & Administration): it
owns the *intent* of access — who may have which role in which application, and the
request → approve → audit loop around it. It never owns target-system *state*.
Fulfillment is an **open plane**: send the decisions to the recommended Baton bridge,
to your own webhook handler, or close the loop with audited manual tasks. Your choice,
never locked in.

---

## What's in these docs

- **[Management API](api.md)** — the HTTP contract your HRIS / onboarding system
  integrates against (identity axis: users + their identities + roster sync).
- **[Webhooks & CloudEvents](webhooks.md)** — the outbound contract a provisioner
  consumes: signed `access.approved` / `access.revoked` CloudEvents, plus the
  reconciliation callback that closes the loop. The published JSON Schemas live
  under [`/schemas`](#published-schemas).
- **[Deployment](deployment.md)** — environment variables, encryption keys, TLS,
  and the Postgres role separation that makes the audit log append-only.

## The three planes

| Plane | What it answers | Surface |
| --- | --- | --- |
| **Decision** (the kernel) | Who *should* have access? request / approve / audit | Admin UI + [Management API](api.md) |
| **Fulfillment** (drivers) | Make the target system match the decision | [Outbound webhooks](webhooks.md) → your bridge/handler |
| **Reconciliation** | Did fulfillment actually take? | [Callback endpoint](webhooks.md#reconciliation) → provisioning status |

governauthzer is the system of record for **intent**, never for **state**. A connector
resolves *our* user → a target account and *our* role → a target entitlement; that
mapping is the bridge's job, not ours.

## Published schemas

The `dataschema` URLs carried on every outbound CloudEvent dereference to versioned
JSON Schemas hosted here:

- [`/schemas/access.approved/1.json`](/schemas/access.approved/1.json)
- [`/schemas/access.revoked/1.json`](/schemas/access.revoked/1.json)

See [Webhooks & CloudEvents → Versioning](webhooks.md#versioning) for the evolution
policy.

## Source of truth

The **canonical** management-API contract is the OpenAPI document served by a running
instance at `/api-docs` (rendered) and `/api-docs/v1.yaml` (raw). It is CI-enforced
against the app (`committee-rails`: drift = a failing test), so these pages link to it
rather than duplicate it.

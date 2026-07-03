---
title: Management API
nav_order: 6
---

# Management API
{: .no_toc }

The HTTP contract your HRIS / onboarding system integrates against.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

## Canonical contract

The **authoritative** spec is the OpenAPI document served by a running instance:

- **Rendered (Redoc):** `https://<your-host>/api-docs`
- **Raw YAML:** `https://<your-host>/api-docs/v1.yaml`

It is enforced against the application in CI via `committee-rails` — every request and
response is schema-checked, so drift fails the build. This page is an orientation, not
a duplicate; integrate against the YAML.

## Scope: identity axis only

At v1 the API exposes exactly one axis: **users and their identities**, plus
**roster sync**. This is deliberate — two data axes, two actors:

| Axis | Velocity | Actor | Surface |
| --- | --- | --- | --- |
| **Identity** — who exists, how attributes change | High, machine-driven (HRIS) | System | **This API** |
| **Policy** — apps, roles, workflows | Low, decision-laden | Operator | Admin UI |
| **Provisioning** — grants flowing outward | Event-driven | Bridge | [Webhooks](webhooks.md) |

Applications, Roles, Accesses and Approval Workflows are **operator-curated in the
admin UI** at v1 — they are not in the HTTP API. (A policy-axis API is an additive
future feature, not a rewrite.)

## Authentication

All `/api/v1/*` calls require a Bearer token:

```
Authorization: Bearer gva_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Tokens are minted in the admin UI (**Admin → API tokens**). The plaintext value is
shown **once** at creation; only a SHA-256 digest is stored. The `gva_` prefix makes
tokens grep-/secret-scanner-friendly.

Verify a token end-to-end:

```sh
curl -sS https://<your-host>/api/v1/whoami \
  -H "Authorization: Bearer gva_..."
# => {"token_id":"...","token_name":"HRIS sync","expires_at":null}
```

### Token scopes

| Scope | Can call | Use |
| --- | --- | --- |
| `full` (default) | the whole management API | HRIS sync, bootstrap tooling |
| `reconcile` | `whoami` + the [bridge-facing endpoints](#fulfillment-plane-bridge-facing): reconciliation, grants read, drift reports | a provisioner bridge |

A `reconcile` token hitting a management endpoint gets `403 scope_insufficient`.
Enforcement is fail-safe: every endpoint requires `full` unless it explicitly opts out.

## Conventions

- **Errors** — one envelope everywhere; branch on the stable `error.code`, not the
  message:

  ```json
  { "error": { "code": "reactivation_required", "message": "...", "details": { "user_id": "..." } } }
  ```

- **Pagination** — offset based: `?page=&per_page=` (default 25, max 100), with
  `X-Total-Count` and `Link: rel="next"/"prev"` headers.
- **Sorting** — `?sort=field` / `?sort=-field`, per-endpoint whitelist.
- **JSON** — snake_case throughout.

## Endpoint map

A quick index — see the OpenAPI for full request/response schemas.

### Users

| Method | Path | Notes |
| --- | --- | --- |
| `POST` | `/api/v1/users` | Create. Accepts inline `external_identities[]`. |
| `GET` | `/api/v1/users` | List. Filters: `status`, `manager_id`, `department`. |
| `GET` | `/api/v1/users/:id` | Show. Embeds identities + computed `roles[]`. |
| `PATCH` | `/api/v1/users/:id` | Attributes **and** status transitions. `status=terminated` runs the revoke cascade. |
| `DELETE` | `/api/v1/users/:id` | **405** — users are never hard-deleted; use `status=terminated`. |

`PATCH` accepts `manager_external_id: {source, external_id}` as an alternative to
`manager_id` (server resolves it), so a manager change needs one round-trip, not two.

### Sync by external id

| Method | Path | Notes |
| --- | --- | --- |
| `PATCH` | `/api/v1/users/by-external-id/:source/:external_id` | Source-keyed upsert for per-record HRIS flows. |

### Roster snapshot (the recommended sync)

| Method | Path | Notes |
| --- | --- | --- |
| `POST` | `/api/v1/sync/snapshots` | Full active-roster snapshot; server diffs into create/update/terminate. |

Snapshot sync makes **silent offboarding** detectable by construction (absence ⇒
orphan ⇒ access freeze + cascade), with guardrails: a circuit breaker rejects any
snapshot that would terminate more than a threshold of active users, plus
`expected_count` and `dry_run`. It requires a **source-scoped** token.

### Fulfillment plane (bridge-facing)

| Method | Path | Notes |
| --- | --- | --- |
| `POST` | `/api/v1/applications/:application_id/reconciliations` | A bridge reports `applied` / `failed` for a delivered event. |
| `GET` | `/api/v1/grants` | Bulk read of active grants — the desired membership a bridge reconciles the target against. Paginated; the self/operator application is excluded. |
| `POST` | `/api/v1/drift-reports` | A bridge records an out-of-band drift sweep as one `provisioning.drift_detected` audit event. Audit-only, no state change. |

All three accept a **`reconcile`-scoped token** (or `full`). Documented with the
outbound flow they close — see [Webhooks → Reconciliation](webhooks.md#reconciliation)
and [Fulfillment → Drift detection](fulfillment.md#drift-detection).

## What the API does *not* do

- **No JIT user creation on login.** Governance begins before first login and
  continues after last login; an OIDC callback never creates a user row.
- **No auto-linking by email.** Identity matching is strictly by `(provider, subject)`
  / `(source, external_id)` — never email.
- **No hard delete.** Audit completeness forbids it; GDPR erasure, if needed, is a
  separate explicit endpoint.

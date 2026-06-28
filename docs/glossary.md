---
title: Glossary
nav_order: 9
---

# Glossary
{: .no_toc }

The terms used across these docs, in one place.
{: .fs-6 .fw-300 }

---

Access (grant)
: The fact that a user holds a role, plus its lifecycle (`pending` → `approved`, or
  revoked). The unit that flows outward as an event.

Application
: A target system you govern access to — Slack, GitHub, AWS, an internal tool.

Approval workflow / step
: The rule for who must approve a request for a role. A workflow is an ordered list of
  steps; the default routes to the requester's manager with an operator fallback. A
  zero-step workflow auto-grants. See [Admin guide](admin-guide.md#approval-workflows).

Audit log / audit event
: The append-only record of every decision (request, approval, revoke, login, admin
  change). Enforced append-only at the database — see
  [Audit-log protection](audit-log-protection.md).

Baton / bridge
: [Baton](https://github.com/conductorone/baton) is ConductorOne's open-source
  (Apache-2.0) connector framework. A *bridge* is a thin service that translates
  governauthzer events into Baton connector calls. See [Fulfillment](fulfillment.md).

Break-glass (emergency-login)
: A single-use, short-TTL login URL issued from the shell
  (`bin/governauthzer emergency-login`). Used to bootstrap the first operator and for
  IdP-outage recovery — not a password.

CloudEvent
: The [CNCF event envelope](https://cloudevents.io) (spec v1.0) governauthzer uses for
  outbound events. See [Webhooks](webhooks.md#envelope).

`dataschema`
: A versioned, dereferenceable URL carried on every CloudEvent, pointing at the JSON
  Schema for that event's `data`. The payload-version axis — see
  [Versioning](webhooks.md#versioning).

Decision plane
: governauthzer itself — the layer that owns the *intent* of access (who should have what,
  and the approve/audit around it). Contrast with fulfillment.

Entitlement
: A permission inside a target system (a group, a scope, an IAM policy). governauthzer has
  **no** entitlement entity — a connector maps our `role.slug` → a target entitlement.

External identity
: How an HRIS identifies a user: `(source, external_id)` (e.g. Workday `employee_id`).
  Never email. Distinct from an OIDC identity.

Fulfillment
: Making a target system match a decision (add/remove the grant). An **open plane**: a
  webhook handler, a Baton bridge, or an audited manual task. See
  [Fulfillment](fulfillment.md).

HRIS
: Your human-resources / onboarding system — the source of users, synced in via the
  [Management API](api.md).

Intent vs state
: governauthzer is the system of record for **intent** (who *should* have access), never
  for **state** (who actually has it in the target right now). State lives in the target,
  reached via fulfillment.

OIDC identity
: How a person signs in: `(provider, subject)`. Linking it is what lets a user log in —
  see [STRICT login](#strict-login).

Operator
: An admin — a user holding the operator role of the built-in application. Operators run
  `/admin`; everyone else is a regular user who requests access.

Orphaned
: A user dropped from the HRIS roster feed (silent offboarding). Snapshot sync flags them
  automatically and freezes their access pending resolution.

Provisioning status
: Per-grant fulfillment state: `not_required` (no subscriber), `pending` (sent, awaiting
  report), `applied`, or `failed`. Set by [reconciliation](#reconciliation).

Reconciliation
: The callback a consumer uses to report `applied` / `failed` for a delivered event,
  closing the loop. See [Webhooks → Reconciliation](webhooks.md#reconciliation).

Role
: A named bundle of access *within one application* (e.g. "Slack Admin"). The unit you
  request, approve, and audit. A *protected* role isn't self-requestable.

Roster snapshot (snapshot sync)
: The recommended HRIS sync: push the full active roster; the server diffs it into
  create/update/terminate, so silent offboarding is detectable by construction. See
  [Management API](api.md#roster-snapshot-the-recommended-sync).

Scope (token)
: An [API token](admin-guide.md#api-tokens)'s permission: `full` (whole management API) or
  `reconcile` (only `whoami` + the reconciliation endpoint).

Self-app
: The built-in "Governauthzer" application. It's system-managed (read-only); its operator
  role is what grants admin access.

STRICT login
: The login policy: a user is matched **only** by `(provider, subject)`. No auto-create on
  login, no email matching. An identity must be linked first
  ([Admin guide](admin-guide.md#users--identities)).

Subject (`sub`)
: The OIDC subject claim — the stable per-provider user identifier you paste when linking
  an OIDC identity.

Suspend / Terminate
: User status transitions. **Suspend** freezes login (grants kept). **Terminate** revokes
  all access (cascade) and fires an `access.revoked` per role downstream.

Webhook subscription
: An outbound delivery target: endpoint URL + signing secret + optional event-type /
  application filters. Created in [Admin → Webhooks](admin-guide.md#webhooks).

---
title: Audit-log protection
parent: Deployment
nav_order: 1
---

# Audit-log tamper protection (Postgres role separation)

governauthzer's audit log (`audit_events`) is append-only by design. The enforcement
is at the **database**, not in application code.

## Threat model

Defends against an honest-but-sloppy or rogue **app-level operator** — anyone with
`rails console` (i.e. the role the application connects as) — silently rewriting
history via `UPDATE audit_events SET ...` or `DELETE`. It does **not** defend against a
Postgres superuser/DBA; that requires external append-only log shipping (a separate,
deferred concern). App-level "immutability" (`readonly?`, `before_destroy`) was
rejected as theater — it's bypassed by the same console it's meant to stop.

## Roles

| Role | Used for | Privilege on `audit_events` |
| --- | --- | --- |
| `governauthzer` (owner/migrator) | migrations, owns the tables | full |
| `governauthzer_app` (runtime) | `rails server` / console | `SELECT, INSERT` only |

The app **serves** as the restricted role and **migrates** as the owner. The split is
opt-in via `GOVERNAUTHZER_DATABASE_USER`; the default is the owner so single-role
installs boot out of the box (the app then warns at boot that protection is off).

## Setup (run once, per database cluster)

1. **Create the runtime role** (as a superuser / the DBA), with its own password:

   ```sql
   CREATE ROLE governauthzer_app LOGIN PASSWORD '<runtime-password>';
   ```

2. **Migrate as the owner**, then **apply grants** as the owner:

   ```sh
   GOVERNAUTHZER_DATABASE_USER=governauthzer \
   GOVERNAUTHZER_DATABASE_PASSWORD=<owner-password> bin/rails db:migrate

   psql "postgres://governauthzer:<owner-password>@<host>/governauthzer_production" \
     -v app_role=governauthzer_app -v app_db=governauthzer_production \
     -f db/grants.sql
   ```

3. **Verify** it took effect (exits non-zero if not):

   ```sh
   bin/rails 'db:audit_protection:verify[governauthzer_app]'
   # => append+read allowed, rewrite+erase denied.
   ```

4. **Serve as the restricted role** — point the running app at it:

   ```sh
   GOVERNAUTHZER_DATABASE_USER=governauthzer_app
   GOVERNAUTHZER_DATABASE_PASSWORD=<runtime-password>
   ```

   With this set, `rails console` (and any app code) gets `permission denied` on
   `UPDATE audit_events`, while normal `INSERT`/`SELECT` keep working.

## Notes

- Re-run `db/grants.sql` after any migration that **renames or replaces** the audit
  table — `ALTER DEFAULT PRIVILEGES` would otherwise hand the new table full DML to the
  app role.
- The four `_cache` / `_queue` / `_cable` databases (Solid stack) need full DML for the
  app role and have no audit table; the same grants script's blanket grants cover them
  if you run it against each, but only the primary needs the `audit_events` REVOKE.
- This is one layer. For stricter (DBA-level) tamper-evidence, ship each `audit_events`
  row to an external append-only sink (deferred — see the audit-log design notes).

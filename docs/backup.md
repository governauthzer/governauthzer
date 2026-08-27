---
title: Backup and restore
parent: Deployment
nav_order: 3
---

# Backup and restore
{: .no_toc }

What is worth copying, what is not, and what a restore has to put back that a database
dump does not carry.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

## What to back up

**Two things: the primary database, and the encryption keys.**

| | Back up | Why |
| --- | --- | --- |
| `governauthzer_production` | **Yes** | Users, catalog, grants, approvals, and the audit log. This is the product. |
| The three encryption keys | **Yes** | Without them a dump is unreadable where it matters most — see below. |
| `..._cache` / `..._queue` / `..._cable` | No | Solid Cache, Queue and Cable. Rebuilt on boot. |
| `governauthzer_storage` volume | No | Nothing writes to it. The app stores no files. |

Restoring without the queue database costs you jobs that were in flight: unsent
notification emails, and webhook retries that had been scheduled. Deliveries recover on
their own — the rows live in the primary database, and the redelivery sweeper runs every
fifteen minutes over anything stranded for more than ten, so a lost retry is back in the
queue inside half an hour. Emails do not recover: an approval decided seconds before the
restore may never be announced, though the decision itself is safe.

## The keys are half the backup

`GOVERNAUTHZER_ENCRYPTION_PRIMARY_KEY`, `..._DETERMINISTIC_KEY` and
`..._KEY_DERIVATION_SALT` decrypt two columns: OIDC client secrets, and webhook signing
secrets. A database restored without the keys it was written under comes back with sign-in
broken and every webhook signature unverifiable, and no amount of database work fixes it —
you would be re-entering the OIDC secret at your identity provider and rotating every
subscription's secret with each bridge operator.

Keep them wherever you keep `SECRET_KEY_BASE` and the database passwords — for the Kamal
deployment that is `.env.production`, which belongs in a password manager and not in git.
Test that you can read them back before you need to.

## Taking a backup

Against the Postgres accessory on the server:

```sh
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" governauthzer-db \
  pg_dump -U governauthzer -d governauthzer_production --format=custom \
  > governauthzer-$(date +%F).dump
```

Run it as the **owner** role. The role the application serves as cannot read the whole
database by design.

Copy the dump off the machine. A backup on the same disk as the database is not a backup.

## Restoring

1. **Bring up an empty database with the roles in place.** On a fresh Kamal deployment,
   `bin/kamal accessory boot db -d production` does this: the first boot of an empty volume
   creates the restricted runtime role and the Solid-stack databases. Roles belong to the
   Postgres cluster, not to the dump — a restore into a cluster that has no
   `governauthzer_app` role will not create one.

2. **Restore as the owner.**

   ```sh
   docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" governauthzer-db \
     pg_restore -U governauthzer -d governauthzer_production --clean --if-exists \
     < governauthzer-2026-08-10.dump
   ```

3. **Re-apply the grants and check them.** Restoring rewrites tables, and the audit-log
   lockdown is a privilege on a table. Deploying re-applies `db/grants.sql` automatically,
   so the simplest correct move is to deploy — but verify rather than assume:

   ```sh
   bin/kamal app exec -d production --reuse "bin/rails 'db:audit_protection:verify[governauthzer_app]'"
   ```

   It exits non-zero if the restored database left the audit log rewritable. See
   [Audit-log protection](audit-log-protection.md).

4. **Restore the same encryption keys**, if the environment is new. Sign in, open
   **Admin → OIDC providers**, and confirm the provider still authenticates.

## What a restore does to the audit trail

Restoring is a privileged write, performed as the owner — the one role that can rewrite
`audit_events`. That is the same boundary the audit-log protection already draws: it
defends the trail against the running application and anyone with `rails console`, not
against whoever holds the database owner's password. The trail after a restore is as
trustworthy as the backup it came from and the person who ran the command. If you need
more than that, ship the audit log off the box as it is written; the protection page
covers where that line sits.

-- Audit-log tamper protection via Postgres role separation.
--
-- Threat model (locked 2026-05-20): an honest-but-sloppy or rogue *app-level*
-- operator — anyone with `rails console`, i.e. the role the application connects as —
-- must not be able to silently rewrite history with `UPDATE audit_events SET ...` or
-- `DELETE`. This is NOT a defense against a DBA / Postgres superuser; that requires
-- external append-only log shipping (a separate, deferred concern). App-level
-- "immutability" (Rails `readonly?`, `before_destroy`) was deliberately rejected as
-- theater: it is bypassed by the very console it is meant to stop. The database is the
-- real trust boundary.
--
-- Topology: the privileged OWNER/migrator role (the role that ran the migrations and
-- owns the tables — `governauthzer` by convention) keeps full rights and runs this
-- script. The RUNTIME role the app serves as (`governauthzer_app` by convention) gets
-- full DML everywhere EXCEPT it cannot UPDATE/DELETE the audit log.
--
-- Run as the owner role, against the PRIMARY database, AFTER migrations. The role
-- named by :app_role must already exist (CREATE ROLE ... LOGIN PASSWORD '...');
-- this script manages privileges only — not role creation or passwords:
--
--   psql "$PRIMARY_DATABASE_URL" \
--     -v app_role=governauthzer_app -v app_db=governauthzer_production \
--     -f db/grants.sql
--
-- Verify it actually took effect with:  bin/rails db:audit_protection:verify
-- (and the app warns at boot if it connected as an over-privileged role).

\set ON_ERROR_STOP on

-- The app role may connect and use the public schema, and gets full DML on every
-- existing table plus sequence usage. audit_events is locked down afterwards.
GRANT CONNECT ON DATABASE :"app_db" TO :"app_role";
GRANT USAGE ON SCHEMA public TO :"app_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"app_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"app_role";

-- Future tables/sequences created by THIS owner role auto-grant to the app role, so a
-- new migration never silently leaves the app without access (and never silently
-- re-grants UPDATE/DELETE on a renamed audit table — see the note below).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"app_role";

-- The whole point: the app role can append to and read the audit log, but cannot
-- rewrite or erase it. Runs AFTER the blanket grant above so the REVOKE wins.
-- (TRUNCATE is owner-only by default and was never granted; revoked here for clarity.)
REVOKE UPDATE, DELETE, TRUNCATE ON audit_events FROM :"app_role";
GRANT SELECT, INSERT ON audit_events TO :"app_role";

-- NOTE: if audit_events is ever renamed/replaced by a migration, re-run this script —
-- ALTER DEFAULT PRIVILEGES would otherwise hand the new table full DML to the app role.

#!/bin/bash
# postgres:16 first-boot init (docker-entrypoint-initdb.d). Runs once, on an empty
# data volume, as the in-container superuser ($POSTGRES_USER = the owner role).
#
# Creates the restricted runtime role and the three Solid-stack databases. It does
# NOT grant anything: privileges — including the audit_events lockdown that makes
# the audit log append-only — are applied by db/grants.sql AFTER the migrations have
# created the tables. The pre-deploy hook runs both in that order.
set -e

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-SQL
	CREATE ROLE governauthzer_app LOGIN PASSWORD '${GOVERNAUTHZER_APP_DB_PASSWORD}';
	CREATE DATABASE governauthzer_production_cache OWNER "$POSTGRES_USER";
	CREATE DATABASE governauthzer_production_queue OWNER "$POSTGRES_USER";
	CREATE DATABASE governauthzer_production_cable OWNER "$POSTGRES_USER";
SQL

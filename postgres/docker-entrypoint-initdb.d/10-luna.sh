#!/bin/bash
# Luna's databases: one role and one database per service. Runs when the data
# volume is created (docker-entrypoint-initdb.d) and again on every
# `docker compose up` (the postgres-init service), so a new service gets its
# database on an existing volume; every step is idempotent and the passwords
# follow the environment (AUTH_DB_PASSWORD, DASHBOARD_DB_PASSWORD,
# PAGES_DB_PASSWORD).
set -euo pipefail

: "${AUTH_DB_PASSWORD:?AUTH_DB_PASSWORD is required}"
: "${DASHBOARD_DB_PASSWORD:?DASHBOARD_DB_PASSWORD is required}"
: "${PAGES_DB_PASSWORD:?PAGES_DB_PASSWORD is required}"

# service_db ROLE DATABASE PASSWORD
service_db() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -v role="$1" -v db="$2" -v pass="$3" <<-'EOSQL'
	SELECT format('CREATE ROLE %I LOGIN', :'role')
	 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role')\gexec
	ALTER ROLE :"role" WITH LOGIN PASSWORD :'pass';
	SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role')
	 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db')\gexec
	ALTER DATABASE :"db" OWNER TO :"role";
	EOSQL
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$2" -v role="$1" <<-'EOSQL'
	ALTER SCHEMA public OWNER TO :"role";
	EOSQL
}

service_db auth_service auth_db "$AUTH_DB_PASSWORD"
service_db dashboard_user dashboard "$DASHBOARD_DB_PASSWORD"
service_db pages_service pages_db "$PAGES_DB_PASSWORD"

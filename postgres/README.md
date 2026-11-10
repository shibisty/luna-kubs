# postgres

The `luna-postgres:18` image: PostgreSQL 18 (alpine) that accepts network
connections over TLS only (`pg_hba.conf`: `hostssl`, everything else rejected).

- `generate-tls.sh` runs before the server and creates a CA and a server
  certificate in `/var/lib/postgresql/tls` when they are missing (a volume in
  compose, an emptyDir in Kubernetes). Clients use `sslmode=require`.
- `docker-entrypoint-initdb.d/10-luna.sh` runs once, when the data volume is
  created: a role and a database per service (`auth_service` / `auth_db`,
  `dashboard_user` / `dashboard`), passwords from `AUTH_DB_PASSWORD` and
  `DASHBOARD_DB_PASSWORD`.

A new service gets a line in `10-luna.sh` and its own DSN; on an existing
volume create its role and database by hand (or recreate the volume).

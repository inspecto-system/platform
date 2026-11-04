#!/bin/sh
# Creates one database per service with two roles (SECURITY.md §6):
#   <service>_migrator — owner of the database, runs migrations (DDL);
#   <service>_app      — used by the running service, data access only (DML).
set -eu

create_service_db() {
  service="$1"; migrator_password="$2"; app_password="$3"
  db="inspecto_${service}"
  psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres <<SQL
CREATE ROLE ${service}_migrator LOGIN PASSWORD '${migrator_password}';
CREATE ROLE ${service}_app LOGIN PASSWORD '${app_password}';
CREATE DATABASE ${db} OWNER ${service}_migrator;
REVOKE ALL ON DATABASE ${db} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${db} TO ${service}_app;
SQL
  psql -v ON_ERROR_STOP=1 --username postgres --dbname "${db}" <<SQL
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ${service}_app;
ALTER DEFAULT PRIVILEGES FOR ROLE ${service}_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${service}_app;
ALTER DEFAULT PRIVILEGES FOR ROLE ${service}_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO ${service}_app;
SQL
}

create_service_db core "${CORE_MIGRATOR_PASSWORD}" "${CORE_APP_PASSWORD}"
create_service_db media "${MEDIA_MIGRATOR_PASSWORD}" "${MEDIA_APP_PASSWORD}"
create_service_db report "${REPORT_MIGRATOR_PASSWORD}" "${REPORT_APP_PASSWORD}"

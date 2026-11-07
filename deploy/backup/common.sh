# shellcheck shell=sh disable=SC2034,SC2154
# SC2034/SC2154: the settings are used, and $here is set, by the scripts that source this file.
# Settings shared by backup.sh, restore.sh and keygen.sh (sourced, not run).
# Values come from deploy/.env (S3 admin key) and may be overridden by environment variables.
deploy="$(cd "$here/.." && pwd)"
[ -f "$deploy/.env" ] || { echo "deploy/.env not found" >&2; exit 1; }
# shellcheck disable=SC1091 # deploy/.env is written by the developer from .env.example
. "$deploy/.env"

BACKUP_DIR="${BACKUP_DIR:-$deploy/backups}"
BACKUP_KEY_FILE="${BACKUP_KEY_FILE:-$deploy/backup.key}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
POSTGRES="${POSTGRES_CONTAINER:-inspecto-dev-postgres-1}"
DATA_NETWORK="${DATA_NETWORK:-inspecto-dev_data}"
DATABASES="inspecto_core inspecto_media inspecto_report"
BUCKETS="photos reports"
AWS_IMAGE="amazon/aws-cli:2.39.6"
AGE_IMAGE="alpine:3.22.8"

die() { echo "FAILED: $*" >&2; exit 1; }

# Application services of the stack that exist in this compose file (nginx only in newer versions).
app_services() {
  compose config --services | grep -E '^(core|media|report|nginx)$' | tr '\n' ' '
}

# docker compose of the stack with the "apps" profile (paths converted for Docker on Windows).
compose() {
  docker compose -f "$(host_path "$deploy/compose.dev.yaml")" --env-file "$(host_path "$deploy/.env")" \
    --profile apps "$@"
}

# Path of a host directory as Docker expects it (Windows paths under Git Bash).
host_path() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }

# s3 DIR ARGS... — the AWS CLI with the S3 admin key in the compose network; DIR is mounted as /data.
s3() {
  dir="$1"; shift
  # As the current user: files it writes into DIR stay removable without root (Linux CI).
  docker run --rm --network "$DATA_NETWORK" -v "$(host_path "$dir"):/data" \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e AWS_ACCESS_KEY_ID="$S3_ADMIN_ACCESS_KEY" -e AWS_SECRET_ACCESS_KEY="$S3_ADMIN_SECRET_KEY" \
    -e AWS_DEFAULT_REGION=us-east-1 "$AWS_IMAGE" --endpoint-url http://s3:8333 s3 "$@"
}

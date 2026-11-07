#!/bin/sh
# Restore check of T-507 ("восстановление на чистый compose"): creates data, makes a backup, DELETES
# the whole compose stack with its volumes, starts a clean one, restores the backup and checks that
# the account, the property, the photo and the PDF report are back byte for byte.
#
# It destroys all data of the local stack, so it runs only with VERIFY_DESTROYS_DATA=yes (CI does that).
set -eu
export MSYS_NO_PATHCONV=1
here="$(cd "$(dirname "$0")" && pwd)"
[ "${VERIFY_DESTROYS_DATA:-}" = yes ] || { echo "refusing: set VERIFY_DESTROYS_DATA=yes to wipe the stack" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export BACKUP_DIR="$tmp/backups" BACKUP_KEY_FILE="$tmp/backup.key"
# shellcheck source=common.sh
. "$here/common.sh"

# data MODE [ENV...] — verify-data.sh in a throw-away container on the services network
data() {
  mode="$1"; shift
  docker run --rm --network inspecto-dev_services -v "$(host_path "$deploy/e2e"):/e2e:ro" \
    -v "$(host_path "$here"):/backup:ro" "$@" alpine:3.22.8 \
    sh -c "apk add --no-cache curl jq > /dev/null && sh /backup/verify-data.sh $mode"
}

printf '\n== Data to back up\n'
state="$(data seed | sed -n 's/^STATE //p')"
[ -n "$state" ] || die "seeding printed no state"
echo "   $state"

printf '\n== Backup\n'
sh "$here/keygen.sh"
sh "$here/backup.sh"
archive="$(ls "$BACKUP_DIR"/inspecto-*.tar.age)"

printf '\n== Clean stack\n'
compose down -v
compose up -d --wait --wait-timeout 600
email="$(echo "$state" | tr ' ' '\n' | sed -n 's/^EMAIL=//p')"
docker run --rm --network inspecto-dev_services alpine:3.22.8 sh -c \
  "apk add --no-cache curl > /dev/null && curl -s -o /dev/null -w '%{http_code}' -X POST http://core:8081/api/v1/auth/login \
   -H 'Content-Type: application/json' -d '{\"email\":\"$email\",\"password\":\"Kitchen-Window-Crack-42\",\"client\":\"android\"}'" \
  > "$tmp/status"
[ "$(cat "$tmp/status")" = 401 ] || die "the clean stack still knows the account (HTTP $(cat "$tmp/status"))"
echo "   ok: the clean stack has no data of the account"

printf '\n== Restore\n'
sh "$here/restore.sh" "$archive"

printf '\n== Restored data\n'
# shellcheck disable=SC2046 # one -e option per KEY=value of the state
data check $(for pair in $state; do printf -- '-e %s ' "$pair"; done)
printf '\nBackup and restore check passed.\n'

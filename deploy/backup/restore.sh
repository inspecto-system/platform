#!/bin/sh
# Restores a backup of backup.sh into the running compose stack (T-507): databases are replaced
# object by object, buckets are made equal to the backup (objects added after it are deleted).
# The application services are stopped meanwhile, so that nobody writes half-restored data.
#
#   sh deploy/backup/restore.sh deploy/backups/inspecto-YYYYmmdd-HHMMSS.tar.age
set -eu
export MSYS_NO_PATHCONV=1
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"

archive="${1:-}"
[ -f "$archive" ] || die "usage: restore.sh BACKUP_FILE"
[ -f "$BACKUP_KEY_FILE" ] || die "private key $BACKUP_KEY_FILE not found"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "decrypt"
# The private key is mounted read-only, never passed as an argument.
docker run --rm -i -v "$(host_path "$BACKUP_KEY_FILE"):/key:ro" "$AGE_IMAGE" sh -c \
  'apk add -q age >/dev/null && age -d -i /key' < "$archive" | tar -C "$work" -xf - \
  || die "cannot decrypt $archive"
for db in $DATABASES; do [ -s "$work/db/$db.dump" ] || die "$db is missing in the backup"; done

services="$(app_services)"
echo "stop application services: $services"
# shellcheck disable=SC2086 # $services is a word list
compose stop $services

for db in $DATABASES; do
  echo "restore $db"
  # As the superuser: objects keep their owners (the <service>_migrator roles of the init scripts).
  docker exec -i "$POSTGRES" pg_restore -U postgres -d "$db" --clean --if-exists --single-transaction \
    < "$work/db/$db.dump"
done

for bucket in $BUCKETS; do
  echo "restore bucket $bucket"
  mkdir -p "$work/s3/$bucket"
  s3 "$work/s3" sync --only-show-errors --delete "/data/$bucket" "s3://$bucket"
done

echo "start application services"
# shellcheck disable=SC2086
compose up -d --wait $services
echo "restored from $archive"

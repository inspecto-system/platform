#!/bin/sh
# Encrypted backup of Inspecto (T-507, SECURITY.md §9): the three PostgreSQL databases and the S3
# buckets "photos" and "reports" of deploy/compose.dev.yaml in one file
#   $BACKUP_DIR/inspecto-YYYYmmdd-HHMMSS.tar.age
# encrypted with age for the public key in $BACKUP_KEY_FILE (create it once with keygen.sh).
# Backups older than BACKUP_RETENTION_DAYS (14) are deleted: deleted data leaves the backups by then.
#
#   sh deploy/backup/backup.sh            # from the platform directory, with the compose stack running
set -eu
export MSYS_NO_PATHCONV=1 # Git Bash on Windows: keep container paths as they are
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"

recipient="$(sed -n 's/^# public key: //p' "$BACKUP_KEY_FILE")"
[ -n "$recipient" ] || die "no public key in $BACKUP_KEY_FILE; run deploy/backup/keygen.sh first"
mkdir -p "$BACKUP_DIR"
stamp="$(date -u +%Y%m%d-%H%M%S)"
work="$(mktemp -d "$BACKUP_DIR/.work-XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/db" "$work/s3"

for db in $DATABASES; do
  echo "dump $db"
  # Custom format: compressed, restored object by object with pg_restore.
  docker exec "$POSTGRES" pg_dump -U postgres -Fc -d "$db" > "$work/db/$db.dump"
done

for bucket in $BUCKETS; do
  echo "copy bucket $bucket"
  s3 "$work/s3" sync --only-show-errors "s3://$bucket" "/data/$bucket"
done

echo "encrypt"
out="$BACKUP_DIR/inspecto-$stamp.tar.age"
tar -C "$work" -cf - db s3 | docker run --rm -i "$AGE_IMAGE" sh -c \
  "apk add -q age >/dev/null && age -r '$recipient'" > "$out.part"
mv "$out.part" "$out"
echo "backup written: $out ($(wc -c < "$out") bytes)"

find "$BACKUP_DIR" -maxdepth 1 -name 'inspecto-*.tar.age' -mtime +"$BACKUP_RETENTION_DAYS" -print -delete \
  | sed 's/^/deleted after retention: /'

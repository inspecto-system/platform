#!/bin/sh
# Creates the age key pair of the backups (once). The file holds the private key: keep a copy in a
# safe place apart from the backups — without it they cannot be restored. Only its public key is
# needed to make backups, so on a server the private key need not be kept next to them.
set -eu
export MSYS_NO_PATHCONV=1
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"

[ ! -e "$BACKUP_KEY_FILE" ] || die "$BACKUP_KEY_FILE already exists"
docker run --rm "$AGE_IMAGE" sh -c 'apk add -q age >/dev/null && age-keygen 2>/dev/null' > "$BACKUP_KEY_FILE"
chmod 600 "$BACKUP_KEY_FILE"
echo "key written: $BACKUP_KEY_FILE"

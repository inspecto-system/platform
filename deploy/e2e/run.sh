#!/bin/sh
# Runs the CP2 scenario in a throw-away container on the compose network, so it reaches core and
# media by their service names, the same way locally and in CI. Start the services first:
#   docker compose -f deploy/compose.dev.yaml --env-file deploy/.env --profile apps up -d --build --wait
# Then checks from outside that nothing of the deleted account is left in the databases and in
# SeaweedFS (T-303): the API alone cannot prove it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

docker run --rm --network inspecto-dev_services -v "$here:/e2e:ro" alpine:3.22.8 \
  sh -c 'apk add --no-cache curl jq > /dev/null && sh /e2e/cp2.sh' > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"

cleanup="$(grep '^CLEANUP ' "$log")" || { echo "FAILED: the scenario printed no CLEANUP line" >&2; exit 1; }
owner="$(echo "$cleanup" | sed 's/.*owner=\([^ ]*\).*/\1/')"
property="$(echo "$cleanup" | sed 's/.*property=\([^ ]*\).*/\1/')"

sql() { docker exec inspecto-dev-postgres-1 psql -U postgres -d "$1" -tAc "$2"; }
# Bytes stored under the property in SeaweedFS; empty directories stay after their objects are deleted.
bytes() { docker exec inspecto-dev-s3-1 sh -c "echo 'fs.du /buckets/photos/$property' | weed shell -master=localhost:9333 2>/dev/null" | sed -n 's/.*logical size: *\([0-9]*\).*/\1/p'; }

printf '\n== Nothing of account %s is left in storage\n' "$owner"
core="$(sql inspecto_core "select (select count(*) from users where id = '$owner') + (select count(*) from properties where owner_id = '$owner')")"
[ "$core" = 0 ] || { echo "   FAILED: $core rows of the account in inspecto_core" >&2; exit 1; }
echo "   ok: no rows in inspecto_core"
# The outbox job runs in the background and retries: give it up to a minute.
for _ in $(seq 1 30); do
  rows="$(sql inspecto_media "select count(*) from photos where owner_id = '$owner'")"
  [ "$rows" = 0 ] && [ "$(bytes)" = 0 ] && { echo "   ok: no photos in inspecto_media, no bytes in SeaweedFS"; exit 0; }
  sleep 2
done
echo "   FAILED: $rows photos in inspecto_media, $(bytes) bytes in SeaweedFS for property $property" >&2
exit 1

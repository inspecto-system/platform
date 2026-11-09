#!/bin/sh
# Runs the CP2 scenario in a throw-away container on the compose network, so it reaches core, media
# and report by their service names, the same way locally and in CI; nginx.sh then checks the entry
# point (nginx). cp2.sh does not go through nginx: its many sign-ins from one IP would hit the sign-in
# rate limit that nginx.sh verifies. Start the services first:
#   docker compose -f deploy/compose.dev.yaml --env-file deploy/.env --profile apps up -d --build --wait
# Then checks from outside that nothing of the deleted property and of the deleted account is left
# in the databases and in SeaweedFS (T-303): the API alone cannot prove it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

docker run --rm --network inspecto-dev_services -v "$here:/e2e:ro" alpine:3.22.8 \
  sh -c 'apk add --no-cache curl jq > /dev/null && sh /e2e/cp2.sh && sh /e2e/nginx.sh' > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"

cleanup="$(grep '^CLEANUP ' "$log")" || { echo "FAILED: the scenario printed no CLEANUP line" >&2; exit 1; }
owner="$(echo "$cleanup" | sed 's/.*owner=\([^ ]*\).*/\1/')"
property="$(echo "$cleanup" | sed 's/.*property=\([^ ]*\).*/\1/')"
deleted="$(echo "$cleanup" | sed 's/.*deleted=\([^ ]*\).*/\1/')"

sql() { docker exec inspecto-dev-postgres-1 psql -U postgres -d "$1" -tAc "$2"; }
# bytes BUCKET PROPERTY — bytes stored under the property in SeaweedFS; empty directories stay after
# their objects are deleted, so only the size proves the clean-up.
bytes() { docker exec inspecto-dev-s3-1 sh -c "echo 'fs.du /buckets/$1/$2' | weed shell -master=localhost:9333 2>/dev/null" | sed -n 's/.*logical size: *\([0-9]*\).*/\1/p'; }
# reports CONDITION — report jobs matching the SQL condition.
reports() { sql inspecto_report "select count(*) from reports where $1"; }

printf '\n== Nothing of account %s is left in storage\n' "$owner"
core="$(sql inspecto_core "select (select count(*) from users where id = '$owner') + (select count(*) from properties where owner_id = '$owner')")"
[ "$core" = 0 ] || { echo "   FAILED: $core rows of the account in inspecto_core" >&2; exit 1; }
echo "   ok: no rows in inspecto_core"
# The outbox jobs run in the background and retry: give them up to a minute.
for _ in $(seq 1 30); do
  rows="$(sql inspecto_media "select count(*) from photos where owner_id = '$owner'")"
  pdfs="$(reports "property_id = '$property' or requested_by = '$owner'")"
  if [ "$rows" = 0 ] && [ "$pdfs" = 0 ] && [ "$(bytes photos "$property")" = 0 ] && [ "$(bytes reports "$property")" = 0 ]; then
    echo "   ok: no photos in inspecto_media, no reports in inspecto_report, no bytes in SeaweedFS"
    clean=1
    break
  fi
  sleep 2
done
[ "${clean:-0}" = 1 ] || {
  echo "   FAILED: $rows photos, $pdfs reports, $(bytes photos "$property") + $(bytes reports "$property") bytes left of account $owner" >&2
  exit 1
}

printf '\n== No report of deleted property %s is left in storage\n' "$deleted"
pdfs="$(reports "property_id = '$deleted'")"
left="$(bytes reports "$deleted")"
[ "$pdfs" = 0 ] && [ "$left" = 0 ] || { echo "   FAILED: $pdfs reports and $left bytes of property $deleted" >&2; exit 1; }
echo "   ok: no reports in inspecto_report, no bytes in bucket reports"

# T-604: the same stack without ml-service. The container is started again whatever the result, so
# that a failed check does not leave the stack degraded.
printf '\n== ml-service stopped (T-604)\n'
docker stop inspecto-dev-ml-1 > /dev/null
trap 'docker start inspecto-dev-ml-1 > /dev/null; rm -f "$log"' EXIT
docker run --rm --network inspecto-dev_services -v "$here:/e2e:ro" alpine:3.22.8 \
  sh -c 'apk add --no-cache curl jq > /dev/null && sh /e2e/ml.sh' > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"

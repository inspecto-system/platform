#!/bin/sh
# T-604: ml-service is stopped — registering a defect works as before, only without a suggestion.
# run.sh stops the ml container before this script and starts it again afterwards; the suggestion
# call must answer 200 with an empty list, quickly (core waits at most 3 s for ml-service).
#
# Needs curl and jq; runs inside the compose network like cp2.sh.
set -eu

CORE="${CORE_URL:-http://core:8081}/api/v1"
MEDIA="${MEDIA_URL:-http://media:8082}/api/v1"
PHOTO="${PHOTO:-$(dirname "$0")/room.jpg}"
RUN="$(date +%s)-$$"
MAX_SECONDS=5

step() { printf '\n== %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
fail() { printf '   FAILED: %s\n' "$*" >&2; exit 1; }
request() {
  method="$1"; url="$2"; shift 2
  curl -sS -o /tmp/e2e-body -w '%{http_code} %{time_total}' -X "$method" "$url" "$@" > /tmp/e2e-status \
    || fail "$method $url: no answer"
  cat /tmp/e2e-body
}
status() { cut -d' ' -f1 /tmp/e2e-status; }
seconds() { cut -d' ' -f2 /tmp/e2e-status; }
expect() { [ "$(status)" = "$1" ] || fail "expected HTTP $1, got $(status): $(head -c 300 /tmp/e2e-body)"; }
json() { request "$1" "$2" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' ${3:+-d "$3"}; }

step "Inspector with a started inspection and an uploaded photo (ml-service is stopped)"
EMAIL="ml-down-$RUN@example.com"
PASSWORD="Kitchen-Window-Crack-42"
request POST "$CORE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"ML down E2E\"}" > /dev/null
expect 201
TOKEN=$(request POST "$CORE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" | jq -r .accessToken)
expect 200
PROPERTY=$(json POST "$CORE/properties" '{"name":"ML down","type":"APARTMENT","address":"Mira 5"}' | jq -r .id)
expect 201
ROOM=$(json POST "$CORE/properties/$PROPERTY/rooms" '{"name":"Kitchen","roomType":"KITCHEN"}' | jq -r .id)
expect 201
INSPECTION=$(json POST "$CORE/properties/$PROPERTY/inspections" \
  "{\"inspectedAt\":\"2026-11-09T09:00:00Z\",\"roomIds\":[\"$ROOM\"],\"templateCodes\":[\"ROOM_STANDARD\"]}" | jq -r .id)
expect 201
json PATCH "$CORE/inspections/$INSPECTION" '{"status":"IN_PROGRESS","version":0}' > /dev/null
expect 200
PHOTO_ID=$(request POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: ml-down-$RUN" \
  -F "propertyId=$PROPERTY" -F "file=@$PHOTO;type=image/jpeg" | jq -r .id)
expect 201
ok "inspection $INSPECTION started, photo $PHOTO_ID uploaded"

step "Suggestion request answers with an empty list, not an error"
ANSWER=$(json POST "$CORE/category-suggestions" "{\"photoId\":\"$PHOTO_ID\"}")
expect 200
[ "$(echo "$ANSWER" | jq -c .items)" = "[]" ] || fail "expected no suggestions: $ANSWER"
[ "$(echo "$ANSWER" | jq 'has("suggestionId")')" = false ] || fail "a suggestionId without suggestions: $ANSWER"
awk -v s="$(seconds)" -v max="$MAX_SECONDS" 'BEGIN { exit !(s < max) }' \
  || fail "the answer took $(seconds) s (at most $MAX_SECONDS s)"
ok "200 {items: []} in $(seconds) s"
json POST "$CORE/category-suggestions" "{\"photoId\":\"$(cat /proc/sys/kernel/random/uuid)\"}" > /dev/null
expect 404
ok "an unknown photo is still 404: the owner is checked before ml-service is called"

step "Defect is registered with the photo as usual"
CRACK=$(json GET "$CORE/defect-categories" | jq -r '.[] | select(.code == "CRACK") | .id')
OBSERVATION=$(json POST "$CORE/inspections/$INSPECTION/defects" \
  "{\"roomId\":\"$ROOM\",\"categoryId\":\"$CRACK\",\"elementGroup\":\"WALLS\",\"title\":\"Crack\",\"severity\":\"MAJOR\"}" \
  | jq -r '.observations[0].id')
expect 201
json POST "$CORE/observations/$OBSERVATION/photos" "{\"photoId\":\"$PHOTO_ID\"}" > /dev/null
expect 201
ok "defect created and the photo attached without ml-service"

step "Clean-up: the test account is deleted with its data and files"
json DELETE "$CORE/users/me" "{\"password\":\"$PASSWORD\"}" > /dev/null
expect 202
ok "account $EMAIL deleted"

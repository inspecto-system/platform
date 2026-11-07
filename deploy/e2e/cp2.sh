#!/bin/sh
# End-to-end scenario of checkpoint CP2 (T-207): from registration to a defect with a photo, a repeat
# inspection, and the clean-up of photos through the outbox of core-service.
#
# Runs against the "apps" profile of deploy/compose.dev.yaml, inside the compose network:
#   deploy/e2e/run.sh
# Needs curl and jq. Every step prints a line; the first failed check stops the script.
set -eu

CORE="${CORE_URL:-http://core:8081}/api/v1"
MEDIA="${MEDIA_URL:-http://media:8082}/api/v1"
REPORT="${REPORT_URL:-http://report:8083}/api/v1"
PHOTO="${PHOTO:-$(dirname "$0")/room.jpg}"
RUN="$(date +%s)-$$"

step() { printf '\n== %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
fail() { printf '   FAILED: %s\n' "$*" >&2; exit 1; }

# request METHOD URL [curl args...] — prints the body and keeps the status in a file: the call
# often runs in a command substitution, a subshell that cannot set variables of the script.
request() {
  method="$1"; url="$2"; shift 2
  curl -sS -o /tmp/e2e-body -w '%{http_code}' -X "$method" "$url" "$@" > /tmp/e2e-status \
    || fail "$method $url: no answer"
  cat /tmp/e2e-body
}
status() { cat /tmp/e2e-status; }
# Bodies are cut short: they may hold the throw-away tokens of the test users.
expect() { [ "$(status)" = "$1" ] || fail "expected HTTP $1, got $(status): $(head -c 300 /tmp/e2e-body)"; }
json() { request "$1" "$2" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' ${3:+-d "$3"}; }

# finish INSPECTION — moves the inspection to COMPLETED from DRAFT or IN_PROGRESS.
finish() {
  current=$(json GET "$CORE/inspections/$1")
  if [ "$(echo "$current" | jq -r .status)" = DRAFT ]; then
    current=$(json PATCH "$CORE/inspections/$1" "{\"status\":\"IN_PROGRESS\",\"version\":$(echo "$current" | jq .version)}")
    expect 200
  fi
  json POST "$CORE/inspections/$1/complete" "{\"version\":$(echo "$current" | jq .version)}" > /dev/null
  expect 200
}

# report_pdf INSPECTION — orders a report, waits until it is ready (every 2 s, up to 60 s, as the
# contract says), downloads it and prints the report id; fails unless the file is a PDF.
report_pdf() {
  id=$(json POST "$REPORT/reports" "{\"inspectionId\":\"$1\",\"locale\":\"ru\"}" | jq -r .id)
  expect 202
  for _ in $(seq 1 30); do
    state=$(json GET "$REPORT/reports/$id" | jq -r .status)
    case "$state" in
      DONE) break ;;
      FAILED) fail "report $id failed: $(head -c 300 /tmp/e2e-body)" ;;
    esac
    sleep 2
  done
  [ "$state" = DONE ] || fail "report $id is not ready after 60 s (status $state)"
  request GET "$REPORT/reports/$id/file" -H "Authorization: Bearer $TOKEN" > /dev/null
  expect 200
  [ "$(head -c 5 /tmp/e2e-body)" = "%PDF-" ] || fail "report $id is not a PDF"
  echo "$id"
}

step "Registration and sign-in"
EMAIL="cp2-$RUN@example.com"
PASSWORD="Kitchen-Window-Crack-42"
request POST "$CORE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"CP2 E2E\"}" > /dev/null
expect 201
TOKEN=$(request POST "$CORE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" | jq -r .accessToken)
expect 200
ok "signed in as $EMAIL"

step "Property, room and inspection"
PROPERTY=$(json POST "$CORE/properties" '{"name":"CP2 apartment","type":"APARTMENT","address":"Mira 5"}' | jq -r .id)
expect 201
ROOM=$(json POST "$CORE/properties/$PROPERTY/rooms" '{"name":"Kitchen","roomType":"KITCHEN"}' | jq -r .id)
expect 201
FIRST=$(json POST "$CORE/properties/$PROPERTY/inspections" \
  "{\"inspectedAt\":\"2026-10-01T09:00:00Z\",\"roomIds\":[\"$ROOM\"],\"templateCodes\":[\"ROOM_STANDARD\"]}")
expect 201
INSPECTION=$(echo "$FIRST" | jq -r .id)
ITEMS=$(echo "$FIRST" | jq '.rooms[0].checklist | length')
[ "$ITEMS" -gt 0 ] || fail "checklist is empty"
json PATCH "$CORE/inspections/$INSPECTION" '{"status":"IN_PROGRESS","version":0}' > /dev/null
expect 200
ok "inspection $INSPECTION started with $ITEMS checklist items"

step "Defect with its first observation"
CRACK=$(json GET "$CORE/defect-categories" | jq -r '.[] | select(.code == "CRACK") | .id')
DEFECT=$(json POST "$CORE/inspections/$INSPECTION/defects" \
  "{\"roomId\":\"$ROOM\",\"categoryId\":\"$CRACK\",\"elementGroup\":\"WALLS\",\"title\":\"Crack by the window\",\"severity\":\"MAJOR\"}")
expect 201
DEFECT_ID=$(echo "$DEFECT" | jq -r .id)
OBSERVATION=$(echo "$DEFECT" | jq -r '.observations[0].id')
[ "$(echo "$DEFECT" | jq -r .currentStatus)" = OPEN ] || fail "new defect is not OPEN"
ok "defect $DEFECT_ID is OPEN"

step "Photo upload to media-service"
UPLOADED=$(request POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: cp2-$RUN" \
  -F "propertyId=$PROPERTY" -F "file=@$PHOTO;type=image/jpeg")
expect 201
PHOTO_ID=$(echo "$UPLOADED" | jq -r .id)
[ "$(echo "$UPLOADED" | jq -r '.width, .height' | tr '\n' x)" = "40x80x" ] \
  || fail "EXIF orientation not applied: $UPLOADED"
AGAIN=$(request POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: cp2-$RUN" \
  -F "propertyId=$PROPERTY" -F "file=@$PHOTO;type=image/jpeg" | jq -r .id)
[ "$AGAIN" = "$PHOTO_ID" ] || fail "repeated upload with the same Idempotency-Key created another photo"
ok "photo $PHOTO_ID stored rotated (40x80), repeat returned the same photo"

step "Photo attached to the observation"
json POST "$CORE/observations/$OBSERVATION/photos" "{\"photoId\":\"$PHOTO_ID\",\"caption\":\"general view\"}" > /dev/null
expect 201
[ "$(json GET "$CORE/defects/$DEFECT_ID" | jq -r '.observations[0].photos[0].photoId')" = "$PHOTO_ID" ] \
  || fail "photo is not shown on the defect"
request DELETE "$MEDIA/photos/$PHOTO_ID" -H "Authorization: Bearer $TOKEN" > /dev/null
expect 409
request GET "$MEDIA/photos/$PHOTO_ID/content?variant=thumb" -H "Authorization: Bearer $TOKEN" -D /tmp/e2e-headers > /dev/null
expect 200
grep -qi '^content-type: image/jpeg' /tmp/e2e-headers || fail "thumbnail is not a JPEG"
ok "photo attached, shown on the defect, protected from direct deletion, thumbnail served"

step "Access of another user"
OTHER_EMAIL="cp2-other-$RUN@example.com"
request POST "$CORE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$OTHER_EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Other\"}" > /dev/null
OTHER=$(request POST "$CORE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$OTHER_EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" | jq -r .accessToken)
request GET "$CORE/defects/$DEFECT_ID" -H "Authorization: Bearer $OTHER" > /dev/null
expect 404
request GET "$MEDIA/photos/$PHOTO_ID/content" -H "Authorization: Bearer $OTHER" > /dev/null
expect 404
ok "defect and photo are hidden from another user (404)"

step "Repeat inspection marks the defect resolved"
REPEAT=$(json POST "$CORE/properties/$PROPERTY/inspections" \
  "{\"inspectedAt\":\"2026-11-01T09:00:00Z\",\"roomIds\":[\"$ROOM\"],\"templateCodes\":[\"ROOM_STANDARD\"]}" | jq -r .id)
expect 201
[ "$(json GET "$CORE/inspections/$REPEAT/open-defects" | jq -r '.[0].defect.id')" = "$DEFECT_ID" ] \
  || fail "defect is not offered for the repeat inspection"
json POST "$CORE/inspections/$REPEAT/observations" "{\"defectId\":\"$DEFECT_ID\",\"status\":\"RESOLVED\"}" > /dev/null
expect 201
[ "$(json GET "$CORE/defects/$DEFECT_ID" | jq -r .currentStatus)" = RESOLVED ] || fail "defect is not RESOLVED"
[ "$(json GET "$CORE/defects/$DEFECT_ID/history" | jq -r '[.[].toStatus] | join(",")')" = "OPEN,RESOLVED" ] \
  || fail "status history is wrong"
ok "defect RESOLVED, history OPEN -> RESOLVED"

step "PDF report of the completed inspection (T-402)"
# The repeat inspection is reported: the first one stays open, later steps change its photos.
json POST "$REPORT/reports" "{\"inspectionId\":\"$REPEAT\"}" > /dev/null
expect 409
finish "$REPEAT"
REPORT_ID=$(report_pdf "$REPEAT")
SIZE=$(wc -c < /tmp/e2e-body)
request GET "$REPORT/reports/$REPORT_ID" -H "Authorization: Bearer $OTHER" > /dev/null
expect 404
request GET "$REPORT/reports/$REPORT_ID/file" -H "Authorization: Bearer $OTHER" > /dev/null
expect 404
ok "report $REPORT_ID downloaded ($SIZE bytes of PDF); refused before completion (409) and to another user (404)"

# wait_gone PHOTO — waits until the outbox job of core has deleted the photo in media (up to 60 s).
wait_gone() {
  for _ in $(seq 1 30); do
    request GET "$MEDIA/photos/$1/content" -H "Authorization: Bearer $TOKEN" > /dev/null
    [ "$(status)" = 404 ] && return 0
    sleep 2
  done
  fail "photo $1 is still in media-service"
}

step "Detached photo is deleted through the outbox"
json DELETE "$CORE/observations/$OBSERVATION/photos/$PHOTO_ID" > /dev/null
expect 204
wait_gone "$PHOTO_ID"
ok "photo $PHOTO_ID deleted in media-service"

step "Deleting the property deletes its photos"
SECOND=$(request POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" -F "propertyId=$PROPERTY" -F "file=@$PHOTO;type=image/jpeg" | jq -r .id)
expect 201
json POST "$CORE/observations/$OBSERVATION/photos" "{\"photoId\":\"$SECOND\"}" > /dev/null
expect 201
json DELETE "$CORE/properties/$PROPERTY" > /dev/null
expect 202
request GET "$CORE/properties/$PROPERTY" -H "Authorization: Bearer $TOKEN" > /dev/null
expect 404
wait_gone "$SECOND"
ok "property and its photo deleted"
DELETED_PROPERTY="$PROPERTY"

step "Deleting the account deletes all its data (T-303)"
ACCOUNT_EMAIL="cp2-account-$RUN@example.com"
request POST "$CORE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ACCOUNT_EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Leaving\"}" > /dev/null
expect 201
TOKEN=$(request POST "$CORE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ACCOUNT_EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" | jq -r .accessToken)
expect 200
OWNER=$(json GET "$CORE/users/me" | jq -r .id)
PROPERTY=$(json POST "$CORE/properties" '{"name":"To delete","type":"HOUSE","address":"Lesnaya 1"}' | jq -r .id)
expect 201
ROOM=$(json POST "$CORE/properties/$PROPERTY/rooms" '{"name":"Hall","roomType":"HALLWAY"}' | jq -r .id)
INSPECTION=$(json POST "$CORE/properties/$PROPERTY/inspections" \
  "{\"inspectedAt\":\"2026-10-01T09:00:00Z\",\"roomIds\":[\"$ROOM\"],\"templateCodes\":[\"ROOM_STANDARD\"]}" | jq -r .id)
expect 201
OBSERVATION=$(json POST "$CORE/inspections/$INSPECTION/defects" \
  "{\"roomId\":\"$ROOM\",\"categoryId\":\"$CRACK\",\"elementGroup\":\"FLOOR\",\"title\":\"Scratch\",\"severity\":\"MINOR\"}" \
  | jq -r '.observations[0].id')
expect 201
LAST=$(request POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" -F "propertyId=$PROPERTY" -F "file=@$PHOTO;type=image/jpeg" | jq -r .id)
expect 201
json POST "$CORE/observations/$OBSERVATION/photos" "{\"photoId\":\"$LAST\"}" > /dev/null
expect 201
finish "$INSPECTION"
report_pdf "$INSPECTION" > /dev/null
json DELETE "$CORE/users/me" '{"password":"Wrong-Password-1"}' > /dev/null
expect 400
json DELETE "$CORE/users/me" "{\"password\":\"$PASSWORD\"}" > /dev/null
expect 202
request POST "$CORE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ACCOUNT_EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" > /dev/null
expect 401
ok "account $OWNER deleted; it cannot sign in"
# run.sh checks the databases and SeaweedFS from outside the network: the photo is no longer
# readable through the API right away (core denies access), so only storage proves the clean-up.
printf 'CLEANUP owner=%s property=%s deleted=%s\n' "$OWNER" "$PROPERTY" "$DELETED_PROPERTY"

printf '\nCP2 scenario passed.\n'

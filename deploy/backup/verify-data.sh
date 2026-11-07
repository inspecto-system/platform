#!/bin/sh
# Data for the restore check of verify.sh, run inside the compose network (needs curl and jq).
#   verify-data.sh seed   — creates an account with a property, a defect with a photo and a PDF report,
#                           prints "STATE key=value ..." with ids and checksums of the files
#   verify-data.sh check  — with the STATE values in the environment, checks that all of it is back
set -eu
CORE=http://core:8081/api/v1
MEDIA=http://media:8082/api/v1
REPORT=http://report:8083/api/v1
PASSWORD="Kitchen-Window-Crack-42"

fail() { echo "FAILED: $*" >&2; exit 1; }
# get URL — body to stdout, fails on an error status
get() { curl -fsS -H "Authorization: Bearer $TOKEN" "$1"; }
post() { curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$1" -d "$2"; }
login() {
  TOKEN=$(curl -fsS -X POST "$CORE/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}" | jq -r .accessToken)
}
sha() { get "$1" | sha256sum | cut -d' ' -f1; }

seed() {
  EMAIL="backup-$(date +%s)@example.com"
  curl -fsS -X POST "$CORE/auth/register" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Backup Check\"}" > /dev/null
  login
  PROPERTY=$(post "$CORE/properties" '{"name":"Backup flat","type":"APARTMENT","address":"Mira 7"}' | jq -r .id)
  ROOM=$(post "$CORE/properties/$PROPERTY/rooms" '{"name":"Hall","roomType":"HALLWAY"}' | jq -r .id)
  INSPECTION=$(post "$CORE/properties/$PROPERTY/inspections" \
    "{\"inspectedAt\":\"2026-10-01T09:00:00Z\",\"roomIds\":[\"$ROOM\"],\"templateCodes\":[\"ROOM_STANDARD\"]}" | jq -r .id)
  curl -fsS -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    "$CORE/inspections/$INSPECTION" -d '{"status":"IN_PROGRESS","version":0}' > /dev/null
  CRACK=$(get "$CORE/defect-categories" | jq -r '.[] | select(.code == "CRACK") | .id')
  DEFECT=$(post "$CORE/inspections/$INSPECTION/defects" \
    "{\"roomId\":\"$ROOM\",\"categoryId\":\"$CRACK\",\"elementGroup\":\"WALLS\",\"title\":\"Crack\",\"severity\":\"MAJOR\"}")
  OBSERVATION=$(echo "$DEFECT" | jq -r '.observations[0].id')
  PHOTO=$(curl -fsS -X POST "$MEDIA/photos" -H "Authorization: Bearer $TOKEN" \
    -F "propertyId=$PROPERTY" -F "file=@/e2e/room.jpg;type=image/jpeg" | jq -r .id)
  post "$CORE/observations/$OBSERVATION/photos" "{\"photoId\":\"$PHOTO\"}" > /dev/null
  version=$(get "$CORE/inspections/$INSPECTION" | jq .version)
  post "$CORE/inspections/$INSPECTION/complete" "{\"version\":$version}" > /dev/null
  REPORT_ID=$(post "$REPORT/reports" "{\"inspectionId\":\"$INSPECTION\"}" | jq -r .id)
  for _ in $(seq 1 30); do
    [ "$(get "$REPORT/reports/$REPORT_ID" | jq -r .status)" = DONE ] && break
    sleep 2
  done
  echo "STATE EMAIL=$EMAIL PROPERTY=$PROPERTY DEFECT=$(echo "$DEFECT" | jq -r .id) PHOTO=$PHOTO" \
    "REPORT_ID=$REPORT_ID PHOTO_SHA=$(sha "$MEDIA/photos/$PHOTO/content?variant=original")" \
    "REPORT_SHA=$(sha "$REPORT/reports/$REPORT_ID/file")"
}

check() {
  login
  [ "$(get "$CORE/properties/$PROPERTY" | jq -r .name)" = "Backup flat" ] || fail "property is not restored"
  [ "$(get "$CORE/defects/$DEFECT" | jq -r '.observations[0].photos[0].photoId')" = "$PHOTO" ] \
    || fail "photo is not attached to the restored defect"
  [ "$(sha "$MEDIA/photos/$PHOTO/content?variant=original")" = "$PHOTO_SHA" ] || fail "photo bytes differ"
  [ "$(get "$REPORT/reports/$REPORT_ID" | jq -r .status)" = DONE ] || fail "report job is not restored"
  [ "$(sha "$REPORT/reports/$REPORT_ID/file")" = "$REPORT_SHA" ] || fail "report bytes differ"
  echo "restored: account, property, defect with its photo (same bytes), PDF report (same bytes)"
}

case "${1:-}" in
  seed) seed ;;
  check) check ;;
  *) fail "usage: verify-data.sh seed|check" ;;
esac

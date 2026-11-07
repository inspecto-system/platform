#!/bin/sh
# Checks of the entry point (T-505, ADR-013, SECURITY.md §2 and §10, TESTING.md SEC-09): HTTPS only,
# security headers, routing by resource, unpublished internal endpoints, body and rate limits.
# Runs inside the compose network next to cp2.sh (deploy/e2e/run.sh). Needs curl and jq.
set -eu

HOST="${NGINX_HOST:-nginx}"
BASE="https://$HOST/api/v1"
RUN="$(date +%s)-$$"

step() { printf '\n== %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
fail() { printf '   FAILED: %s\n' "$*" >&2; exit 1; }

# call METHOD URL [curl args...] — keeps the status, headers and body in files (see cp2.sh).
call() {
  method="$1"; url="$2"; shift 2
  curl -ksS -o /tmp/ngx-body -D /tmp/ngx-headers -w '%{http_code}' -X "$method" "$url" "$@" > /tmp/ngx-status \
    || fail "$method $url: no answer"
}
status() { cat /tmp/ngx-status; }
expect() { [ "$(status)" = "$1" ] || fail "expected HTTP $1, got $(status): $(head -c 300 /tmp/ngx-body)"; }
header() { grep -i "^$1:" /tmp/ngx-headers | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }
code() { jq -r .code /tmp/ngx-body; }

step "Plain HTTP redirects to HTTPS"
call GET "http://$HOST/api/v1/.well-known/jwks.json"
expect 301
case "$(header Location)" in https://*) ;; *) fail "redirect target is $(header Location)" ;; esac
ok "301 to $(header Location)"

step "Security headers (SEC-09)"
call GET "$BASE/.well-known/jwks.json"
expect 200
case "$(header Strict-Transport-Security)" in max-age=31536000*) ;; *) fail "HSTS: $(header Strict-Transport-Security)" ;; esac
[ "$(header X-Content-Type-Options)" = nosniff ] || fail "X-Content-Type-Options missing"
[ "$(header Referrer-Policy)" = no-referrer ] || fail "Referrer-Policy missing"
[ "$(header X-Frame-Options)" = DENY ] || fail "X-Frame-Options missing"
case "$(header Content-Security-Policy)" in *"default-src 'none'"*"frame-ancestors 'none'"*) ;; *) fail "CSP: $(header Content-Security-Policy)" ;; esac
[ "$(header Server)" = nginx ] || fail "Server header discloses a version: $(header Server)"
ok "HSTS, nosniff, Referrer-Policy, X-Frame-Options, CSP; Server without version"

step "Routing to core, media and report"
EMAIL="nginx-$RUN@example.com"
PASSWORD="Kitchen-Window-Crack-42"
call POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Nginx Check\"}"
expect 201
call POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"client\":\"android\"}"
expect 200
TOKEN=$(jq -r .accessToken /tmp/ngx-body)
call GET "$BASE/properties" -H "Authorization: Bearer $TOKEN"
expect 200
call GET "$BASE/photos/limits" -H "Authorization: Bearer $TOKEN"
expect 200
[ "$(jq -r .maxFileSizeBytes /tmp/ngx-body)" -gt 0 ] || fail "photo limits are not from media-service"
call GET "$BASE/reports?inspectionId=$(cat /proc/sys/kernel/random/uuid)" -H "Authorization: Bearer $TOKEN"
[ "$(status)" = 200 ] || [ "$(status)" = 404 ] || fail "reports answered $(status)"
[ -n "$(header X-Request-Id)" ] || fail "no X-Request-Id in the answer"
ok "properties (core), photo limits (media), reports (report) through one host"

step "Internal endpoints and actuators are not published (ADR-013)"
for path in /internal/v1/reports /internal/v1/access/properties/x /actuator/health /health/ready; do
  call GET "https://$HOST$path"
  expect 404
done
call GET "https://$HOST/api/v1/../../internal/v1/reports" --path-as-is
expect 404
call GET "https://$HOST/api/v1/%2e%2e/%2e%2e/internal/v1/reports" --path-as-is
expect 404
[ "$(code)" = NOT_FOUND ] || fail "404 is not problem details"
ok "/internal/**, actuators and health checks answer 404, also through ../"

step "Body limits"
head -c 1100000 /dev/zero | tr '\0' 'a' > /tmp/ngx-big
call POST "$BASE/properties" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary @/tmp/ngx-big
expect 413
[ "$(code)" = IMAGE_TOO_LARGE ] || fail "413 without problem details"
call POST "$BASE/photos" -H "Authorization: Bearer $TOKEN" -F "file=@/tmp/ngx-big;type=image/jpeg"
[ "$(status)" != 413 ] || fail "a 1 MB photo was refused by nginx"
ok "1 MB JSON refused (413), the same size passes to media-service as a photo"

step "Rate limit of sign-in (SECURITY.md §2)"
limited=0
for _ in 1 2 3 4 5 6 7 8; do
  call POST "$BASE/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"nobody-$RUN@example.com\",\"password\":\"Wrong-Password-1\",\"client\":\"android\"}"
  if [ "$(status)" = 429 ]; then limited=1; break; fi
done
[ "$limited" = 1 ] || fail "8 sign-ins in a row were not limited"
[ "$(code)" = RATE_LIMITED ] || fail "429 without code RATE_LIMITED"
[ "$(header Retry-After)" = 60 ] || fail "429 without Retry-After"
ok "429 RATE_LIMITED with Retry-After"

printf '\nnginx checks passed.\n'

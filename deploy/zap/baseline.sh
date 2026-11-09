#!/bin/sh
# OWASP ZAP baseline (T-506, SECURITY.md §11): a passive scan of the web app and of the API through
# nginx in the compose network. Any warning fails, except the ones accepted in rules.tsv with a reason.
# The stack must be running (deploy/e2e/run.sh starts nothing). Reports go to deploy/zap/out/.
set -eu
export MSYS_NO_PATHCONV=1
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/out"
mkdir -p "$out"
cp "$here/rules.tsv" "$out/rules.tsv"
wrk="$out"
if command -v cygpath > /dev/null 2>&1; then wrk="$(cygpath -w "$out")"; fi

status=0
for target in https://nginx/login https://nginx/api/v1/.well-known/jwks.json; do
  name="$(echo "$target" | sed 's|https://nginx/||; s|[^a-z0-9]|-|g')"
  printf '\n== ZAP baseline: %s\n' "$target"
  docker run --rm --network inspecto-dev_services -u root -v "$wrk:/zap/wrk:rw" zaproxy/zap-stable:2.17.0 \
    zap-baseline.py -t "$target" -m 2 -c rules.tsv -r "$name.html" -w "$name.md" || status=$?
done
exit "$status"

#!/bin/sh
# Runs the CP2 scenario in a throw-away container on the compose network, so it reaches core and
# media by their service names, the same way locally and in CI. Start the services first:
#   docker compose -f deploy/compose.dev.yaml --env-file deploy/.env --profile apps up -d --build --wait
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
docker run --rm --network inspecto-dev_services -v "$here:/e2e:ro" alpine:3.22.8 \
  sh -c 'apk add --no-cache curl jq > /dev/null && sh /e2e/cp2.sh'

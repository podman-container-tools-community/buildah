#!/usr/bin/env bash
# Exercises what people use buildah for with a built binary, as root and rootless:
#   hack/functional-test.sh <buildah> <registry host:port>
# Runs test/functional.bats with bats from mise.toml on PATH (mise install). Needs
# network access to quay.io, a plain-HTTP registry at <registry>, sudo, runc or crun,
# netavark, jq, curl, newuidmap/newgidmap and a subordinate ID range for the current user.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
status=0
for mode in root rootless; do
  echo "=== ${mode}" >&2
  BUILDAH="$(realpath "$1")" REGISTRY="$2" MODE="${mode}" \
    bats --formatter tap "${repo}/test/functional.bats" || status=1
done
exit "${status}"

#!/usr/bin/env bash
# Exercises what people use buildah for with a built binary, as root and rootless:
#   hack/functional-test.sh <buildah> <registry host:port>
# Runs test/functional.bats with the bats release from hack/install-bats.sh. Needs
# network access to quay.io and github.com, a plain-HTTP registry at <registry>, sudo,
# runc or crun, netavark, jq, curl, newuidmap/newgidmap and a subordinate ID range for
# the current user.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
bats="$(mktemp -d)"
trap 'rm -rf "${bats}"' EXIT
"${repo}/hack/install-bats.sh" "${bats}"

status=0
for mode in root rootless; do
  echo "=== ${mode}" >&2
  BUILDAH="$(realpath "$1")" REGISTRY="$2" MODE="${mode}" \
    "${bats}/bin/bats" --formatter tap "${repo}/test/functional.bats" || status=1
done
exit "${status}"

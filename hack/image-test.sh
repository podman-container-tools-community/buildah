#!/usr/bin/env bash
# Builds the image for the host's platform from a built binary, laid out like goreleaser's
# dockers_v2 context, and runs test/image.bats against it:
#   hack/image-test.sh <buildah>
# Needs Docker with buildx and network access to quay.io, docker.io and github.com (bats,
# hack/install-bats.sh).
set -euo pipefail

buildah="$(realpath "$1")"
repo="$(cd "$(dirname "$0")/.." && pwd)"
image=localhost/buildah:test
platform="linux/$(docker version --format '{{.Server.Arch}}')"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/ctx/.build/packaging" "${work}/ctx/${platform}"
cp -r "${repo}/packaging/image" "${work}/ctx/.build/packaging/"
cp "${buildah}" "${work}/ctx/${platform}/buildah"
docker buildx build --quiet --load --platform "${platform}" -t "${image}" -f "${repo}/Dockerfile" "${work}/ctx" >/dev/null

"${repo}/hack/install-bats.sh" "${work}/bats"
status=0
IMAGE="${image}" "${work}/bats/bin/bats" --formatter tap "${repo}/test/image.bats" || status=1

docker image rm "${image}" >/dev/null
exit "${status}"

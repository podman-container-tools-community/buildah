#!/usr/bin/env bash
# Builds the image for the host's platform from a built binary, laid out like goreleaser's
# dockers_v2 context, and uses it as root and rootless:
#   hack/image-test.sh <buildah>
# Needs Docker with buildx and network access to quay.io, docker.io and github.com.
set -euo pipefail

buildah="$(realpath "$1")"
repo="$(cd "$(dirname "$0")/.." && pwd)"
base="${BASE_IMAGE:-quay.io/libpod/alpine:latest}"
image=localhost/buildah:test
platform="linux/$(docker version --format '{{.Server.Arch}}')"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/ctx/.build/packaging" "${work}/ctx/${platform}" "${work}/src"
cp -r "${repo}/packaging/image" "${work}/ctx/.build/packaging/"
cp "${buildah}" "${work}/ctx/${platform}/buildah"
docker buildx build --quiet --load --platform "${platform}" -t "${image}" -f "${repo}/Dockerfile" "${work}/ctx" >/dev/null

cat >"${work}/src/Containerfile" <<EOF
FROM ${base}
RUN grep '^Seccomp:' /proc/self/status > /seccomp
COPY hello /hello
EOF
echo hello >"${work}/src/hello"
chmod -R a+rX "${work}/src"

in_image() {
  echo "+ [image] $*" >&2
  docker run --rm --privileged -v "${work}/src:/src:ro" "${image}" bash -c "$@"
}

# Same checks as hack/functional-test.sh: RUN confined by seccomp, the build user in a
# user namespace with its subordinate ID ranges (three lines in uid_map).
# shellcheck disable=SC2016 # expanded by the shell in the image
check='c="$(buildah from localhost/built)" && buildah run "$c" -- cat /seccomp /hello'
in_image "buildah build --quiet -t localhost/built /src >/dev/null && ${check}" |
  diff - <(printf 'Seccomp:\t2\nhello\n')
in_image "buildah build --quiet --isolation oci -t localhost/built /src >/dev/null && ${check}" |
  diff - <(printf 'Seccomp:\t2\nhello\n')
in_image "su build -c 'buildah unshare cat /proc/self/uid_map' | awk 'END { exit NR != 3 }'"
in_image "su build -c 'buildah build --quiet -t localhost/built /src >/dev/null && ${check}'" |
  diff - <(printf 'Seccomp:\t2\nhello\n')
# Short names resolve through registries.conf.
in_image "buildah pull --quiet alpine >/dev/null"
# Build context from a Git URL, which needs git in the image. buildah 1.26 does not
# support the #ref:subdirectory syntax yet, and the repository has no Containerfile at its
# root, so it is skipped there.
version="$("${buildah}" --version | awk '{ print $3 }')"
if [[ "${version}" != 1.26.* ]]; then
  in_image "buildah build --quiet https://github.com/docker-library/hello-world.git#master:amd64 >/dev/null"
fi

docker image rm "${image}" >/dev/null
echo "image tests passed" >&2

#!/usr/bin/env bats
# Tests for the image, run on the Docker host by hack/image-test.sh. IMAGE is the image
# under test.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  local base="${BASE_IMAGE:-quay.io/libpod/alpine:latest}"
  WORK="$(mktemp -d)"
  mkdir "${WORK}/src"
  cat >"${WORK}/src/Containerfile" <<CONTAINERFILE
FROM ${base}
RUN grep '^Seccomp:' /proc/self/status > /seccomp
COPY hello /hello
CONTAINERFILE
  echo hello >"${WORK}/src/hello"
  chmod -R a+rX "${WORK}/src"
  export IMAGE WORK
}

teardown_file() {
  rm -rf "${WORK}"
}

# A shell command in a privileged container of the image, without overriding anything.
in_image() {
  docker run --rm --privileged -v "${WORK}/src:/src:ro" "${IMAGE}" sh -c "$1"
}

# Builds the test Containerfile and prints the built image's /seccomp and /hello: RUN has
# to be confined by seccomp, as in test/functional.bats.
# shellcheck disable=SC2016 # expanded by the shell in the image
check='c="$(buildah from localhost/built)" && buildah run "$c" -- cat /seccomp /hello'

@test "capabilities label as in upstream's image" {
  run -0 --separate-stderr docker image inspect "${IMAGE}" \
    --format '{{index .Config.Labels "io.containers.capabilities"}}'
  [[ "${output}" == 'CHOWN,'*',SYS_CHROOT' ]]
}

@test "buildah is the command, not the entrypoint" {
  run -0 --separate-stderr docker run --rm "${IMAGE}" buildah --version
  [[ "${output}" == 'buildah version '* ]]
}

@test "root build with chroot isolation" {
  run -0 --separate-stderr in_image "buildah build --quiet -t localhost/built /src >/dev/null && ${check}"
  expect_output $'Seccomp:\t2\nhello'
}

@test "root build with oci isolation" {
  run -0 --separate-stderr in_image "buildah build --quiet --isolation oci -t localhost/built /src >/dev/null && ${check}"
  expect_output $'Seccomp:\t2\nhello'
}

@test "rootless: user namespace with the subordinate ID ranges" {
  run -0 --separate-stderr in_image "su build -c 'buildah unshare cat /proc/self/uid_map'"
  [[ "${#lines[@]}" -eq 3 ]]
}

@test "rootless build" {
  run -0 --separate-stderr in_image "su build -c 'buildah build --quiet -t localhost/built /src >/dev/null && ${check}'"
  expect_output $'Seccomp:\t2\nhello'
}

@test "storage.conf: overlay with the additional image store, as root and rootless" {
  run -0 --separate-stderr in_image "buildah info --format '{{.store.GraphDriverName}} {{.store.GraphRoot}}'"
  expect_output "overlay /var/lib/containers/storage"
  run -0 --separate-stderr in_image "su build -c \"buildah info --format '{{.store.GraphDriverName}} {{.store.GraphRoot}}'\""
  expect_output "overlay /home/build/.local/share/containers/storage"
  run -0 in_image "test -f /var/lib/shared/overlay-images/images.lock && grep -q /var/lib/shared /etc/containers/storage.conf"
}

@test "short names resolve through registries.conf" {
  run -0 --separate-stderr in_image "buildah pull --quiet alpine"
}

# Needs git in the image. The repository has no Containerfile at its root.
@test "build context from a Git URL" {
  run -0 --separate-stderr docker run --rm "${IMAGE}" buildah --version
  [[ "${output}" != *" 1.26."* ]] || skip "buildah 1.26 does not support #ref:subdirectory"
  run -0 --separate-stderr in_image "buildah build --quiet https://github.com/docker-library/hello-world.git#master:amd64"
}

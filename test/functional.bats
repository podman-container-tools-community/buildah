#!/usr/bin/env bats
# What people use buildah for, with a built binary. hack/functional-test.sh runs them as
# root and rootless: BUILDAH is the binary, REGISTRY a plain-HTTP registry (host:port),
# MODE root or rootless. Tests run in file order and share the storage.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  : "${BUILDAH:?}" "${REGISTRY:?}" "${MODE:?}"
  BASE_IMAGE="${BASE_IMAGE:-quay.io/libpod/alpine:latest}"
  WORK="$(mktemp -d)"
  chmod 0755 "${WORK}"
  mkdir "${WORK}/context"
  cat >"${WORK}/context/Containerfile" <<CONTAINERFILE
FROM ${BASE_IMAGE}
RUN grep '^Seccomp:' /proc/self/status > /seccomp
COPY hello /hello
CONTAINERFILE
  echo hello >"${WORK}/context/hello"
  # No RUN, so it builds for every platform without emulation.
  cat >"${WORK}/context/Containerfile.multiarch" <<CONTAINERFILE
FROM ${BASE_IMAGE}
COPY hello /hello
CONTAINERFILE
  export BASE_IMAGE WORK
}

teardown_file() {
  buildah rm --all >/dev/null || true
  buildah rmi --all --force >/dev/null || true
  # overlay leaves its mounts behind.
  sudo umount -R "${WORK}/root/overlay" 2>/dev/null || true
  sudo rm -rf "${WORK}"
}

# buildah with storage of its own, through sudo for root.
buildah() {
  local storage=(--root "${WORK}/root" --runroot "${WORK}/run" --storage-driver overlay)
  if [[ "${MODE}" == root ]]; then
    sudo "${BUILDAH}" "${storage[@]}" "$@"
  else
    "${BUILDAH}" "${storage[@]}" "$@"
  fi
}

@test "version" {
  run -0 --separate-stderr buildah version
}

# RUN has to be confined by seccomp with every isolation (mode 2 is filter). Without cgo,
# buildah silently runs it unconfined.
@test "RUN is confined by seccomp with chroot and oci isolation" {
  run -0 --separate-stderr buildah from --pull=always "${BASE_IMAGE}"
  local ctr="${output}" isolation
  for isolation in chroot oci; do
    run -0 --separate-stderr buildah run --isolation "${isolation}" --network host "${ctr}" -- grep '^Seccomp:' /proc/self/status
    expect_output $'Seccomp:\t2'
  done
  buildah rm "${ctr}"
}

@test "storage driver is overlay" {
  run -0 --separate-stderr buildah info
  jq -e '.store.GraphDriverName == "overlay"' <<<"${output}"
}

@test "working container runs as root, configured and committed" {
  run -0 --separate-stderr buildah from "${BASE_IMAGE}"
  local ctr="${output}"
  run -0 --separate-stderr buildah run --isolation chroot "${ctr}" -- id -u
  expect_output 0
  buildah config --env FOO=bar "${ctr}"
  buildah commit --quiet "${ctr}" localhost/committed
  buildah rm "${ctr}"
  run -0 --separate-stderr buildah inspect --type image localhost/committed
  jq -e '.OCIv1.config.Env | index("FOO=bar")' <<<"${output}"
}

@test "build with chroot and oci isolation" {
  local isolation ctr
  for isolation in chroot oci; do
    buildah build --quiet --isolation "${isolation}" --network host -t "localhost/built:${isolation}" "${WORK}/context"
    run -0 --separate-stderr buildah from "localhost/built:${isolation}"
    ctr="${output}"
    run -0 --separate-stderr buildah run --isolation chroot "${ctr}" -- cat /seccomp /hello
    expect_output $'Seccomp:\t2\nhello'
    buildah rm "${ctr}"
  done
}

@test "push to a registry and pull back" {
  local tag="${REGISTRY}/test-${MODE}:built"
  buildah push --tls-verify=false localhost/built:chroot "docker://${tag}"
  buildah rmi localhost/built:chroot
  buildah pull --quiet --tls-verify=false "docker://${tag}"
}

@test "multi-platform build into a manifest list, pushed with every image" {
  local tag="${REGISTRY}/test-${MODE}"
  buildah build --quiet --platform linux/amd64,linux/arm64 --manifest localhost/multiarch \
    -f "${WORK}/context/Containerfile.multiarch" "${WORK}/context"
  buildah manifest push --all --tls-verify=false localhost/multiarch "docker://${tag}:multiarch"
  run -0 curl -fsS -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "http://${REGISTRY}/v2/test-${MODE}/manifests/multiarch"
  jq -e '[.manifests[].platform.architecture] | sort == ["amd64", "arm64"]' <<<"${output}"
}

@test "rootless: user namespace with the subordinate ID range" {
  [[ "${MODE}" == rootless ]] || skip "root"
  run -0 --separate-stderr buildah unshare cat /proc/self/uid_map
  [[ "${#lines[@]}" -eq 2 ]]
}

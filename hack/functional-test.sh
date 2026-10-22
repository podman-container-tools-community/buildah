#!/usr/bin/env bash
# Exercises what people use buildah for with a built binary, as root and rootless:
#   hack/functional-test.sh <buildah> <registry host:port>
# Needs network access to quay.io, a plain-HTTP registry at <registry>, sudo, runc or
# crun, netavark, newuidmap/newgidmap and a subordinate ID range for the current user.
set -euo pipefail

buildah="$(realpath "$1")"
registry="$2"
base="${BASE_IMAGE:-quay.io/libpod/alpine:latest}"
work="$(mktemp -d)"
chmod 0755 "${work}"
mkdir "${work}/context"
cat >"${work}/context/Containerfile" <<EOF
FROM ${base}
RUN grep '^Seccomp:' /proc/self/status > /seccomp
COPY hello /hello
EOF
echo hello >"${work}/context/hello"
# No RUN, so it builds for every platform without emulation.
cat >"${work}/context/Containerfile.multiarch" <<EOF
FROM ${base}
COPY hello /hello
EOF

# mode is root or rootless; each gets its own storage.
mode=
run() {
  local storage=(--root "${work}/${mode}/root" --runroot "${work}/${mode}/run" --storage-driver overlay)
  echo "+ [${mode}] buildah $*" >&2
  if [[ "${mode}" == root ]]; then
    sudo "${buildah}" "${storage[@]}" "$@"
  else
    "${buildah}" "${storage[@]}" "$@"
  fi
}

# RUN has to be confined by seccomp with every isolation (mode 2 is filter). Without
# cgo, buildah silently runs it unconfined.
check_seccomp() {
  grep -qx $'Seccomp:\t2'
}

suite() {
  mode="$1"
  local tag="${registry}/test-${mode}"
  local ctr isolation

  run version
  run info | jq -e '.store.GraphDriverName == "overlay"' >/dev/null

  # Working containers, RUN with both isolations.
  ctr="$(run from --pull=always "${base}")"
  for isolation in chroot oci; do
    run run --isolation "${isolation}" --network host "${ctr}" -- grep '^Seccomp:' /proc/self/status | check_seccomp
  done
  run run --isolation chroot "${ctr}" -- id -u | grep -qx 0
  run config --env FOO=bar "${ctr}"
  run commit --quiet "${ctr}" "localhost/committed:${mode}" >/dev/null
  run rm "${ctr}"

  # Containerfile builds, pushed to a registry and pulled back.
  for isolation in chroot oci; do
    run build --quiet --isolation "${isolation}" --network host -t "localhost/built:${isolation}" "${work}/context" >/dev/null
    ctr="$(run from "localhost/built:${isolation}")"
    run run --isolation chroot "${ctr}" -- cat /seccomp | check_seccomp
    run run --isolation chroot "${ctr}" -- cat /hello | grep -qx hello
    run rm "${ctr}"
  done
  run push --tls-verify=false "localhost/built:chroot" "docker://${tag}:built"
  run rmi "localhost/built:chroot" >/dev/null
  run pull --quiet --tls-verify=false "docker://${tag}:built" >/dev/null

  # Multi-platform build into a manifest list, pushed with every image.
  run build --quiet --platform linux/amd64,linux/arm64 --manifest "localhost/multiarch:${mode}" \
    -f "${work}/context/Containerfile.multiarch" "${work}/context" >/dev/null
  run manifest push --all --tls-verify=false "localhost/multiarch:${mode}" "docker://${tag}:multiarch"
  curl -fsS -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' "http://${tag/\//\/v2\/}/manifests/multiarch" |
    jq -e '[.manifests[].platform.architecture] | sort == ["amd64", "arm64"]' >/dev/null

  # Rootless: a user namespace with the subordinate ID range as the second mapping.
  if [[ "${mode}" == rootless ]]; then
    run unshare cat /proc/self/uid_map | awk 'END { exit NR != 2 }'
  fi

  run rm --all >/dev/null
  run rmi --all --force >/dev/null
}

suite root
suite rootless

# overlay leaves its mounts behind.
sudo umount -R "${work}/root/root/overlay" "${work}/rootless/root/overlay" 2>/dev/null || true
sudo rm -rf "${work}"
echo "functional tests passed" >&2

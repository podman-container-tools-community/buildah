#!/usr/bin/env bats
# Signing and signature verification with a built binary; hack/functional-test.sh runs it
# after functional.bats, as root and rootless, with BUILDAH, REGISTRY and MODE set the
# same way. Releases are built with containers_image_openpgp: GPG signatures verify, but
# signing with GPG (--sign-by) is not supported. buildah push has no sigstore signing.
# The cases run in order and later ones use what earlier ones pushed.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  : "${BUILDAH:?}" "${REGISTRY:?}" "${MODE:?}"
  WORK="$(mktemp -d)"
  chmod 0755 "${WORK}"
  export WORK
  export GPG_REPO="${REGISTRY}/signed-${MODE}/gpg"

  # The image to sign: built from scratch, so nothing is pulled.
  local ctr
  ctr="$(buildah from scratch)"
  buildah config --label signing=test "${ctr}"
  buildah commit --quiet "${ctr}" localhost/signing >/dev/null
  buildah rm "${ctr}" >/dev/null

  # registries.d with a lookaside directory for the repository.
  mkdir "${WORK}/registries.d" "${WORK}/lookaside"
  cat >"${WORK}/registries.d/test.yaml" <<EOF
docker:
  ${GPG_REPO}:
    lookaside: file://${WORK}/lookaside
EOF

  # A GPG key for simple signing, and a second one nothing is signed with.
  local name
  for name in signer other; do
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --quick-gen-key "${name} <${name}@example.com>" rsa2048 sign never
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --export >"${WORK}/${name}.gpg"
  done
}

teardown_file() {
  local name
  for name in signer other; do
    gpgconf --homedir "${WORK}/gnupg-${name}" --kill gpg-agent 2>/dev/null || true
  done
  buildah rm --all >/dev/null || true
  buildah rmi --all --force >/dev/null || true
  # overlay leaves its mounts behind.
  sudo umount -R "${WORK}/root/overlay" 2>/dev/null || true
  sudo rm -rf "${WORK}"
}

# gpg without prompts, in the home directory GNUPGHOME names.
gpg_quiet() {
  [[ -d "${GNUPGHOME}" ]] || mkdir -m 0700 "${GNUPGHOME}"
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' "$@"
}

# buildah with storage and registries.d of its own, through sudo for root.
buildah() {
  local global=(--root "${WORK}/root" --runroot "${WORK}/run" --storage-driver overlay
    --registries-conf-dir "${WORK}/registries.d")
  if [[ "${MODE}" == root ]]; then
    sudo "${BUILDAH}" "${global[@]}" "$@"
  else
    "${BUILDAH}" "${global[@]}" "$@"
  fi
}

# write_policy <file> <repository> <requirement JSON>: rejects everything but <repository>.
write_policy() {
  jq -n --arg repo "$2" --argjson req "$3" \
    '{default: [{type: "reject"}], transports: {docker: {($repo): [$req]}}}' >"$1"
}

@test "gpg: signing with --sign-by fails with a clear error" {
  GNUPGHOME="${WORK}/gnupg-signer" run -125 buildah push --tls-verify=false --sign-by signer@example.com \
    localhost/signing "docker://${GPG_REPO}:sign-by"
  [[ "${output}" == *"signing is not supported"*"containers_image_openpgp"* ]]
}

# The signature is made with gpg, as by a signer outside this build, and stored where the
# lookaside configuration in registries.d points.
@test "gpg: policy accepts an image signed by gpg in a lookaside" {
  buildah push --quiet --tls-verify=false --digestfile "${WORK}/gpg.digest" localhost/signing "docker://${GPG_REPO}:latest"
  local digest
  digest="$(cat "${WORK}/gpg.digest")"
  local sigdir="${WORK}/lookaside/${GPG_REPO#*/}@${digest/:/=}"
  mkdir -p "${sigdir}"
  jq -nc --arg ref "${GPG_REPO}:latest" --arg digest "${digest}" \
    '{critical: {identity: {"docker-reference": $ref}, image: {"docker-manifest-digest": $digest},
      type: "atomic container signature"}, optional: {}}' |
    GNUPGHOME="${WORK}/gnupg-signer" gpg_quiet --sign --output "${sigdir}/signature-1"

  write_policy "${WORK}/gpg-policy.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/signer.gpg\"}"
  buildah pull --quiet --tls-verify=false --signature-policy "${WORK}/gpg-policy.json" "docker://${GPG_REPO}:latest"
  # Pulling an image that is already there can skip the copy and its policy check.
  buildah rmi "${GPG_REPO}:latest"
}

@test "gpg: policy rejects the image for another key" {
  write_policy "${WORK}/gpg-other.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/other.gpg\"}"
  run -125 buildah pull --quiet --tls-verify=false --signature-policy "${WORK}/gpg-other.json" "docker://${GPG_REPO}:latest"
  [[ "${output}" == *"Source image rejected"* ]]
}

@test "gpg: from verifies the signature too" {
  run -0 --separate-stderr buildah from --pull=always --tls-verify=false \
    --signature-policy "${WORK}/gpg-policy.json" "docker://${GPG_REPO}:latest"
  buildah rm "${output}"
  run -125 buildah from --pull=always --tls-verify=false \
    --signature-policy "${WORK}/gpg-other.json" "docker://${GPG_REPO}:latest"
  [[ "${output}" == *"Source image rejected"* ]]
}

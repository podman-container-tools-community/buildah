#!/usr/bin/env bash
# Builds a static musl libseccomp for every target with zig cc:
#   hack/build-libseccomp.sh <libseccomp tarball> <sysroot>
# installs into <sysroot>/<arch>, e.g. <sysroot>/aarch64/lib/libseccomp.a.
# Needs zig and gperf.
set -euo pipefail

tarball="$(realpath "$1")"
sysroot="$(realpath -m "$2")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

for arch in x86_64 aarch64; do
  target="${arch}-linux-musl"
  mkdir "${work}/${arch}"
  tar -xzf "${tarball}" -C "${work}/${arch}" --strip-components=1
  (
    cd "${work}/${arch}"
    ./configure --quiet --host="${target}" --prefix="${sysroot}/${arch}" \
      CC="zig cc -target ${target}" AR="zig ar" RANLIB="zig ranlib" \
      --enable-static --disable-shared
    make --silent -j"$(nproc)" >/dev/null
    make --silent install >/dev/null
  )
done

#!/usr/bin/env bash
# Builds the C sysroot for the static build with zig cc:
#   hack/build-sysroot.sh <sysroot>
# A static musl libseccomp for both architectures, installed to <sysroot>/<arch>/{include,lib}
# (libseccomp-golang finds it through PKG_CONFIG_LIBDIR, set in .goreleaser.yaml), and
# hack/musl-compat.h, which .goreleaser.yaml includes for the releases that need it.
# Needs zig, gperf and curl. Renovate bumps the libseccomp version and the tarball's
# sha256 together; the version keeps the tag's v, which its digest lookup needs.
set -euo pipefail

# renovate: datasource=github-release-attachments depName=seccomp/libseccomp
LIBSECCOMP_VERSION=v2.6.1
LIBSECCOMP_SHA256=501f66c667225d53791b97e1d7cf85ab764c297d04881f60f38f451c4b0ee1be

sysroot="$(realpath -m "$1")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${sysroot}"
cp "$(dirname "$0")/musl-compat.h" "${sysroot}/"

command -v gperf >/dev/null || sudo apt-get install -y --no-install-recommends gperf
tarball="${work}/libseccomp-${LIBSECCOMP_VERSION#v}.tar.gz"
curl -fsSLo "${tarball}" \
  "https://github.com/seccomp/libseccomp/releases/download/${LIBSECCOMP_VERSION}/libseccomp-${LIBSECCOMP_VERSION#v}.tar.gz"
sha256sum --check --strict <<<"${LIBSECCOMP_SHA256}  ${tarball}"
mkdir "${work}/src"
tar -xzf "${tarball}" -C "${work}/src" --strip-components=1
for arch in x86_64 aarch64; do
  mkdir "${work}/${arch}"
  (
    cd "${work}/${arch}"
    "${work}/src/configure" --quiet --host="${arch}-linux-musl" --prefix="${sysroot}/${arch}" \
      --enable-static --disable-shared \
      CC="zig cc -target ${arch}-linux-musl" AR="zig ar" RANLIB="zig ranlib"
    make --silent -j"$(nproc)" >/dev/null
    make --silent install >/dev/null
  )
done

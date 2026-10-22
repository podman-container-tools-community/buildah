[![CI](https://github.com/podman-container-tools-community/buildah/actions/workflows/ci.yaml/badge.svg)](https://github.com/podman-container-tools-community/buildah/actions/workflows/ci.yaml)
[![Release](https://github.com/podman-container-tools-community/buildah/actions/workflows/release.yaml/badge.svg)](https://github.com/podman-container-tools-community/buildah/actions/workflows/release.yaml)
[![GitHub license](https://img.shields.io/github/license/podman-container-tools-community/buildah)](https://github.com/podman-container-tools-community/buildah/blob/main/LICENSE)
[![Current Release](https://img.shields.io/github/release/podman-container-tools-community/buildah.svg?logo=github)](https://github.com/podman-container-tools-community/buildah/releases/latest)
[![GitHub Repo stars](https://img.shields.io/github/stars/podman-container-tools-community/buildah?style=flat&logo=github)](https://github.com/podman-container-tools-community/buildah/stargazers)
[![GitHub all releases](https://img.shields.io/github/downloads/podman-container-tools-community/buildah/total?logo=github)](https://github.com/podman-container-tools-community/buildah/releases/latest)
[![ghcr.io Pulls](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fpodman-container-tools-community%2Fbuildah%2Fbuildah.json&query=%24.downloads&logo=github&label=ghcr.io%20pulls)](https://github.com/podman-container-tools-community/buildah/pkgs/container/buildah)

# buildah (community build)

⭐ Don't forget to star this repository! ⭐

Community-maintained, static binaries and container images of
[buildah](https://github.com/podman-container-tools/buildah), part of
[podman-container-tools](https://github.com/podman-container-tools).
**These are not official releases.** They are built from unmodified upstream source
and are not supported by the upstream maintainers.

## Why this exists

Upstream does not publish distribution-independent binaries, and its images are based
on Fedora packages, so they can lag behind upstream releases
([podman-container-tools/buildah#6902](https://github.com/podman-container-tools/buildah/issues/6902)).
Distribution packages are often several releases behind, and some environments (CI
runners, minimal or non-Linux-distribution hosts) have no package at all. This project
fills that gap with:

- static binaries for `linux/amd64` and `linux/arm64` (more on request),
- `.deb` and `.rpm` packages of the same binaries that replace the distribution's
  `buildah` package,
- a multi-arch image based on Alpine, with a shell, Git and rootless support,
- every maintained upstream minor version (1.26 and newer), not only the newest one.

## Install

### apt (Debian, Ubuntu)

The apt repository follows upstream's latest release. It needs apt 2.3.10 or newer
(Debian 12, Ubuntu 22.04 and later) for the inline key in the sources file:

```sh
curl -fsSL https://raw.githubusercontent.com/podman-container-tools-community/buildah/main/packaging/apt/buildah.sources |
  sudo tee /etc/apt/sources.list.d/buildah.sources
sudo apt update
sudo apt install buildah
```

To stay on one release, replace `releases/latest/download` in the URI with
`releases/download/vX.Y.Z`.

The packages use epoch 3, so they stay installed when the distribution ships its own
buildah update. To go back to the distribution's package, remove the source and run
`sudo apt install --allow-downgrades buildah=<version>`.

The package recommends `netavark` (see [Limitations](#limitations)), an OCI runtime
(`crun` or `runc`), `uidmap` and the distribution's package with `/etc/containers`.
Ubuntu 22.04 has no netavark package.

### rpm (Fedora, RHEL, openSUSE)

There is no dnf repository. Download the package from the release, check its signature
(`dnf install` does not check local files) and install it:

```sh
sudo rpm --import https://raw.githubusercontent.com/podman-container-tools-community/buildah/main/packaging/gpg.asc
rpm -K buildah-1.46.0-1.x86_64.rpm
sudo dnf install ./buildah-1.46.0-1.x86_64.rpm
```

`rpm -K` has to report `signatures OK`. The packages use epoch 3 (Fedora's buildah uses
2), so `dnf upgrade` does not switch back to the distribution's buildah. Upstream's
own COPR builds use epoch 102 and win over these packages.

The deb and rpm packages and the apt repository are signed with the GPG key in
[`packaging/gpg.asc`](packaging/gpg.asc)
(`59E1 335F 8162 F5DF FE1D  4DA9 7243 E2C2 DA62 80BC`).

### Image

```sh
docker run --rm --privileged -v "$PWD:/src" ghcr.io/podman-container-tools-community/buildah:latest \
  buildah build -t registry.example.com/app:latest /src
```

The image runs buildah like upstream's image does: chroot isolation
(`BUILDAH_ISOLATION=chroot`) with the container's network and namespaces
([`packaging/image/containers.conf`](packaging/image/containers.conf)), and
`/var/lib/containers` and `/var/tmp` as volumes, because overlay cannot be stacked on
the container's own overlay. It contains containers-common's default `policy.json` (accept
everything), and its `registries.conf` resolves short names such as `alpine` on Docker Hub.
Like upstream's image, it has no entrypoint, so commands start with `buildah`.

The image is Alpine with the static binary, `bash`, `curl`, `tzdata`, `git` (build
contexts from Git URLs), `newuidmap`/`newgidmap`, `fuse-overlayfs` and Alpine's
`netavark` and `crun`. With `-e BUILDAH_ISOLATION=oci`, a privileged container can use
OCI isolation with host networking, the image's default; private networks need a newer
netavark than Alpine's with recent buildah releases. Alpine's own buildah and
containers-common packages are not installed (`apk add buildah` would replace the
static binary); `apk add` other tools as needed. For rootless builds, run as the `build`
user (UID 1000, subordinate IDs 1-999 and 1001-65535 like upstream's image, storage in
the `/home/build/.local/share/containers` volume):

```sh
docker run --rm --privileged --user build -v "$PWD:/src" \
  ghcr.io/podman-container-tools-community/buildah:latest buildah build -t registry.example.com/app:latest /src
```

## Trust model

This repository contains **only build configuration**. Nothing here can change what is
compiled from Go:

- Source comes from the Go module proxy (`proxy.golang.org`) at the upstream tag and is
  verified against the Go checksum database (`sum.golang.org`), using
  [goreleaser verifiable builds](https://goreleaser.com/customization/builds/verifiable_builds/).
  Dependencies and their hashes are upstream's own `go.sum`.
- Exception: releases whose `go.mod` has `replace` directives (1.26.0 to 1.26.9, 1.27.0
  to 1.27.6, 1.28, 1.29.0 to 1.29.5, 1.30 and 1.35 to 1.37) cannot be built from the
  module proxy, which ignores those directives. They are built from the upstream Git
  checkout at the release tag and its `vendor/` directory, unmodified; the binary
  records the upstream commit (`vcs.revision`) instead of a module hash.
- The C parts (cgo in buildah and its dependencies, musl, libseccomp) are compiled with
  [zig](https://ziglang.org) at a pinned version. libseccomp comes from its upstream
  release tarball, pinned by version and sha256 in
  [`.github/actions/setup`](.github/actions/setup/action.yaml).
- Builds run only in GitHub Actions. Binaries and checksums are signed keyless with
  [cosign](https://github.com/sigstore/cosign) via GitHub OIDC, images are signed the
  same way, and every file in `checksums.txt` gets a GitHub build provenance
  attestation.
- The apt repository metadata (`InRelease`) and the rpm packages are additionally signed
  with a GPG key, because apt and rpm cannot verify sigstore signatures; apt verifies
  the deb packages through the checksums in the signed `InRelease`. The key is kept in
  this repository's secrets and used only by the release workflow.
- Builds are reproducible: with the same Go, zig and libseccomp versions, anyone gets
  bit-for-bit identical binaries.

## Which versions are released

Every upstream [GitHub release](https://github.com/podman-container-tools/buildah/releases)
since `v1.26.0`, drafts and prereleases excluded
([`hack/upstream-releases.sh`](hack/upstream-releases.sh)). Upstream maintains several
minor versions at once (1.26, 1.29, 1.33, 1.37, 1.39 and 1.41 all had patch releases in
2026), so there is no version list to maintain here.

## Release flow

1. [`sync.yaml`](.github/workflows/sync.yaml) runs every 6 hours, on every push to `main`
   and on demand. For every upstream release that has no tag here yet, it creates the tag
   on the current commit and dispatches [`release.yaml`](.github/workflows/release.yaml)
   on it. It only runs once the repository variable `RELEASES_ENABLED` is `true`.
2. `release.yaml` builds that tag: GitHub release, images on `ghcr.io`, signatures and
   attestations. Image tags: `vX.Y.Z` always, `vX.Y` for the newest release of a minor,
   `vX` and `latest` for upstream's latest release.
3. Before anything is published, [`test.yaml`](.github/workflows/test.yaml) builds the
   release and runs the [bats](https://github.com/bats-core/bats-core) tests in
   [`test/functional.bats`](test/functional.bats) through
   [`hack/functional-test.sh`](hack/functional-test.sh) on amd64 and arm64 runners, as
   root and rootless: `from`, `run` and `build` with chroot and OCI
   isolation (checking that seccomp confines `RUN`), overlay storage, `commit`, `push`,
   `pull`, a multi-platform `build --manifest` with `manifest push --all`, and
   `unshare`. [`hack/image-test.sh`](hack/image-test.sh) builds the image from the same
   binary and runs [`test/image.bats`](test/image.bats): `build` in it as root and as
   the rootless `build` user, from a Git URL and with a short image name. Both install
   the pinned bats release with [`hack/install-bats.sh`](hack/install-bats.sh). Upstream's own integration tests are not run, because they need upstream's
   CI VMs and, for older releases, registry content that changed since.
4. [`ci.yaml`](.github/workflows/ci.yaml) runs `test.yaml` for the newest release of every
   minor version on pull requests.

A release can also be started by hand for an existing tag:

```sh
gh workflow run release.yaml --ref v1.46.0
```

## How it works

- The workflows check out upstream buildah at the release tag into the workspace root
  and this repository into `.build/`. [`.github/actions/setup`](.github/actions/setup/action.yaml)
  hides `.build/` from Git (`.git/info/exclude`), so goreleaser sees a clean upstream
  checkout and takes module path, `go.sum`, tag and completions from it. The goreleaser
  configuration and `Dockerfile` are used from `.build/`.
- goreleaser's `gomod.proxy` then compiles `<module>/cmd/buildah@<tag>` from the Go
  module proxy, verified against sum.golang.org, rather than from the checkout. The
  module path changed from `github.com/containers/buildah` to `go.podman.io/buildah` in
  1.44; both work.
- buildah needs cgo: rootless re-execution into a user namespace, chroot isolation and
  seccomp are C code. A `CGO_ENABLED=0` build compiles, but rootless commands re-execute
  themselves endlessly and `RUN` steps run without seccomp. So both architectures are
  cross-compiled on one amd64 runner with `zig cc` for musl and linked statically
  (`-linkmode external -extldflags '-static -s'`) against a static libseccomp that
  [`hack/build-libseccomp.sh`](hack/build-libseccomp.sh) builds with zig, too.
- Dependencies use what musl 1.2.4 removed: go-sqlite3 the `*64` functions
  (`-D_LARGEFILE64_SOURCE`), and containers/storage before buildah 1.36 `basename()`
  without including `libgen.h`, so for releases before 1.36
  [`hack/musl-compat.h`](hack/musl-compat.h) is included into every C file.
- Every release is built with the newest stable Go, not the version in upstream's
  `go.mod`. Exceptions for releases whose pinned dependencies break with the newest Go
  are listed in [`.github/actions/setup`](.github/actions/setup/action.yaml): 1.44.x
  uses Go 1.26. The Go version used is recorded in each binary (`go version -m`).
- Build tags follow upstream's Makefile for what works in a static binary: `seccomp`,
  `apparmor`, `containers_image_openpgp` (pure-Go OpenPGP instead of gpgme),
  `exclude_graphdriver_btrfs` and `exclude_graphdriver_devicemapper` (needed for older
  releases).
- The upstream commit and build time are passed with `-X main.GitCommit` and
  `-X main.buildInfo`, as upstream's Makefile does, so `buildah version` shows them.
- The release is signed keyless with cosign through GitHub OIDC: the checksum file
  (`checksums.txt.sigstore.json`) and the images. A GitHub build provenance
  attestation is created for every file in `checksums.txt`.

## Verify a binary

Download the binary (or archive, or package), `checksums.txt` and `checksums.txt.sigstore.json` from
the release. The examples use buildah `v1.46.0`.

1. **Signature of the checksums**, proving the file came from this repository's workflow:

   ```sh
   cosign verify-blob \
     --certificate-identity-regexp '^https://github.com/podman-container-tools-community/buildah/\.github/workflows/release\.yaml@' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     --bundle checksums.txt.sigstore.json \
     checksums.txt
   ```

2. **Checksum of the binary**:

   ```sh
   sha256sum --check --ignore-missing checksums.txt
   ```

3. **Build provenance** (optional, needs the GitHub CLI):

   ```sh
   gh attestation verify buildah-linux-amd64 --repo podman-container-tools-community/buildah
   ```

4. **Source**: the module hash embedded in the binary must match the Go checksum database,
   which proves the Go code came from the upstream tag:

   ```sh
   go version -m buildah-linux-amd64 | grep -P '^\tmod'
   # mod  go.podman.io/buildah  v1.46.0  h1:+xBsV2cccaVTi0CY1c/D8nVe5LCWv1xtBOKoIDoq5o4=
   curl -s https://sum.golang.org/lookup/go.podman.io/buildah@v1.46.0
   # go.podman.io/buildah v1.46.0 h1:+xBsV2cccaVTi0CY1c/D8nVe5LCWv1xtBOKoIDoq5o4=
   ```

   Before 1.44 the module path is `github.com/containers/buildah`. For releases built
   from the checkout (see [Trust model](#trust-model)), compare `vcs.revision` with the
   upstream tag instead:

   ```sh
   go version -m buildah-linux-amd64 | grep vcs.revision
   git ls-remote https://github.com/podman-container-tools/buildah 'refs/tags/v1.37.8^{}'
   ```

### Verify an image

```sh
cosign verify ghcr.io/podman-container-tools-community/buildah:v1.46.0 \
  --certificate-identity-regexp '^https://github.com/podman-container-tools-community/buildah/\.github/workflows/release\.yaml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Reproduce a build

See [Reproduce locally](#reproduce-locally). Use the Go version shown by `go version -m`
on the released binary, and the zig and libseccomp versions from
[`.github/actions/setup`](.github/actions/setup/action.yaml) at the release tag.

## Limitations

The binaries are static and linked against musl. Compared to a distribution package,
this means:

- **netavark is needed.** Recent buildah releases refuse to create any container
  without a `netavark` binary in the helper directories, even with `--network host`.
  The packages recommend the distribution's netavark, and the image contains Alpine's.
- **No GPG signing.** `buildah push --sign-by <fingerprint>` and `buildah commit
  --sign-by` fail. Verifying GPG signatures through `policy.json` (`signedBy` with
  `keyPath`) works. Sigstore signing and verification work fully.
- **No Sequoia-PGP** signature backend.
- **No btrfs storage driver.** overlay and vfs work.
- **No libsubid.** Rootless user namespaces still work: `/etc/subuid` and `/etc/subgid`
  are read directly and `newuidmap`/`newgidmap` are used. Subordinate ID ranges served
  by NSS providers (sssd, FreeIPA) are not supported; libsubid loads those with
  `dlopen`, which is impossible in a static binary.
- **No NSS.** User lookups read `/etc/passwd` and `/etc/group` only, and name
  resolution uses musl's resolver (`/etc/hosts` and DNS): no LDAP users, mDNS
  (`.local`) or systemd-resolved specific behaviour.
- **No journald.** Built without the `systemd` tag.
- **No default configuration.** The binary does not install `/etc/containers`. The
  packages recommend the distribution's package that owns it
  (`golang-github-containers-common` on Debian and Ubuntu, `containers-common` on rpm
  distributions); the image ships `policy.json`, `containers.conf` and `registries.conf`.
- **Linux only**, `amd64` and `arm64`. The arm64 binary is cross-compiled and tested on
  arm64 runners.

## Reproduce locally

Needs Go, [zig](https://ziglang.org/download/), gperf, pkg-config and goreleaser.

```sh
git clone --branch v1.46.0 https://github.com/podman-container-tools/buildah
cd buildah
git clone https://github.com/podman-container-tools-community/buildah .build
printf '/.build/\n/dist/\n' >> .git/info/exclude
curl -fsSLo /tmp/libseccomp-2.6.0.tar.gz https://github.com/seccomp/libseccomp/releases/download/v2.6.0/libseccomp-2.6.0.tar.gz
.build/hack/build-libseccomp.sh /tmp/libseccomp-2.6.0.tar.gz /tmp/sysroot
cp .build/hack/musl-compat.h /tmp/sysroot/
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/buildah \
GITHUB_REPOSITORY_NAME=buildah IS_LATEST=false IS_LATEST_MINOR=false SYSROOT=/tmp/sysroot GOTOOLCHAIN=local \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,docker,sbom
```

For releases with `replace` directives in `go.mod`, use a copy of the configuration
with `proxy: false`, as [`.github/actions/setup`](.github/actions/setup/action.yaml)
does. With the same Go, zig and libseccomp versions, the binaries are bit-for-bit
identical.

## Layout

This repository is checked out to `.build/` inside an upstream checkout.

```
.goreleaser.yaml                     build, archive, package, image and signing configuration
Dockerfile                           image (its RUN steps run on the build platform, no emulation)
hack/upstream-releases.sh            upstream releases to build
hack/build-libseccomp.sh             static musl libseccomp for both architectures
hack/musl-compat.h                   declares basename() for releases before 1.36
hack/install-bats.sh                 pinned bats-core release for the tests
hack/update-checksums.sh             recompute the bats-core sha256 pin after a version bump
hack/functional-test.sh              runs test/functional.bats as root and rootless
hack/image-test.sh                   builds the image and runs test/image.bats
test/                                bats tests for the binary and the image
.github/actions/setup/               hide .build/ from Git, install Go, zig, libseccomp, syft, goreleaser
.github/workflows/test.yaml          build one release, run functional and image tests on amd64 and arm64
.github/workflows/ci.yaml            pull requests: test.yaml for newest release per minor
.github/workflows/sync.yaml          schedule and main: tag new releases, dispatch release.yaml
.github/workflows/release.yaml       dispatch on a tag: test.yaml, then release, images, signing
.github/workflows/renovate.yaml      Renovate pull requests: commit the recomputed bats-core sha256
packaging/gpg.asc                    public GPG key for packages and the apt repository
packaging/apt/buildah.sources        apt source for the latest release
packaging/image/                     policy.json, containers.conf and registries.conf for the image
renovate.json                        base image, action and libseccomp updates
```

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

The apt repository follows the newest upstream release. It needs apt 2.3.10 or newer
(Debian 12, Ubuntu 22.04 and later) for the inline key in the sources file:

```sh
curl -fsSL https://raw.githubusercontent.com/podman-container-tools-community/buildah/main/packaging/apt/buildah.sources |
  sudo tee /etc/apt/sources.list.d/buildah.sources
sudo apt update
sudo apt install buildah
```

The repository only serves the newest release: after a new upstream release, the `.deb`
URLs in an older cached index are gone (404), so run `sudo apt update` before
`apt install` or `apt upgrade`. To stay on one release, replace
`releases/latest/download` in the URI with `releases/download/vX.Y.Z`.

The packages use epoch 3, so they stay installed when the distribution ships its own
buildah update. To go back to the distribution's package, remove the source and run
`sudo apt install --allow-downgrades buildah=<version>`.

The package depends on the distribution's package with `/etc/containers`
(`golang-github-containers-common` or `containers-common`), because buildah refuses to
pull without its `policy.json`. It recommends `netavark` (see
[Limitations](#limitations)), an OCI runtime (`crun` or `runc`), `uidmap` and
`fuse-overlayfs`. Ubuntu 22.04 has no netavark package, so buildah 1.44 and newer cannot
create containers there.

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

The image is Alpine with the static binary, BusyBox `sh` (no `bash`), `curl`, `tzdata`,
`git` (build contexts from Git URLs), `newuidmap`/`newgidmap`, `fuse-overlayfs` and
Alpine's `netavark` and `crun`. With `-e BUILDAH_ISOLATION=oci`, a privileged container can use
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
- Exception: releases whose `go.mod` has `replace` directives (1.26.3 to 1.26.9, 1.27.0
  to 1.27.6, 1.28, 1.29.0 to 1.29.5, 1.30 and 1.35 to 1.37) cannot be built from the
  module proxy, which ignores those directives. They are built from the upstream Git
  checkout at the release tag and its `vendor/` directory, unmodified; the binary
  records the upstream commit (`vcs.revision`) instead of a module hash.
- The C parts (cgo in buildah and its dependencies, musl, libseccomp) are compiled with
  [zig](https://ziglang.org) at a version pinned in [`mise.toml`](mise.toml). libseccomp comes from
  its upstream release tarball, pinned by version and sha256 in
  [`hack/build-sysroot.sh`](hack/build-sysroot.sh).
- Builds run only in GitHub Actions. Binaries and checksums are signed keyless with
  [cosign](https://github.com/sigstore/cosign) via GitHub OIDC, images are signed the
  same way, and every file in `checksums.txt` gets a GitHub build provenance
  attestation.
- Every archive has an SPDX SBOM next to it (`<archive>.sbom.json`, listed in
  `checksums.txt`), and every image carries one per platform as a BuildKit attestation,
  covered by the image signature. syft finds the Go modules in the binary; the C code it
  cannot see there (musl, libseccomp, and the SQLite that `github.com/mattn/go-sqlite3`
  bundles) is listed in `static-libraries.spdx.json`, which is in the archive and in the
  image under `/usr/share/sbom/buildah/`, and merged into both SBOMs. The image's SBOM:
  `docker buildx imagetools inspect ghcr.io/podman-container-tools-community/buildah:latest --format '{{ json .SBOM }}'`.
- The apt repository metadata (`InRelease`) and the rpm packages are additionally signed
  with a GPG key, because apt and rpm cannot verify sigstore signatures; apt verifies
  the deb packages through the checksums in the signed `InRelease`. The key is kept in
  this repository's secrets and used only by the release workflow.
- Every release is built with the newest stable Go, not the minimum in upstream's
  `go.mod` (exceptions are listed in [`.github/actions/setup`](.github/actions/setup/action.yaml)).
  The Go version used is recorded in each binary (`go version -m`).
- Builds are reproducible: with the same Go, zig and libseccomp versions, anyone gets
  bit-for-bit identical binaries.

## Which versions are released

Every upstream [GitHub release](https://github.com/podman-container-tools/buildah/releases)
since `v1.26.3`, drafts and prereleases excluded
([`hack/upstream-releases.sh`](hack/upstream-releases.sh)); 1.26.0 to 1.26.2 are left out
because they vendor a libseccomp-golang that does not compile against libseccomp 2.6.
Upstream maintains several minor versions at once (1.26, 1.29, 1.33, 1.37, 1.39 and 1.41
all had patch releases in 2026), so there is no version list to maintain here.

## Release flow

New upstream releases are picked up automatically, usually within six hours. Each
release is built and tested ([`test/`](test)) before anything is published, then
released here with binaries, packages, the apt repository and images on `ghcr.io`, all
signed.

Image tags: `vX.Y.Z` and `vX.Y.Z-immutable` always, `vX.Y` for the newest release of a
minor, `vX` and `latest` for the newest upstream release by version (not upstream's
GitHub "latest" flag, which a backport release of an older minor can take).
`vX.Y.Z-immutable` is pushed once by the release and never moves.

Releases are built by the pipeline on `main`; the release notes name the pipeline
commit. The release's Git tag in this repository only anchors the GitHub release (it
points at the repository's first commit) and never moves.

Images are rebuilt without a new release when the Alpine base image or its packages
change: weekly for the newest release of every minor, and after changes to the image
definition. A rebuild takes the released archives, checks them against the
cosign-signed `checksums.txt` and builds the image with the current `Dockerfile`, so the
images always contain exactly the released binaries. It updates every tag of that
release except `vX.Y.Z-immutable`, which keeps the digest of the original release.

## Verify a binary

Download the binary (or archive, or package), `checksums.txt` and `checksums.txt.sigstore.json` from
the release. The examples use buildah `v1.46.0`.

1. **Signature of the checksums**, proving the file came from this repository's release
   workflow on `main`:

   ```sh
   cosign verify-blob \
     --certificate-identity https://github.com/podman-container-tools-community/buildah/.github/workflows/release.yaml@refs/heads/main \
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

Every image, released or rebuilt, is signed by the `images.yaml` workflow on `main`:

```sh
cosign verify ghcr.io/podman-container-tools-community/buildah:v1.46.0 \
  --certificate-identity https://github.com/podman-container-tools-community/buildah/.github/workflows/images.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Reproduce a build

See [Reproduce locally](#reproduce-locally). Use the Go version shown by `go version -m`
on the released binary, and the zig and libseccomp versions from
[`mise.lock`](mise.lock) and [`hack/build-sysroot.sh`](hack/build-sysroot.sh) at the
pipeline commit named in the release notes.

## Limitations

The binaries are static and linked against musl. Compared to a distribution package,
this means:

- **netavark is needed.** Recent buildah releases refuse to create any container
  without a `netavark` binary in the helper directories, even with `--network host`.
  The packages depend on the distribution's netavark (so they do not install on Ubuntu
  22.04, which has none), and the image contains Alpine's.
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
- **No default configuration.** The binary does not install `/etc/containers`. The
  packages recommend the distribution's package that owns it
  (`golang-github-containers-common` on Debian and Ubuntu, `containers-common` on rpm
  distributions); the image ships `policy.json`, `containers.conf` and `registries.conf`.
- **The apt repository serves only the newest release.** Its sources point at
  `releases/latest/download`, so once a new upstream release is published, the `.deb`
  URLs in a cached index return 404 until `sudo apt update` runs (see
  [apt](#apt-debian-ubuntu)). This is by design; there is no package pool with older
  releases.
- **Linux only**, `amd64` and `arm64`. The arm64 binary is cross-compiled and checked to
  be static, but its functional tests do not run: CI tests on amd64 only.

## Reproduce locally

Needs Go, gperf, pkg-config and [mise](https://mise.jdx.dev), which installs zig, goreleaser
and syft from `.build/mise.lock`:

```sh
git clone --branch v1.46.0 https://github.com/podman-container-tools/buildah
cd buildah
git clone https://github.com/podman-container-tools-community/buildah .build
printf '/.build/\n/dist/\n/.zig-cache/\n' >> .git/info/exclude
(cd .build && mise install)
eval "$(mise env -C .build)"
.build/hack/build-sysroot.sh /tmp/sysroot
SYSROOT=/tmp/sysroot GOTOOLCHAIN=local \
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/buildah \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,sbom
```

For releases with `replace` directives in `go.mod`, use a copy of the configuration
with `proxy: false`, as [`.github/actions/setup`](.github/actions/setup/action.yaml)
does. With the same Go, zig and libseccomp versions, the binaries are bit-for-bit
identical.
How to run the tests is described in [`AGENTS.md`](AGENTS.md).

## Contributing

Bug reports and pull requests are welcome. [`CONTRIBUTING.md`](CONTRIBUTING.md) explains
how to report a problem, what changes we accept and how to propose one. How the build
works, how to run the tests and the release workflows are described in
[`AGENTS.md`](AGENTS.md).

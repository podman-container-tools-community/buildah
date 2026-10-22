# syntax=docker/dockerfile:1

# Pinned by index digest so image builds stay reproducible; Renovate bumps it (both FROM
# lines name the same image).
FROM alpine:3.24@sha256:71e9b7bae160ba167fa17414401b94cbcdaf3c32feeab9298bd794a2a0614c35 AS base

# Everything that has to run happens here, on the build host's platform, so no emulation
# is needed: apk installs the target architecture's packages into a copy of the target's
# file system, without their scripts (only fuse-overlayfs has one, a modprobe). Only what
# changed ends up in /delta, so the final image adds one layer on top of Alpine's.
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:71e9b7bae160ba167fa17414401b94cbcdaf3c32feeab9298bd794a2a0614c35 AS delta
ARG TARGETARCH
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]
# Versions come from the Alpine release the base image pins; apk cannot pin older ones,
# because the repositories only keep the newest.
# hadolint ignore=DL3018
RUN apk add --no-cache findutils tar
COPY --from=base / /rootfs/
# hadolint ignore=DL3018
RUN <<EOF
case "${TARGETARCH}" in
  amd64) arch=x86_64 ;;
  arm64) arch=aarch64 ;;
  *) echo "unsupported architecture ${TARGETARCH}" >&2; exit 1 ;;
esac
touch /marker
# git: build contexts from Git URLs. shadow-subids: newuidmap and newgidmap (file
# capabilities) for rootless. fuse-overlayfs: rootless overlay where the kernel's is not
# allowed. netavark: recent buildah releases refuse to create containers without it, even
# with host networking, which the image uses by default (packaging/image/containers.conf).
# crun: OCI runtime for --isolation oci; chroot stays the default (BUILDAH_ISOLATION).
# bash, curl, tzdata: scripts written for upstream's Fedora-based image.
apk --root /rootfs --arch "${arch}" --no-cache --no-scripts add \
  git shadow-subids fuse-overlayfs netavark crun bash curl tzdata

# Unprivileged user for rootless builds, with its own storage volume. The subordinate ID
# ranges are upstream's: they stay below 65536, so they also fit into a container that
# only has 65536 IDs mapped (rootless Docker or podman, user namespace remapping).
echo 'build:x:1000:1000:build:/home/build:/bin/bash' >> /rootfs/etc/passwd
echo 'build:x:1000:' >> /rootfs/etc/group
echo 'build:!::0:::::' >> /rootfs/etc/shadow
printf 'root:1:65535\nbuild:1:999\nbuild:1001:64535\n' | tee -a /rootfs/etc/subuid >> /rootfs/etc/subgid
mkdir -p /rootfs/home/build/.local/share/containers
chown -R 1000:1000 /rootfs/home/build

# ctime cannot be preserved, so -cnewer finds exactly what the steps above wrote.
mkdir /delta
find /rootfs -mindepth 1 -cnewer /marker -printf '%P\0' |
  tar -C /rootfs --null --no-recursion --xattrs --xattrs-include='security.*' -T - -cf - |
  tar -C /delta --xattrs --xattrs-include='security.*' -xpf -
EOF

FROM base
ARG TARGETPLATFORM
ENV BUILDAH_ISOLATION=chroot
COPY --from=delta /delta/ /
COPY .build/packaging/image/policy.json .build/packaging/image/containers.conf \
  .build/packaging/image/registries.conf /etc/containers/
COPY $TARGETPLATFORM/buildah /usr/bin/buildah
# Storage and buildah's temporary overlays (build context) need a file system that is
# not the image's overlay.
VOLUME ["/var/lib/containers", "/var/tmp", "/home/build/.local/share/containers"]
# No entrypoint, like upstream's image: `docker run <image> buildah ...` and CI systems
# that run a shell script in the image both work.
CMD ["/bin/bash"]

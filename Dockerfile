# syntax=docker/dockerfile:1

# Recent buildah releases refuse to create containers unless a netavark binary exists,
# even with host networking, which the image always uses (packaging/image/containers.conf).
# The link only satisfies that check; if anything runs it, buildah fails on the unknown
# arguments. This stage runs on the build host's platform, so no emulation is needed.
FROM --platform=$BUILDPLATFORM gcr.io/distroless/static-debian13:debug@sha256:11c839f18a0d7b91b093cda53a5d4cee84f23ec450a6f6e1bf17ab12bf296333 AS links
SHELL ["/busybox/sh", "-c"]
RUN mkdir -p /out/usr/libexec/podman && ln -s /usr/bin/buildah /out/usr/libexec/podman/netavark

# distroless/static brings CA certificates, /etc/passwd, /tmp and /var/tmp.
# Pinned by index digest so image builds stay reproducible; Renovate bumps it.
FROM gcr.io/distroless/static-debian13:latest@sha256:034df5c1737e8241f6ed6423a12e720ee0f6d6f088609ee172f98f6f2166ef5d
ARG TARGETPLATFORM
ENV BUILDAH_ISOLATION=chroot
COPY .build/packaging/image/policy.json .build/packaging/image/containers.conf /etc/containers/
COPY --from=links /out/ /
COPY $TARGETPLATFORM/buildah /usr/bin/buildah
# Storage and buildah's temporary overlays (build context) need a file system that is
# not the image's overlay.
VOLUME ["/var/lib/containers", "/var/tmp"]
ENTRYPOINT ["/usr/bin/buildah"]

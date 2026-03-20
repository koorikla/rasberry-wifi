# syntax=docker/dockerfile:1

# Stage 1: extract and decompress Broadcom firmware.
# Run on linux/amd64 (native, no QEMU) — firmware blobs are architecture-independent.
# Files are at /lib/firmware/brcm/ (not /usr/lib/firmware/) and are .zst compressed.
# hadolint ignore=DL3029
FROM --platform=linux/amd64 alpine:3.21 AS firmware
RUN apk add --no-cache linux-firmware-brcm zstd

# Decompress firmware files for CYW43455 (RPi5 onboard WiFi via SDIO).
# Files are symlinks → /lib/firmware/cypress/cyfmac43455-sdio*.zst
# Use zstdcat (follows symlinks) rather than zstd -d (which ignores symlinks).
RUN cd /lib/firmware/brcm && \
    zstdcat brcmfmac43455-sdio.bin.zst                             > brcmfmac43455-sdio.bin && \
    zstdcat brcmfmac43455-sdio.clm_blob.zst                        > brcmfmac43455-sdio.clm_blob && \
    zstdcat brcmfmac43455-sdio.txt.zst                             > brcmfmac43455-sdio.txt && \
    zstdcat brcmfmac43455-sdio.raspberrypi,5-model-b.bin.zst      > "brcmfmac43455-sdio.raspberrypi,5-model-b.bin" && \
    zstdcat brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob.zst > "brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob" && \
    zstdcat brcmfmac43455-sdio.raspberrypi,5-model-b.txt.zst      > "brcmfmac43455-sdio.raspberrypi,5-model-b.txt"

# Stage 2: assemble extension image
# Talos system extension layout:
#   /manifest.yaml   — extension metadata
#   /rootfs/         — files overlaid onto the Talos root filesystem
FROM scratch AS extension
COPY manifest.yaml /manifest.yaml

# Generic fallback firmware (used if no board-specific variant is found)
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.bin \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.bin
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.clm_blob \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.txt \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.txt

# RPi5 board-specific firmware (preferred by brcmfmac over the generic files)
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob
COPY --from=firmware /lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.txt \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.txt

LABEL org.opencontainers.image.title="sys-kernel-firmware-wifi"
LABEL org.opencontainers.image.description="WiFi firmware blobs for RPi5 Talos extension"
LABEL org.opencontainers.image.source="https://github.com/koorikla/rasberry-wifi"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"

# syntax=docker/dockerfile:1

# Stage 1: extract Broadcom firmware from Alpine linux-firmware package
FROM alpine:3.21 AS firmware
RUN apk add --no-cache linux-firmware-brcm

# Stage 2: assemble extension image
# Talos system extension layout:
#   /manifest.yaml   — extension metadata
#   /rootfs/         — files overlaid onto the Talos root filesystem
FROM scratch AS extension
COPY manifest.yaml /manifest.yaml

# Firmware blobs for CYW43455 (RPi5 onboard WiFi)
COPY --from=firmware /usr/lib/firmware/brcm/brcmfmac43455-sdio.bin \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.bin
COPY --from=firmware /usr/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
COPY --from=firmware /usr/lib/firmware/brcm/brcmfmac43455-sdio.txt \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.txt

# RPi5-specific firmware variant (board-specific .bin)
# This file may not exist in all linux-firmware versions; the COPY will fail
# silently if --chmod is not used. If missing, brcmfmac falls back to the generic .bin.
COPY --from=firmware /usr/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin \
     /rootfs/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin

LABEL org.opencontainers.image.title="sys-kernel-firmware-wifi"
LABEL org.opencontainers.image.description="WiFi firmware blobs for RPi5 Talos extension"
LABEL org.opencontainers.image.source="https://github.com/koorikla/rasberry-wifi"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"

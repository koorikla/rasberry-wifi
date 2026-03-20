# syntax=docker/dockerfile:1

# Build wpa_supplicant for arm64 from Alpine
FROM --platform=linux/arm64 alpine:3.21 AS builder
RUN apk add --no-cache wpa_supplicant

# Assemble extension image
FROM scratch AS extension
COPY manifest.yaml /manifest.yaml

# wpa_supplicant and wpa_cli binaries
COPY --from=builder /sbin/wpa_supplicant /rootfs/usr/local/sbin/wpa_supplicant
COPY --from=builder /sbin/wpa_cli        /rootfs/usr/local/sbin/wpa_cli

# Extension service definition
# Path must match Talos extension service loader expectations
COPY wpa_supplicant.service /rootfs/etc/extension-services/wpa_supplicant.yaml

LABEL org.opencontainers.image.title="wpa-supplicant"
LABEL org.opencontainers.image.description="wpa_supplicant extension service for Talos Linux WiFi"
LABEL org.opencontainers.image.source="https://github.com/koorikla/rasberry-wifi"
LABEL org.opencontainers.image.licenses="BSD-3-Clause"

# CLAUDE.md — rasberry-wifi

## What this project is

Custom Talos Linux image builder for Raspberry Pi 5 with WiFi support.
WiFi on RPi5/Talos requires three things upstream doesn't provide:
a kernel with brcmfmac compiled in, Broadcom firmware blobs, and wpa_supplicant.
This repo builds all three and assembles them into a flashable metal image.

## Three-stage build

1. **Kernel** — patches talos-rpi5/talos-builder to add CFG80211 + BRCMFMAC,
   produces `ghcr.io/koorikla/rasberry-wifi-kernel:TALOS_VERSION`
2. **Extensions** — builds two OCI system extensions:
   - `ghcr.io/koorikla/sys-kernel-firmware-wifi` — Broadcom firmware blobs
   - `ghcr.io/koorikla/wpa-supplicant` — wpa_supplicant binary + service
3. **Image** — siderolabs/imager assembles everything into `metal-arm64.raw.xz`

## Make targets

```bash
make build                  # full pipeline: kernel + extensions + image
make kernel                 # Stage 1 only
make extensions             # Stage 2 only (both extensions in parallel)
make image                  # Stage 3 only (requires stages 1+2 done)
make clean                  # remove _out/
make flash DISK=/dev/sdX    # dd image to target disk
make help                   # list all targets
```

## Key constraints

- `CONFIG_CFG80211` must be `=y` (built-in), not `=m` — Talos networking requirement
- Kernel modules (brcmutil, brcmfmac) must be signed with the key used at kernel build time —
  cannot be added separately after the fact
- wpa_supplicant extension service runs in host network namespace (no containers)
- WiFi credentials go in `overlays/wifi-credentials.yaml` (gitignored) — never commit secrets
- No SSH on Talos — all config is declarative via talosctl + machine config patches

## Kernel base

talos-rpi5/talos-builder (https://github.com/talos-rpi5/talos-builder)
Community RPi5 kernel. We apply `kernel/config.patch` on top of it.
See `docs/KERNEL-BUILD.md` for details.

## WiFi chip

Raspberry Pi 5: Infineon/Cypress CYW43455 connected via SDIO
Driver: brcmfmac + brcmutil
Firmware: brcmfmac43455-sdio.* (from linux-firmware)
See `docs/WIFI-STATUS.md` for full status and known issues.

## Related projects

- `../talos/` — home lab cluster config (koorikla, single-node)
- `../kalatalos/` — RPi5 Talos worker (Big Mouth Billy Bass), includes earlier WiFi research

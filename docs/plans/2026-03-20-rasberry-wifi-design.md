---
name: rasberry-wifi design
description: Design doc for custom Talos Linux RPi5 image with WiFi support
type: project
date: 2026-03-20
---

# rasberry-wifi — Design Document

## Purpose

Build a custom Talos Linux metal image for Raspberry Pi 5 (arm64) with working WiFi support.
WiFi on RPi5/Talos requires three components that don't exist in upstream Talos: a kernel with
wireless drivers compiled in, firmware blobs, and a wpa_supplicant service. This repo builds
all three and assembles them into a flashable metal image.

## Context

- Talos v1.12.6 (current latest stable)
- RPi5 uses CYW43455 (Infineon/Cypress) connected via SDIO — driver: `brcmfmac`
- Upstream Talos strips `CONFIG_CFG80211`, `CONFIG_BRCMUTIL`, `CONFIG_BRCMFMAC` from all kernels
- Feature request siderolabs/talos#11185 closed "Not Planned" Dec 2025
- This repo takes the custom-build path: patch the talos-rpi5 kernel, build extensions, assemble image
- Related projects: `kalatalos` (Talos RPi worker node), `talos` (home lab cluster config)

## Three Build Outputs

### 1. Custom Kernel

Built on top of [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) (community RPi5 kernel).

Kernel config additions required:
```
CONFIG_CFG80211=y          # must be built-in, not module
CONFIG_BRCMUTIL=m
CONFIG_BRCMFMAC=m
CONFIG_BRCMFMAC_SDIO=y
CONFIG_BRCMFMAC_PROTO_BCDC=y
CONFIG_BRCMFMAC_PROTO_MSGBUF=y
```

Constraint: kernel modules must be signed with the key used at kernel build time.
The patch lives in `kernel/config.patch` and is applied to the talos-rpi5 build tree.

### 2. System Extensions

Both built with `ghcr.io/siderolabs/extensions-builder` targeting Talos v1.12.6.

**`sys-kernel-firmware-wifi`** (`extensions/sys-kernel-firmware-wifi/`)
- Ships Broadcom firmware blobs from `linux-firmware` into `/lib/firmware/brcm/`
- Files: `brcmfmac43455-sdio.bin`, `brcmfmac43455-sdio.clm_blob`, `brcmfmac43455-sdio.txt`,
  `brcmfmac43455-sdio.raspberrypi,5-model-b.bin`
- Published to: `ghcr.io/koorikla/sys-kernel-firmware-wifi`

**`wpa-supplicant`** (`extensions/wpa-supplicant/`)
- Ships `wpa_supplicant` binary + config as a Talos extension service
- Runs in host network namespace (required for WiFi interface access)
- Config injected via Talos machine config `files:` block
- Published to: `ghcr.io/koorikla/wpa-supplicant`

### 3. Metal Image

Assembled by `ghcr.io/siderolabs/imager:v1.12.6`:
- Board: `rpi_generic`
- Custom kernel artifact from Stage 1
- Both extensions from Stage 2
- Kernel args: `console=ttyAMA0,115200`
- Output: `metal-arm64.raw.xz` → SD card / USB

## CI Pipeline (GitHub Actions)

Three sequential stages on `ubuntu-latest`:

```
push/release → free disk space
    │
    ▼
Stage 1: Build kernel
  clone talos-rpi5/talos-builder @ HEAD
  apply kernel/config.patch
  build kernel → publish to ghcr.io/koorikla/rasberry-wifi-kernel (or cache)
    │
    ▼
Stage 2: Build extensions (can run in parallel jobs)
  sys-kernel-firmware-wifi → ghcr.io/koorikla/sys-kernel-firmware-wifi:v1.12.6
  wpa-supplicant           → ghcr.io/koorikla/wpa-supplicant:v1.12.6
    │
    ▼
Stage 3: Assemble image
  siderolabs/imager + custom kernel ref + both extensions
  → upload metal-arm64.raw.xz as workflow artifact
  → on release: push to ghcr.io/koorikla/rasberry-wifi:${{ github.ref_name }}
```

## Repository Structure

```
rasberry-wifi/
├── .claude/
│   └── settings.json                   # superpowers permissions
├── .github/
│   └── workflows/
│       └── build.yml                   # 3-stage CI
├── kernel/
│   ├── config.patch                    # kernel config additions
│   └── README.md                       # talos-rpi5 fork integration notes
├── extensions/
│   ├── sys-kernel-firmware-wifi/
│   │   ├── Dockerfile
│   │   ├── Makefile
│   │   └── manifest.yaml
│   └── wpa-supplicant/
│       ├── Dockerfile
│       ├── Makefile
│       ├── manifest.yaml
│       └── wpa_supplicant.service      # Talos extension service definition
├── overlays/                           # machine config patches (placeholder)
├── docs/
│   ├── plans/
│   │   └── 2026-03-20-rasberry-wifi-design.md
│   ├── WIFI-STATUS.md                  # what works, what's blocked, full research
│   └── KERNEL-BUILD.md                 # custom kernel build guide
├── _out/                               # gitignored
├── .gitignore
├── Makefile                            # kernel / extensions / image / build / clean / flash
├── CLAUDE.md
└── README.md
```

## Makefile Targets

| Target | Action |
|--------|--------|
| `build` | kernel + extensions + image (full pipeline) |
| `kernel` | build custom kernel only |
| `extensions` | build both extensions |
| `image` | assemble final metal image (requires kernel + extensions) |
| `clean` | remove `_out/` |
| `flash DISK=/dev/sdX` | `dd` the `.raw.xz` to target disk |

## Key Constraints

- **Module signing**: brcmfmac kernel modules must be signed at kernel build time — cannot patch in separately
- **CFG80211 built-in**: must be `=y` not `=m` (Talos requirement for networking stack)
- **wpa_supplicant host network namespace**: extension service needs `hostNetwork: true` equivalent
- **Talos machine config**: WiFi interface + credentials configured via `network.interfaces` in machine config patch (not wpa_supplicant.conf directly)
- **No shell on Talos**: all configuration is declarative via machine config

## Known Issues / Open Problems

See `docs/WIFI-STATUS.md` for full detail. TL;DR:
- talos-rpi5/talos-builder kernel build is complex; CI time will be heavy (30-60 min)
- brcmfmac firmware for RPi5 may need board-specific `.bin` file (varies by Talos version)
- wpa_supplicant as Talos extension is untested upstream; may need Talos 1.13+
- No upstream support path — this is fully custom, rebases required on each Talos/RPi5 release

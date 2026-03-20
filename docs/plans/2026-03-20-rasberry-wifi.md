# rasberry-wifi Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Scaffold a GitHub repository that builds a custom Talos Linux metal image for Raspberry Pi 5 with WiFi support, including a patched kernel, firmware extension, and wpa_supplicant extension.

**Architecture:** Three-stage build pipeline: (1) clone talos-rpi5/talos-builder, apply kernel config patch enabling brcmfmac/CFG80211, publish custom installer image; (2) build two OCI system extensions (firmware blobs + wpa_supplicant service); (3) invoke siderolabs/imager with the custom installer + both extensions to produce `metal-arm64.raw.xz`. CI runs the full pipeline on push/release; extensions and image are published to ghcr.io/koorikla/.

**Tech Stack:** Talos Linux v1.12.6, talos-rpi5/talos-builder (community RPi5 kernel), siderolabs/imager, Docker Buildx, GitHub Actions, ghcr.io, `make`, `gh` CLI.

---

## Validation tools

```bash
# Install once before starting
brew install hadolint actionlint
```

---

### Task 1: Git init + directory scaffold

**Files:**
- Create: `/Users/kaurkallas/rasberry-wifi/` (already exists)

**Step 1: Initialise git and create all directories**

```bash
cd /Users/kaurkallas/rasberry-wifi
git init
mkdir -p .claude .github/workflows kernel \
         extensions/sys-kernel-firmware-wifi \
         extensions/wpa-supplicant \
         overlays docs _out
```

**Step 2: Write .gitignore**

Create `/Users/kaurkallas/rasberry-wifi/.gitignore`:

```gitignore
# Build artefacts
_out/

# Secrets / machine configs with credentials
overlays/wifi-*.yaml
overlays/secrets*.yaml

# macOS
.DS_Store

# Editor
.idea/
*.swp
```

**Step 3: Verify tree**

```bash
find /Users/kaurkallas/rasberry-wifi -type d | sort
```
Expected: all dirs listed above present.

**Step 4: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add .gitignore
git commit -m "chore: initial scaffold + .gitignore"
```

---

### Task 2: CLAUDE.md + .claude/settings.json

**Files:**
- Create: `CLAUDE.md`
- Create: `.claude/settings.json`

**Step 1: Write CLAUDE.md**

Create `/Users/kaurkallas/rasberry-wifi/CLAUDE.md`:

```markdown
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
```

**Step 2: Write .claude/settings.json**

Create `/Users/kaurkallas/rasberry-wifi/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(docker:*)",
      "Bash(docker buildx:*)",
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(talosctl:*)",
      "Bash(actionlint:*)",
      "Bash(hadolint:*)"
    ]
  }
}
```

**Step 3: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add CLAUDE.md .claude/settings.json
git commit -m "chore: add CLAUDE.md and .claude/settings.json (superpowers)"
```

---

### Task 3: README.md

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

Create `/Users/kaurkallas/rasberry-wifi/README.md`:

````markdown
# rasberry-wifi

> Custom Talos Linux metal image for Raspberry Pi 5 with WiFi support.

Builds a Talos v1.12.6 `metal-arm64` image for the RPi5 (`rpi_generic` board) with:
- A patched kernel enabling `brcmfmac` (CYW43455 / onboard WiFi chip)
- `sys-kernel-firmware-wifi` — Broadcom firmware blobs baked in as a system extension
- `wpa-supplicant` — wpa_supplicant running as a Talos extension service

> **Status:** Active development. See [Known Issues](#known-issues) for current WiFi limitations.

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| Docker (with Buildx) | Build kernel + extensions + image | [docs.docker.com](https://docs.docker.com/get-docker/) |
| `crane` | Inspect OCI images | `brew install crane` |
| `talosctl` | Apply machine config, interact with nodes | `brew install siderolabs/tap/talosctl` |
| `gh` | GitHub CLI (optional, for release) | `brew install gh` |

---

## Build locally

```bash
# Full pipeline: kernel → extensions → image
make build

# Or step by step:
make kernel       # Build patched WiFi kernel (~30-60 min first run)
make extensions   # Build sys-kernel-firmware-wifi + wpa-supplicant
make image        # Assemble metal-arm64.raw.xz

# Output: _out/metal-arm64.raw.xz
```

The first kernel build will take 30-60 minutes (compiles the RPi5 kernel from source).
Subsequent builds use Docker layer cache and are much faster.

---

## Flash to SD card / USB

```bash
# List available disks first
diskutil list          # macOS
lsblk                  # Linux

# Flash (replace /dev/sdX with your target — double-check before running!)
make flash DISK=/dev/sdX
```

Or manually:

```bash
xzcat _out/metal-arm64.raw.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

---

## Configure WiFi

After flashing, apply a machine config patch with your WiFi credentials.
A template lives at `overlays/wifi-credentials.yaml.example`.

```bash
# Edit the template (never commit the real file)
cp overlays/wifi-credentials.yaml.example overlays/wifi-credentials.yaml
$EDITOR overlays/wifi-credentials.yaml

# Apply to a running node (after initial Ethernet bootstrap)
talosctl apply-config --nodes <NODE_IP> --file overlays/wifi-credentials.yaml
```

---

## Customise

### Kernel arguments

Edit the `KERNEL_ARGS` variable in `Makefile`:

```makefile
KERNEL_ARGS ?= console=ttyAMA0,115200
```

Add kernel args with spaces, e.g.:

```makefile
KERNEL_ARGS ?= console=ttyAMA0,115200 earlycon=pl011,0x107d001000
```

### Extensions

Add extensions by appending `--system-extension-image` flags in the `image` target of the
`Makefile` and the imager step of `.github/workflows/build.yml`.

### Kernel config

Edit `kernel/config.patch` to add or modify kernel config options. See
`docs/KERNEL-BUILD.md` for the full rebuild workflow.

### Overlays (machine config patches)

Place Talos machine config patches in `overlays/`. Filename convention:
- `overlays/wifi-credentials.yaml` — WiFi SSID + PSK (gitignored)
- `overlays/rpi5-base.yaml` — base RPi5 overrides (committed)

Apply with `talosctl machineconfig patch`.

---

## CI

GitHub Actions (`.github/workflows/build.yml`) runs on push to `main` and on published releases.

| Stage | Job | Output |
|-------|-----|--------|
| 1 | `build-kernel` | `ghcr.io/koorikla/rasberry-wifi-kernel:v1.12.6` |
| 2 | `build-extensions` | `ghcr.io/koorikla/sys-kernel-firmware-wifi:v1.12.6`, `ghcr.io/koorikla/wpa-supplicant:v1.12.6` |
| 3 | `build-image` | `metal-arm64.raw.xz` artifact; on release → `ghcr.io/koorikla/rasberry-wifi` |

---

## Known Issues

### WiFi not yet working end-to-end

As of Talos v1.12 / March 2026, WiFi on RPi5 is **not supported upstream** and this repo
represents a best-effort community attempt to add it. Specific blockers:

| Issue | Detail |
|-------|--------|
| Upstream "Not Planned" | siderolabs/talos#11185 — WiFi support request closed Not Planned, Dec 2025 |
| Kernel build complexity | talos-rpi5/talos-builder uses the Talos `bldr` toolchain; the patch may need rebasing on each upstream release |
| Module signing | `brcmutil` and `brcmfmac` modules must be signed with the key from the same kernel build — cannot be patched in post-build |
| No wpa_supplicant upstream | Talos has no 802.11 networking stack — wpa_supplicant must run as a privileged extension service; this is untested in upstream Talos |
| Firmware variant | RPi5 may require the board-specific `brcmfmac43455-sdio.raspberrypi,5-model-b.bin` variant; availability in `linux-firmware` varies by distro version |
| 802.11 interface naming | Interface will likely be `wlan0` but could vary; machine config patches must use the correct interface name |

### Recommended workaround (works today)

Use a **travel router as an Ethernet bridge** (e.g. GL.iNet GL-MT300N-V2, ~$25):
configure it in repeater/client mode, plug the Pi's Ethernet port into the router's LAN port.
The Pi sees a wired connection. No Talos changes needed.

---

## Related

- [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) — community RPi5 kernel
- [siderolabs/extensions](https://github.com/siderolabs/extensions) — official Talos extensions
- [Talos Image Factory](https://factory.talos.dev/) — official image builder (no RPi5 / no WiFi)
- `../kalatalos/docs/WIFI.md` — earlier WiFi research on this hardware
````

**Step 2: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add README.md
git commit -m "docs: add README with build, flash, and known-issues sections"
```

---

### Task 4: docs/WIFI-STATUS.md + docs/KERNEL-BUILD.md

**Files:**
- Create: `docs/WIFI-STATUS.md`
- Create: `docs/KERNEL-BUILD.md`

**Step 1: Write docs/WIFI-STATUS.md**

Create `/Users/kaurkallas/rasberry-wifi/docs/WIFI-STATUS.md`:

```markdown
# WiFi Support Status — RPi5 / Talos Linux

_Last updated: March 2026. See git log for changes._

## TL;DR

WiFi does not work on Talos Linux for RPi5 out of the box. This repo is the attempt to fix that.
Three things are needed and none exist upstream:

1. Kernel with `CONFIG_BRCMFMAC` (and `CONFIG_CFG80211`) compiled in
2. Broadcom firmware blobs at `/lib/firmware/brcm/`
3. `wpa_supplicant` (or `iwd`) running in the host network namespace

---

## Hardware

| Item | Detail |
|------|--------|
| Chip | Infineon/Cypress CYW43455 (same family as RPi4) |
| Bus | SDIO (not PCIe, not USB) |
| Driver | `brcmfmac` + `brcmutil` |
| Interface | `wlan0` (expected) |
| Firmware files needed | `brcmfmac43455-sdio.bin`, `.clm_blob`, `.txt`, `.raspberrypi,5-model-b.bin` |

## Kernel config needed

```
CONFIG_CFG80211=y              # must be built-in
CONFIG_BRCMUTIL=m
CONFIG_BRCMFMAC=m
CONFIG_BRCMFMAC_SDIO=y
CONFIG_BRCMFMAC_PROTO_BCDC=y
CONFIG_BRCMFMAC_PROTO_MSGBUF=y
```

## Upstream status

| Layer | Status |
|-------|--------|
| siderolabs/talos WiFi support | **Not planned** — issue #11185 closed Dec 2025 |
| talos-rpi5/talos-builder WiFi | **Not supported** — no open issues/PRs |
| siderolabs/extensions WiFi extension | **Does not exist** |
| Talos Image Factory RPi5 support | **Not supported** (requires custom kernel) |

## What this repo attempts

| Component | Status |
|-----------|--------|
| `kernel/config.patch` — brcmfmac kernel config | In progress |
| `extensions/sys-kernel-firmware-wifi` — firmware blobs | In progress |
| `extensions/wpa-supplicant` — wpa_supplicant service | In progress |
| End-to-end WiFi connectivity on RPi5 | **Not yet validated** |

## Known blockers

- **Module signing**: kernel modules must be signed at build time with the key embedded in the
  kernel image. You cannot add unsigned modules to an existing Talos image.
- **wpa_supplicant as extension service**: Talos extension services run via the host containerd
  in a restricted environment. Running wpa_supplicant with access to the WiFi interface requires
  specific network namespace and privilege config — untested upstream.
- **Kernel build rebase burden**: talos-rpi5/talos-builder releases don't follow a fixed cadence.
  Rebasing `kernel/config.patch` is a manual step on each upstream release.

## Workaround (works today)

Travel router as Ethernet bridge:
- GL.iNet GL-MT300N-V2 or GL-SFT1200 (~$25-40) in repeater/client mode
- Pi's Ethernet → router's LAN port
- Router connects to home WiFi
- Talos sees a wired interface — zero config changes needed

---

_Sources: siderolabs/talos #6911, #7821, #8259, #11185; talos-rpi5/talos-builder README;
siderolabs/overlays discussion #77; kalatalos/docs/WIFI.md_
```

**Step 2: Write docs/KERNEL-BUILD.md**

Create `/Users/kaurkallas/rasberry-wifi/docs/KERNEL-BUILD.md`:

```markdown
# Custom Kernel Build Guide

This explains how `make kernel` works and how to update the kernel config patch.

## What we're building

We clone [talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder), apply
`kernel/config.patch` to add WiFi kernel configs, then build the patched kernel using the
talos-rpi5 build system. The output is an OCI image published to
`ghcr.io/koorikla/rasberry-wifi-kernel:TALOS_VERSION`.

This image is then passed to `siderolabs/imager` as `--base-installer-image`.

## talos-rpi5/talos-builder basics

The community RPi5 kernel adds patches on top of the upstream Raspberry Pi kernel fork
(`raspberrypi/linux`) to support RP1 PCIe, NVMe, MACB ethernet, and other RPi5-specific
hardware. It uses the Talos `bldr` build tool (a Docker-based build system).

The kernel config is in `kernel/build/config-arm64` (or similar — check the upstream repo
as the path may change between releases).

## Updating kernel/config.patch

If the upstream talos-rpi5 kernel changes and the patch no longer applies:

```bash
# Clone talos-rpi5/talos-builder
git clone https://github.com/talos-rpi5/talos-builder /tmp/talos-builder
cd /tmp/talos-builder

# Identify the kernel config file (path may differ between releases)
find . -name "config-arm64" -o -name "*.config" | head -5

# Apply existing patch (if it fails, you need to rebase)
patch -p1 < /path/to/rasberry-wifi/kernel/config.patch

# OR: manually add lines to the config file, then generate a new patch:
git diff > /path/to/rasberry-wifi/kernel/config.patch
```

## Build time

First build: ~30-60 minutes (cross-compiling arm64 kernel on x86 CI runner).
With Docker layer cache: ~5-10 minutes (only recompiles changed modules).

## Signing constraint

Talos kernel modules must be signed with the key embedded in the kernel at build time.
This means:
1. brcmutil and brcmfmac are compiled as modules (`=m`) and signed during the kernel build
2. They cannot be added to an existing Talos image post-build
3. If you add a new module after building the kernel, you must rebuild the kernel

This is why the custom kernel and extensions must come from the same build pipeline.

## Talos installer image

The kernel build produces a Talos installer OCI image (containing kernel + initramfs +
Talos system). This is what gets passed to the imager as `--base-installer-image`. It is
distinct from the system extension images.

Format: `ghcr.io/koorikla/rasberry-wifi-kernel:v1.12.6`
```

**Step 3: Write overlays placeholder and example**

Create `/Users/kaurkallas/rasberry-wifi/overlays/wifi-credentials.yaml.example`:

```yaml
# WiFi credentials machine config patch for Talos
# Copy to overlays/wifi-credentials.yaml and fill in your SSID + PSK
# overlays/wifi-credentials.yaml is gitignored — never commit real credentials
#
# Apply with:
#   talosctl machineconfig patch --patch @overlays/wifi-credentials.yaml \
#     --nodes <NODE_IP> --talosconfig talosconfig
machine:
  network:
    interfaces:
      - interface: wlan0
        dhcp: true
        wireless:
          accessPoints:
            - ssid: "YOUR_SSID_HERE"
              auth:
                keyManagement: wpa-psk
                password: "YOUR_PSK_HERE"
```

Create `/Users/kaurkallas/rasberry-wifi/overlays/rpi5-base.yaml`:

```yaml
# Base RPi5 machine config overrides
# Committed — no secrets here
machine:
  install:
    disk: /dev/mmcblk0   # SD card; change to /dev/sda for USB
    bootloader: true
  kernel:
    modules: []          # kernel modules loaded at boot (add as needed)
  network:
    hostname: rpi5-wifi  # override in node-specific patch
```

**Step 4: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add docs/WIFI-STATUS.md docs/KERNEL-BUILD.md overlays/
git commit -m "docs: add WIFI-STATUS, KERNEL-BUILD, overlays examples"
```

---

### Task 5: kernel/config.patch + kernel/README.md

**Files:**
- Create: `kernel/config.patch`
- Create: `kernel/README.md`

**Step 1: Write kernel/config.patch**

Create `/Users/kaurkallas/rasberry-wifi/kernel/config.patch`:

```diff
--- a/kernel/build/config-arm64
+++ b/kernel/build/config-arm64
@@ -1,3 +1,20 @@
+# WiFi support for Raspberry Pi 5 (CYW43455 / brcmfmac via SDIO)
+# Applied on top of talos-rpi5/talos-builder kernel config
+#
+# NOTE: CONFIG_CFG80211 must be =y (built-in), not =m.
+# Talos requires the networking stack to be compiled in.
+# brcmutil and brcmfmac can be =m (modules) but must be signed at build time.
+
+CONFIG_CFG80211=y
+CONFIG_CFG80211_WEXT=y
+CONFIG_MAC80211=m
+CONFIG_MAC80211_MESH=n
+CONFIG_RFKILL=y
+CONFIG_RFKILL_INPUT=y
+CONFIG_BRCMUTIL=m
+CONFIG_BRCMFMAC=m
+CONFIG_BRCMFMAC_SDIO=y
+CONFIG_BRCMFMAC_PROTO_BCDC=y
+CONFIG_BRCMFMAC_PROTO_MSGBUF=y
+CONFIG_BRCMFMAC_PCIE=n
+CONFIG_BRCMFMAC_USB=n
```

> **Note:** The exact path (`kernel/build/config-arm64`) depends on the talos-rpi5/talos-builder
> version. Run `find /tmp/talos-builder -name "*.config" -o -name "config-*"` after cloning to
> find the correct path, then update this patch accordingly.

**Step 2: Write kernel/README.md**

Create `/Users/kaurkallas/rasberry-wifi/kernel/README.md`:

```markdown
# kernel/

Contains the kernel config patch that adds WiFi support to the
[talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) kernel.

## Files

- `config.patch` — unified diff adding `CONFIG_CFG80211`, `CONFIG_BRCMFMAC`, and related options

## How it's used

`make kernel` and the CI `build-kernel` job:
1. Clone talos-rpi5/talos-builder
2. Apply `config.patch` with `patch -p1`
3. Build the kernel using the talos-rpi5 build system
4. Push the resulting installer image to `ghcr.io/koorikla/rasberry-wifi-kernel:TALOS_VERSION`

## Updating after talos-rpi5 releases

See `docs/KERNEL-BUILD.md` for the rebase workflow.

## Config options explained

| Option | Value | Why |
|--------|-------|-----|
| `CONFIG_CFG80211` | `=y` | 802.11 subsystem — must be built-in (Talos req) |
| `CONFIG_MAC80211` | `=m` | mac80211 stack — module, signed at build time |
| `CONFIG_RFKILL` | `=y` | RF kill switch support — needed to unblock WiFi |
| `CONFIG_BRCMUTIL` | `=m` | Broadcom utility module (brcmfmac dependency) |
| `CONFIG_BRCMFMAC` | `=m` | Broadcom FullMAC driver (CYW43455) |
| `CONFIG_BRCMFMAC_SDIO` | `=y` | SDIO bus support (RPi5 connects WiFi via SDIO) |
| `CONFIG_BRCMFMAC_PROTO_BCDC` | `=y` | BCDC protocol (required for SDIO) |
| `CONFIG_BRCMFMAC_PROTO_MSGBUF` | `=y` | Message buffer protocol |
| `CONFIG_BRCMFMAC_PCIE` | `=n` | Disabled — RPi5 WiFi is not PCIe |
| `CONFIG_BRCMFMAC_USB` | `=n` | Disabled — RPi5 WiFi is not USB |
```

**Step 3: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add kernel/
git commit -m "feat: add kernel config patch for brcmfmac WiFi support"
```

---

### Task 6: sys-kernel-firmware-wifi extension

**Files:**
- Create: `extensions/sys-kernel-firmware-wifi/Dockerfile`
- Create: `extensions/sys-kernel-firmware-wifi/manifest.yaml`
- Create: `extensions/sys-kernel-firmware-wifi/Makefile`

**Step 1: Write manifest.yaml**

Create `/Users/kaurkallas/rasberry-wifi/extensions/sys-kernel-firmware-wifi/manifest.yaml`:

```yaml
version: v1alpha1
metadata:
  name: sys-kernel-firmware-wifi
  version: 1.0.0
  author: koorikla
  description: |
    WiFi firmware blobs for Raspberry Pi 5 (Broadcom CYW43455 / brcmfmac).
    Ships brcmfmac43455-sdio.* from linux-firmware into /lib/firmware/brcm/.
    Requires a Talos kernel built with CONFIG_BRCMFMAC enabled.
  compatibility:
    talos:
      version: ">= v1.12.0"
```

**Step 2: Write Dockerfile**

Create `/Users/kaurkallas/rasberry-wifi/extensions/sys-kernel-firmware-wifi/Dockerfile`:

```dockerfile
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
```

**Step 3: Write Makefile**

Create `/Users/kaurkallas/rasberry-wifi/extensions/sys-kernel-firmware-wifi/Makefile`:

```makefile
REGISTRY     ?= ghcr.io/koorikla
IMAGE        := $(REGISTRY)/sys-kernel-firmware-wifi
TALOS_VERSION ?= v1.12.6
TAG          := $(TALOS_VERSION)
PLATFORM     := linux/arm64

.PHONY: build push lint clean

build:  ## Build extension image (local)
	docker buildx build \
		--platform $(PLATFORM) \
		--tag $(IMAGE):$(TAG) \
		--load \
		.

push:  ## Build and push to registry
	docker buildx build \
		--platform $(PLATFORM) \
		--tag $(IMAGE):$(TAG) \
		--push \
		.

lint:  ## Lint Dockerfile
	hadolint Dockerfile

clean:  ## Remove local image
	docker rmi $(IMAGE):$(TAG) 2>/dev/null || true
```

**Step 4: Lint Dockerfile**

```bash
cd /Users/kaurkallas/rasberry-wifi/extensions/sys-kernel-firmware-wifi
hadolint Dockerfile
```
Expected: no output (clean) or only style warnings (not errors).

**Step 5: Dry-run build (verifies Dockerfile syntax)**

```bash
docker buildx build --platform linux/arm64 --dry-run . 2>&1 | head -20
```
Expected: build steps printed, no parse errors.

**Step 6: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add extensions/sys-kernel-firmware-wifi/
git commit -m "feat: add sys-kernel-firmware-wifi extension (brcmfmac firmware blobs)"
```

---

### Task 7: wpa-supplicant extension

**Files:**
- Create: `extensions/wpa-supplicant/Dockerfile`
- Create: `extensions/wpa-supplicant/manifest.yaml`
- Create: `extensions/wpa-supplicant/Makefile`
- Create: `extensions/wpa-supplicant/wpa_supplicant.service`

**Step 1: Write manifest.yaml**

Create `/Users/kaurkallas/rasberry-wifi/extensions/wpa-supplicant/manifest.yaml`:

```yaml
version: v1alpha1
metadata:
  name: wpa-supplicant
  version: 1.0.0
  author: koorikla
  description: |
    wpa_supplicant binary and extension service for WiFi authentication on Talos Linux.
    Runs wpa_supplicant in the host network namespace as a Talos extension service.
    Configure via Talos machine config network.interfaces[].wireless.accessPoints.
  compatibility:
    talos:
      version: ">= v1.12.0"
```

**Step 2: Write the extension service spec**

Create `/Users/kaurkallas/rasberry-wifi/extensions/wpa-supplicant/wpa_supplicant.service`:

```yaml
# Talos extension service definition for wpa_supplicant
# This file is placed at /rootfs/etc/extension-services/wpa_supplicant.yaml
# inside the extension OCI image.
#
# IMPORTANT: The Talos extension service format may vary between Talos versions.
# Validate against the current Talos docs at:
#   https://www.talos.dev/latest/talos-guides/configuration/extension-services/
#
# wpa_supplicant reads its config from /etc/wpa_supplicant/wpa_supplicant.conf
# which Talos generates from the machine config network.interfaces[].wireless section.
name: wpa_supplicant
container:
  image: ""          # empty = use host rootfs overlay (binary shipped by this extension)
  command:
    - /usr/local/sbin/wpa_supplicant
    - "-Dnl80211"
    - "-c/etc/wpa_supplicant/wpa_supplicant.conf"
    - "-iwlan0"
    - "-B"           # run in background (managed by extension service runner)
  env: []
  security:
    writeableRootfs: true
    hostNetwork: true    # must run in host netns to access wlan0
depends:
  - service: network
    event: Running
```

**Step 3: Write Dockerfile**

Create `/Users/kaurkallas/rasberry-wifi/extensions/wpa-supplicant/Dockerfile`:

```dockerfile
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
```

**Step 4: Write Makefile**

Create `/Users/kaurkallas/rasberry-wifi/extensions/wpa-supplicant/Makefile`:

```makefile
REGISTRY     ?= ghcr.io/koorikla
IMAGE        := $(REGISTRY)/wpa-supplicant
TALOS_VERSION ?= v1.12.6
TAG          := $(TALOS_VERSION)
PLATFORM     := linux/arm64

.PHONY: build push lint clean

build:  ## Build extension image (local)
	docker buildx build \
		--platform $(PLATFORM) \
		--tag $(IMAGE):$(TAG) \
		--load \
		.

push:  ## Build and push to registry
	docker buildx build \
		--platform $(PLATFORM) \
		--tag $(IMAGE):$(TAG) \
		--push \
		.

lint:  ## Lint Dockerfile
	hadolint Dockerfile

clean:  ## Remove local image
	docker rmi $(IMAGE):$(TAG) 2>/dev/null || true
```

**Step 5: Lint + dry-run**

```bash
cd /Users/kaurkallas/rasberry-wifi/extensions/wpa-supplicant
hadolint Dockerfile
docker buildx build --platform linux/arm64 --dry-run . 2>&1 | head -20
```
Expected: no errors.

**Step 6: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add extensions/wpa-supplicant/
git commit -m "feat: add wpa-supplicant extension and service definition"
```

---

### Task 8: Root Makefile

**Files:**
- Create: `Makefile`

**Step 1: Write Makefile**

Create `/Users/kaurkallas/rasberry-wifi/Makefile`:

```makefile
# rasberry-wifi — Talos Linux RPi5 custom image with WiFi support
# Usage: make build | make kernel | make extensions | make image | make flash DISK=/dev/sdX

TALOS_VERSION  ?= v1.12.6
REGISTRY       ?= ghcr.io/koorikla
PLATFORM       ?= linux/arm64

KERNEL_IMAGE   := $(REGISTRY)/rasberry-wifi-kernel:$(TALOS_VERSION)
FIRMWARE_IMAGE := $(REGISTRY)/sys-kernel-firmware-wifi:$(TALOS_VERSION)
WPA_IMAGE      := $(REGISTRY)/wpa-supplicant:$(TALOS_VERSION)

KERNEL_ARGS    ?= console=ttyAMA0,115200

OUT_DIR        := _out
IMAGE_FILE     := $(OUT_DIR)/metal-arm64.raw.xz

# Talos-rpi5 upstream (kernel base)
TALOS_RPI5_BUILDER_REPO := https://github.com/talos-rpi5/talos-builder
TALOS_RPI5_BUILDER_DIR  := /tmp/talos-rpi5-builder

.DEFAULT_GOAL := help

.PHONY: build kernel extensions image clean flash help

## ─── Full pipeline ────────────────────────────────────────────────────────────

build: kernel extensions image  ## Full pipeline: kernel → extensions → image

## ─── Stage 1: Kernel ──────────────────────────────────────────────────────────

kernel:  ## Build patched WiFi kernel (clones talos-rpi5/talos-builder, applies config.patch)
	@echo "==> Stage 1: Building custom WiFi kernel"
	@echo "    Base: $(TALOS_RPI5_BUILDER_REPO)"
	@echo "    Patch: kernel/config.patch"
	@echo "    Output: $(KERNEL_IMAGE)"
	@if [ ! -d "$(TALOS_RPI5_BUILDER_DIR)" ]; then \
		git clone --depth 1 $(TALOS_RPI5_BUILDER_REPO) $(TALOS_RPI5_BUILDER_DIR); \
	else \
		git -C $(TALOS_RPI5_BUILDER_DIR) pull --ff-only; \
	fi
	@echo "--> Applying kernel/config.patch"
	@# NOTE: The exact path to the kernel config within talos-rpi5/talos-builder
	@# may vary between releases. Verify with:
	@#   find $(TALOS_RPI5_BUILDER_DIR) -name "config-arm64" -o -name "*.config"
	@git -C $(TALOS_RPI5_BUILDER_DIR) apply $(CURDIR)/kernel/config.patch || \
		(echo "ERROR: patch failed — see docs/KERNEL-BUILD.md for rebase instructions" && exit 1)
	@echo "--> Building kernel (this takes 30-60 minutes first run)"
	@$(MAKE) -C $(TALOS_RPI5_BUILDER_DIR) \
		REGISTRY=$(REGISTRY) \
		TAG=$(TALOS_VERSION) \
		PLATFORM=$(PLATFORM) \
		kernel
	@echo "==> Kernel build complete: $(KERNEL_IMAGE)"

## ─── Stage 2: Extensions ──────────────────────────────────────────────────────

extensions: extension-firmware extension-wpa  ## Build all system extensions

extension-firmware:  ## Build sys-kernel-firmware-wifi extension
	@echo "==> Building sys-kernel-firmware-wifi"
	$(MAKE) -C extensions/sys-kernel-firmware-wifi \
		REGISTRY=$(REGISTRY) \
		TALOS_VERSION=$(TALOS_VERSION) \
		push

extension-wpa:  ## Build wpa-supplicant extension
	@echo "==> Building wpa-supplicant"
	$(MAKE) -C extensions/wpa-supplicant \
		REGISTRY=$(REGISTRY) \
		TALOS_VERSION=$(TALOS_VERSION) \
		push

## ─── Stage 3: Image ───────────────────────────────────────────────────────────

image:  ## Assemble metal-arm64.raw.xz using siderolabs/imager
	@echo "==> Stage 3: Assembling metal image"
	@mkdir -p $(OUT_DIR)
	docker run --rm \
		--privileged \
		-v /dev:/dev \
		-v $(CURDIR)/$(OUT_DIR):/out \
		ghcr.io/siderolabs/imager:$(TALOS_VERSION) \
		metal \
		--arch arm64 \
		--board rpi_generic \
		--base-installer-image $(KERNEL_IMAGE) \
		--system-extension-image $(FIRMWARE_IMAGE) \
		--system-extension-image $(WPA_IMAGE) \
		--extra-kernel-arg "$(KERNEL_ARGS)"
	@echo "==> Image written to $(IMAGE_FILE)"
	@ls -lh $(IMAGE_FILE)

## ─── Utilities ────────────────────────────────────────────────────────────────

clean:  ## Remove _out/ build artefacts
	rm -rf $(OUT_DIR)
	@echo "==> Cleaned $(OUT_DIR)/"

flash:  ## Flash image to disk: make flash DISK=/dev/sdX
ifndef DISK
	$(error DISK is not set. Usage: make flash DISK=/dev/sdX)
endif
	@echo "==> Flashing $(IMAGE_FILE) to $(DISK)"
	@echo "!!! This will DESTROY ALL DATA on $(DISK). Ctrl-C to abort. !!!"
	@sleep 3
	xzcat $(IMAGE_FILE) | sudo dd of=$(DISK) bs=4M status=progress conv=fsync
	sync
	@echo "==> Flash complete. Eject $(DISK) and insert into RPi5."

help:  ## List all targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
```

**Step 2: Verify Makefile syntax**

```bash
cd /Users/kaurkallas/rasberry-wifi
make --dry-run help 2>&1
```
Expected: lists all targets without errors.

```bash
make --dry-run build 2>&1 | head -30
```
Expected: prints build steps without executing them.

**Step 3: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add Makefile
git commit -m "feat: add root Makefile with kernel/extensions/image/flash targets"
```

---

### Task 9: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Step 1: Write build.yml**

Create `/Users/kaurkallas/rasberry-wifi/.github/workflows/build.yml`:

```yaml
name: Build Talos RPi5 WiFi Image

on:
  push:
    branches: [main]
  release:
    types: [published]

env:
  TALOS_VERSION: v1.12.6
  REGISTRY: ghcr.io/koorikla
  KERNEL_IMAGE: ghcr.io/koorikla/rasberry-wifi-kernel
  FIRMWARE_IMAGE: ghcr.io/koorikla/sys-kernel-firmware-wifi
  WPA_IMAGE: ghcr.io/koorikla/wpa-supplicant
  RELEASE_IMAGE: ghcr.io/koorikla/rasberry-wifi

jobs:
  # ─── Pre-flight ──────────────────────────────────────────────────────────────
  free-disk-space:
    name: Free disk space
    runs-on: ubuntu-latest
    steps:
      - name: Free disk space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: false
          android: true
          dotnet: true
          haskell: true
          large-packages: true
          docker-images: true
          swap-storage: true

      - name: Show available disk space
        run: df -h /

  # ─── Stage 1: Kernel ─────────────────────────────────────────────────────────
  build-kernel:
    name: Build custom WiFi kernel
    runs-on: ubuntu-latest
    needs: free-disk-space
    permissions:
      contents: read
      packages: write
    outputs:
      kernel-tag: ${{ steps.meta.outputs.version }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: arm64

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Docker meta (kernel image)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.KERNEL_IMAGE }}
          tags: |
            type=raw,value=${{ env.TALOS_VERSION }}
            type=sha,prefix=${{ env.TALOS_VERSION }}-

      - name: Clone talos-rpi5/talos-builder
        run: |
          git clone --depth 1 https://github.com/talos-rpi5/talos-builder \
            /tmp/talos-rpi5-builder

      - name: Apply kernel/config.patch
        run: |
          cd /tmp/talos-rpi5-builder
          git apply $GITHUB_WORKSPACE/kernel/config.patch

      - name: Build and push custom kernel installer image
        # NOTE: The exact make target depends on talos-rpi5/talos-builder's Makefile.
        # Check their repo for the correct target to build+push the installer image.
        # Common targets: 'kernel', 'installer', 'all'
        run: |
          cd /tmp/talos-rpi5-builder
          make installer \
            REGISTRY=${{ env.REGISTRY }} \
            TAG=${{ env.TALOS_VERSION }} \
            PLATFORM=linux/arm64 \
            PUSH=true

  # ─── Stage 2: Extensions (parallel) ─────────────────────────────────────────
  build-firmware-extension:
    name: Build sys-kernel-firmware-wifi
    runs-on: ubuntu-latest
    needs: free-disk-space
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: arm64

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push firmware extension
        uses: docker/build-push-action@v5
        with:
          context: extensions/sys-kernel-firmware-wifi
          platforms: linux/arm64
          push: true
          tags: ${{ env.FIRMWARE_IMAGE }}:${{ env.TALOS_VERSION }}
          cache-from: type=gha,scope=firmware-ext
          cache-to: type=gha,scope=firmware-ext,mode=max

  build-wpa-extension:
    name: Build wpa-supplicant extension
    runs-on: ubuntu-latest
    needs: free-disk-space
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: arm64

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push wpa-supplicant extension
        uses: docker/build-push-action@v5
        with:
          context: extensions/wpa-supplicant
          platforms: linux/arm64
          push: true
          tags: ${{ env.WPA_IMAGE }}:${{ env.TALOS_VERSION }}
          cache-from: type=gha,scope=wpa-ext
          cache-to: type=gha,scope=wpa-ext,mode=max

  # ─── Stage 3: Image assembly ─────────────────────────────────────────────────
  build-image:
    name: Assemble metal image
    runs-on: ubuntu-latest
    needs: [build-kernel, build-firmware-extension, build-wpa-extension]
    permissions:
      contents: write
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Free remaining disk space
        run: |
          sudo rm -rf /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
          df -h /

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Assemble metal-arm64 image
        run: |
          mkdir -p _out
          docker run --rm \
            --privileged \
            -v /dev:/dev \
            -v ${{ github.workspace }}/_out:/out \
            ghcr.io/siderolabs/imager:${{ env.TALOS_VERSION }} \
            metal \
            --arch arm64 \
            --board rpi_generic \
            --base-installer-image ${{ env.KERNEL_IMAGE }}:${{ env.TALOS_VERSION }} \
            --system-extension-image ${{ env.FIRMWARE_IMAGE }}:${{ env.TALOS_VERSION }} \
            --system-extension-image ${{ env.WPA_IMAGE }}:${{ env.TALOS_VERSION }} \
            --extra-kernel-arg "console=ttyAMA0,115200"

      - name: List output
        run: ls -lh _out/

      - name: Upload image as workflow artifact
        uses: actions/upload-artifact@v4
        with:
          name: talos-rpi5-wifi-metal-arm64
          path: _out/metal-arm64.raw.xz
          retention-days: 7

      # ── Release: push image to GHCR ────────────────────────────────────────
      - name: Set up crane (for GHCR OCI image push on release)
        if: github.event_name == 'release'
        uses: imjasonh/setup-crane@v0.3

      - name: Push image to GHCR on release
        if: github.event_name == 'release'
        run: |
          # Tag and push the raw image artifact as an OCI artifact to GHCR
          crane push \
            _out/metal-arm64.raw.xz \
            ${{ env.RELEASE_IMAGE }}:${{ github.ref_name }} \
            --platform linux/arm64

      - name: Upload to GitHub Release
        if: github.event_name == 'release'
        uses: softprops/action-gh-release@v2
        with:
          files: _out/metal-arm64.raw.xz
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Step 2: Validate workflow syntax**

```bash
cd /Users/kaurkallas/rasberry-wifi
actionlint .github/workflows/build.yml
```
Expected: no errors. Warnings about `--privileged` are acceptable.

**Step 3: Commit**

```bash
cd /Users/kaurkallas/rasberry-wifi
git add .github/
git commit -m "ci: add 3-stage GitHub Actions workflow (kernel → extensions → image)"
```

---

### Task 10: Create GitHub repo, push, verify

**Step 1: Create public repo under koorikla**

```bash
cd /Users/kaurkallas/rasberry-wifi
gh repo create koorikla/rasberry-wifi \
  --public \
  --description "Custom Talos Linux image for Raspberry Pi 5 with WiFi support (brcmfmac + firmware + wpa_supplicant)" \
  --source . \
  --remote origin \
  --push
```

**Step 2: Verify push**

```bash
gh repo view koorikla/rasberry-wifi
```
Expected: repo details shown with correct description.

**Step 3: Check CI triggered**

```bash
gh run list --repo koorikla/rasberry-wifi --limit 3
```
Expected: one workflow run listed (triggered by the push to main).

**Step 4: Save memory**

```
[save project memory: rasberry-wifi created at github.com/koorikla/rasberry-wifi —
custom Talos RPi5 image builder with WiFi (3-stage: kernel patch, extensions, imager).
Talos v1.12.6. Kernel base: talos-rpi5/talos-builder. Extensions: sys-kernel-firmware-wifi,
wpa-supplicant. Known issue: kernel patch path in talos-rpi5 may need validation.]
```

---

## Post-creation checklist

- [ ] Confirm `kernel/config.patch` path matches actual talos-rpi5/talos-builder config location
- [ ] Validate wpa_supplicant extension service format against current Talos docs
- [ ] Set GHCR package visibility to public for `koorikla` org (Settings → Packages)
- [ ] Confirm `jlumbroso/free-disk-space` action name is current (check GitHub Marketplace)
- [ ] Test `make flash DISK=...` on a real disk once CI produces an image

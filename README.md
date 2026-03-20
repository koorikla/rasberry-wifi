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

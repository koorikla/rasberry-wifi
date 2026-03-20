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

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

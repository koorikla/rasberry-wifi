# kernel/

Contains the script and reference config that add WiFi support to the
[talos-rpi5/talos-builder](https://github.com/talos-rpi5/talos-builder) kernel.

## Files

- `apply-config.sh` — shell script that sets each WiFi config option via `sed`.
  Handles all three forms: `CONFIG_FOO=old`, `# CONFIG_FOO is not set`, and absent entries.
  **This is what the CI and `make kernel` use.**
- `config.patch` — human-readable reference showing what config values get applied.
  Not a unified diff; do not use with `patch(1)` or `git apply`.

## How it's used

`make kernel` and the CI `build-kernel` job:
1. Clone `talos-rpi5/talos-builder`
2. Run `make checkouts patches` — clones `siderolabs/pkgs`, `siderolabs/talos`,
   and `talos-rpi5/sbc-raspberrypi5`, then applies the RPi5 patches via `git am`
3. Run `apply-config.sh checkouts/pkgs/kernel/build/config-arm64` — adds WiFi options
4. Run `make kernel REGISTRY=ghcr.io REGISTRY_USERNAME=koorikla PUSH=true` — builds and pushes

The CI uses `ubuntu-24.04-arm` (native ARM64). An x86 runner with QEMU would take 6+ hours.

## Updating after talos-rpi5 releases

See `docs/KERNEL-BUILD.md` for the rebase workflow. The `apply-config.sh` script is robust
against config file changes — it finds and replaces each option regardless of line number.

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

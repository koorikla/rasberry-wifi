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

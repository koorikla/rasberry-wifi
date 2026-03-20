#!/usr/bin/env bash
# Apply WiFi kernel config options to a Talos Linux kernel config file.
#
# Usage: ./apply-config.sh <path-to-config-arm64>
#
# The config file lives inside the siderolabs/pkgs checkout after
# talos-rpi5/talos-builder runs `make checkouts patches`:
#   checkouts/pkgs/kernel/build/config-arm64
#
# Handles all three forms:
#   CONFIG_FOO=old_value       → CONFIG_FOO=new_value
#   # CONFIG_FOO is not set   → CONFIG_FOO=new_value
#   (absent)                  → appended at end of file
set -euo pipefail

CONFIG="${1:?Usage: $0 <path-to-config>}"

set_config() {
    local opt="$1" val="$2"
    if grep -q "^${opt}=" "${CONFIG}"; then
        sed -i "s|^${opt}=.*|${opt}=${val}|" "${CONFIG}"
    elif grep -q "^# ${opt} is not set" "${CONFIG}"; then
        sed -i "s|^# ${opt} is not set|${opt}=${val}|" "${CONFIG}"
    else
        echo "${opt}=${val}" >> "${CONFIG}"
    fi
}

echo "==> Applying WiFi kernel config to ${CONFIG}"

# 802.11 subsystem — must be built-in (=y), not a module; Talos networking requirement
set_config CONFIG_CFG80211 y
set_config CONFIG_CFG80211_WEXT y

# mac80211 stack
set_config CONFIG_MAC80211 m
set_config CONFIG_MAC80211_MESH n

# RF kill switch (needed to unblock the WiFi interface)
set_config CONFIG_RFKILL y
set_config CONFIG_RFKILL_INPUT y

# Broadcom FullMAC driver for CYW43455 (RPi5 onboard WiFi via SDIO)
set_config CONFIG_BRCMUTIL m
set_config CONFIG_BRCMFMAC m
set_config CONFIG_BRCMFMAC_SDIO y
set_config CONFIG_BRCMFMAC_PROTO_BCDC y
set_config CONFIG_BRCMFMAC_PROTO_MSGBUF y
set_config CONFIG_BRCMFMAC_PCIE n
set_config CONFIG_BRCMFMAC_USB n

echo "==> Done. Current WiFi-related config values:"
grep -E "^(CONFIG_CFG80211|CONFIG_MAC80211|CONFIG_RFKILL|CONFIG_BRCM)" "${CONFIG}" | sort

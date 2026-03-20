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

.PHONY: build kernel extensions extension-firmware extension-wpa image clean flash help

## ─── Full pipeline ────────────────────────────────────────────────────────────

build: kernel extensions image  ## Full pipeline: kernel → extensions → image

## ─── Stage 1: Kernel ──────────────────────────────────────────────────────────

kernel:  ## Build patched WiFi kernel (clones talos-rpi5/talos-builder, runs apply-config.sh)
	@echo "==> Stage 1: Building custom WiFi kernel"
	@echo "    Base: $(TALOS_RPI5_BUILDER_REPO)"
	@echo "    Config script: kernel/apply-config.sh"
	@if [ ! -d "$(TALOS_RPI5_BUILDER_DIR)" ]; then \
		git clone --depth 1 $(TALOS_RPI5_BUILDER_REPO) $(TALOS_RPI5_BUILDER_DIR); \
	else \
		git -C $(TALOS_RPI5_BUILDER_DIR) pull --ff-only; \
	fi
	@echo "--> Setting up talos-rpi5 build (make checkouts patches)"
	@$(MAKE) -C $(TALOS_RPI5_BUILDER_DIR) checkouts patches
	@echo "--> Applying WiFi kernel config"
	@bash $(CURDIR)/kernel/apply-config.sh \
		$(TALOS_RPI5_BUILDER_DIR)/checkouts/pkgs/kernel/build/config-arm64
	@echo "--> Building kernel (this takes 30-60 minutes first run)"
	@$(MAKE) -C $(TALOS_RPI5_BUILDER_DIR) \
		REGISTRY=ghcr.io \
		REGISTRY_USERNAME=koorikla \
		PUSH=true \
		PLATFORM=$(PLATFORM) \
		kernel
	@echo "==> Kernel build complete"

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

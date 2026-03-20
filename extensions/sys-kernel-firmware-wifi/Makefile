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

# stop on error, no built in rules, run silently
MAKEFLAGS="-S -s -r"

# get tag and commit information
IMAGE_COMMIT := $(shell git log -1 | head -n 1 | cut -d" " -f2)
IMAGE_TAG := $(shell git tag --contains ${IMAGE_COMMIT})

# set the version from the tag and commit details
IMAGE_VERSION := $(or $(IMAGE_TAG),$(IMAGE_COMMIT))
ifneq ($(shell git status --porcelain),)
    IMAGE_VERSION := $(IMAGE_VERSION)-dirty
endif

# set the image name
IMAGE_NAME := "ghcr.io/uwcip/jupyterhub-base-notebook"
IMAGE_ID := "${IMAGE_NAME}:${IMAGE_VERSION}"

all: build

.PHONY: build
build:
	@echo "building image for ${IMAGE_ID}"
	docker build --progress plain -t $(IMAGE_NAME):latest .

.PHONY: push
push: build
	@echo "pushing $(IMAGE_ID)"
	docker tag $(IMAGE_NAME):latest $(IMAGE_ID)
	docker push $(IMAGE_ID)

.PHONY: clean
clean:
	@echo "removing built image ${IMAGE_ID}"
	docker image rm -f $(IMAGE_NAME):latest $(IMAGE_ID)

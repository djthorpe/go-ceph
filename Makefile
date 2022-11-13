DOCKERBIN := $(shell which docker)
GOBIN := $(shell which go)
NAME := "go-ceph"
TAG := v17

# Build the docker image
all: dependencies docker-build

docker-build:
	${DOCKERBIN} build --tag "${NAME}:${TAG}" --build-arg VERSION=${TAG} --build-arg BUILDPLATFORM=$(shell ${GOBIN} env GOARCH) .

FORCE:

dependencies:
ifeq (,${DOCKERBIN})
        $(error "Missing docker binary")
endif
ifeq (,${GOBIN})
        $(error "Missing go binary")
endif


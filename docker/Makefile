VERSION := $(shell git rev-parse --short HEAD)
LDFLAGS := "-s -w -X 'github.com/rubycdp/ferrum/docker/internal/config.Version=$(VERSION)'"
NAME := "driver"
BIN := "bin/$(NAME)"

.PHONY: build run fmt formatting-check lint vet test clean docker* version

CGO_ENABLED ?= 0
build: fmt
	CGO_ENABLED=$(CGO_ENABLED) go build -o $(BIN) -ldflags=$(LDFLAGS) .

run: build
	$(BIN)

fmt:
	go fmt ./...

formatting-check:
	@gofmt -l -d $$(find . -not -path '*/\.*' -type f -name '*.go') | grep ^ && exit 1 || true > /dev/null 2>&1

lint:
	staticcheck ./...

vet:
	go vet ./...

test:
	go test -race ./...

clean:
	rm -f bin/*

BROWSER ?= chromium
IMAGE ?= ghcr.io/rubycdp/$(BROWSER)
TAG ?= latest

docker.build:
	docker buildx build --load --build-arg BROWSER=$(BROWSER) --build-arg VERSION=$(VERSION) -t $(IMAGE):$(TAG) .

docker.run:
	docker run --rm --name $(BROWSER) -p 3000:3000 $(IMAGE):$(TAG)

docker.stop:
	docker stop $(BROWSER)

docker.sh:
	docker run --rm -it --entrypoint /bin/bash $(IMAGE):$(TAG)

docker.ssh:
	docker exec -it $(BROWSER) /bin/bash

version:
	@echo $(VERSION)

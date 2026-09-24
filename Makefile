PLUGIN_ID := oai-basispoints
BUILD_DIR := build/linux/amd64
OUTPUT := $(BUILD_DIR)/$(PLUGIN_ID).so

.PHONY: build test vet clean

build:
	mkdir -p $(BUILD_DIR)
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -trimpath -buildmode=c-shared -o $(OUTPUT) ./cmd/basispoints

test:
	go test ./...

vet:
	go vet ./...

clean:
	rm -rf build

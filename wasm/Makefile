SHELL := /usr/bin/env bash

FLYE_VERSION ?= 2.9.6
IMAGE ?= flye-wasm-native:$(FLYE_VERSION)
C2W ?= c2w
WASMTIME ?= wasmtime
MODULE ?= dist/flye-$(FLYE_VERSION)-complete.wasm

.PHONY: all image wasm smoke parity verify clean

all: wasm

image:
	docker build --platform linux/amd64 --tag "$(IMAGE)" --file Dockerfile ..

wasm: image
	mkdir -p "$(dir $(MODULE))"
	"$(C2W)" --target-arch=amd64 "$(IMAGE)" "$(MODULE)"
	printf '0061736d' | xxd -r -p | cmp -n 4 - "$(MODULE)"
	sha256sum "$(MODULE)" > "$(MODULE).sha256"

smoke:
	FLYE_NATIVE_IMAGE="$(IMAGE)" FLYE_WASM_MODULE="$(abspath $(MODULE))" WASMTIME="$(WASMTIME)" \
		bash verify/cli-smoke.sh

parity:
	FLYE_NATIVE_IMAGE="$(IMAGE)" FLYE_WASM_MODULE="$(abspath $(MODULE))" WASMTIME="$(WASMTIME)" \
		bash verify/end-to-end.sh

verify: smoke parity

clean:
	rm -rf dist

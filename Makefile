.PHONY: test image-test box-test

# Host-side tests: tv, the installer.
test:
	uv run --with pytest pytest -q tests

# Builds the image; TV_RUNTIME picks the runtime (default: Apple's container).
image-test:
	sh tests/image_test.sh

# Starts the box from the image and checks what it sets up (no tailnet needed).
box-test: image-test
	sh tests/box_test.sh

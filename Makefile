.PHONY: test image-test

# Host-side tests: tv, the installer.
test:
	uv run --with pytest pytest -q tests

# Builds the image; TV_RUNTIME picks the runtime (default: Apple's container).
image-test:
	sh tests/image_test.sh

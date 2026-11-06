.PHONY: test image-test box-test app app-test project app-release app-publish

# Host-side tests: tv, the installer.
test:
	uv run --with pytest pytest -q tests

# Builds the image; TV_RUNTIME picks the runtime (default: Apple's container).
image-test:
	sh tests/image_test.sh

# Starts the box from the image and checks what it sets up (no tailnet needed).
box-test: image-test
	sh tests/box_test.sh

# The Mac app (mac/): XcodeGen makes the project, xcodebuild builds it.
XCODEBUILD = xcodebuild -project mac/TerminalValues.xcodeproj -scheme TerminalValues -derivedDataPath mac/build -quiet

# The project lists every source file, so it's made afresh each time.
project:
	cd mac && xcodegen generate --quiet

app: project
	$(XCODEBUILD) build

app-test: project
	@mkdir -p mac/build
	@xcodebuild -project mac/TerminalValues.xcodeproj -scheme TerminalValues -derivedDataPath mac/build \
	    test > mac/build/test.log 2>&1; s=$$?; grep -E '✘|: error:|Test run with' mac/build/test.log | grep -v CoreSimulator; exit $$s

# Sparkle's tools sign the update with its private key, so the download is
# checked against the digest GitHub gives for the release asset. The same
# version as the app's Sparkle (mac/project.yml).
SPARKLE_VERSION = 2.10.1
SPARKLE_SHA256 = 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_BIN = mac/build/sparkle/bin

# A signed, notarized release, made on the Mac that holds the signing keys
# (GitHub holds none of them): from a checkout of the tag, with release.sh's
# variables set, make app-release VERSION=0.1.0, then make app-publish
# VERSION=0.1.0 puts the .dmg and Sparkle's feed on the GitHub release.
app-release: $(SPARKLE_BIN)/generate_appcast
	SPARKLE_BIN=$(SPARKLE_BIN) sh mac/scripts/release.sh $(VERSION)

app-publish:
	gh release create v$(VERSION) --verify-tag --title "Terminal Values v$(VERSION)" --generate-notes \
	    mac/build/release/feed/Terminal-Values-$(VERSION).dmg mac/build/release/feed/appcast.xml

$(SPARKLE_BIN)/generate_appcast:
	@mkdir -p mac/build/sparkle
	curl -fsSL -o mac/build/sparkle.tar.xz \
	    https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz
	echo "$(SPARKLE_SHA256)  mac/build/sparkle.tar.xz" | shasum -a 256 -c -
	tar -xJ -C mac/build/sparkle -f mac/build/sparkle.tar.xz
	rm mac/build/sparkle.tar.xz

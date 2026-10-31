.PHONY: test image-test box-test app app-test project app-release

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

# A signed, notarized release by hand (normally GitHub Actions does it, on a
# version tag): make app-release VERSION=0.1.0, with release.sh's variables set.
app-release:
	sh mac/scripts/release.sh $(VERSION)

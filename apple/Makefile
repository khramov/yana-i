# Builds and tests the macOS app without an Apple Developer account. See README.md for signing and iCloud.

XCODEBUILD = xcodebuild -project YanaMac/YanaMac.xcodeproj -destination 'platform=macOS'
UNSIGNED = CODE_SIGNING_ALLOWED=NO

.PHONY: build desktop test test-kit test-app test-release test-ui

## build: build the app (Debug, unsigned)
build:
	$(XCODEBUILD) -scheme YanaMac build $(UNSIGNED)

## desktop: build the app in Release (unsigned) and copy it to ~/Desktop, replacing any earlier copy
desktop:
	$(XCODEBUILD) -scheme YanaMac -configuration Release build $(UNSIGNED)
	@products="$$($(XCODEBUILD) -scheme YanaMac -configuration Release -showBuildSettings $(UNSIGNED) 2>/dev/null \
		| sed -n 's/^ *BUILT_PRODUCTS_DIR = //p')"; \
	rm -rf ~/Desktop/YanaMac.app 2>/dev/null || { echo "Cannot replace ~/Desktop/YanaMac.app. Move it to the Trash," \
		"or allow your terminal under System Settings › Privacy & Security › App Management." >&2; exit 1; }; \
	ditto "$$products/YanaMac.app" ~/Desktop/YanaMac.app && echo "Copied to ~/Desktop/YanaMac.app"

## test: run the package tests and the app tests
test: test-kit test-app

## test-kit: run the YanaKit package tests
test-kit:
	YanaKit/test.sh

## test-app: run the app tests (Debug, unsigned)
test-app:
	$(XCODEBUILD) -scheme YanaMac test $(UNSIGNED)

## test-release: run the app tests in Release, where some SwiftData predicate failures only show up
test-release:
	$(XCODEBUILD) -scheme YanaMac -configuration Release test $(UNSIGNED) ENABLE_TESTABILITY=YES

## test-ui: run the UI tests (signed ad hoc)
test-ui:
	YanaMac/test-ui.sh

APP      := AirControl
BUNDLE   := build/$(APP).app
BINARY   := .build/release/$(APP)
# Prefer a real identity so macOS permission grants (camera now, Accessibility
# in M3) survive rebuilds; fall back to ad-hoc if none is installed.
IDENTITY := $(shell security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
ifeq ($(IDENTITY),)
IDENTITY := -
endif

VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
UNIVERSAL := .build/apple/Products/Release/$(APP)

.PHONY: run bundle build clean dist

# Shareable DMG: universal (arm64 + x86_64) release build + install notes.
# Signed with whatever identity is installed — WITHOUT a paid Developer ID +
# notarization, recipients must approve it once in System Settings → Privacy
# & Security → "Open Anyway" (covered in READ ME FIRST.txt).
dist:
	swift build -c release --arch arm64 --arch x86_64
	rm -rf dist
	mkdir -p dist/stage/$(APP).app/Contents/MacOS dist/stage/$(APP).app/Contents/Resources
	cp Info.plist dist/stage/$(APP).app/Contents/Info.plist
	cp $(UNIVERSAL) dist/stage/$(APP).app/Contents/MacOS/$(APP)
	cp AppIcon.icns dist/stage/$(APP).app/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(IDENTITY)" dist/stage/$(APP).app
	cp "READ ME FIRST.txt" dist/stage/
	ln -s /Applications dist/stage/Applications
	hdiutil create -volname "AirControl $(VERSION)" -srcfolder dist/stage \
		-ov -format UDZO "dist/AirControl-$(VERSION).dmg"
	@echo "==> dist/AirControl-$(VERSION).dmg"

run: bundle
	open $(BUNDLE)

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	cp AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(IDENTITY)" $(BUNDLE)

build:
	swift build -c release

clean:
	rm -rf .build build

APP      := AirControl
BUNDLE   := build/$(APP).app
BINARY   := .build/release/$(APP)
# Prefer a real identity so macOS permission grants (camera now, Accessibility
# in M3) survive rebuilds; fall back to ad-hoc if none is installed.
IDENTITY := $(shell security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
ifeq ($(IDENTITY),)
IDENTITY := -
endif

.PHONY: run bundle build clean

run: bundle
	open $(BUNDLE)

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	codesign --force --sign "$(IDENTITY)" $(BUNDLE)

build:
	swift build -c release

clean:
	rm -rf .build build

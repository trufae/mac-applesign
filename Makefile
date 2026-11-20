# AppleSign: macOS front-end for node-applesign (arm64 only)
#
#   make            build the app (builds the applesign SEA first if missing)
#   make run        build and launch
#   make install    copy AppleSign.app to $(PREFIX)
#   make uninstall  remove it from $(PREFIX)
#   make dmg        build build/AppleSign-$(VERSION)-arm64.dmg
#   make applesign  rebuild the applesign SEA from $(APPLESIGN_SRC)

CONFIG ?= Release
PREFIX ?= /Applications
APPLESIGN_SRC ?= ../node-applesign
VERSION ?= $(shell sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' AppleSign.xcodeproj/project.pbxproj | head -n 1)
IDENTITY ?= -

DERIVED = build/dd
APP = $(DERIVED)/Build/Products/$(CONFIG)/AppleSign.app
DMG = build/AppleSign-$(VERSION)-arm64.dmg

XCODEBUILD = xcodebuild -project AppleSign.xcodeproj -scheme AppleSign \
	-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
	-destination 'platform=macOS,arch=arm64' \
	MARKETING_VERSION=$(VERSION)

all: vendor/applesign
	$(XCODEBUILD) build

vendor/applesign:
	./scripts/build-applesign.sh $(APPLESIGN_SRC)

applesign:
	./scripts/build-applesign.sh $(APPLESIGN_SRC)

run: all
	-pkill -x AppleSign
	open $(APP)

install: all
	rm -rf "$(PREFIX)/AppleSign.app"
	ditto "$(APP)" "$(PREFIX)/AppleSign.app"
	@echo "Installed $(PREFIX)/AppleSign.app"

uninstall:
	-pkill -x AppleSign
	rm -rf "$(PREFIX)/AppleSign.app"

sign: all
	./scripts/codesign-app.sh "$(APP)" "$(IDENTITY)"

dmg: sign
	./scripts/make-dmg.sh "$(APP)" "$(DMG)"

clean:
	rm -rf build

distclean: clean
	rm -rf vendor .cache

.PHONY: all applesign run install uninstall sign dmg clean distclean

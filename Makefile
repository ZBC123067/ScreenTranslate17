ARCHS = arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = roothide
DISABLE_ROOTLESS_COMPAT_WARNING = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ScreenTranslate17
ScreenTranslate17_FILES = Tweak.xm \
    Sources/STCommon.m Sources/STPreferences.m Sources/STCache.m Sources/STPrivacy.m \
    Sources/STTranslationService.m Sources/STOCRService.m Sources/STTextScanner.m \
    Sources/STOverlayManager.m Sources/STRegionSelector.m Sources/STInputHelper.m Sources/STManager.m
ScreenTranslate17_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Sources -Wno-deprecated-declarations
ScreenTranslate17_FRAMEWORKS = UIKit Foundation Vision CoreGraphics QuartzCore ImageIO
ScreenTranslate17_LIBRARIES = roothide
ScreenTranslate17_ENTITLEMENTS = entitlements.plist
include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = ScreenTranslate17Prefs
ScreenTranslate17Prefs_FILES = Preferences/STRootListController.m Sources/STCommon.m Sources/STPreferences.m Sources/STCache.m Sources/STPrivacy.m Sources/STTranslationService.m
ScreenTranslate17Prefs_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Sources -Wno-deprecated-declarations
ScreenTranslate17Prefs_FRAMEWORKS = UIKit Foundation
# RootHide's distributed SDK intentionally omits a link stub for the private
# Preferences framework. This bundle is loaded by the Settings process, where
# those Objective-C classes are already present, so leave them for runtime lookup.
ScreenTranslate17Prefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
ScreenTranslate17Prefs_LIBRARIES = roothide
ScreenTranslate17Prefs_ENTITLEMENTS = entitlements.plist
ScreenTranslate17Prefs_INSTALL_PATH = /Library/PreferenceBundles
ScreenTranslate17Prefs_RESOURCE_DIRS = Preferences/Resources
ScreenTranslate17Prefs_RESOURCE_FILES = Preferences/Info.plist
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	cp Preferences/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ScreenTranslate17.plist

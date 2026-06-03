ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTubeMusic
TARGET = iphone:clang:16.5:13.0
PACKAGE_VERSION = 1.0.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTMusicDiscordRPC
$(TWEAK_NAME)_FILES = Tweak.m DiscordRPCManager.m SettingsViewController.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
$(TWEAK_NAME)_FRAMEWORKS = UIKit MediaPlayer Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

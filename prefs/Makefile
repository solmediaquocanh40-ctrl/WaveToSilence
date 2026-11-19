TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WaveToSilencePrefs
WaveToSilencePrefs_FILES = WSRootListController.m
WaveToSilencePrefs_FRAMEWORKS = UIKit
WaveToSilencePrefs_INSTALL_PATH = /Library/PreferenceBundles
WaveToSilencePrefs_CFLAGS = -fobjc-arc
WaveToSilencePrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

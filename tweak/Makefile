TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WaveToSilence
WaveToSilence_FILES = Tweak.x
WaveToSilence_CFLAGS = -fobjc-arc
WaveToSilence_FRAMEWORKS = UIKit CallKit

include $(THEOS_MAKE_PATH)/tweak.mk

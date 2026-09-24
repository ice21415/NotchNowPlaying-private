TARGET := iphone:clang:latest:15.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
THEOS_PACKAGE_DIR := ../build-packages-backlight-flow-probe

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := NNPBacklightFlowProbe
NNPBacklightFlowProbe_FILES := Tweak.xm
NNPBacklightFlowProbe_CFLAGS := -fobjc-arc -fvisibility=hidden -fno-ident
NNPBacklightFlowProbe_LDFLAGS := -Wl,-dead_strip -Wl,-undefined,dynamic_lookup
NNPBacklightFlowProbe_FRAMEWORKS := Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

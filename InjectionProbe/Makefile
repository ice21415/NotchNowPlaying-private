TARGET := iphone:clang:latest:15.0
ARCHS := arm64e
INSTALL_TARGET_PROCESSES := SpringBoard
THEOS_PACKAGE_DIR := build-packages

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := NNPInjectionProbe
NNPInjectionProbe_FILES := Probe.c
NNPInjectionProbe_CFLAGS := -fvisibility=hidden -fno-ident
NNPInjectionProbe_LDFLAGS := -Wl,-dead_strip -lsubstrate
NNPInjectionProbe_FRAMEWORKS := CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

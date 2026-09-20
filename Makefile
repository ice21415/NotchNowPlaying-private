TARGET := iphone:clang:latest:15.0
ARCHS := arm64e
INSTALL_TARGET_PROCESSES := SpringBoard
THEOS_PACKAGE_DIR := build-packages

DEBUG := 0
STRIP := 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := NotchNowPlaying
NotchNowPlaying_FILES := Tweak.xm NNPState.m NNPView.m NNPController.m
NNP_SAFE_BOOT_TEST ?= 1
NNP_DEBUG_SHOW_WHILE_UNLOCKED ?= 0
NNP_ALLOW_ALL_MEDIA ?= 0
NotchNowPlaying_CFLAGS := -fobjc-arc -DNNP_SAFE_BOOT_TEST=$(NNP_SAFE_BOOT_TEST) -DNNP_DEBUG_SHOW_WHILE_UNLOCKED=$(NNP_DEBUG_SHOW_WHILE_UNLOCKED) -DNNP_ALLOW_ALL_MEDIA=$(NNP_ALLOW_ALL_MEDIA) -fvisibility=hidden -fno-ident
NotchNowPlaying_LDFLAGS := -Wl,-dead_strip
NotchNowPlaying_FRAMEWORKS := UIKit

ifeq ($(NNP_SAFE_BOOT_TEST),0)
NotchNowPlaying_FILES += NNPMediaController.m
NotchNowPlaying_LDFLAGS += -Wl,-undefined,dynamic_lookup
endif

include $(THEOS_MAKE_PATH)/tweak.mk

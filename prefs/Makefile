TARGET := iphone:clang:latest:15.0
ARCHS := arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := NotchNowPlayingPrefs
NotchNowPlayingPrefs_FILES := NNPPrefsListController.m NNPPowerController.m NNPPowerChartView.m
NotchNowPlayingPrefs_INSTALL_PATH := /Library/PreferenceBundles
NotchNowPlayingPrefs_CFLAGS := -fobjc-arc -I.. -fvisibility=hidden
NotchNowPlayingPrefs_FRAMEWORKS := UIKit
NotchNowPlayingPrefs_LDFLAGS := -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

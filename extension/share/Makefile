# the share sheet extension: its own small executable, started at _NSExtensionMain, which exists from ios 8
TARGET := iphone:clang:14.5:8.0
ARCHS ?= armv7 arm64

include $(THEOS)/makefiles/common.mk
THEOS_VENDOR_INCLUDE_PATH := $(shell mkdir -p ../../build/novendor && touch ../../build/novendor/.git && cd ../../build/novendor && pwd)

APPEX_NAME = NoshigramShare
NoshigramShare_FILES = noshi_share_extension.m
NoshigramShare_USE_MODULES = 0
NoshigramShare_CFLAGS = -std=gnu99 -fno-objc-arc -fblocks -O2 -g -Wall -Wextra -Werror
NoshigramShare_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
NoshigramShare_INSTALL_PATH = /Applications/Noshigram.app/PlugIns
NoshigramShare_CODESIGN_FLAGS = -S../../packaging/entitlements-share.plist

include $(THEOS_MAKE_PATH)/appex.mk

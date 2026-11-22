# the ios build of noshigram with theos: the app, its share extension, the deb (`make package`) and the ipa
# (`make package PACKAGE_FORMAT=ipa`). the host tests stay in tests/Makefile (`make test`)
#
# needs: THEOS, the ios toolchain and the iPhoneOS14.5 sdk of theos/sdks, the static deps from
# scripts/build_deps.sh in deps/<slice>, and NOSHI_API_ID / NOSHI_API_HASH in the environment
# (or in local/credentials.env)

# ios 7 and later, on armv7 (iphone 4s, 5, 5c, ipad 2 to 4, ipad mini) and arm64 devices alike
TARGET := iphone:clang:14.5:7.0
# release flags by default: a theos debug build defines DEBUG, which turns on the self checks of rlottie
DEBUG ?= 0
ARCHS ?= armv7 arm64
INSTALL_TARGET_PROCESSES = Noshigram

-include local/credentials.env

DEPS ?= $(CURDIR)/deps

include $(THEOS)/makefiles/common.mk

# the headers theos vendors for tweaks shadow the sdk (MobileCoreServices among them), the app reads the sdk only
THEOS_VENDOR_INCLUDE_PATH := $(shell mkdir -p build/novendor && touch build/novendor/.git && cd build/novendor && pwd)

# host side: tests and the tl tables, the ios toolchain cannot build host programs
PYTHON  ?= python3
SCHEMAS := schemas/api.tl schemas/mtproto.tl schemas/secret.tl
TLGEN   := $(PYTHON) tools/tlgen.py

.PHONY: test test-icons test-video sanitize generate check-generated credentials stage-resources clean-bundle

test:
	$(MAKE) -C tests test

test-icons:
	$(PYTHON) -m unittest discover -s tests -p test_app_icons.py

test-video:
	$(MAKE) -C tests/video test

sanitize:
	$(MAKE) -C tests sanitize

generate:
	$(TLGEN) --out core/tl/generated $(SCHEMAS)

check-generated:
	@rm -rf build/generated-check
	@$(TLGEN) --out build/generated-check $(SCHEMAS)
	@diff -r build/generated-check core/tl/generated && echo "generated tl tables are current"

# the api id and hash never enter the repository
credentials:
	@bash scripts/gen_credentials.sh build/generated/noshi_credentials.h

# the flat resources of the bundle and its Info.plist, copied into the .app by theos
stage-resources:
	@bash scripts/stage_bundle.sh build/bundle
	@cp packaging/Info.plist build/bundle/Info.plist

# theos copies the resources over the bundle of the last build and never takes a file away, so a picture removed from the
# repository stayed in every incremental deb; the bundle is made anew from the staged files and the binaries of each arch
clean-bundle:
	@rm -rf $(THEOS_OBJ_DIR)/Noshigram.app

before-all:: credentials stage-resources clean-bundle

# ---- sources -------------------------------------------------------------------------------------------

WEBP_FILES   := $(wildcard third_party/libwebp/src/*/*.c)
OPUS_FILES   := $(wildcard third_party/opus/celt/*.c third_party/opus/silk/*.c third_party/opus/silk/fixed/*.c \
                  third_party/opus/src/*.c third_party/ogg/src/*.c)
ZBAR_FILES   := $(addprefix third_party/zbar/zbar/,config.c error.c symbol.c image.c refcnt.c img_scanner.c scanner.c \
                  decoder.c misc.c decoder/qr_finder.c qrcode/qrdec.c qrcode/qrdectxt.c qrcode/rs.c qrcode/isaac.c \
                  qrcode/bch15_5.c qrcode/binarize.c qrcode/util.c)
RLOTTIE_FILES := $(wildcard third_party/rlottie/src/*/*.cpp third_party/rlottie/src/*/*/*.cpp)
TGVOIP_FILES := $(wildcard third_party/libtgvoip/*.cpp third_party/libtgvoip/audio/*.cpp \
                  third_party/libtgvoip/os/posix/*.cpp third_party/libtgvoip/os/darwin/*.cpp)
CORE_FILES   := $(wildcard core/*/*.c core/tl/generated/*.c)
APP_FILES    := $(wildcard app/*/*.m app/*/*/*.m)

CORE_DIRS := $(sort $(dir $(wildcard core/*/*.h))) core/tl/generated/
APP_DIRS  := $(sort $(dir $(wildcard app/*/*.h app/*/*/*.h)))
CORE_INCLUDES := $(addprefix -I,$(CORE_DIRS)) -isystem $(DEPS)/$(THEOS_CURRENT_ARCH)/include \
                 -Ithird_party/opus/include -Ithird_party/ogg/include

# the c core is held to the strict warnings, upstream libraries build as they ship
STRICT_C := -std=c99 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion
VENDOR_CXX := -std=c++14 -fvisibility=hidden -w

$(foreach f,$(WEBP_FILES),$(eval $(f)_CFLAGS = -std=c99 -w -Ithird_party/libwebp))
$(foreach f,$(OPUS_FILES),$(eval $(f)_CFLAGS = -std=c99 -w -DOPUS_BUILD -DFIXED_POINT -DDISABLE_FLOAT_API -DVAR_ARRAYS \
    -DPACKAGE_VERSION=\"1.5.2\" -Ithird_party/opus/include -Ithird_party/opus/celt -Ithird_party/opus/silk \
    -Ithird_party/opus/silk/fixed -Ithird_party/opus/src -Ithird_party/ogg/include))
# NOSHI_ZBAR_IOS keeps the timer of zbar off the posix timers ios lacks
$(foreach f,$(ZBAR_FILES),$(eval $(f)_CFLAGS = -std=gnu99 -w -DNOSHI_ZBAR_IOS -Ithird_party/zbar/include \
    -Ithird_party/zbar/zbar -Ithird_party/zbar/zbar/decoder -Ithird_party/zbar/zbar/qrcode))
# the portable raster path: the neon asm needs a build of its own
$(foreach f,$(RLOTTIE_FILES),$(eval $(f)_CFLAGS = $(VENDOR_CXX) -fno-exceptions -fno-rtti -U__ARM_NEON__ -UDEBUG \
    -include limits -include cstdint -D_LIBCPP_DISABLE_AVAILABILITY -Ithird_party/rlottie/config \
    -Ithird_party/rlottie/inc -Ithird_party/rlottie/src/vector -Ithird_party/rlottie/src/vector/freetype \
    -Ithird_party/rlottie/src/vector/pixman -Ithird_party/rlottie/src/lottie -Ithird_party/rlottie/src/binding/c))
# libtgvoip throws and casts across its address classes, so it keeps exceptions and rtti
$(foreach f,$(TGVOIP_FILES),$(eval $(f)_CFLAGS = $(VENDOR_CXX) -DTGVOIP_NO_DSP -DTGVOIP_LOG_VERBOSITY=2 \
    -D_LIBCPP_DISABLE_AVAILABILITY -Ithird_party/libtgvoip -Ithird_party/opus/include -Iapp/net -Icore/base))
$(foreach f,$(CORE_FILES),$(eval $(f)_CFLAGS = $(STRICT_C)))
$(foreach f,$(APP_FILES),$(eval $(f)_CFLAGS = -std=gnu99 -fno-objc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-error \
    $(addprefix -I,$(APP_DIRS)) -Ibuild/generated -Ithird_party/rlottie/inc -Ithird_party/libwebp \
    -Ithird_party/libtgvoip -Ithird_party/zbar/include))

# ---- the app -------------------------------------------------------------------------------------------

APPLICATION_NAME = Noshigram

Noshigram_FILES = $(APP_FILES) $(CORE_FILES) $(WEBP_FILES) $(OPUS_FILES) $(ZBAR_FILES) $(RLOTTIE_FILES) $(TGVOIP_FILES)
Noshigram_USE_MODULES = 0
Noshigram_CFLAGS = -O2 -g $(CORE_INCLUDES)
# developer builds: a picture of the screen on request, see app/lifecycle/noshi_dev_screen.m
Noshigram_CFLAGS += $(if $(NOSHI_DEV),-DNOSHI_DEV)
Noshigram_FRAMEWORKS = UIKit Foundation Security CoreGraphics QuartzCore ImageIO CoreText AVFoundation CoreMedia \
    CoreVideo CoreAudio AudioToolbox CoreLocation Accelerate MobileCoreServices CFNetwork
Noshigram_WEAK_FRAMEWORKS = OpenGLES CoreMotion AssetsLibrary AddressBook AddressBookUI MediaPlayer
Noshigram_LIBRARIES = z c++ sqlite3 iconv
Noshigram_LDFLAGS = $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libssl.a $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libcrypto.a \
    $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libavformat.a $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libavcodec.a \
    $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libswresample.a $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libavutil.a \
    $(DEPS)/$(THEOS_CURRENT_ARCH)/lib/libvpx.a -Wl,-dead_strip
Noshigram_RESOURCE_DIRS = build/bundle
Noshigram_CODESIGN_FLAGS = -Spackaging/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# the share sheet extension starts at _NSExtensionMain and needs ios 8, it is built by its own makefile
SUBPROJECTS += extension/share
include $(THEOS_MAKE_PATH)/aggregate.mk

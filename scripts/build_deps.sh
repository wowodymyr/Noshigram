#!/usr/bin/env bash
# fetches and builds the static libraries the app links: openssl, libvpx and ffmpeg, for armv7 (ios 5) and arm64 (ios 7)
# output: deps/<slice>/{include,lib}, which the theos makefile reads
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
TC="${NOSHI_TC:-$THEOS/toolchain/linux/iphone/bin}"
SDK="${NOSHI_SDK:-$THEOS/sdks/iPhoneOS14.5.sdk}"
OUT="${NOSHI_DEPS:-$ROOT/deps}"
SRC="$OUT/src"
JOBS="${NOSHI_JOBS:-$(nproc)}"

OPENSSL_VER=3.0.15
VPX_VER=1.15.0
FFMPEG_VER=7.1.1

mkdir -p "$SRC"
fetch() {
    local url="$1" dir="$2"
    [[ -d "$SRC/$dir" ]] && return 0
    curl -fsSL "$url" | tar -xz -C "$SRC"
}
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" "openssl-$OPENSSL_VER"
fetch "https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX_VER.tar.gz" "libvpx-$VPX_VER"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.gz" "ffmpeg-$FFMPEG_VER"

for slice in ${NOSHI_SLICES:-armv7 arm64}; do
    if [[ "$slice" == armv7 ]]; then minimum=5.0; arch=arm; cpu=armv7; ossl=ios-cross;
    else minimum=7.0; arch=aarch64; cpu=generic; ossl=ios64-cross; fi
    prefix="$OUT/$slice"
    flags="-target $slice-apple-ios$minimum -isysroot $SDK -O2 -fPIC -B$TC"
    mkdir -p "$prefix" "$OUT/build/$slice"

    if [[ ! -f "$prefix/lib/libcrypto.a" ]]; then
        rm -rf "$OUT/build/$slice/openssl" && mkdir -p "$OUT/build/$slice/openssl"
        (
            cd "$OUT/build/$slice/openssl"
            # the ios configs of openssl put their own sysroot at $CROSS_TOP/SDKs/$CROSS_SDK
            mkdir -p "$OUT/sdkroot/SDKs" && ln -sfn "$SDK" "$OUT/sdkroot/SDKs/iPhoneOS.sdk"
            export CROSS_TOP="$OUT/sdkroot" CROSS_SDK=iPhoneOS.sdk
            CC="$TC/clang $flags" AR="$TC/llvm-ar" RANLIB="$TC/llvm-ranlib" \
            "$SRC/openssl-$OPENSSL_VER/Configure" "$ossl" no-shared no-async no-tests no-ui-console no-engine \
                no-dso no-asm --prefix="$prefix" --openssldir=/var/mobile/Library/Noshigram/ssl
            make -j"$JOBS" build_libs
            make install_dev
        )
    fi

    if [[ ! -f "$prefix/lib/libvpx.a" ]]; then
        rm -rf "$OUT/build/$slice/vpx" && mkdir -p "$OUT/build/$slice/vpx"
        (
            cd "$OUT/build/$slice/vpx"
            # vp8 encode and decode serve the video calls, the stickers need only the vp9 decoder
            CC="$TC/clang" CXX="$TC/clang++" AR="$TC/llvm-ar" LD="$TC/clang" CFLAGS="$flags" LDFLAGS="$flags" \
            "$SRC/libvpx-$VPX_VER/configure" --target=generic-gnu --prefix="$prefix" \
                --extra-cflags="$flags" --extra-cxxflags="$flags -std=c++14 -stdlib=libc++ -fno-exceptions -fno-rtti -D_LIBCPP_DISABLE_AVAILABILITY" \
                --enable-vp8 --enable-vp9 --disable-vp9-encoder --enable-realtime-only --disable-vp9-highbitdepth \
                --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-webm-io \
                --disable-libyuv --disable-multithread --enable-pic
            make -j"$JOBS" HAVE_GNU_STRIP=no
            cp libvpx_g.a libvpx.a
            make install HAVE_GNU_STRIP=no
        )
    fi

    if [[ ! -f "$prefix/lib/libavcodec.a" ]]; then
        rm -rf "$OUT/build/$slice/ffmpeg" && mkdir -p "$OUT/build/$slice/ffmpeg"
        (
            cd "$OUT/build/$slice/ffmpeg"
            PKG_CONFIG_PATH="$prefix/lib/pkgconfig" "$SRC/ffmpeg-$FFMPEG_VER/configure" \
                --prefix="$prefix" --target-os=darwin --arch="$arch" --cpu="$cpu" --enable-cross-compile \
                --cc="$TC/clang" --cxx="$TC/clang++" --ar="$TC/llvm-ar" --ranlib="$TC/llvm-ranlib" --nm="$TC/nm" \
                --extra-cflags="$flags" --extra-ldflags="$flags" \
                --disable-everything --disable-autodetect --disable-asm --disable-network --disable-programs \
                --disable-doc --disable-debug --disable-swscale --disable-avfilter --disable-avdevice \
                --disable-postproc --enable-pic --enable-small --enable-static --disable-shared --enable-libvpx \
                --enable-swresample --enable-protocol=file --enable-decoder=libvpx_vp9,flac \
                --enable-demuxer=matroska,flac --enable-parser=vp9,flac --pkg-config-flags=--static
            grep -q '^#define CONFIG_LIBVPX_VP9_DECODER 1$' config_components.h
            grep -q '^#define CONFIG_FLAC_DECODER 1$' config_components.h
            make -j"$JOBS"
            make install
        )
    fi
    "$TC/lipo" -info "$prefix"/lib/*.a
done

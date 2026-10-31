#!/usr/bin/env bash
# Cross-compiles the trimmed, static GPL FFmpeg that ships in resources/ffmpeg: ffmpeg.exe with
# only the encoders, filters and libraries the ops use, and a decode-only ffprobe.exe.
#
# Runs on Linux or WSL (Ubuntu) with:
#   apt install mingw-w64 nasm cmake meson ninja-build pkg-config autoconf automake libtool xz-utils
#   update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
#   update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix
#
# Usage: scripts/ffmpeg/build.sh <resources/ffmpeg dir> <LICENSES dir>
# Sources are downloaded once into $WORK (default ~/ayris-ffmpeg); nothing is installed system-wide.
set -euo pipefail

OUT=$(realpath "$1")
LICENSE_OUT=$(realpath "$2")
WORK=${WORK:-$HOME/ayris-ffmpeg}
PREFIX=$WORK/prefix
HOST=x86_64-w64-mingw32
JOBS=${JOBS:-$(nproc)}

FFMPEG=9.0.2
ZLIB=1.3.2
X264=b35605ace3ddf7c1a5d67a2eb553f034aef41d55 # stable branch
LAME=3.100
OGG=1.3.6
VORBIS=1.3.7
OPUS=1.6.1
VPX=v1.17.0
ZIMG=release-3.0.6
DAV1D=1.5.4

mkdir -p "$WORK/src" "$PREFIX"
cd "$WORK/src"
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
export PKG_CONFIG_PATH=
# Static mingw builds don't ship libssp, so fortified calls would fail to link.
export CFLAGS="-O2 -D_FORTIFY_SOURCE=0"
export CXXFLAGS=$CFLAGS
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"

fetch() { # url dir
  [ -d "$2" ] && return
  curl -fsSL --retry 5 "$1" -o "$2.tar"
  mkdir "$2" && tar -xf "$2.tar" -C "$2" --strip-components=1 && rm "$2.tar"
}
clone() { # url ref dir
  [ -d "$3" ] && return
  git clone -q --recursive "$1" "$3" && git -C "$3" checkout -q "$2" && git -C "$3" submodule -q update --init --recursive
}
done_mark() { [ -f "$PREFIX/.$1" ]; }
mark() { touch "$PREFIX/.$1"; }
autotools() { # dir, extra configure args...
  local dir=$1
  shift
  (cd "$dir" && ./configure --host=$HOST --prefix="$PREFIX" --enable-static --disable-shared "$@" &&
    make -j"$JOBS" && make install)
}

if ! done_mark zlib; then
  fetch "https://github.com/madler/zlib/releases/download/v$ZLIB/zlib-$ZLIB.tar.xz" zlib
  make -C zlib -f win32/Makefile.gcc PREFIX=$HOST- BINARY_PATH="$PREFIX/bin" \
    INCLUDE_PATH="$PREFIX/include" LIBRARY_PATH="$PREFIX/lib" -j"$JOBS" install
  mark zlib
fi

if ! done_mark x264; then
  clone https://code.videolan.org/videolan/x264.git $X264 x264
  (cd x264 && ./configure --host=$HOST --cross-prefix=$HOST- --prefix="$PREFIX" --enable-static \
    --disable-cli --disable-opencl && make -j"$JOBS" && make install)
  mark x264
fi

if ! done_mark lame; then
  fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME/lame-$LAME.tar.gz" lame
  # 3.100 lists a symbol it no longer has; harmless for static builds but breaks some linkers.
  sed -i '/lame_init_old/d' lame/include/libmp3lame.sym
  autotools lame --disable-frontend --disable-gtktest --disable-decoder --enable-nasm
  mark lame
fi

if ! done_mark ogg; then
  fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG.tar.xz" ogg
  autotools ogg
  mark ogg
fi

if ! done_mark vorbis; then
  fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS.tar.xz" vorbis
  autotools vorbis --with-ogg="$PREFIX" --disable-docs --disable-examples --disable-oggtest
  mark vorbis
fi

if ! done_mark opus; then
  fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS.tar.gz" opus
  autotools opus --disable-doc --disable-extra-programs --disable-stack-protector
  mark opus
fi

if ! done_mark vpx; then
  clone https://chromium.googlesource.com/webm/libvpx $VPX vpx
  # VP9 encoding only: FFmpeg's own decoders read VP8 and VP9.
  (cd vpx && CROSS=$HOST- ./configure --target=x86_64-win64-gcc --prefix="$PREFIX" \
    --enable-static --disable-shared --disable-examples --disable-tools --disable-docs \
    --disable-unit-tests --disable-vp8 --disable-vp9-decoder && make -j"$JOBS" && make install)
  mark vpx
fi

if ! done_mark zimg; then
  clone https://github.com/sekrit-twc/zimg.git $ZIMG zimg
  (cd zimg && ./autogen.sh >/dev/null)
  autotools zimg
  mark zimg
fi

if ! done_mark dav1d; then
  # The release tarball: git clones from code.videolan.org can fail with GnuTLS errors.
  fetch "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D/dav1d-$DAV1D.tar.xz" dav1d
  (cd dav1d && meson setup build --cross-file=package/crossfiles/x86_64-w64-mingw32.meson \
    --prefix="$PREFIX" --libdir=lib --default-library=static --buildtype=release \
    -Denable_tools=false -Denable_tests=false && ninja -C build install)
  mark dav1d
fi

fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz" ffmpeg

COMMON=(
  --arch=x86_64 --target-os=mingw32 --cross-prefix=$HOST- --pkg-config=pkg-config
  --pkg-config-flags=--static --extra-cflags="-I$PREFIX/include"
  --extra-ldflags="-L$PREFIX/lib -static" --enable-gpl --enable-version3 --enable-static --disable-shared
  # Nothing is picked up from the build machine; every library is named below.
  --disable-autodetect --enable-w32threads --enable-zlib
  --disable-doc --disable-debug --disable-ffplay --disable-network
  # The app reads and writes local files and reads -progress from a pipe.
  --disable-protocols --enable-protocol=file,pipe
)

build_ffmpeg() { # dir, extra configure args...
  local dir=$WORK/build-$1
  shift
  rm -rf "$dir" && mkdir -p "$dir"
  (cd "$dir" && "$WORK/src/ffmpeg/configure" "${COMMON[@]}" "$@" && make -j"$JOBS")
}

# ffmpeg.exe: every native codec, format and filter, plus the encoders the ops name (libx264,
# libvpx-vp9, libmp3lame, libvorbis, libopus), zscale for HDR tone mapping, and dav1d for AV1.
# The one device is lavfi, which the tests use to generate their sample clips.
build_ffmpeg full --disable-ffprobe --disable-indevs --enable-indev=lavfi --disable-outdevs \
  --enable-libx264 --enable-libvpx --enable-libmp3lame --enable-libvorbis --enable-libopus \
  --enable-libzimg --enable-libdav1d

# ffprobe.exe: demuxers, parsers and decoders only.
build_ffmpeg probe --disable-ffmpeg --disable-avdevice --disable-avfilter --disable-swscale \
  --disable-encoders --disable-muxers --enable-libdav1d

mkdir -p "$OUT"
cp "$WORK/build-full/ffmpeg.exe" "$WORK/build-probe/ffprobe.exe" "$OUT/"

# GPL: the license, the libraries' own licenses, and how to rebuild from source.
LIBS=$LICENSE_OUT/ffmpeg-libraries
mkdir -p "$LIBS"
cp "$WORK/src/ffmpeg/COPYING.GPLv3" "$LICENSE_OUT/FFmpeg-GPL-3.0.txt"
cp "$WORK/src/x264/COPYING" "$LIBS/x264.txt"
cp "$WORK/src/lame/COPYING" "$LIBS/lame.txt"
cp "$WORK/src/ogg/COPYING" "$LIBS/libogg.txt"
cp "$WORK/src/vorbis/COPYING" "$LIBS/libvorbis.txt"
cp "$WORK/src/opus/COPYING" "$LIBS/opus.txt"
cp "$WORK/src/vpx/LICENSE" "$LIBS/libvpx.txt"
cp "$WORK/src/zimg/COPYING" "$LIBS/zimg.txt"
cp "$WORK/src/dav1d/COPYING" "$LIBS/dav1d.txt"
cp "$WORK/src/zlib/LICENSE" "$LIBS/zlib.txt"
{
  echo "FFmpeg $FFMPEG, built by scripts/ffmpeg/build.sh in the Ayris source."
  echo "Sources: ffmpeg $FFMPEG, x264 $X264, lame $LAME, libogg $OGG, libvorbis $VORBIS,"
  echo "opus $OPUS, libvpx $VPX, zimg $ZIMG, dav1d $DAV1D, zlib $ZLIB."
  echo
  echo "ffmpeg.exe configuration:"
  grep -m1 FFMPEG_CONFIGURATION "$WORK/build-full/config.h" | cut -d'"' -f2
  echo
  echo "ffprobe.exe configuration:"
  grep -m1 FFMPEG_CONFIGURATION "$WORK/build-probe/config.h" | cut -d'"' -f2
} >"$LICENSE_OUT/FFmpeg-BUILD.txt"

ls -la "$OUT"

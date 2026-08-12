#!/bin/zsh
set -euo pipefail

# Builds redistributable GPL FFmpeg tools from checksummed upstream sources.
# No --enable-nonfree component is used. The result is cached outside the app bundle.
project_dir="${0:A:h:h}"
ffmpeg_version="8.0.3"
x264_commit="c24e06c2e184345ceb33eb20a15d1024d9fd3497"
ffmpeg_sha256="6136812ea6d4e68bdba27e33c2a94382711cdf4f8602ffef056ff792bd6f9818"
x264_sha256="090d730e867fc63631782a1287974635d1237d0fa7c6fd1d09fd543620a56689"
build_root="$project_dir/.build/ffmpeg-source-$ffmpeg_version-arm64-v3"
source_dir="$build_root/sources"
prefix_dir="$build_root/prefix"
tool_dir="$build_root/tools"
neutral_prefix="/private/tmp/FootageFlow-FFmpeg-$ffmpeg_version-arm64-prefix"
private_home_pattern="/""Users/"

if [[ -x "$tool_dir/ffmpeg" && -x "$tool_dir/ffprobe" && -f "$tool_dir/LICENSE_FFMPEG.txt" && -f "$tool_dir/LICENSE_X264.txt" ]]; then
  if "$tool_dir/ffmpeg" -version 2>&1 | head -n 4 | grep -q -- '--enable-nonfree'; then
    print -u2 -- "Cached FFmpeg build is non-redistributable"
    exit 1
  fi
  if ! "$tool_dir/ffmpeg" -version 2>&1 | head -n 4 | grep -q -- '--enable-securetransport'; then
    print -u2 -- "Cached FFmpeg build cannot read HTTPS media"
    exit 1
  fi
  if strings "$tool_dir/ffmpeg" "$tool_dir/ffprobe" | grep -Fq "$private_home_pattern"; then
    print -u2 -- "Cached FFmpeg build contains a private developer path"
    exit 1
  fi
  print -r -- "$tool_dir"
  exit 0
fi

mkdir -p "$source_dir" "$prefix_dir" "$tool_dir"
ln -sfn "$prefix_dir" "$neutral_prefix"

download_and_verify() {
  local url="$1" destination="$2" expected="$3"
  if [[ ! -f "$destination" || "$(shasum -a 256 "$destination" | awk '{print $1}')" != "$expected" ]]; then
    curl --fail --location --silent --show-error --retry 2 --retry-delay 2 \
      --connect-timeout 20 --max-time 900 --output "$destination.download" "$url"
    actual="$(shasum -a 256 "$destination.download" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { print -u2 -- "Source checksum verification failed"; exit 1; }
    mv "$destination.download" "$destination"
  fi
}

ffmpeg_archive="$source_dir/ffmpeg-$ffmpeg_version.tar.xz"
x264_archive="$source_dir/x264-$x264_commit.tar.gz"
download_and_verify "https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz" "$ffmpeg_archive" "$ffmpeg_sha256"
download_and_verify "https://codeload.github.com/mirror/x264/tar.gz/$x264_commit" "$x264_archive" "$x264_sha256"

ffmpeg_source="$source_dir/ffmpeg-$ffmpeg_version"
x264_source="$source_dir/x264-$x264_commit"
[[ -d "$ffmpeg_source" ]] || tar -xJf "$ffmpeg_archive" -C "$source_dir"
[[ -d "$x264_source" ]] || tar -xzf "$x264_archive" -C "$source_dir"

jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || print 4)"
export MACOSX_DEPLOYMENT_TARGET="15.0"

if [[ ! -f "$prefix_dir/lib/libx264.a" ]]; then
  cd "$x264_source"
  ./configure --prefix="$neutral_prefix" --host=aarch64-apple-darwin \
    --enable-static --disable-cli --disable-opencl
  make -j"$jobs"
  make install
fi

cd "$ffmpeg_source"
if [[ ! -f ffbuild/config.mak ]]; then
  PKG_CONFIG_PATH="$neutral_prefix/lib/pkgconfig" ./configure \
    --prefix="/opt/FootageFlow/FFmpeg" --arch=arm64 --target-os=darwin \
    --cc="xcrun clang" --enable-static --disable-shared --disable-autodetect \
    --enable-gpl --enable-libx264 --enable-audiotoolbox --enable-videotoolbox \
    --enable-securetransport \
    --pkg-config=true \
    --disable-ffplay --disable-doc --disable-debug \
    --extra-cflags="-I$neutral_prefix/include -mmacosx-version-min=15.0" \
    --extra-ldflags="-L$neutral_prefix/lib -mmacosx-version-min=15.0" --extra-libs="-lx264"
fi
make -j"$jobs" ffmpeg ffprobe
cp ffmpeg ffprobe "$tool_dir/"
chmod 755 "$tool_dir/ffmpeg" "$tool_dir/ffprobe"
cp COPYING.GPLv2 "$tool_dir/LICENSE_FFMPEG.txt"
cp "$x264_source/COPYING" "$tool_dir/LICENSE_X264.txt"
cp LICENSE.md "$tool_dir/README_FFMPEG.txt"

version_output="$($tool_dir/ffmpeg -version 2>&1 | head -n 4)"
print -r -- "$version_output" | grep -q -- '--enable-gpl'
if print -r -- "$version_output" | grep -q -- '--enable-nonfree'; then
  print -u2 -- "FFmpeg unexpectedly contains nonfree components"
  exit 1
fi
if strings "$tool_dir/ffmpeg" "$tool_dir/ffprobe" | grep -Fq "$private_home_pattern"; then
  print -u2 -- "FFmpeg build unexpectedly contains a private developer path"
  exit 1
fi
print -r -- "$tool_dir"

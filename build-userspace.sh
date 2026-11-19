#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "$0")" && pwd)
version=$(dpkg-query -W -f='${Version}' libcamera0.4)
if [[ $version != 0.4.0-7 ]]; then
    echo "The patch was verified against Debian libcamera 0.4.0-7. Rebase and test before using a different version." >&2
    exit 1
fi
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
apt-get source "libcamera=$version" >&2
cd libcamera-0.4.0
patch -p1 --forward --batch < "$project/libcamera-lapbc710.patch" >&2
meson setup build --prefix=/usr --libdir="lib/$multiarch" --libexecdir="libexec/$multiarch" \
    -Dpipelines=simple,uvcvideo,ipu3 -Dipas=simple,ipu3 -Dcam=disabled -Dqcam=disabled \
    -Dgstreamer=disabled -Dpycamera=disabled -Ddocumentation=disabled -Dtracing=disabled \
    -Dlibunwind=disabled -Dlc-compliance=disabled -Dudev=enabled --buildtype=release >&2
meson compile -C build -j "${JOBS:-5}" >&2
DESTDIR="$work/stage" meson install -C build --no-rebuild >&2
libraries="$work/stage/usr/lib/$multiarch"
LD_LIBRARY_PATH="$libraries" build/src/apps/ipa-verify/ipa_verify \
    "$libraries/libcamera/ipa_soft_simple.so" >&2

output="$project/build/userspace"
mkdir -p -- "$output"
stage=$(mktemp -d "$output/$version.XXXXXX")
cp -a -- "$libraries/." "$stage/"
printf '%s\n' "$stage"

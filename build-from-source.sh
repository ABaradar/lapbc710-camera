#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

project=$(cd -- "$(dirname -- "$0")" && pwd)
export PATH="$PATH:/usr/sbin:/sbin"

usage() {
    echo "Usage: $0 kernel KERNEL_SOURCE_TREE [INSTALLED_KERNEL_RELEASE]" >&2
    echo "       $0 libcamera LIBCAMERA_0_4_0_SOURCE_TREE" >&2
    exit 2
}

(( $# >= 2 )) || usage
mode=$1
source_tree=$(realpath -- "$2")
[[ -d $source_tree ]] || usage
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

case "$mode" in
kernel)
    (( $# <= 3 )) || usage
    release=${3:-$(uname -r)}
    [[ $release =~ ^[0-9][A-Za-z0-9.+_-]*$ ]] || usage
    headers="/lib/modules/$release/build"
    if [[ ! -r $headers/Module.symvers ]]; then
        echo "Install the build headers and Module.symvers for $release." >&2
        exit 1
    fi
    bridge="$source_tree/drivers/media/pci/intel/ipu-bridge.c"
    mkdir -p -- "$work/bridge" "$work/sensor"
    python3 - "$bridge" "$work/bridge/ipu-bridge.c" <<'PY'
import sys
from pathlib import Path

original, output = map(Path, sys.argv[1:])
source = original.read_text()
anchor = '\tIPU_SENSOR_CONFIG("OVTI01AS", 1, 400000000),'
if '"OVTI01AF"' in source:
    sys.exit("This bridge already knows OVTI01AF. Check native sensor support first.")
if source.count(anchor) != 1:
    sys.exit("Expected OV01A1S configuration not found. Review the bridge source before porting.")
entry = '\tIPU_SENSOR_CONFIG("OVTI01AF", 1, 400000000),\n'
output.write_text(source.replace(anchor, entry + anchor))
PY
    cp -- "$project/bridge/Makefile" "$work/bridge/"
    cp -- "$project/sensor/"{Makefile,ov01a1s.c} "$work/sensor/"
    for component in bridge sensor; do
        make -C "$headers" M="$work/$component" modules >&2
    done
    modules=("$work/bridge/ipu-bridge.ko" "$work/sensor/ov01a1s.ko")
    for module in "${modules[@]}"; do
        vermagic=$(modinfo -F vermagic "$module")
        [[ ${vermagic%% *} == "$release" ]]
    done
    destination="$project/build/kernel/$release"
    mkdir -p -- "$destination"
    install -m 0644 -- "${modules[@]}" "$destination/"
    printf '%s\n' "$destination"
    ;;
libcamera)
    (( $# == 2 )) || usage
    cp -a -- "$source_tree" "$work/source"
    cd "$work/source"
    patch -p1 --fuzz=0 --forward --batch < "$project/libcamera-lapbc710.patch" >&2
    meson setup "$work/build" --prefix=/usr --libdir=lib \
        -Dpipelines=simple,uvcvideo,ipu3 -Dipas=simple,ipu3 -Dcam=disabled -Dqcam=disabled \
        -Dgstreamer=disabled -Dpycamera=disabled -Ddocumentation=disabled -Dtracing=disabled \
        -Dlc-compliance=disabled -Dudev=enabled --buildtype=release >&2
    meson compile -C "$work/build" -j "${JOBS:-5}" >&2
    DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild >&2
    libraries="$work/stage/usr/lib"
    [[ -f $libraries/libcamera.so.0.4 && -f $libraries/libcamera-base.so.0.4 ]]
    LD_LIBRARY_PATH="$libraries" "$work/build/src/apps/ipa-verify/ipa_verify" \
        "$libraries/libcamera/ipa_soft_simple.so" >&2
    mkdir -p -- "$project/build/userspace"
    destination=$(mktemp -d "$project/build/userspace/portable-0.4.XXXXXX")
    cp -a -- "$libraries/." "$destination/"
    printf '%s\n' "$destination"
    ;;
*) usage ;;
esac

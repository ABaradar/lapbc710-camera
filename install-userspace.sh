#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if (( EUID != 0 || $# != 1 )); then
    echo "Usage: sudo bash install-userspace.sh STAGED_MULTIARCH_LIBDIR" >&2
    exit 2
fi
[[ $(cat /sys/class/dmi/id/board_name) == LAPBC710 ]]
source_dir=$(realpath -- "$1")
project=$(cd -- "$(dirname -- "$0")" && pwd)
tuning="$project/tuning/simple/ov01a1s.yaml"
files=(libcamera.so.0.4 libcamera-base.so.0.4 libcamera/ipa_{soft_simple,ipu3}.so{,.sign})
bundle_hash=$(
    cd -- "$source_dir"
    { sha256sum -- "${files[@]}"; sha256sum < "$tuning"; } | sha256sum
)
root=/usr/local/lib/lapbc710-camera
destination="$root/releases/${bundle_hash:0:16}"
install -d -m 0755 -- "$root/releases"

if [[ ! -d $destination ]]; then
    temporary=$(mktemp -d "$root/releases/.install.XXXXXX")
    trap 'rm -rf -- "$temporary"' EXIT
    install -d -m 0755 "$temporary/ipa" "$temporary/tuning/simple"
    install -m 0644 -- "$tuning" "$temporary/tuning/simple/ov01a1s.yaml"
    for file in "${files[@]}"; do
        case "$file" in
            libcamera/*) target="$temporary/ipa/${file##*/}" ;;
            *) target="$temporary/$file" ;;
        esac
        install -m 0644 -- "$source_dir/$file" "$target"
    done
    chmod 0755 "$temporary"
    mv -T -- "$temporary" "$destination"
    trap - EXIT
fi
printf '%s\n' "$destination"

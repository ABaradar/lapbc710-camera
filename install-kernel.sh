#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if (( EUID != 0 || $# != 1 )); then
    echo "Usage: sudo bash install-kernel.sh KERNEL_RELEASE" >&2
    exit 2
fi
[[ $(cat /sys/class/dmi/id/board_name) == LAPBC710 ]]
project=$(cd -- "$(dirname -- "$0")" && pwd)
release=$1
[[ $release =~ ^[0-9][A-Za-z0-9.+_-]*$ && -d /lib/modules/$release ]]
source_dir="$project/build/kernel/$release"
updates="/lib/modules/$release/updates"
destination="$updates/lapbc710-camera"
files=(ipu-bridge.ko ov01a1s.ko)

for file in "${files[@]}"; do
    vermagic=$(modinfo -F vermagic "$source_dir/$file")
    [[ ${vermagic%% *} == "$release" ]]
done

verify() {
    [[ $(modinfo -k "$release" -F filename ipu_bridge) == "$destination/ipu-bridge.ko" ]] &&
    [[ $(modinfo -k "$release" -F filename ov01a1s) == "$destination/ov01a1s.ko" ]] &&
    modprobe -S "$release" --resolve-alias acpi:OVTI01AF: | awk '$0 == "ov01a1s" { found=1 } END { exit !found }'
}
if [[ -d $destination ]]; then
    verify
    echo "Camera overlay is already installed for $release."
    exit 0
fi

install -d -m 0755 -- "$updates"
temporary=$(mktemp -d "$updates/.lapbc710.XXXXXX")
installed=0

rollback() {
    result=$?
    if (( result != 0 && installed )); then
        rm -f -- "$destination/"{ipu-bridge,ov01a1s}.ko
        rmdir -- "$destination"
        depmod "$release"
    fi
    rm -rf -- "$temporary"
}
trap rollback EXIT
for file in "${files[@]}"; do
    install -m 0644 -- "$source_dir/$file" "$temporary/"
done
chmod 0755 "$temporary"
mv -T -- "$temporary" "$destination"
installed=1
depmod "$release"
verify
if command -v lsinitramfs >/dev/null && command -v update-initramfs >/dev/null &&
    [[ -r /boot/initrd.img-$release ]] &&
    lsinitramfs "/boot/initrd.img-$release" |
    awk '/\/(intel-ipu6[^/]*|ipu-bridge|ov01a1s)\.ko/ { found=1 } END { exit !found }'; then
    update-initramfs -u -k "$release"
fi
trap - EXIT
echo "Installed the camera modules for $release. Validate capture after booting that kernel."

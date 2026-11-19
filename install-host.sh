#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if (( EUID != 0 )); then
    echo "Run this script as root on the LAPBC710 host." >&2
    exit 1
fi

project_dir=$(cd -- "$(dirname -- "$0")" && pwd)
kernel_release=$(uname -r)
module_dir="/lib/modules/$kernel_release/updates/lapbc710-camera"
bridge="$project_dir/bridge/ipu-bridge.ko"
sensor="$project_dir/sensor/ov01a1s.ko"
sensor_driver=/sys/bus/i2c/devices/i2c-OVTI01AF:00/driver

if [[ $(cat /sys/class/dmi/id/board_name) != LAPBC710 ||
      ! -L $sensor_driver || $(basename "$(readlink "$sensor_driver")") != ov01a1s ]]; then
    echo "The LAPBC710 sensor must be bound to ov01a1s before installation." >&2
    exit 1
fi

for module_file in "$bridge" "$sensor"; do
    vermagic=$(modinfo -F vermagic "$module_file")
    if [[ ${vermagic%% *} != "$kernel_release" ]]; then
        echo "Kernel release mismatch for $module_file." >&2
        exit 1
    fi
done

mkdir -- "$module_dir"

rollback_failed_install() {
    local result=$?
    if (( result != 0 )); then
        rm -f -- "$module_dir/ipu-bridge.ko" "$module_dir/ov01a1s.ko"
        rmdir -- "$module_dir"
        depmod "$kernel_release"
    fi
}
trap rollback_failed_install EXIT

install -m 0644 -- "$bridge" "$sensor" "$module_dir/"
depmod "$kernel_release"

[[ $(modinfo -k "$kernel_release" -F filename ipu_bridge) == "$module_dir/ipu-bridge.ko" ]]
[[ $(modinfo -k "$kernel_release" -F filename ov01a1s) == "$module_dir/ov01a1s.ko" ]]
[[ $(modprobe -S "$kernel_release" --resolve-alias 'acpi:OVTI01AF:') == ov01a1s ]]
echo "Camera modules installed for $kernel_release."

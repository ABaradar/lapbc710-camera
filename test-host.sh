#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if (( EUID != 0 )); then
    echo "Run this script as root on the LAPBC710 host." >&2
    exit 1
fi

project_dir=$(cd -- "$(dirname -- "$0")" && pwd)
bridge="$project_dir/bridge/ipu-bridge.ko"
sensor="$project_dir/sensor/ov01a1s.ko"
sensor_device=/sys/bus/i2c/devices/i2c-OVTI01AF:00

if [[ $(cat /sys/class/dmi/id/board_name) != LAPBC710 || ! -d $sensor_device ]]; then
    echo "The expected LAPBC710 camera hardware is missing." >&2
    exit 1
fi

for module_file in "$bridge" "$sensor"; do
    vermagic=$(modinfo -F vermagic "$module_file")
    if [[ ${vermagic%% *} != "$(uname -r)" ]]; then
        echo "Kernel release mismatch for $module_file." >&2
        exit 1
    fi
done

if [[ -d /sys/module/ov01a1s ]]; then
    echo "ov01a1s is already loaded. Check the current driver and media topology first." >&2
    exit 1
fi

for module in intel_ipu6_isys intel_ipu6 ipu_bridge; do
    if [[ ! -d /sys/module/$module ]]; then
        echo "Expected baseline module $module is missing." >&2
        exit 1
    fi
done

started=$(date --iso-8601=seconds)
bridge_replaced=0
sensor_loaded=0

finish() {
    local result=$?
    trap - EXIT

    journalctl -k -b --since "$started" --no-pager \
        -g 'ipu6|ipu.bridge|OVTI01AF|ov01a1s|INT3472' || true
    if (( result != 0 )); then
        echo "Camera probe failed. Restoring the packaged IPU6 modules." >&2
        if (( sensor_loaded )); then
            rmmod ov01a1s || echo "Could not unload ov01a1s." >&2
        fi
        if (( bridge_replaced )); then
            for module in intel_ipu6_isys intel_ipu6 ipu_bridge; do
                if [[ -d /sys/module/$module ]]; then
                    rmmod "$module" || echo "Could not unload $module." >&2
                fi
            done
        fi
        modprobe intel_ipu6 && modprobe intel_ipu6_isys ||
            echo "Could not restore the packaged IPU6 stack." >&2
    fi
    exit "$result"
}
trap finish EXIT

rmmod intel_ipu6_isys intel_ipu6 ipu_bridge
insmod "$bridge"
bridge_replaced=1
modprobe intel_ipu6
modprobe intel_ipu6_isys
insmod "$sensor"
sensor_loaded=1

for attempt in {1..5}; do
    if [[ -L $sensor_device/driver && $(basename "$(readlink "$sensor_device/driver")") == ov01a1s ]]; then
        echo "OVTI01AF is bound to ov01a1s. The live modules are ready for a capture test."
        exit 0
    fi
    sleep 1
done
echo "OVTI01AF did not bind to ov01a1s." >&2
exit 1

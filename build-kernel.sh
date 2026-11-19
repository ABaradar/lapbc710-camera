#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "$0")" && pwd)
release=${1:-$(uname -r)}
[[ $release =~ ^[0-9][A-Za-z0-9.+_-]*$ && $# -le 1 ]]
headers="/lib/modules/$release/build"
[[ -r $headers/Module.symvers ]] || { echo "Install linux-headers-$release first." >&2; exit 1; }
source_version=$(dpkg-query -W -f='${source:Version}' "linux-headers-$release")
series=$(cut -d. -f1,2 <<< "$release")
output="$project/build/kernel/$release"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work/modules/bridge" "$work/modules/sensor"

if [[ $release == 6.12.117+deb13-amd64 && $source_version == 6.12.117-1 ]]; then
    cp -- "$project/bridge/ipu-bridge.c" "$work/modules/bridge/"
else
    if /usr/sbin/modprobe -S "$release" --resolve-alias acpi:OVTI01AF: >/dev/null 2>&1; then
        echo "This kernel already resolves OVTI01AF. Test its driver first." >&2
        exit 1
    fi
    (
        cd "$work"
        apt-get download "linux-source-$series=$source_version" >&2
        dpkg-deb -x linux-source-*.deb source
    )
    bridge_path="linux-source-$series/drivers/media/pci/intel/ipu-bridge.c"
    tar -xJOf "$work/source/usr/src/linux-source-$series.tar.xz" "$bridge_path" \
        > "$work/modules/bridge/ipu-bridge.c"
    python3 - "$work/modules/bridge/ipu-bridge.c" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
anchor = '\tIPU_SENSOR_CONFIG("OVTI01AS", 1, 400000000),'
if '"OVTI01AF"' in source or source.count(anchor) != 1:
    sys.exit("Kernel bridge has changed. Review the new source before porting the modules.")
path.write_text(source.replace(anchor, '\tIPU_SENSOR_CONFIG("OVTI01AF", 1, 400000000),\n' + anchor))
PY
fi

cp -- "$project/bridge/Makefile" "$work/modules/bridge/"
cp -- "$project/sensor/"{Makefile,ov01a1s.c} "$work/modules/sensor/"
for component in bridge sensor; do
    make -C "$headers" M="$work/modules/$component" modules >&2
done
mkdir -p -- "$output"
for module in bridge/ipu-bridge.ko sensor/ov01a1s.ko; do
    module_file="$work/modules/$module"
    vermagic=$(/usr/sbin/modinfo -F vermagic "$module_file")
    [[ ${vermagic%% *} == "$release" ]]
    install -m 0644 -- "$module_file" "$output/"
done
printf '%s\n' "$output"

#!/usr/bin/env bash
set -euo pipefail

echo "Running kernel $(uname -r)"
sensor=/sys/bus/i2c/devices/i2c-OVTI01AF:00/driver
[[ -L $sensor && $(basename "$(readlink "$sensor")") == ov01a1s ]]
/usr/sbin/modinfo -F filename ipu_bridge
/usr/sbin/modinfo -F filename ov01a1s

camera=$(pw-dump | python3 -c '
import json, sys

nodes = []
for obj in json.load(sys.stdin):
    if obj.get("type") != "PipeWire:Interface:Node":
        continue
    properties = obj.get("info", {}).get("props", {})
    if properties.get("media.class") == "Video/Source":
        nodes.append(properties)
raw = [n for n in nodes if n.get("device.api") == "v4l2"
       and ("ipu6" in n.get("node.description", "").lower()
            or "0000_00_05.0" in n.get("node.name", ""))]
cameras = [n["node.name"] for n in nodes if n.get("device.api") == "libcamera"
           and n.get("node.name", "").endswith("PC00.LNK0")]
if raw or len(cameras) != 1:
    sys.exit(f"Expected one built-in libcamera source and no raw IPU6 sources; found {len(cameras)} and {len(raw)}.")
print(cameras[0])
')
portal=$(busctl --user get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Camera IsCameraPresent)
[[ $portal == 'b true' ]] || { echo "The desktop camera portal reports no camera." >&2; exit 1; }
pid=$(systemctl --user show pipewire -P MainPID)
timeout 15s gst-launch-1.0 -q pipewiresrc "target-object=$camera" \
    stream-properties='props,media.type=Video,media.category=Capture,media.role=Camera' \
    num-buffers=90 '!' video/x-raw,width=1280,height=800 '!' fakesink sync=false
[[ $pid == "$(systemctl --user show pipewire -P MainPID)" ]]
echo "One built-in PipeWire camera delivered 90 frames at 1280×800."

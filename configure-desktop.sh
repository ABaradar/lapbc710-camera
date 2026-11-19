#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 || $# != 1 )); then
    echo "Run as your desktop user. Usage: bash configure-desktop.sh BUNDLE_PATH|--stock" >&2
    exit 2
fi
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
bundle=$1
if [[ $bundle != --stock ]]; then
    bundle=$(realpath -- "$bundle")
    [[ $bundle =~ ^/usr/local/lib/lapbc710-camera(/releases/[0-9a-f]{16})?$ ]]
    [[ -r $bundle/libcamera.so.0.4 && -r $bundle/ipa/ipa_soft_simple.so.sign ]]
fi

for service in pipewire wireplumber; do
    directory="$config_dir/$service.service.d"
    dropin="$directory/50-lapbc710-camera.conf"
    if [[ $bundle == --stock ]]; then
        rm -f -- "$dropin"
    else
        mkdir -p -- "$directory"
        temporary=$(mktemp "$directory/.lapbc710.XXXXXX")
        printf '[Service]\nEnvironment="LD_LIBRARY_PATH=%s"\nEnvironment="LIBCAMERA_IPA_MODULE_PATH=%s/ipa"\n' \
            "$bundle" "$bundle" > "$temporary"
        if [[ -r $bundle/tuning/simple/ov01a1s.yaml ]]; then
            printf 'Environment="LIBCAMERA_IPA_CONFIG_PATH=%s/tuning"\n' "$bundle" >> "$temporary"
        fi
        mv -T -- "$temporary" "$dropin"
    fi
done

systemctl --user daemon-reload
systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service
systemctl --user is-active pipewire.service wireplumber.service pipewire-pulse.service

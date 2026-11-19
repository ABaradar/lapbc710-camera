# LAPBC710 Linux webcam

Source-based camera support for the ADATA XPG Xenia Xe and Intel NUC M15 LAPBC710 with Tiger Lake IPU6 (`8086:9a19`) and the OmniVision OV01A1S RGB‑IR sensor (`OVTI01AF`). This is a community workaround. The source builders accept inputs from any Linux distribution. Live hardware and browser capture were verified on Debian 13 with kernel `6.12.117+deb13-amd64` and libcamera `0.4.0-7`. Other distributions and newer library ABIs need compatibility testing.

The kernel modules connect the sensor to the IPU6 media graph. The libcamera patch reconstructs RGB from the sensor’s RGB‑IR mosaic, rotates this board’s image 180°, and fixes an exposure calculation that could crash PipeWire. The sensor tuning sets a measured black level and the exposure algorithm can add bounded digital gain in dim scenes. PipeWire exposes the result as one **Built-in Front Camera** for WebRTC.

## Build on your distribution

Check that the firmware enables the camera and that `cat /sys/class/dmi/id/board_name` returns `LAPBC710`. Check `lspci -nnk -s 00:05.0` for `8086:9a19`, and check for `/sys/bus/acpi/devices/OVTI01AF:00`. If the distribution already delivers a working stream from this sensor, use its stack. [Intel hardware specification](https://www.intel.com/content/dam/support/us/en/documents/intel-nuc/laptop-kit/BC57_KIT_PROD_SPEC.pdf)

### Kernel modules

Use the kernel source matching the distribution’s **exact** target kernel and its installed build headers at `/lib/modules/<release>/build`. You also need Kbuild, the compiler and development tools for that kernel, Python 3, kmod, and the distribution’s Intel IPU6 firmware. The builder stages the modules without touching the running kernel. It refuses a bridge that already supports the sensor ID or has an unfamiliar sensor table.

```bash
release=$(uname -r)
bash build-from-source.sh kernel /path/to/matching-linux-source "$release"
sudo bash install-kernel.sh "$release"
```

The installer places the overlay under `/lib/modules/<release>/updates/lapbc710-camera` and verifies module resolution with `depmod` and `modinfo`. On distributions without Debian’s initramfs tools, rebuild the target initramfs using the distribution’s tooling if it contains IPU6 modules. Follow the distribution’s module-signing procedure if Secure Boot enforces signatures. Boot the target kernel, keep the previous working kernel as a fallback, and rebuild after kernel upgrades. The builder has no DKMS or automatic upgrade hook. [Linux external module build guide](https://docs.kernel.org/kbuild/modules.html)

### libcamera and PipeWire

Use the upstream libcamera **v0.4.0** source, or a distribution source tree whose libcamera ABI is **0.4** and accepts the patch. The builder requires a C++ compiler, Meson, Ninja, pkg-config, libyaml and libudev development headers, Python modules Jinja2, PyYAML and PLY, and a supported crypto library with OpenSSL tooling for IPA signing. Package names vary. [libcamera build requirements](https://libcamera.org/getting-started.html)

```bash
stage=$(bash build-from-source.sh libcamera /path/to/libcamera-v0.4.0)
```

Before switching the desktop stack, confirm your PipeWire libcamera SPA plugin links to `libcamera.so.0.4`. Locate `libspa-libcamera.so` using the distro package manager and check its dependencies with `readelf -d /path/to/libspa-libcamera.so`. If it uses a newer ABI, test the stock distribution stack first. Port the patch to that release if needed. Keep the libcamera libraries and IPA modules from the same build.

With PipeWire, WirePlumber, and PipeWire Pulse running as systemd user services, use the commands below. They install a versioned local bundle and restart those multimedia services, which briefly interrupts audio and video. On other session managers, use the equivalent process environment for both the camera discovery service and the PipeWire server. The bundle’s libraries are at its root, its IPA modules are in `ipa/`, and its tuning is in `tuning/`. See `configure-desktop.sh` for the exact environment variables.

```bash
bundle=$(sudo bash install-userspace.sh "$stage")
bash configure-desktop.sh "$bundle"
bash verify-host.sh
```

Restore the distribution’s desktop stack with `bash configure-desktop.sh --stock`. The optional Debian APT helpers, rollback notes, and host findings are in the [Debian 13 runbook](docs/debian-13.md).

## Browser and troubleshooting

- In Chrome, enable **PipeWire Camera support** at `chrome://flags/#enable-webrtc-pipewire-camera` if the option exists. In Firefox, set `media.webrtc.camera.allow-pipewire` to `true`. Restart the browser, allow camera access, and select **Built-in Front Camera**.
- Direct V4L2 applications can list the IPU6’s many raw capture nodes. Keep those devices available for libcamera. Use the single processed PipeWire source in the browser.
- Run `python3 verify-browser.py chrome --resolution 1280x720 --check-image` or the corresponding `firefox` command. The test uses a disposable browser profile and localhost. It reports video and optional brightness statistics without saving frames.
- For a compatibility report, include your distribution, kernel, libcamera and PipeWire versions, the board and ACPI IDs, and which layer failed. Share filtered logs with personal details removed.

## Upstream and licenses

The matching hardware report is [intel/ipu6-drivers#323](https://github.com/intel/ipu6-drivers/issues/323). The long-term integration paths are [Linux media](https://docs.kernel.org/process/submitting-patches.html) for the bridge and sensor, and [libcamera](https://libcamera.org/contributing.html) for RGB‑IR processing and tuning. [Source and license notices](NOTICE.md)

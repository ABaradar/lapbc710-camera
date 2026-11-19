# Source and license notices

- `bridge/ipu-bridge.c` is based on the Debian Linux 6.12.117-1 source and retains the Linux source file’s GPL-2.0 SPDX identifier. The repository adds the OVTI01AF sensor entry. [Linux source](https://github.com/torvalds/linux/blob/master/drivers/media/pci/intel/ipu-bridge.c) · [GPL version 2](LICENSES/GPL-2.0-only.txt)
- `sensor/ov01a1s.c` is based on Intel’s driver at commit `c09fa9a6e98b951ea4ab9d4100aa85281a659074`. It retains Intel’s copyright notice and GPL-2.0 SPDX identifier. This copy includes local changes for the OVTI01AF identifier, firmware-node camera controls and propagation of power-resource errors. [Intel driver source](https://github.com/intel/ipu6-drivers/blob/c09fa9a6e98b951ea4ab9d4100aa85281a659074/drivers/media/i2c/ov01a1s.c) · [GPL version 2](LICENSES/GPL-2.0-only.txt)
- `libcamera-lapbc710.patch` modifies libcamera files licensed under LGPL-2.1-or-later. [libcamera source](https://gitlab.freedesktop.org/camera/libcamera) · [LGPL version 2.1](LICENSES/LGPL-2.1-or-later.txt)
- `tuning/simple/ov01a1s.yaml` is available under [CC0 1.0](LICENSES/CC0-1.0.txt).
- Original shell and Python scripts, documentation, and build wrappers are available under the [MIT License](LICENSE).

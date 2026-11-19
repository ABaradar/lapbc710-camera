# Debian 13 setup and test notes

## What is installed

This laptop has a Tiger Lake Intel IPU6 at PCI `0000:00:05.0` (`8086:9a19`) and an OmniVision OV01A1S RGB‑IR sensor identified by ACPI as `OVTI01AF:00`. The sensor is on I²C controller `00:15.3`, address `0x36`, and sends pixels over CSI‑2 port 5. The IPU6 uses a firmware-backed capture pipeline. [Intel hardware specification](https://www.intel.com/content/dam/support/us/en/documents/intel-nuc/laptop-kit/BC57_KIT_PROD_SPEC.pdf) · [Intel IPU6 documentation](https://docs.kernel.org/driver-api/media/drivers/ipu6.html)

| Layer | Installed configuration |
| --- | --- |
| Kernel | Debian `6.12.117+deb13-amd64` with two modules in `/lib/modules/6.12.117+deb13-amd64/updates/lapbc710-camera/`. `ipu-bridge` adds the ACPI sensor ID and creates the CSI link. `ov01a1s` binds the sensor. |
| Image processing | Patched Debian libcamera `0.4.0-7` at `/usr/local/lib/lapbc710-camera/releases/6fb58b25c23b8cf8`. The processing separates the RGB‑IR mosaic before debayering and rotates the image 180°. Its sensor-specific tuning fixes the black reference, and automatic exposure can add up to 4× digital gain in dark scenes. |
| Desktop | User systemd drop-ins named `50-lapbc710-camera.conf` for both `pipewire.service` and `wireplumber.service` point to the same local libcamera build and signed IPA modules. The desktop portal exposes **Built-in Front Camera**. |
| Browser | Chrome has **PipeWire Camera support** enabled. The normal Firefox profile sets `media.webrtc.camera.allow-pipewire` in `user.js`, which applies when Firefox next launches. Site and desktop camera permission prompts still apply. |

The stock kernel saw the IPU6 but had no driver bound to the sensor. Once the sensor streamed, Debian’s software ISP treated the 4×4 RGB‑IR pattern as a 2×2 Bayer pattern. This produced the magenta checkerboard. The firmware also reported zero rotation even though the image needed a half turn. Raw sample analysis confirmed the repeating `IGIG / GBGR / IGIG / GRGB` tile. The live PipeWire comparison measured a reduction in repeating chroma variation from 59.52 to 0.27 on an 8-bit-derived scale. The image still uses libcamera’s generic color tuning. [Intel RGB‑IR sensor profile](https://github.com/intel/ipu6-camera-hal/blob/main/config/linux/ipu6/gcss/graph_settings_ov01a1s.xml)

After the image fix, browser testing exposed an independent libcamera `0.4.0` crash. Kernel logs identified an integer divide error in the simple IPA’s automatic exposure code. A nearly full black-level offset could leave fewer histogram entries than exposure bins, making the old bin-width calculation zero. The patch maps each remaining entry to a valid bin even for a very short histogram.

Meet later showed **Camera might be blocked** while Chrome was actively receiving 1280×720 frames. A sample of the active stream showed over 99% of pixels at or near black. The camera's synthetic pattern measured a black reference of 64 on the 10-bit sensor. [The sensor tuning](../tuning/simple/ov01a1s.yaml) pins that reference instead of estimating it from each scene. The patched IPA adds sensor digital gain only after exposure and analog gain reach their limits, and reduces digital gain first when the exposure algorithm detects excess brightness. The raw sensor can still produce nearly black frames in a very dark room or with a covered lens. After adding light, a local Chrome test received 1280×720 frames with median luma 129 out of 255 and 0% near-black pixels. PipeWire stayed running.

## Google Meet and the extra cameras

The 64 `/dev/video*` nodes are IPU6 ISYS capture endpoints. They expose parts of the raw media-controller pipeline. The sensor, its active link, image processing and browser capture all have to work together for normal webcam video. A browser using direct Video4Linux can enumerate the IPU6 endpoints individually. PipeWire groups the pipeline into a single usable **Built-in Front Camera**. Keep the kernel endpoints available because libcamera uses them. [WirePlumber camera configuration](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/video.html)

- **Chrome** — open `chrome://flags/#enable-webrtc-pipewire-camera` and check that **PipeWire Camera support** is **Enabled**. Fully quit and reopen Chrome after changing it. [Chromium camera flag](https://chromium.googlesource.com/chromium/src/+/36ddf4a08efa862b60953b7d3ef82c8ce6c99914/chrome/browser/flag-metadata.json)
- **Firefox** — open `about:config` and check that `media.webrtc.camera.allow-pipewire` is `true`. Fully quit and reopen Firefox to pick up the startup preference. [Firefox backend selection](https://sources.debian.org/src/firefox-esr/153.5.1esr-1~deb13u1/dom/media/systemservices/video_engine/video_capture_factory.cc)
- In Google Meet, allow camera access when prompted, open **Settings → Video**, and select **Built-in Front Camera**. If the old list is still present, quit the entire browser and reopen it. If the camera is missing after that, check the site’s camera permission and the desktop camera prompt. No changes to Meet or its account settings were made during local testing.

## Verify after reboot

Boot into `6.12.117+deb13-amd64` and log into the same desktop user. The module aliases and dependency index load the camera drivers, and systemd reads the two desktop drop-ins. Chrome and Firefox retain their profile settings. No live reload, custom GRUB option, or manual launch is required for this configuration.

Run from the repository root with the camera app and any meeting preview closed.

```bash
bash verify-host.sh
python3 verify-browser.py chrome
python3 verify-browser.py firefox
```

To check the image itself, uncover the lens, point it toward a lit scene, and run `python3 verify-browser.py chrome --resolution 1280x720 --check-image`. This reports brightness percentiles and the percentage of near-black pixels. It does not save images.

The host check verifies sensor binding, one built-in PipeWire camera, portal availability, and 90 delivered frames at 1280×800. The browser checks use disposable profiles on localhost and wait for a real video frame. They do not join a meeting or save video. An attached external webcam can appear in addition to the built-in one.

Chrome 157 and Firefox 160 each listed one built-in camera and received real frames at 640×480 and 1280×720, with no PipeWire restart during the tests. With Chrome explicitly forced to direct V4L2, the localhost test found no camera it could open. A cold boot and the signed-in Meet preview remain to be checked.

## Carry the fix to a new kernel

Kernel modules must match their exact kernel release and symbol versions. Debian package upgrades do not rebuild this overlay automatically. Keep the currently working kernel available in GRUB until the new one passes capture.

The build script was tested against `6.12.117+deb13-amd64` and `6.12.116+deb13-amd64`. The latter was built as a second-release check. Its boot and camera capture were left untested.

1. Install the new Debian kernel and matching headers. Set `release` to its full directory name under `/lib/modules`, including the Debian architecture suffix.
2. Build and stage the camera modules before rebooting.

   ```bash
   bash build-kernel.sh "$release"
   sudo bash install-kernel.sh "$release"
   ```

   The builder uses the exact Debian source package version identified by the installed headers. If that source is no longer available from APT, obtain the matching Debian package before porting. If the new kernel already resolves the sensor ID or the bridge source has changed shape, the script stops for review. Test the new native driver first. Older vendor sensor code may need API changes on a newer kernel.
3. Boot the new kernel and run the checks above. If capture fails, boot the previous working kernel from GRUB’s **Advanced options** and inspect `journalctl -k -b` from the failing boot. These out-of-tree modules are unsigned. The tested machine has Secure Boot disabled. If signature enforcement is enabled later, sign the modules with a key the running kernel trusts.

## Carry the fix through desktop package upgrades

The local userspace bundle sits outside distro package ownership, so APT does not overwrite it. After any libcamera, PipeWire or WirePlumber update, run the host and browser checks again. The local bundle was built against Debian libcamera `0.4.0-7`. A new libcamera ABI or an incompatible plugin update requires testing a compatible build. Do not keep an old override indefinitely in place of distro updates.

To rebuild the verified Debian version, enable the matching `deb-src` entry and install the build tools if needed.

```bash
sudo apt install build-essential dpkg-dev meson ninja-build patch libyaml-dev libudev-dev libgnutls28-dev python3-jinja2 python3-yaml python3-ply
stage=$(bash build-userspace.sh)
bundle=$(sudo bash install-userspace.sh "$stage")
bash configure-desktop.sh "$bundle"
bash verify-host.sh
```

`build-userspace.sh` deliberately stops for a different package version. To migrate to a new version, first try the stock stack using the rollback command below. If stock still needs the RGB‑IR or orientation fix, rebase [the patch](../libcamera-lapbc710.patch) onto the installed Debian source, reevaluate the exposure fix, and update the build and installer for the new library ABI before deploying. Review `systemctl --user show pipewire wireplumber -p DropInPaths` and `journalctl --user -u pipewire -b` when diagnosing an upgrade.

## Rollback and script reference

- `configure-desktop.sh --stock` removes the camera-specific desktop drop-ins and restarts PipeWire, WirePlumber and PipeWire Pulse. This briefly interrupts audio and video. `configure-desktop.sh /usr/local/lib/lapbc710-camera` selects the earlier local image-processing build, which still has the exposure crash. Prefer the verified release listed above.
- `configure-browser.py chrome --default` clears the managed Chrome flag while Chrome is closed. `configure-browser.py firefox --profile PROFILE_DIRECTORY --default` removes the managed startup block. Reset the preference in Firefox’s `about:config` as well if Firefox previously loaded it.
- `build-kernel.sh` builds for the running kernel by default, or for the release supplied as its argument. `install-kernel.sh` installs only that release’s staged modules and runs `depmod`. It refreshes that release’s initramfs if the camera modules were already included. A kernel rollback is simplest by selecting an older kernel in GRUB.
- `test-host.sh` and `install-host.sh` are the initial live-bring-up scripts. The live tester expects the original unbound sensor and exits if `ov01a1s` is already loaded. Use the newer build, install and verify scripts for maintenance.

## Why kernel development stayed on the host

The IPU6 processor is alone in IOMMU group 2 and advertises function-level reset. The camera sensor’s I²C controller is in group 14 with two other controllers, including the laptop’s touchpad controller. Full capture in a VM would also need working guest ACPI descriptions and sensor power, clock and reset control. Hardware capture in a guest was left unverified. Loadable module development on the host produced a working camera without changing the boot configuration or rebooting during testing. [Linux VFIO documentation](https://docs.kernel.org/driver-api/vfio.html)

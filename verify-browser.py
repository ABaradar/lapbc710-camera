#!/usr/bin/env python3
"""Test real WebRTC capture on localhost with a disposable browser profile."""

import argparse
import http.server
import json
import os
import pathlib
import signal
import subprocess
import tempfile
import time

PAGE = b"""<!doctype html><meta charset=utf-8><video muted autoplay playsinline></video>
<script>
async function check() {
  const report = {};
  let stream;
  const devices = async () => (await navigator.mediaDevices.enumerateDevices())
    .filter(device => device.kind === 'videoinput');
  try {
    const parameters = new URLSearchParams(location.search);
    const constraints = {};
    if (parameters.has('width')) constraints.width = {exact: Number(parameters.get('width'))};
    if (parameters.has('height')) constraints.height = {exact: Number(parameters.get('height'))};
    stream = await navigator.mediaDevices.getUserMedia({video: constraints});
    if (!parameters.has('direct') && stream.getVideoTracks()[0].label !== 'Built-in Front Camera') {
      const camera = (await devices()).find(device => device.label === 'Built-in Front Camera');
      if (!camera) throw Error('The built-in PipeWire camera was not enumerated');
      stream.getTracks().forEach(track => track.stop());
      constraints.deviceId = {exact: camera.deviceId};
      stream = await navigator.mediaDevices.getUserMedia({video: constraints});
    }
    const video = document.querySelector('video');
    video.srcObject = stream;
    await video.play();
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(Error('No video frame arrived')), 7000);
      video.requestVideoFrameCallback(() => { clearTimeout(timer); resolve(); });
    });
    report.captured = [video.videoWidth, video.videoHeight];
    if (parameters.has('checkImage')) {
      const canvas = document.createElement('canvas');
      canvas.width = 160;
      canvas.height = 90;
      const context = canvas.getContext('2d', {willReadFrequently: true});
      await new Promise(resolve => setTimeout(resolve, 3500));
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
      const luma = [];
      for (let offset = 0; offset < pixels.length; offset += 4) {
        luma.push(0.2126 * pixels[offset] + 0.7152 * pixels[offset + 1] + 0.0722 * pixels[offset + 2]);
      }
      luma.sort((a, b) => a - b);
      report.image = {
        medianLuma: Math.round(luma[Math.floor(luma.length * 0.5)]),
        p90Luma: Math.round(luma[Math.floor(luma.length * 0.9)]),
        nearBlackPercent: Math.round(1000 * luma.filter(value => value <= 8).length / luma.length) / 10,
      };
      if (report.image.nearBlackPercent >= 98) throw Error('Camera frames are almost entirely black');
    }
  } catch (error) { report.error = String(error); }
  try {
    report.cameras = (await devices()).map(device => device.label);
  } catch (error) { report.enumerationError = String(error); }
  if (stream) stream.getTracks().forEach(track => track.stop());
  await fetch('/result', {method: 'POST', body: JSON.stringify(report)});
}
check();
</script>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        root = self.path.partition("?")[0] == "/"
        self.send_response(200 if root else 404)
        self.end_headers()
        if root:
            self.wfile.write(PAGE)

    def do_POST(self):
        if self.path != "/result":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.result = json.loads(body)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("browser", choices=("chrome", "firefox"))
    parser.add_argument("--direct-v4l2", action="store_true")
    parser.add_argument("--resolution", choices=("640x480", "1280x720", "1280x800"))
    parser.add_argument("--check-image", action="store_true",
                        help="measure brightness in memory and fail on nearly black frames")
    args = parser.parse_args()
    with (
        tempfile.TemporaryDirectory(prefix="lapbc710-browser-", ignore_cleanup_errors=True) as directory,
        http.server.HTTPServer(("127.0.0.1", 0), Handler) as server,
    ):
        profile = pathlib.Path(directory)
        if args.browser == "chrome":
            choice = 2 if args.direct_v4l2 else 1
            state = {"browser": {"enabled_labs_experiments": [f"enable-webrtc-pipewire-camera@{choice}"]}}
            (profile / "Local State").write_text(json.dumps(state))
            command = [
                "google-chrome", f"--user-data-dir={profile}", "--headless=new",
                "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
                "--use-fake-ui-for-media-stream",
            ]
        else:
            allow_pipewire = str(not args.direct_v4l2).lower()
            (profile / "user.js").write_text(
                f'user_pref("media.webrtc.camera.allow-pipewire", {allow_pipewire});\n'
                'user_pref("media.navigator.permission.disabled", true);\n'
            )
            command = ["firefox", "--headless", "--no-remote", "--profile", str(profile)]
        with tempfile.TemporaryFile() as log:
            parameters = ["direct=1"] if args.direct_v4l2 else []
            if args.check_image:
                parameters.append("checkImage=1")
            if args.resolution:
                width, height = args.resolution.split("x")
                parameters += [f"width={width}", f"height={height}"]
            url = f"http://127.0.0.1:{server.server_port}/"
            if parameters:
                url += "?" + "&".join(parameters)
            process = subprocess.Popen(
                command + [url],
                stdout=log, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                server.timeout = 0.5
                server.result = None
                deadline = time.monotonic() + 24
                while server.result is None and process.poll() is None and time.monotonic() < deadline:
                    server.handle_request()
                if server.result is None:
                    log.seek(0)
                    print(log.read().decode(errors="replace")[-2500:])
                    raise SystemExit("Browser did not report a result. Check for a camera portal prompt.")
                print(json.dumps(server.result, indent=2))
                return int(not server.result.get("captured") or "error" in server.result)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


if __name__ == "__main__":
    raise SystemExit(main())

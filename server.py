# /// script
# requires-python = ">=3.11"
# ///
"""Local web server for the Watchbar library. Run with `uv run server.py`."""

import json
import mimetypes
import os
import re
import sys
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import youtube

HOST = "127.0.0.1"
PORT = 8765
WEB_DIR = os.path.join(youtube.ROOT, "web")
AUTO_REFRESH_INTERVAL = 300
DOWNLOAD_CONCURRENCY = 3
CHUNK = 1 << 20


class Library:
    """Watch Later, subscriptions and download state, shared by all requests."""

    def __init__(self):
        self.lock = threading.Lock()
        self.watch_later = []
        self.subscriptions = []
        self.set_video_ids = {}
        self.downloads = {}  # id -> {"status", "progress", "message"}
        self.removed = set()
        self.loading = False
        self.error = None
        self.download_slots = threading.BoundedSemaphore(DOWNLOAD_CONCURRENCY)

    def snapshot(self):
        with self.lock:
            return {
                "loading": self.loading,
                "error": self.error,
                "watchLater": self.watch_later,
                "subscriptions": self.subscriptions,
                "downloads": self.downloads,
                "local": sorted(youtube.local_files()),
            }

    def refresh(self):
        with self.lock:
            if self.loading:
                return
            self.loading = True
        threading.Thread(target=self._load, daemon=True).start()

    def _load(self):
        error = None
        try:
            if not youtube.cookies_are_fresh():
                youtube.extract_cookies()
            watch_later = youtube.fetch_watch_later()
            if watch_later is None:
                error = ("Watch Later did not load. Check that Safari is "
                         "signed in to YouTube.")
            subscriptions = youtube.fetch_subscriptions()
            try:
                set_video_ids = youtube.fetch_set_video_ids()
            except Exception as e:
                print(f"[load] setVideoIds failed: {e}")
                set_video_ids = None
        except Exception as e:
            print(f"[load] failed: {e}")
            watch_later = subscriptions = set_video_ids = None
            error = f"Loading failed: {e}"
        with self.lock:
            if watch_later is not None:
                self.watch_later = watch_later
            if subscriptions is not None:
                self.subscriptions = subscriptions
            if set_video_ids is not None:
                self.set_video_ids = set_video_ids
            self.error = error
            self.loading = False
        print(f"[load] {len(self.watch_later)} Watch Later, "
              f"{len(self.subscriptions)} subscription uploads")

    def find(self, vid):
        with self.lock:
            for video in self.watch_later + self.subscriptions:
                if video["id"] == vid:
                    return video
        return None

    def _in_watch_later(self, vid):
        return any(v["id"] == vid for v in self.watch_later)

    def ensure_in_watch_later(self, vid):
        """Downloads stay a subset of Watch Later, so a Subscriptions video is
        saved to Watch Later before it downloads."""
        video = self.find(vid)
        with self.lock:
            self.removed.discard(vid)
            if video is None or self._in_watch_later(vid):
                return
            self.watch_later.append(dict(video))
        threading.Thread(target=self._add_remote, args=(vid,), daemon=True).start()

    def _add_remote(self, vid):
        try:
            if not youtube.add_to_watch_later(vid):
                youtube.extract_cookies()
                if not youtube.add_to_watch_later(vid):
                    print(f"[add] failed: {vid}")
        except Exception as e:
            print(f"[add] error: {e}")

    def remove(self, vid):
        with self.lock:
            svid = self.set_video_ids.pop(vid, None)
            self.watch_later = [v for v in self.watch_later if v["id"] != vid]
            in_flight = self.downloads.get(vid, {}).get("status") == "downloading"
            if in_flight:
                self.removed.add(vid)
            else:
                self.downloads.pop(vid, None)
        if not in_flight:
            youtube.delete_local_files(vid)
        threading.Thread(
            target=self._remove_remote, args=(vid, svid), daemon=True
        ).start()

    def _remove_remote(self, vid, svid):
        try:
            if svid and youtube.remove_from_watch_later(vid, svid):
                return
            # Safari rotates YouTube's session cookies, which logs out the
            # cached copy before COOKIE_MAX_AGE is reached.
            youtube.extract_cookies()
            svid = youtube.fetch_set_video_ids().get(vid)
            if not svid or not youtube.remove_from_watch_later(vid, svid):
                print(f"[remove] failed: {vid}")
        except Exception as e:
            print(f"[remove] error: {e}")

    def delete_local(self, vid):
        with self.lock:
            self.downloads.pop(vid, None)
        youtube.delete_local_files(vid)

    def download(self, vid):
        with self.lock:
            entry = self.downloads.get(vid)
            if entry and entry["status"] in ("queued", "downloading"):
                return
            if vid in youtube.local_files():
                return
            self.downloads[vid] = {"status": "queued", "progress": None,
                                   "message": None}
        self.ensure_in_watch_later(vid)
        threading.Thread(target=self._download, args=(vid,), daemon=True).start()

    def download_all(self):
        with self.lock:
            ids = [v["id"] for v in self.watch_later]
        for vid in ids:
            self.download(vid)

    def _download(self, vid):
        with self.download_slots:
            with self.lock:
                if vid in self.removed:
                    self.downloads.pop(vid, None)
                    return
                self.downloads[vid]["status"] = "downloading"

            def progress(pct):
                with self.lock:
                    entry = self.downloads.get(vid)
                    if entry:
                        entry["progress"] = pct

            ok, output = youtube.download(vid, progress)
        with self.lock:
            removed = vid in self.removed
            if ok:
                self.downloads.pop(vid, None)
            else:
                self.downloads[vid] = {
                    "status": "failed", "progress": None,
                    "message": "Download failed. Click to retry.",
                }
                print(f"[download] failed {vid}:\n{output[-1500:]}")
        if ok and removed:
            youtube.delete_local_files(vid)


library = Library()


def auto_refresh():
    while True:
        time.sleep(AUTO_REFRESH_INTERVAL)
        library.refresh()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def _json(self, data, status=HTTPStatus.OK):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _not_found(self):
        self._json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/state":
            return self._json(library.snapshot())
        m = re.fullmatch(r"/api/transcript/([\w-]{11})", path)
        if m:
            file = youtube.local_files().get(m.group(1))
            if not file:
                return self._not_found()
            return self._json(youtube.transcript(m.group(1), file))
        m = re.fullmatch(r"/media/([\w-]{11})\.vtt", path)
        if m:
            file = youtube.local_files().get(m.group(1))
            vtt = file and youtube.captions_vtt(m.group(1), file)
            if not vtt:
                return self._not_found()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/vtt; charset=utf-8")
            self.send_header("Content-Length", str(len(vtt)))
            self.end_headers()
            self.wfile.write(vtt)
            return
        m = re.fullmatch(r"/media/([\w-]{11})\.mp4", path)
        if m:
            file = youtube.local_files().get(m.group(1))
            if not file:
                return self._not_found()
            return self._send_file(file, "video/mp4")
        return self._static(path)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            body = {}
        vid = body.get("id", "")
        actions = {
            "/api/refresh": lambda: library.refresh(),
            "/api/download-all": lambda: library.download_all(),
            "/api/download": lambda: library.download(vid),
            "/api/watch-later/add": lambda: library.ensure_in_watch_later(vid),
            "/api/watch-later/remove": lambda: library.remove(vid),
            "/api/delete-local": lambda: library.delete_local(vid),
        }
        action = actions.get(path)
        if action is None:
            return self._not_found()
        if path not in ("/api/refresh", "/api/download-all") and not re.fullmatch(
                r"[\w-]{11}", vid):
            return self._json({"error": "bad id"}, HTTPStatus.BAD_REQUEST)
        action()
        self._json(library.snapshot())

    def _static(self, path):
        if path == "/":
            path = "/index.html"
        file = os.path.realpath(os.path.join(WEB_DIR, path.lstrip("/")))
        if not file.startswith(WEB_DIR + os.sep) or not os.path.isfile(file):
            return self._not_found()
        mime = mimetypes.guess_type(file)[0] or "application/octet-stream"
        self._send_file(file, mime)

    def _send_file(self, file, mime):
        size = os.path.getsize(file)
        start, end = 0, size - 1
        ranged = self.headers.get("Range")
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", ranged or "")
        if m:
            if m.group(1):
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
            elif m.group(2):
                start = max(0, size - int(m.group(2)))
            if start > end:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            self.send_response(HTTPStatus.PARTIAL_CONTENT)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else:
            self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        try:
            with open(file, "rb") as f:
                f.seek(start)
                remaining = end - start + 1
                while remaining > 0:
                    chunk = f.read(min(CHUNK, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the browser cancels range requests while seeking


def main():
    sys.stdout.reconfigure(line_buffering=True)
    library.refresh()
    threading.Thread(target=auto_refresh, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    url = f"http://{HOST}:{PORT}/"
    print(f"Watchbar web is running at {url}")
    if not os.environ.get("WATCHBAR_WEB_NO_BROWSER"):
        webbrowser.open(url)
    server.serve_forever()


if __name__ == "__main__":
    main()

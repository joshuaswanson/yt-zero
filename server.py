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
from urllib.parse import parse_qs, urlparse

import youtube

HOST = "127.0.0.1"
PORT = 8765
WEB_DIR = os.path.join(youtube.ROOT, "web")
AUTO_REFRESH_INTERVAL = 300
DOWNLOAD_CONCURRENCY = 3
CHUNK = 1 << 20
CHANNELS_MAX_AGE = 3600
CHANNEL_PAGE = 30
CHANNEL_VIDEOS_MAX_AGE = 600
OTHER_DOWNLOADS_FILE = os.path.join(youtube.CACHE_DIR, "other_downloads.json")


class Library:
    """Watch Later, subscriptions and download state, shared by all requests."""

    def __init__(self):
        self.lock = threading.Lock()
        self.watch_later = []
        self.subscriptions = []
        self.subscription_days = youtube.SUBSCRIPTIONS_DAYS
        self.subscriptions_end = False
        self.loading_more = False
        self.channels = None
        self.channels_fetched_at = 0
        self.channels_lock = threading.Lock()
        self.channel_videos = {}  # channel id -> {"videos", "count", "end", "fetched_at"}
        self.channel_videos_lock = threading.Lock()
        self.set_video_ids = {}
        self.downloads = {}  # id -> {"status", "progress", "message"}
        # Videos downloaded without being saved to Watch Later, by id.
        self.other_downloads = _read_json(OTHER_DOWNLOADS_FILE, {})
        self.active = {}  # id -> youtube.Download
        self.removed = set()
        self.loading = False
        self.error = None
        self.download_slots = threading.BoundedSemaphore(DOWNLOAD_CONCURRENCY)

    def snapshot(self):
        with self.lock:
            watch_later_ids = {v["id"] for v in self.watch_later}
            return {
                "loading": self.loading,
                "error": self.error,
                "watchLater": self.watch_later,
                "subscriptions": self.subscriptions,
                "subscriptionDays": self.subscription_days,
                "subscriptionsEnd": self.subscriptions_end,
                "loadingMore": self.loading_more,
                "downloads": self.downloads,
                "otherDownloads": [v for vid, v in self.other_downloads.items()
                                   if vid not in watch_later_ids],
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
        with self.lock:
            days = self.subscription_days
        try:
            if not youtube.cookies_are_fresh():
                youtube.extract_cookies()
            watch_later = youtube.fetch_watch_later()
            if watch_later is None:
                error = ("Watch Later did not load. Check that Safari is "
                         "signed in to YouTube.")
            subscriptions, subscriptions_end = youtube.fetch_subscriptions(days)
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
                self._set_subscriptions(days, subscriptions, subscriptions_end)
            if set_video_ids is not None:
                self.set_video_ids = set_video_ids
            self.error = error
            self.loading = False
        print(f"[load] {len(self.watch_later)} Watch Later, "
              f"{len(self.subscriptions)} subscription uploads")

    def _set_subscriptions(self, days, subscriptions, reached_end):
        # A fetch for a shorter window than the current one is out of date.
        if days == self.subscription_days:
            self.subscriptions = subscriptions
            self.subscriptions_end = reached_end

    def load_more_subscriptions(self):
        with self.lock:
            if self.loading_more or self.subscriptions_end:
                return
            self.loading_more = True
            self.subscription_days += youtube.SUBSCRIPTIONS_MORE_DAYS
            days = self.subscription_days
        threading.Thread(
            target=self._load_more, args=(days,), daemon=True
        ).start()

    def _load_more(self, days):
        try:
            subscriptions, reached_end = youtube.fetch_subscriptions(days)
        except Exception as e:
            print(f"[load] more subscriptions error: {e}")
            subscriptions, reached_end = None, False
        with self.lock:
            if subscriptions is not None:
                self._set_subscriptions(days, subscriptions, reached_end)
            self.loading_more = False

    def get_channels(self, force=False):
        with self.channels_lock:
            stale = time.time() - self.channels_fetched_at > CHANNELS_MAX_AGE
            if force or self.channels is None or stale:
                channels = youtube.fetch_channels()
                if channels is not None:
                    self.channels = channels
                    self.channels_fetched_at = time.time()
            return self.channels

    def set_subscribed(self, channel, subscribed):
        ok = youtube.set_subscribed(channel["id"], subscribed)
        if not ok:
            # Safari rotates YouTube's session cookies, which logs out the
            # cached copy before COOKIE_MAX_AGE is reached.
            youtube.extract_cookies()
            ok = youtube.set_subscribed(channel["id"], subscribed)
        if ok:
            with self.channels_lock:
                channels = [c for c in self.channels or [] if c["id"] != channel["id"]]
                if subscribed:
                    channels.append({"id": channel["id"], "name": str(channel.get("name", "")),
                                     "avatar": str(channel.get("avatar", ""))})
                self.channels = sorted(channels, key=lambda c: c["name"].casefold())
        return ok

    def get_channel_videos(self, channel_id, more=False, refresh=False):
        with self.channel_videos_lock:
            with self.lock:
                entry = self.channel_videos.get(channel_id)
            fresh = entry and time.time() - entry["fetched_at"] < CHANNEL_VIDEOS_MAX_AGE
            if entry and fresh and not more and not refresh:
                return entry
            count = entry["count"] if entry else CHANNEL_PAGE
            if more and entry:
                count += CHANNEL_PAGE
            videos, reached_end = youtube.fetch_channel_videos(channel_id, count)
            if videos is None:
                return None
            entry = {"videos": videos, "count": count, "end": reached_end,
                     "fetched_at": time.time()}
            with self.lock:
                self.channel_videos[channel_id] = entry
            return entry

    def find(self, vid):
        with self.lock:
            channel_videos = [v for e in self.channel_videos.values() for v in e["videos"]]
            others = list(self.other_downloads.values())
            for video in self.watch_later + self.subscriptions + channel_videos + others:
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
            self._forget_other_download(vid)
        youtube.delete_local_files(vid)

    def _remember_other_download(self, vid):
        video = self.find(vid)
        with self.lock:
            if video is None or self._in_watch_later(vid):
                return
            self.other_downloads[vid] = {
                k: video[k] for k in ("id", "title", "duration", "timestamp", "channel")}
            _write_json(OTHER_DOWNLOADS_FILE, self.other_downloads)

    def _forget_other_download(self, vid):
        if self.other_downloads.pop(vid, None):
            _write_json(OTHER_DOWNLOADS_FILE, self.other_downloads)

    def download(self, vid, save_to_watch_later=True):
        with self.lock:
            entry = self.downloads.get(vid)
            if entry and entry["status"] in ("queued", "downloading"):
                return
            if vid in self.active or vid in youtube.local_files():
                return
            entry = {"status": "queued", "progress": None, "message": None}
            self.downloads[vid] = entry
        if save_to_watch_later:
            self.ensure_in_watch_later(vid)
        else:
            self._remember_other_download(vid)
        threading.Thread(
            target=self._download, args=(vid, entry), daemon=True
        ).start()

    def cancel(self, vid):
        with self.lock:
            self.downloads.pop(vid, None)
            self._forget_other_download(vid)
            job = self.active.get(vid)
        if job:
            job.cancel()

    def download_all(self):
        with self.lock:
            ids = [v["id"] for v in self.watch_later]
        for vid in ids:
            self.download(vid)

    def _download(self, vid, entry):
        def progress(pct):
            with self.lock:
                entry["progress"] = pct

        with self.download_slots:
            with self.lock:
                if self.downloads.get(vid) is not entry:
                    return
                if vid in self.removed:
                    self.downloads.pop(vid, None)
                    return
                entry["status"] = "downloading"
                job = self.active[vid] = youtube.Download(vid, progress)
            ok, output = job.run()
        with self.lock:
            del self.active[vid]
            removed = vid in self.removed
            if job.cancelled:
                return
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


def _read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


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
        m = re.fullmatch(r"/api/channel/(UC[\w-]{22})", path)
        if m:
            query = parse_qs(urlparse(self.path).query)
            entry = library.get_channel_videos(
                m.group(1), more=query.get("more") == ["1"],
                refresh=query.get("refresh") == ["1"])
            if entry is None:
                return self._json({"error": "fetch failed"}, HTTPStatus.BAD_GATEWAY)
            return self._json({"videos": entry["videos"], "end": entry["end"]})
        if path == "/api/channels":
            force = parse_qs(urlparse(self.path).query).get("refresh") == ["1"]
            return self._json({"channels": library.get_channels(force)})
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
        if path == "/api/subscription":
            channel = body.get("channel") or {}
            if not re.fullmatch(r"UC[\w-]{22}", str(channel.get("id", ""))):
                return self._json({"error": "bad channel"}, HTTPStatus.BAD_REQUEST)
            ok = library.set_subscribed(channel, body.get("subscribed") is True)
            return self._json({"ok": ok, "channels": library.channels})
        vid = body.get("id", "")
        actions = {
            "/api/refresh": lambda: library.refresh(),
            "/api/download-all": lambda: library.download_all(),
            "/api/subscriptions/more": lambda: library.load_more_subscriptions(),
            "/api/download": lambda: library.download(
                vid, save_to_watch_later=body.get("watchLater") is not False),
            "/api/cancel": lambda: library.cancel(vid),
            "/api/watch-later/add": lambda: library.ensure_in_watch_later(vid),
            "/api/watch-later/remove": lambda: library.remove(vid),
            "/api/delete-local": lambda: library.delete_local(vid),
        }
        action = actions.get(path)
        if action is None:
            return self._not_found()
        if path not in ("/api/refresh", "/api/download-all",
                        "/api/subscriptions/more") and not re.fullmatch(
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

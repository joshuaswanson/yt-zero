"""YouTube access through yt-dlp and Safari's cookies."""

import hashlib
import http.cookiejar
import json
import os
import re
import ssl
import subprocess
import threading
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
DOWNLOAD_DIR = os.path.join(ROOT, "downloads")
CACHE_DIR = os.path.join(ROOT, ".cache")
COOKIE_FILE = os.path.join(CACHE_DIR, "cookies.txt")
TRANSCRIPT_DIR = os.path.join(CACHE_DIR, "transcripts")
CAPTION_DIR = os.path.join(CACHE_DIR, "captions")

YT_DLP = "yt-dlp"
FFMPEG = "ffmpeg"
FFPROBE = "ffprobe"
COOKIE_MAX_AGE = 1800
SUBSCRIPTIONS_DAYS = 8
SUBSCRIPTIONS_MORE_DAYS = 7
SUBSCRIPTIONS_VIDEOS_PER_DAY = 25

for _d in (DOWNLOAD_DIR, CACHE_DIR, TRANSCRIPT_DIR, CAPTION_DIR):
    os.makedirs(_d, exist_ok=True)


def _ssl_ctx():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def cookies_are_fresh():
    if not os.path.exists(COOKIE_FILE):
        return False
    return time.time() - os.path.getmtime(COOKIE_FILE) < COOKIE_MAX_AGE


def extract_cookies():
    if os.path.exists(COOKIE_FILE):
        os.remove(COOKIE_FILE)
    subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--cookies", COOKIE_FILE, "--skip-download", "--no-write-subs",
         "--no-write-auto-subs",
         "https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
        capture_output=True, cwd=CACHE_DIR, timeout=60,
    )


def _load_cookies():
    jar = http.cookiejar.MozillaCookieJar(COOKIE_FILE)
    jar.load()
    return {
        c.name: c.value for c in jar
        if c.domain in (".youtube.com", "www.youtube.com")
    }


def _sapisidhash(cookies):
    sapisid = cookies.get("SAPISID") or cookies.get("__Secure-3PAPISID", "")
    ts = str(int(time.time()))
    digest = hashlib.sha1(
        f"{ts} {sapisid} https://www.youtube.com".encode()
    ).hexdigest()
    return f"SAPISIDHASH {ts}_{digest}"


_client_version = {"value": None, "fetched": 0.0}


def _get_client_version():
    if _client_version["value"] and time.time() - _client_version["fetched"] < 3600:
        return _client_version["value"]
    try:
        req = urllib.request.Request("https://www.youtube.com")
        req.add_header("User-Agent", "Mozilla/5.0")
        page = urllib.request.urlopen(req, context=_ssl_ctx(), timeout=10).read().decode()
        m = re.search(r'"clientVersion":"([\d.]+)"', page)
        if m:
            _client_version.update(value=m.group(1), fetched=time.time())
    except Exception as e:
        print(f"[youtube] client version lookup failed: {e}")
    return _client_version["value"] or "2.20250101.00.00"


def _int(value):
    return int(value) if value.isdigit() else None


def _video_fields(channel_field="channel"):
    return f"%(id)s\t%(title)s\t%(duration)s\t%(timestamp)s\t%({channel_field})s"


def _parse_videos(stdout):
    videos = []
    for line in stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) != 5:
            continue
        vid, title, duration, timestamp, channel = parts
        videos.append({
            "id": vid, "title": title, "duration": _int(duration) or 0,
            "timestamp": _int(timestamp),
            "channel": "" if channel == "NA" else channel,
        })
    return videos


def fetch_watch_later():
    """Watch Later in playlist order, or None when the fetch fails."""
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist",
         # The playlist only carries relative dates ("3 years ago"); this
         # option converts them to approximate timestamps.
         "--extractor-args", "youtubetab:approximate_date",
         "--print", _video_fields(),
         "https://www.youtube.com/playlist?list=WL"],
        capture_output=True, text=True, timeout=90,
    )
    if result.returncode != 0:
        print(f"[load] Watch Later failed:\n{result.stderr.strip()[-1000:]}")
        return None
    videos = _parse_videos(result.stdout)
    return videos


def fetch_subscriptions(days):
    """Uploads from the subscriptions feed in the past `days` days, newest
    first, as (videos, reached_end). videos is None when the fetch fails."""
    cutoff = int(time.time()) - days * 86400
    max_videos = days * SUBSCRIPTIONS_VIDEOS_PER_DAY
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist", "--playlist-end", str(max_videos),
         "--extractor-args", "youtubetab:approximate_date",
         # The feed is newest first, so stop at the first video past the
         # cutoff. ">=?" lets entries without a date (live streams) through.
         "--break-match-filters", f"timestamp>=?{cutoff}",
         "--print", _video_fields(),
         "https://www.youtube.com/feed/subscriptions"],
        capture_output=True, text=True, timeout=120,
    )
    # 101 is yt-dlp's exit code for stopping at --break-match-filters, which
    # means older uploads exist.
    if result.returncode not in (0, 101):
        print(f"[load] subscriptions failed:\n{result.stderr.strip()[-1000:]}")
        return None, False
    videos = _parse_videos(result.stdout)
    return videos, result.returncode == 0 and len(videos) < max_videos


def fetch_channel_videos(channel_id, count):
    """The channel's newest `count` uploads as (videos, reached_end). videos
    is None when the fetch fails."""
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist", "--playlist-end", str(count),
         "--extractor-args", "youtubetab:approximate_date",
         # Channel tab entries leave "channel" empty.
         "--print", _video_fields("playlist_channel"),
         f"https://www.youtube.com/channel/{channel_id}/videos"],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        print(f"[load] channel {channel_id} failed:\n{result.stderr.strip()[-1000:]}")
        return None, False
    videos = _parse_videos(result.stdout)
    return videos, len(videos) < count


def fetch_channels():
    """Subscribed channels sorted by name, or None when the fetch fails."""
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist",
         "--print", "%(channel_id)s\t%(title)s\t%(thumbnails.-1.url)s",
         "https://www.youtube.com/feed/channels"],
        capture_output=True, text=True, timeout=90,
    )
    if result.returncode != 0:
        print(f"[load] channels failed:\n{result.stderr.strip()[-1000:]}")
        return None
    channels = []
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        channel_id, name, avatar = parts
        if avatar.startswith("//"):
            avatar = "https:" + avatar
        channels.append({"id": channel_id, "name": name,
                         "avatar": "" if avatar == "NA" else avatar})
    return sorted(channels, key=lambda c: c["name"].casefold())


def fetch_set_video_ids():
    """Map video id to its Watch Later entry id, which removal needs."""
    cookies = _load_cookies()
    req = urllib.request.Request("https://www.youtube.com/playlist?list=WL")
    req.add_header("Cookie", "; ".join(f"{k}={v}" for k, v in cookies.items()))
    req.add_header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
    page = urllib.request.urlopen(req, context=_ssl_ctx(), timeout=20).read().decode()
    renderers = list(
        re.finditer(r'"playlistVideoRenderer":\{"videoId":"([^"]+)"', page)
    )
    mappings = {}
    for m, following in zip(renderers, renderers[1:] + [None]):
        chunk = page[m.start():following.start() if following else len(page)]
        svid = re.search(r'"setVideoId":"([^"]+)"', chunk)
        if svid:
            mappings[m.group(1)] = svid.group(1)
    return mappings


def _innertube_post(endpoint, body, log_tag):
    """POST to YouTube's web client API as the signed-in Safari user. Returns
    the parsed response, or None on an HTTP error."""
    cookies = _load_cookies()
    payload = json.dumps({
        "context": {"client": {"clientName": "WEB",
                               "clientVersion": _get_client_version()}},
        **body,
    }).encode()
    req = urllib.request.Request(
        f"https://www.youtube.com/youtubei/v1/{endpoint}",
        data=payload, method="POST",
    )
    req.add_header("Cookie", "; ".join(f"{k}={v}" for k, v in cookies.items()))
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", _sapisidhash(cookies))
    req.add_header("Origin", "https://www.youtube.com")
    req.add_header("X-Origin", "https://www.youtube.com")
    req.add_header("User-Agent", "Mozilla/5.0")
    try:
        body = urllib.request.urlopen(req, context=_ssl_ctx(), timeout=20).read().decode()
    except urllib.error.HTTPError as e:
        print(f"[{log_tag}] HTTP {e.code}: {e.read().decode()[:500]}")
        return None
    return json.loads(body)


def _edit_watch_later(action, log_tag):
    response = _innertube_post(
        "browse/edit_playlist", {"actions": [action], "playlistId": "WL"}, log_tag)
    if response is None:
        return False
    status = response.get("status")
    if status != "STATUS_SUCCEEDED":
        print(f"[{log_tag}] unexpected status: {status}")
    return status == "STATUS_SUCCEEDED"


def set_subscribed(channel_id, subscribed):
    """Subscribe to or unsubscribe from a channel. Returns True when YouTube
    confirms the new state."""
    endpoint = "subscription/subscribe" if subscribed else "subscription/unsubscribe"
    response = _innertube_post(endpoint, {"channelIds": [channel_id]}, "subscribe")
    for action in (response or {}).get("actions", []):
        update = action.get("updateSubscribeButtonAction")
        if update:
            return update.get("subscribed") == subscribed
    print(f"[subscribe] no subscription state in response for {channel_id}")
    return False


def remove_from_watch_later(video_id, set_video_id):
    return _edit_watch_later({
        "setVideoId": set_video_id,
        "removedVideoId": video_id,
        "action": "ACTION_REMOVE_VIDEO",
    }, "remove")


def add_to_watch_later(video_id):
    return _edit_watch_later(
        {"addedVideoId": video_id, "action": "ACTION_ADD_VIDEO"}, "add"
    )


def local_files():
    """Map video id to the final merged mp4 for every download."""
    files = {}
    for f in os.listdir(DOWNLOAD_DIR):
        m = re.search(r'\[([a-zA-Z0-9_-]{11})\]\.mp4$', f)
        if m:
            files[m.group(1)] = os.path.join(DOWNLOAD_DIR, f)
    return files


def delete_local_files(video_id):
    """Delete the video and every leftover file yt-dlp wrote for it."""
    for f in os.listdir(DOWNLOAD_DIR):
        if f"[{video_id}]" in f:
            try:
                os.remove(os.path.join(DOWNLOAD_DIR, f))
            except OSError:
                pass
    for d, ext in ((TRANSCRIPT_DIR, ".json"), (CAPTION_DIR, ".vtt")):
        try:
            os.remove(os.path.join(d, video_id + ext))
        except OSError:
            pass


# Printed once before downloading: the size of each stream that will be
# fetched, so progress can cover the video and audio streams together.
_SIZES_TEMPLATE = "before_dl:SIZES " + " ".join([
    "%(requested_formats.0.filesize,requested_formats.0.filesize_approx,filesize,filesize_approx)s",
    "%(requested_formats.1.filesize,requested_formats.1.filesize_approx)s",
])
_PROGRESS_TEMPLATE = ("download:PROGRESS %(progress.downloaded_bytes)s "
                      "%(progress.total_bytes,progress.total_bytes_estimate)s "
                      "%(progress.filename)s")


class Download:
    """One video download that can be cancelled from another thread."""

    def __init__(self, video_id, progress_cb):
        self.video_id = video_id
        self.progress_cb = progress_cb
        self.cancelled = False
        self._proc = None
        self._lock = threading.Lock()

    def run(self):
        """Download at up to 1080p, anonymously first because signed-in
        requests can be limited to 360p. Returns (ok, last output lines)."""
        ok, output = self._run([])
        if not ok and not self.cancelled:
            ok, output = self._run(["--cookies-from-browser", "safari"])
        if self.cancelled:
            delete_local_files(self.video_id)
            return False, output
        for f in os.listdir(DOWNLOAD_DIR):
            if f"[{self.video_id}]" in f and f.endswith(".vtt"):
                os.remove(os.path.join(DOWNLOAD_DIR, f))
        return ok, output

    def cancel(self):
        with self._lock:
            self.cancelled = True
            if self._proc:
                self._proc.terminate()

    def _run(self, cookie_args):
        with self._lock:
            if self.cancelled:
                return False, ""
            self._proc = proc = subprocess.Popen(
                [YT_DLP, "--ignore-config", "--ignore-errors", "--newline",
                 "--no-simulate", "--progress",
                 *cookie_args,
                 # H.264 and AAC play in every browser.
                 "-f", "bv*[vcodec^=avc1][height<=1080]+ba[acodec^=mp4a]"
                       "/b[ext=mp4][height<=1080]/bv*[height<=1080]+ba/b",
                 "--write-auto-subs", "--sub-langs", "en.*", "--embed-subs",
                 "--embed-chapters", "--merge-output-format", "mp4",
                 "--print", _SIZES_TEMPLATE,
                 "--progress-template", _PROGRESS_TEMPLATE,
                 "-o", os.path.join(DOWNLOAD_DIR, "%(title)s [%(id)s].%(ext)s"),
                 f"https://www.youtube.com/watch?v={self.video_id}"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
            )
        sizes = []
        streams = {}  # filename -> [downloaded, total], in download order
        tail = []
        for line in proc.stdout:
            line = line.rstrip()
            if line.startswith("SIZES "):
                sizes = [_int(v) for v in line.split()[1:]]
            elif line.startswith("PROGRESS "):
                _, done, total, name = line.split(" ", 3)
                if not name.endswith(".vtt"):
                    streams[name] = [_int(done) or 0, _int(total)]
                    pct = _overall_percent(sizes, list(streams.values()))
                    if pct is not None:
                        self.progress_cb(pct)
            else:
                tail = (tail + [line])[-40:]
        proc.wait()
        with self._lock:
            self._proc = None
        return proc.returncode == 0 and self.video_id in local_files(), "\n".join(tail)


def _overall_percent(sizes, streams):
    """Percent of all streams downloaded. A stream's own reported total
    replaces the size printed before the download once it starts."""
    done = total = 0
    for i in range(max(len(sizes), len(streams))):
        stream_done, stream_total = streams[i] if i < len(streams) else (0, None)
        size = stream_total or (sizes[i] if i < len(sizes) else None)
        if size:
            done += stream_done
            total += size
    return min(100.0, 100 * done / total) if total else None


_TIMING = re.compile(r"(\d+):(\d+):(\d+)[,.](\d+)\s+-->")


def transcript(video_id, path):
    """{"lines": [[start, text, new_speaker]], "chapters": [[start, title]]}"""
    cache = os.path.join(TRANSCRIPT_DIR, video_id + ".json")
    try:
        with open(cache) as f:
            return json.load(f)
    except (OSError, ValueError):
        pass
    srt = subprocess.run(
        [FFMPEG, "-v", "error", "-i", path, "-map", "0:s:0", "-f", "srt", "-"],
        capture_output=True, text=True, timeout=120,
    )
    lines = _parse_srt(srt.stdout) if srt.returncode == 0 else []
    chapters = _embedded_chapters(path)
    if not chapters:
        chapters = _youtube_chapters(video_id)
        if chapters is None:
            return {"lines": lines, "chapters": []}  # retry the lookup next time
    data = {"lines": lines, "chapters": chapters}
    with open(cache, "w") as f:
        json.dump(data, f)
    return data


def _parse_srt(srt):
    # Cue text can contain blank lines, so cues are delimited by their timing
    # rows. The row just before each timing row is the next cue's index.
    rows = srt.replace("\r", "").split("\n")
    timings = [i for i, row in enumerate(rows) if _TIMING.match(row.strip())]
    cues = []
    for k, i in enumerate(timings):
        end = timings[k + 1] - 1 if k + 1 < len(timings) else len(rows)
        h, mi, s, ms = (int(g) for g in _TIMING.match(rows[i].strip()).groups())
        text = [r.strip() for r in rows[i + 1:end] if r.strip()]
        cues.append((h * 3600 + mi * 60 + s + ms / 1000, text))
    # YouTube auto-captions roll. Each cue repeats the previous cue's last
    # line above the new one, so keep only lines the previous cue lacked.
    lines = []
    previous = []
    for start, text in cues:
        new = [t for t in text if t not in previous]
        if new:
            # Auto-captions start a new speaker's words with ">>".
            for i, part in enumerate(" ".join(new).split(">>")):
                if part.strip():
                    lines.append([round(start, 2), part.strip(), i > 0])
        if text:
            previous = text
    return lines


def _embedded_chapters(path):
    result = subprocess.run(
        [FFPROBE, "-v", "error", "-show_chapters", "-of", "json", path],
        capture_output=True, text=True, timeout=30,
    )
    try:
        chapters = json.loads(result.stdout).get("chapters", [])
    except ValueError:
        return []
    return [[float(c["start_time"]), c.get("tags", {}).get("title", "")]
            for c in chapters]


def _youtube_chapters(video_id):
    try:
        result = subprocess.run(
            [YT_DLP, "--ignore-config", "--skip-download", "--print",
             "%(chapters)j", f"https://www.youtube.com/watch?v={video_id}"],
            capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    out = result.stdout.strip()
    if out in ("", "NA", "null"):
        return []
    try:
        return [[float(c["start_time"]), c["title"]] for c in json.loads(out)]
    except (ValueError, KeyError, TypeError):
        return None


def captions_vtt(video_id, path):
    """WebVTT of the first embedded subtitle track, or None."""
    cache = os.path.join(CAPTION_DIR, video_id + ".vtt")
    if not os.path.exists(cache):
        result = subprocess.run(
            [FFMPEG, "-v", "error", "-y", "-i", path, "-map", "0:s:0",
             "-f", "webvtt", cache],
            capture_output=True, timeout=120,
        )
        if result.returncode != 0:
            return None
    with open(cache, "rb") as f:
        return f.read()

"""YouTube access through yt-dlp and Safari's cookies."""

import hashlib
import http.cookiejar
import json
import os
import re
import ssl
import subprocess
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
SUBSCRIPTIONS_MAX_AGE_DAYS = 8
SUBSCRIPTIONS_MAX_VIDEOS = 200

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


def fetch_watch_later():
    """Watch Later in playlist order, or None when the fetch fails."""
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist",
         # The playlist only carries relative dates ("3 years ago"); this
         # option converts them to approximate timestamps.
         "--extractor-args", "youtubetab:approximate_date",
         "--print", "%(id)s\t%(title)s\t%(duration)s\t%(timestamp)s\t%(channel)s",
         "https://www.youtube.com/playlist?list=WL"],
        capture_output=True, text=True, timeout=90,
    )
    if result.returncode != 0:
        print(f"[load] Watch Later failed:\n{result.stderr.strip()[-1000:]}")
        return None
    videos = []
    for line in result.stdout.strip().split("\n"):
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


def fetch_subscriptions():
    """Recent uploads from the subscriptions feed, newest first, or None when
    the fetch fails."""
    cutoff = int(time.time()) - SUBSCRIPTIONS_MAX_AGE_DAYS * 86400
    result = subprocess.run(
        [YT_DLP, "--ignore-config", "--cookies-from-browser", "safari",
         "--flat-playlist", "--playlist-end", str(SUBSCRIPTIONS_MAX_VIDEOS),
         "--extractor-args", "youtubetab:approximate_date",
         # The feed is newest first, so stop at the first video past the
         # cutoff. ">=?" lets entries without a date (live streams) through.
         "--break-match-filters", f"timestamp>=?{cutoff}",
         "--print", "%(id)s\t%(title)s\t%(duration)s\t%(timestamp)s\t%(channel)s",
         "https://www.youtube.com/feed/subscriptions"],
        capture_output=True, text=True, timeout=120,
    )
    # 101 is yt-dlp's exit code for stopping at --break-match-filters.
    if result.returncode not in (0, 101):
        print(f"[load] subscriptions failed:\n{result.stderr.strip()[-1000:]}")
        return None
    videos = []
    for line in result.stdout.strip().split("\n"):
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


def _edit_watch_later(action, log_tag):
    cookies = _load_cookies()
    payload = json.dumps({
        "context": {"client": {"clientName": "WEB",
                               "clientVersion": _get_client_version()}},
        "actions": [action],
        "playlistId": "WL",
    }).encode()
    req = urllib.request.Request(
        "https://www.youtube.com/youtubei/v1/browse/edit_playlist",
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
        return False
    status = json.loads(body).get("status")
    if status != "STATUS_SUCCEEDED":
        print(f"[{log_tag}] unexpected status: {status}")
    return status == "STATUS_SUCCEEDED"


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


def download(video_id, progress_cb):
    """Download at up to 1080p, anonymously first because signed-in requests
    can be limited to 360p. Returns (ok, last output lines)."""
    ok, output = _run_download(video_id, [], progress_cb)
    if not ok:
        ok, output = _run_download(
            video_id, ["--cookies-from-browser", "safari"], progress_cb
        )
    for f in os.listdir(DOWNLOAD_DIR):
        if f"[{video_id}]" in f and f.endswith(".vtt"):
            os.remove(os.path.join(DOWNLOAD_DIR, f))
    return ok, output


def _run_download(video_id, cookie_args, progress_cb):
    proc = subprocess.Popen(
        [YT_DLP, "--ignore-config", "--ignore-errors", "--newline",
         *cookie_args,
         # H.264 and AAC play in every browser.
         "-f", "bv*[vcodec^=avc1][height<=1080]+ba[acodec^=mp4a]"
               "/b[ext=mp4][height<=1080]/bv*[height<=1080]+ba/b",
         "--write-auto-subs", "--sub-langs", "en.*", "--embed-subs",
         "--embed-chapters", "--merge-output-format", "mp4",
         "-o", os.path.join(DOWNLOAD_DIR, "%(title)s [%(id)s].%(ext)s"),
         f"https://www.youtube.com/watch?v={video_id}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    tail = []
    for line in proc.stdout:
        line = line.rstrip()
        tail = (tail + [line])[-40:]
        m = re.search(r'\[download\]\s+([\d.]+)%', line)
        if m:
            progress_cb(float(m.group(1)))
    proc.wait()
    return proc.returncode == 0 and video_id in local_files(), "\n".join(tail)


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

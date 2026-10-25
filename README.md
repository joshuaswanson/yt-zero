# WatchBar web

A browser interface for your YouTube Watch Later playlist and subscriptions. It downloads videos locally and plays them in the page with a transcript.

## Features

- Subscriptions, Watch Later, and Downloaded sections
- Grid or list layout, sorted by playlist order, title, length, or date published
- Download a single video or all of Watch Later, three at a time
- Remove videos from Watch Later, which also deletes their downloads
- Downloading a subscription video saves it to Watch Later first
- Player with play and pause (click the video or press space), a scrubber, 5 second skips with the arrow keys, subtitles, and a 0.5x to 3x speed slider
- Transcript sidebar that follows along, seeks when you click a line, and marks chapters and speaker changes
- Remembers where you stopped in each video and shows it as a red bar on the thumbnail

## Requirements

- macOS with Safari signed in to YouTube
- [uv](https://docs.astral.sh/uv/), [yt-dlp](https://github.com/yt-dlp/yt-dlp), and [ffmpeg](https://ffmpeg.org/) (`brew install uv yt-dlp ffmpeg`)
- Full Disk Access for the app that runs the server (for example Terminal), so yt-dlp can read Safari's cookies

## Usage

```bash
./run.sh
```

This starts the server at http://127.0.0.1:8765 and opens it in your browser. The page works while the server runs.

Downloads go to `downloads/`. Transcripts, subtitles, and cookies are cached in `.cache/`. Playback positions and layout settings are stored in the browser.

## Fonts

Barlow and Barlow Condensed by Jeremy Tribby, under the SIL Open Font License (`web/fonts/OFL.txt`).

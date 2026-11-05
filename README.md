# YouTube Zero

YouTube with zero ads, zero Shorts, and zero lag. Just the videos.

YouTube Zero is a local web app for your YouTube Watch Later playlist, subscriptions, and channels. It downloads videos locally and plays them in the page with a transcript.

## Features

- Subscriptions, Watch Later, and Downloaded sections, with a Load more button that reaches further back in Subscriptions
- A list of your subscribed channels in the sidebar. Each channel opens a page of its videos, where you can also subscribe or unsubscribe
- Grid or list layout, sorted by date added, date published, title, or length
- Download a single video or all of Watch Later, three at a time, and stop a download in progress
- Remove videos from Watch Later, which also deletes their downloads
- Downloading a subscription video saves it to Watch Later first. Videos watched from a channel page download without being saved to Watch Later
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

This starts the server at http://127.0.0.1:8765, or at the next free port up to 8784, and opens it in your browser. The page works while the server runs.

To use YouTube Zero as its own window, run `./window.sh`, or a `.command` file that runs it. It starts the server and opens the app in a new Safari window. Closing that window stops the server and any downloads in progress. A reload keeps the server running. If the server is already running, it opens another window.

Downloads go to `downloads/`. Transcripts, subtitles, and cookies are cached in `.cache/`. Playback positions and layout settings are saved in `.cache/prefs.json`, so every browser and port shares them.

## Fonts

Rubik by Hubert and Fischer, under the SIL Open Font License (`web/fonts/OFL.txt`).

## Icons

[Phosphor Icons](https://phosphoricons.com/) by Helena Zhang and Tobias Fried, under the MIT License.

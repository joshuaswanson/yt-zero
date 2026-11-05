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
- Full Disk Access for YouTube Zero (or for Terminal when you use `run.sh`), so yt-dlp can read Safari's cookies. Turn it on in System Settings, under Privacy & Security, then Full Disk Access
- Xcode Command Line Tools to build the Mac app (`xcode-select --install`)

## Usage

Build the Mac app and install it in `/Applications`:

```bash
macos/build.sh
```

Open YouTube Zero from Applications, Launchpad, or Spotlight. It starts the server in the background and shows the library in its own window. Quitting the app stops the server and any downloads in progress. Links to YouTube open in your default browser. The server log is in `~/Library/Logs/YouTube Zero.log`.

The app runs the code in this folder, so changes to the server or the web files take effect the next time you open it. Run `macos/build.sh` again after moving this folder or changing anything in `macos/`.

To use a browser, run:

```bash
./run.sh
```

This starts the server at http://127.0.0.1:8765, or at the next free port up to 8784, and opens it in your browser.

Downloads go to `downloads/`. Transcripts, subtitles, and cookies are cached in `.cache/`. Playback positions and layout settings are saved in `.cache/prefs.json`, so every browser and port shares them.

## Fonts

Rubik by Hubert and Fischer, under the SIL Open Font License (`web/fonts/OFL.txt`).

## Icons

[Phosphor Icons](https://phosphoricons.com/) by Helena Zhang and Tobias Fried, under the MIT License.

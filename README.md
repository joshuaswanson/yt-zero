# YouTube Zero

YouTube with zero ads, zero Shorts, and zero lag. Just the videos.

YouTube Zero is a native Mac app for your YouTube Watch Later playlist, subscriptions, and channels. It downloads videos and plays them with a transcript.

## Features

- Subscriptions, Watch Later, and Downloaded sections, with a Load more button that reaches further back in Subscriptions
- A list of your subscribed channels in the sidebar. Each channel opens a page of its videos, where you can also subscribe or unsubscribe
- Grid or list layout, sorted by date added, date published, title, or length
- Download a single video or all of Watch Later, three at a time, and stop a download in progress
- The same buttons on every video in every section: open on YouTube, download or delete the download, and add to or remove from Watch Later. Removing a video from Watch Later keeps its download
- Downloading a subscription video saves it to Watch Later first. Videos watched from a channel page download without being saved to Watch Later
- Player with play and pause (click the video or press space), a scrubber, 5 second skips with the arrow keys, subtitles, and a 0.5x to 3x speed slider
- Transcript sidebar that follows along, seeks when you click a line, and marks chapters and speaker changes
- Remembers where you stopped in each video and shows it as a red bar on the thumbnail

## Requirements

- macOS 15 or later, with Safari signed in to YouTube
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org/) (`brew install yt-dlp ffmpeg`)
- Full Disk Access for YouTube Zero, so yt-dlp can read Safari's cookies. Turn it on in System Settings, under Privacy & Security, then Full Disk Access
- Xcode Command Line Tools to build the app (`xcode-select --install`)

## Usage

Build the app and install it in `/Applications`:

```bash
macos/build.sh
```

Open YouTube Zero from Applications, Launchpad, or Spotlight. Links to YouTube open in your default browser. Quitting the app stops any downloads in progress and deletes their partial files.

- Downloads go to `~/Movies/YouTube Zero`.
- Playback positions, layout settings, transcripts, and cookies are kept in `~/Library/Application Support/YouTube Zero`.
- The log is in `~/Library/Logs/YouTube Zero.log`.

The app is built from the Swift sources in `macos/Sources`. Run `macos/build.sh` again after changing them.

## Fonts

Rubik by Hubert and Fischer, under the SIL Open Font License (`macos/Resources/OFL.txt`).

## Icons

[Phosphor Icons](https://phosphoricons.com/) by Helena Zhang and Tobias Fried, under the MIT License.

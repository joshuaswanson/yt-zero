<img src="macos/icon.svg" width="128" alt="YT Zero icon">

# YT Zero

YouTube with zero ads, zero Shorts, and zero lag. Just the videos.

YT Zero is a native Mac app for your YouTube Watch Later playlist, subscriptions, and channels.

## Features

- Subscriptions, Watch Later, and Downloaded sections, with a Load more button that reaches further back in Subscriptions
- A list of your subscribed channels in the sidebar. Each channel opens a page of its videos, where you can also subscribe or unsubscribe
- Grid or list layout, sorted by date added, date published, title, or length
- Download a single video or all of Watch Later, three at a time, and stop a download in progress
- The same buttons on every video in every section: open on YouTube, add to or remove from Watch Later, and download or delete the download. Removing a video from Watch Later keeps its download
- Downloading a subscription video saves it to Watch Later first. Videos watched from a channel page download without being saved to Watch Later
- Player with play and pause (click the video or press space), a scrubber, 5 second skips with the arrow keys, subtitles, and a 0.5x to 3x speed slider
- Transcript sidebar that follows along, seeks when you click a line, and marks chapters and speaker changes
- Remembers where you stopped in each video and shows it as a red bar on the thumbnail

## Requirements

- macOS 15 or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org/) (`brew install yt-dlp ffmpeg`)
- Xcode Command Line Tools to build the app (`xcode-select --install`)

## Usage

Build the app and install it in `/Applications`:

```bash
macos/build.sh
```

Open YT Zero from Applications, Launchpad, or Spotlight. Links to YouTube open in your default browser. Quitting the app stops any downloads in progress and deletes their partial files.

## Signing in

YT Zero uses the first of these that is signed in to YouTube:

1. Its own session. Choose Sign In to YouTube from the account menu at the bottom of the sidebar, or from the YT Zero menu.
2. Safari, when YT Zero has Full Disk Access (System Settings, then Privacy & Security, then Full Disk Access).
3. Chrome, Brave, Edge, or Firefox. Reading Chrome's cookies asks for Keychain access once.

The sign-in is saved to `cookies.txt` in the app's Application Support folder, which only your user account can read. It keeps only YouTube's cookies and the Google sign-in cookies behind them.

## Files

- Downloads go to `~/Movies/YT Zero`.
- Playback positions, layout settings, transcripts, and the sign-in are kept in `~/Library/Application Support/YT Zero`.
- The log is in `~/Library/Logs/YT Zero.log`.

The app is built from the Swift sources in `macos/Sources`. Run `macos/build.sh` again after changing them.

## Fonts

Rubik by Hubert and Fischer, under the SIL Open Font License (`macos/Resources/OFL.txt`).

## Icons

[Phosphor Icons](https://phosphoricons.com/) by Helena Zhang and Tobias Fried, under the MIT License (`macos/Resources/Phosphor-LICENSE.txt`).

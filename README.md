<img src="macos/banner.svg" height="96" alt="YT Zero">

YouTube with zero ads, zero Shorts, and zero lag. Just the videos.

YT Zero is a native Mac app for your YouTube Watch Later playlist, subscriptions, and channels.

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

The app is built from the Swift sources in `macos/Sources`. Run `macos/build.sh` again after changing them. To publish a new version, commit your changes and run `macos/release.sh 2.1` with the new version number. It builds the app and publishes it as a GitHub release. Installed copies then offer the update.

## Fonts

Rubik by Hubert and Fischer, under the SIL Open Font License (`macos/Resources/OFL.txt`).

## Icons

[Phosphor Icons](https://phosphoricons.com/) by Helena Zhang and Tobias Fried, under the MIT License (`macos/Resources/Phosphor-LICENSE.txt`).

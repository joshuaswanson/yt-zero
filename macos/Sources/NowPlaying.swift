import AppKit
import MediaPlayer

/// Publishes the open video to Control Center's Now Playing widget and
/// receives play, pause, and seek commands from it, the media keys, and headphones.
@MainActor
enum NowPlaying {
    private static var center: MPNowPlayingInfoCenter { .default() }
    private static var commands: MPRemoteCommandCenter { .shared() }

    static func start(_ model: PlayerModel) {
        stop()
        on(commands.playCommand) { $0.play() }
        on(commands.pauseCommand) { $0.pause() }
        on(commands.togglePlayPauseCommand) { $0.toggle() }
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: PlayerModel.skipSeconds)]
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: PlayerModel.skipSeconds)]
        on(commands.skipForwardCommand) { $0.skip(PlayerModel.skipSeconds) }
        on(commands.skipBackwardCommand) { $0.skip(-PlayerModel.skipSeconds) }
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in PlayerModel.current?.seek(to: position) }
            return .success
        }
        update(model: model)
        loadArtwork(for: model)
    }

    static func update(model: PlayerModel?) {
        guard let model, let video = model.video else { return }
        var info = center.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = video.title
        info[MPMediaItemPropertyArtist] = video.channel
        info[MPMediaItemPropertyPlaybackDuration] = model.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = model.time
        info[MPNowPlayingInfoPropertyPlaybackRate] = model.isPlaying ? Double(model.player.defaultRate) : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(model.player.defaultRate)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        center.nowPlayingInfo = info
        center.playbackState = model.isPlaying ? .playing : .paused
    }

    static func stop() {
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                        commands.skipForwardCommand, commands.skipBackwardCommand,
                        commands.changePlaybackPositionCommand] {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    private static func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PlayerModel) -> Void) {
        command.isEnabled = true
        command.addTarget { _ in
            Task { @MainActor in
                guard let model = PlayerModel.current else { return }
                action(model)
                update(model: model)
            }
            return .success
        }
    }

    private static func loadArtwork(for model: PlayerModel) {
        guard let id = model.video?.id else { return }
        Task {
            guard let image = await ImageStore.shared.load(thumbnailURLs(id)), model.video?.id == id else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            center.nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }
}

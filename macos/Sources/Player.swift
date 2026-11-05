import AVFoundation
import AppKit
import SwiftUI

struct Flash: Identifiable, Equatable {
    enum Position { case center, back, forward }
    let id = UUID()
    let icon: Icon?
    let text: String?
    let position: Position
}

enum TranscriptRow: Identifiable {
    case chapter(index: Int, Chapter)
    case line(TranscriptLine, speakerBreak: Bool)

    var id: Int {
        switch self {
        case .chapter(let index, _): -(index + 1)
        case .line(let line, _): line.id
        }
    }

    var start: Double {
        switch self {
        case .chapter(_, let chapter): chapter.start
        case .line(let line, _): line.start
        }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    static let resumeMin: Double = 5
    static let resumeEndMargin: Double = 10
    static let skipSeconds: Double = 5
    static let flashDuration: TimeInterval = 0.6
    static let previewWidth: CGFloat = 176

    static weak var current: PlayerModel?

    let player = AVPlayer()
    @Published private(set) var video: Video?
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var transcriptLoaded = false
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var rows: [TranscriptRow] = []
    @Published private(set) var currentLine: Int?
    @Published var followPaused = false
    @Published private(set) var flash: Flash?
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var videoAspect: CGFloat = 16 / 9
    var scrubbing = false

    private var library: Library { Library.shared }
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var lastSave = Date.distantPast
    private var ended = false
    private var generator: AVAssetImageGenerator?
    private var previewTarget: Double?
    private var previewBusy = false
    private var skipShown: Double = 0
    private var skipShownAt = Date.distantPast

    init() { Self.current = self }

    // MARK: Opening and closing

    func open(_ video: Video, file: URL) {
        teardown()
        self.video = video
        let item = AVPlayerItem(url: file)
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.replaceCurrentItem(with: item)
        player.defaultRate = Float(library.settings.speed)
        time = 0
        duration = Double(video.duration)
        ended = false
        followPaused = false
        currentLine = nil
        transcriptLoaded = false
        lines = []
        rows = []
        previewImage = nil

        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.previewWidth * 2, height: 0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        self.generator = generator

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnd() }
        }
        installKeyMonitor()

        Task {
            let asset = item.asset
            if let length = try? await asset.load(.duration).seconds, length.isFinite, length > 0 { duration = length }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
                videoAspect = size.width / size.height
            }
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) { item.select(nil, in: group) }
            guard player.currentItem === item else { return }
            let resume = library.positions[video.id] ?? 0
            if resume >= Self.resumeMin && resume < duration - Self.resumeEndMargin {
                await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
                time = resume
            }
            play()
        }
        Task {
            let transcript = await background { Transcripts.load(videoID: video.id, file: file) }
            guard self.video?.id == video.id else { return }
            lines = transcript.lines
            rows = Self.rows(transcript)
            transcriptLoaded = true
            updateCurrentLine()
        }
    }

    func close() {
        savePosition(force: true)
        teardown()
        video = nil
        library.playing = nil
    }

    private func teardown() {
        player.pause()
        isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        timeObserver = nil
        endObserver = nil
        keyMonitor = nil
        generator?.cancelAllCGImageGeneration()
        generator = nil
        player.replaceCurrentItem(with: nil)
    }

    private static func rows(_ transcript: Transcript) -> [TranscriptRow] {
        var chapters = transcript.chapters[...]
        var rows: [TranscriptRow] = []
        var chapterIndex = 0
        for (i, line) in transcript.lines.enumerated() {
            while let chapter = chapters.first, chapter.start <= line.start + 0.5 {
                rows.append(.chapter(index: chapterIndex, chapter))
                chapterIndex += 1
                chapters = chapters.dropFirst()
            }
            rows.append(.line(line, speakerBreak: line.newSpeaker && i > 0))
        }
        return rows
    }

    // MARK: Playback

    func play() {
        if ended {
            ended = false
            player.seek(to: .zero)
        }
        player.defaultRate = Float(library.settings.speed)
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        savePosition(force: true)
    }

    func toggle() { isPlaying ? pause() : play() }

    func toggleFromScreen() {
        toggle()
        showFlash(Flash(icon: isPlaying ? .play : .pause, text: nil, position: .center))
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), duration > 0 ? duration : seconds)
        ended = false
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateCurrentLine()
    }

    func skip(_ seconds: Double) {
        seek(to: time + seconds)
        // Repeated skips in one direction add up while the indicator is visible.
        let now = Date()
        let continues = now.timeIntervalSince(skipShownAt) < Self.flashDuration && skipShown.sign == seconds.sign
        skipShown = continues ? skipShown + seconds : seconds
        skipShownAt = now
        let label = "\(skipShown > 0 ? "+" : "\u{2212}")\(Int(abs(skipShown)))s"
        showFlash(Flash(icon: nil, text: label, position: skipShown > 0 ? .forward : .back))
    }

    func setSpeed(_ speed: Double) {
        library.settings.speed = speed
        player.defaultRate = Float(speed)
        if isPlaying { player.rate = Float(speed) }
    }

    private func showFlash(_ flash: Flash) { self.flash = flash }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, video != nil else { return }
        if !scrubbing { time = seconds }
        if isPlaying && player.rate == 0 && player.timeControlStatus == .paused { isPlaying = false }
        updateCurrentLine()
        savePosition(force: false)
    }

    private func didEnd() {
        ended = true
        isPlaying = false
        if let id = video?.id { library.setPosition(id, nil) }
    }

    func savePosition(force: Bool) {
        guard let id = video?.id, !ended else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) >= 5 else { return }
        lastSave = now
        if time > 0 { library.setPosition(id, time) }
    }

    // MARK: Transcript

    private func updateCurrentLine() {
        var lo = 0, hi = lines.count - 1
        var index: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time + 0.05 { index = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        if index != currentLine { currentLine = index }
    }

    var caption: String? {
        guard library.settings.captions, let index = currentLine, index < lines.count else { return nil }
        let line = lines[index]
        let next = index + 1 < lines.count ? lines[index + 1].start : .infinity
        return time < min(next, line.start + 8) ? line.text : nil
    }

    // MARK: Scrubber preview

    /// Generates only the latest hovered frame once the previous one finishes,
    /// so the preview keeps up with fast mouse movement.
    func requestPreview(_ seconds: Double) {
        previewTarget = seconds
        if !previewBusy { generateNextPreview() }
    }

    private func generateNextPreview() {
        guard let target = previewTarget, let generator else { return }
        previewTarget = nil
        previewBusy = true
        generator.generateCGImageAsynchronously(for: CMTime(seconds: target, preferredTimescale: 600)) { image, _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let image { self.previewImage = image }
                self.previewBusy = false
                self.generateNextPreview()
            }
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 49: toggleFromScreen()
            case 123: skip(-Self.skipSeconds)
            case 124: skip(Self.skipSeconds)
            case 53: close()
            default: return event
            }
            return nil
        }
    }
}

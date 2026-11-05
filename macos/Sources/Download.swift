import Foundation

/// One video download that can be cancelled from another thread.
final class Download: @unchecked Sendable {
    let videoID: String
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var process: Process?
    private var cancelledFlag = false

    var cancelled: Bool { lock.withLock { cancelledFlag } }

    init(videoID: String, onProgress: @escaping (Double) -> Void) {
        self.videoID = videoID
        self.onProgress = onProgress
    }

    /// Downloads at up to 1080p, anonymously first because signed-in requests
    /// can be limited to 360p. Returns whether it worked and the last output lines.
    func run() -> (ok: Bool, output: String) {
        var (ok, output) = attempt(cookieArguments: [])
        if !ok && !cancelled {
            (ok, output) = YouTube.withCookies { cookies in
                cookies.isEmpty ? (ok, output) : attempt(cookieArguments: cookies)
            }
        }
        if cancelled {
            YouTube.deleteLocalFiles(videoID)
            return (false, output)
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.downloads.path)) ?? []
        for name in names where name.contains("[\(videoID)]") && name.hasSuffix(".vtt") {
            try? FileManager.default.removeItem(at: Paths.downloads.appendingPathComponent(name))
        }
        return (ok, output)
    }

    func cancel() {
        lock.withLock {
            cancelledFlag = true
            process?.terminate()
        }
    }

    /// Waits for a cancelled download's process to exit, for use at quit.
    func waitForExit() {
        let running = lock.withLock { process }
        running?.waitUntilExit()
    }

    // Printed once before downloading: the size of each stream that will be
    // fetched, so progress can cover the video and audio streams together.
    private static let sizesTemplate = "before_dl:SIZES "
        + "%(requested_formats.0.filesize,requested_formats.0.filesize_approx,filesize,filesize_approx)s "
        + "%(requested_formats.1.filesize,requested_formats.1.filesize_approx)s"
    private static let progressTemplate = "download:PROGRESS %(progress.downloaded_bytes)s "
        + "%(progress.total_bytes,progress.total_bytes_estimate)s %(progress.filename)s"

    private func attempt(cookieArguments: [String]) -> (Bool, String) {
        let process = Process()
        let pipe = Pipe()
        let started: Bool = lock.withLock {
            guard !cancelledFlag, let ytDlp = Tools.ytDlp else { return false }
            process.executableURL = URL(fileURLWithPath: ytDlp)
            process.arguments = [
                "--ignore-config", "--ignore-errors", "--newline", "--no-simulate", "--progress",
            ] + cookieArguments + [
                // H.264 and AAC play everywhere, including AVFoundation.
                "-f", "bv*[vcodec^=avc1][height<=1080]+ba[acodec^=mp4a]/b[ext=mp4][height<=1080]/bv*[height<=1080]+ba/b",
                "--write-auto-subs", "--sub-langs", "en.*", "--embed-subs",
                "--embed-chapters", "--merge-output-format", "mp4",
                "--print", Self.sizesTemplate,
                "--progress-template", Self.progressTemplate,
                "-o", Paths.downloads.appendingPathComponent("%(title)s [%(id)s].%(ext)s").path,
                "https://www.youtube.com/watch?v=\(videoID)",
            ]
            process.environment = Tools.environment
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return false }
            self.process = process
            return true
        }
        guard started else { return (false, "") }

        var sizes: [Int?] = []
        var streams: [(name: String, done: Int, total: Int?)] = []
        var tail: [String] = []
        var buffer = Data()
        let handle = pipe.fileHandleForReading
        func receive(line: String) {
            if line.hasPrefix("SIZES ") {
                sizes = line.split(separator: " ").dropFirst().map { Int($0) }
            } else if line.hasPrefix("PROGRESS ") {
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 4, !parts[3].hasSuffix(".vtt") else { return }
                let entry = (name: parts[3], done: Int(parts[1]) ?? 0, total: Int(parts[2]))
                if let i = streams.firstIndex(where: { $0.name == entry.name }) { streams[i] = entry } else { streams.append(entry) }
                if let percent = overallPercent(sizes: sizes, streams: streams.map { ($0.done, $0.total) }) {
                    onProgress(percent)
                }
            } else {
                tail = Array((tail + [line]).suffix(40))
            }
        }
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                receive(line: String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
        process.waitUntilExit()
        lock.withLock { self.process = nil }
        let ok = process.terminationStatus == 0 && YouTube.localFiles()[videoID] != nil
        return (ok, tail.joined(separator: "\n"))
    }
}

/// Percent of all streams downloaded. A stream's own reported total replaces
/// the size printed before the download once it starts.
func overallPercent(sizes: [Int?], streams: [(done: Int, total: Int?)]) -> Double? {
    var done = 0, total = 0
    for i in 0..<max(sizes.count, streams.count) {
        let stream = i < streams.count ? streams[i] : (done: 0, total: nil)
        if let size = stream.total ?? (i < sizes.count ? sizes[i] : nil), size > 0 {
            done += stream.done
            total += size
        }
    }
    return total > 0 ? min(100, 100 * Double(done) / Double(total)) : nil
}

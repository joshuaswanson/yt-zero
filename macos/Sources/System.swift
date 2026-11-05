import Foundation

enum Paths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YT Zero")
    static let downloads = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/YT Zero")
    static let transcripts = support.appendingPathComponent("transcripts")
    static let cookies = support.appendingPathComponent("cookies.txt")
    static let prefs = support.appendingPathComponent("prefs.json")
    static let otherDownloads = support.appendingPathComponent("other_downloads.json")
    static let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/YT Zero.log")
    static let safariCookies = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")

    static func prepare() {
        for dir in [support, downloads, transcripts] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        FileManager.default.createFile(atPath: log.path, contents: nil)
    }
}

enum Tools {
    static let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func find(_ name: String) -> String? {
        searchPath.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let ytDlp = find("yt-dlp")
    static let ffmpeg = find("ffmpeg")
    static let ffprobe = find("ffprobe")

    static var missing: [String] {
        [("yt-dlp", ytDlp), ("ffmpeg", ffmpeg), ("ffprobe", ffprobe)].filter { $0.1 == nil }.map(\.0)
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPath + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}

private let logQueue = DispatchQueue(label: "log")

func log(_ message: String) {
    let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
    logQueue.async {
        guard let handle = try? FileHandle(forWritingTo: Paths.log) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    }
}

struct RunResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
}

/// Runs a command to completion on the calling thread.
func run(_ executable: String?, _ arguments: [String], timeout: TimeInterval) -> RunResult {
    guard let executable else { return RunResult(status: -1, stdout: "", stderr: "not installed") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = Tools.environment
    process.currentDirectoryURL = Paths.support
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch {
        return RunResult(status: -1, stdout: "", stderr: error.localizedDescription)
    }
    let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
    var errData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        errData = err.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    group.wait()
    process.waitUntilExit()
    timer.cancel()
    return RunResult(status: process.terminationStatus,
                     stdout: String(decoding: outData, as: UTF8.self),
                     stderr: String(decoding: errData, as: UTF8.self))
}

/// Moves blocking work (processes, synchronous HTTP) off the main thread.
func background<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
    }
}

func firstMatch(_ pattern: String, in text: String) -> [String]? {
    allMatches(pattern, in: text, limit: 1).first
}

func allMatches(_ pattern: String, in text: String, limit: Int = .max) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var results: [[String]] = []
    let range = NSRange(text.startIndex..., in: text)
    regex.enumerateMatches(in: text, range: range) { match, _, stop in
        guard let match else { return }
        results.append((0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        })
        if results.count >= limit { stop.pointee = true }
    }
    return results
}

func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? data.write(to: url, options: .atomic)
}

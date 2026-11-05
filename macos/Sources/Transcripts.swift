import Foundation

/// Transcripts come from the subtitle track yt-dlp embeds in each download.
/// The cache stores {"lines": [[start, text, newSpeaker]], "chapters": [[start, title]]}.
enum Transcripts {
    static func load(videoID: String, file: URL) -> Transcript {
        let cache = Paths.transcripts.appendingPathComponent("\(videoID).json")
        if let data = try? Data(contentsOf: cache), let transcript = decode(data) { return transcript }

        let srt = run(Tools.ffmpeg, ["-v", "error", "-i", file.path, "-map", "0:s:0", "-f", "srt", "-"], timeout: 120)
        let lines = srt.ok ? parseSRT(srt.stdout) : []
        var chapters = embeddedChapters(file)
        if chapters.isEmpty {
            guard let online = youtubeChapters(videoID) else {
                return Transcript(lines: lines, chapters: [])  // retry the lookup next time
            }
            chapters = online
        }
        let json: [String: Any] = [
            "lines": lines.map { [$0.start, $0.text, $0.newSpeaker] },
            "chapters": chapters.map { [$0.start, $0.title] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) { try? data.write(to: cache, options: .atomic) }
        return Transcript(lines: lines, chapters: chapters)
    }

    private static func decode(_ data: Data) -> Transcript? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rawLines = json["lines"] as? [[Any]], let rawChapters = json["chapters"] as? [[Any]] else { return nil }
        let lines = rawLines.enumerated().compactMap { i, row -> TranscriptLine? in
            guard row.count >= 3, let start = (row[0] as? NSNumber)?.doubleValue, let text = row[1] as? String
            else { return nil }
            return TranscriptLine(id: i, start: start, text: text, newSpeaker: (row[2] as? Bool) ?? false)
        }
        let chapters = rawChapters.compactMap { row -> Chapter? in
            guard row.count >= 2, let start = (row[0] as? NSNumber)?.doubleValue, let title = row[1] as? String
            else { return nil }
            return Chapter(start: start, title: title)
        }
        return Transcript(lines: lines, chapters: chapters)
    }

    static func parseSRT(_ srt: String) -> [TranscriptLine] {
        // Cue text can contain blank lines, so cues are delimited by their
        // timing rows. The row just before each timing row is the next cue's index.
        let timing = try! NSRegularExpression(pattern: #"^(\d+):(\d+):(\d+)[,.](\d+)\s+-->"#)
        let rows = srt.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func start(_ row: String) -> Double? {
            guard let m = timing.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { return nil }
            let g = (1...4).map { Double((row as NSString).substring(with: m.range(at: $0))) ?? 0 }
            return g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000
        }
        let timings = rows.indices.filter { start(rows[$0]) != nil }
        var cues: [(Double, [String])] = []
        for (k, i) in timings.enumerated() {
            let end = k + 1 < timings.count ? timings[k + 1] - 1 : rows.count
            cues.append((start(rows[i])!, rows[(i + 1)..<max(i + 1, end)].filter { !$0.isEmpty }))
        }
        // YouTube auto-captions roll. Each cue repeats the previous cue's last
        // line above the new one, so keep only lines the previous cue lacked.
        var lines: [TranscriptLine] = []
        var previous: [String] = []
        for (at, text) in cues {
            let new = text.filter { !previous.contains($0) }
            if !new.isEmpty {
                // Auto-captions start a new speaker's words with ">>".
                for (i, part) in new.joined(separator: " ").components(separatedBy: ">>").enumerated() {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        lines.append(TranscriptLine(id: lines.count, start: (at * 100).rounded() / 100,
                                                    text: trimmed, newSpeaker: i > 0))
                    }
                }
            }
            if !text.isEmpty { previous = text }
        }
        return lines
    }

    private static func embeddedChapters(_ file: URL) -> [Chapter] {
        let result = run(Tools.ffprobe, ["-v", "error", "-show_chapters", "-of", "json", file.path], timeout: 30)
        guard let json = (try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8))) as? [String: Any],
              let chapters = json["chapters"] as? [[String: Any]] else { return [] }
        return chapters.map {
            Chapter(start: Double($0["start_time"] as? String ?? "") ?? 0,
                    title: ($0["tags"] as? [String: Any])?["title"] as? String ?? "")
        }
    }

    private static func youtubeChapters(_ videoID: String) -> [Chapter]? {
        let result = run(Tools.ytDlp, ["--ignore-config", "--skip-download", "--print", "%(chapters)j",
                                       "https://www.youtube.com/watch?v=\(videoID)"], timeout: 60)
        guard result.ok else { return nil }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["", "NA", "null"].contains(out) { return [] }
        guard let chapters = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [[String: Any]] else {
            return nil
        }
        return chapters.compactMap { c in
            guard let start = (c["start_time"] as? NSNumber)?.doubleValue, let title = c["title"] as? String
            else { return nil }
            return Chapter(start: start, title: title)
        }
    }
}

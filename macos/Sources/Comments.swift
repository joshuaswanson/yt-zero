import Foundation

/// The top comments on a video, fetched once with yt-dlp and cached.
enum Comments {
    static let count = 20

    static func load(videoID: String) -> [Comment]? {
        let cache = Paths.comments.appendingPathComponent("\(videoID).json")
        if let cached = readJSON([Comment].self, from: cache) { return cached }
        let result = YouTube.withCookies { cookies in run(Tools.ytDlp, ["--ignore-config"] + cookies + [
            "--skip-download", "--write-comments",
            "--extractor-args", "youtube:comment_sort=top;max_comments=\(count),\(count),0,0",
            "--print", "%(comments)j", "https://www.youtube.com/watch?v=\(videoID)",
        ], timeout: 90) }
        guard result.ok else {
            log("[comments] \(videoID) failed:\n\(result.stderr.suffix(500))")
            return nil
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [[String: Any]] ?? []
        let comments = raw.compactMap { c -> Comment? in
            guard let id = c["id"] as? String, let text = c["text"] as? String else { return nil }
            return Comment(id: id, author: c["author"] as? String ?? "", avatar: c["author_thumbnail"] as? String ?? "",
                           text: text, likes: (c["like_count"] as? NSNumber)?.intValue ?? 0,
                           age: c["_time_text"] as? String ?? "", pinned: c["is_pinned"] as? Bool ?? false,
                           byUploader: c["author_is_uploader"] as? Bool ?? false,
                           hearted: c["is_favorited"] as? Bool ?? false)
        }
        writeJSON(comments, to: cache)
        return comments
    }
}

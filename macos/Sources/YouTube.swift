import CryptoKit
import Foundation

/// YouTube access through yt-dlp and Safari's cookies. Every function blocks,
/// so call them through `background`.
enum YouTube {
    static let subscriptionsDays = 8
    static let subscriptionsMoreDays = 7
    static let subscriptionsVideosPerDay = 25
    static let cookieMaxAge: TimeInterval = 1800
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

    // MARK: Cookies

    static func cookiesAreFresh() -> Bool {
        guard let date = try? Paths.cookies.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return false }
        return Date().timeIntervalSince(date) < cookieMaxAge
    }

    static func canReadSafariCookies() -> Bool {
        do {
            try FileHandle(forReadingFrom: Paths.safariCookies).close()
            return true
        } catch let error as NSError {
            let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            return !(posix == Int(EPERM) || posix == Int(EACCES) || error.code == NSFileReadNoPermissionError)
        }
    }

    /// Where the YouTube sign-in comes from, in the order they are tried.
    enum CookieSource: String, CaseIterable {
        case app, safari, chrome, brave, edge, firefox

        var name: String {
            switch self {
            case .app: "YouTube Zero"
            case .safari: "Safari"
            case .chrome: "Chrome"
            case .brave: "Brave"
            case .edge: "Edge"
            case .firefox: "Firefox"
            }
        }

        fileprivate var profilePath: String? {
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            return switch self {
            case .app: nil
            case .safari: Paths.safariCookies.path
            case .chrome: support.appendingPathComponent("Google/Chrome").path
            case .brave: support.appendingPathComponent("BraveSoftware/Brave-Browser").path
            case .edge: support.appendingPathComponent("Microsoft Edge").path
            case .firefox: support.appendingPathComponent("Firefox/Profiles").path
            }
        }
    }

    /// Writes the first working sign-in to the cookie file: the app's own
    /// session, then each installed browser. Returns nil when none is signed in.
    static func prepareCookies(appCookies: [HTTPCookie]) -> CookieSource? {
        if !appCookies.isEmpty {
            writeCookies(appCookies)
            if hasYouTubeLogin() { return .app }
        }
        for source in CookieSource.allCases where source != .app {
            guard let path = source.profilePath, FileManager.default.fileExists(atPath: path) else { continue }
            if source == .safari && !canReadSafariCookies() { continue }
            if extractCookies(from: source) { return source }
        }
        try? FileManager.default.removeItem(at: Paths.cookies)
        return nil
    }

    /// yt-dlp exports every cookie the browser has, so the export goes to the
    /// private temporary directory and only YouTube and Google cookies are kept.
    private static func extractCookies(from source: CookieSource) -> Bool {
        try? FileManager.default.removeItem(at: Paths.cookies)
        let export = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-zero-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: export) }
        _ = run(Tools.ytDlp, [
            "--ignore-config", "--cookies-from-browser", source.rawValue, "--cookies", export.path,
            "--skip-download", "--no-write-subs", "--no-write-auto-subs",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        ], timeout: 60)
        guard let text = try? String(contentsOf: export, encoding: .utf8) else { return false }
        let kept = text.split(separator: "\n").filter { line in
            var entry = Substring(line)
            if entry.hasPrefix("#HttpOnly_") { entry = entry.dropFirst("#HttpOnly_".count) } else if entry.hasPrefix("#") { return false }
            return isYouTubeDomain(String(entry.prefix { $0 != "\t" }))
        }
        saveCookieFile(kept.map(String.init))
        let found = hasYouTubeLogin()
        log("[cookies] \(source.name): \(found ? "signed in" : "not signed in")")
        return found
    }

    static func hasYouTubeLogin() -> Bool {
        let cookies = loadCookies()
        return cookies["SAPISID"] != nil || cookies["__Secure-3PAPISID"] != nil
    }

    private static func writeCookies(_ cookies: [HTTPCookie]) {
        saveCookieFile(cookies.filter { isYouTubeDomain($0.domain) }.map { c in
            let expiry = Int(c.expiresDate?.timeIntervalSince1970 ?? 0)
            return [c.domain, c.domain.hasPrefix(".") ? "TRUE" : "FALSE", c.path, c.isSecure ? "TRUE" : "FALSE",
                    String(expiry), c.name, c.value].joined(separator: "\t")
        })
    }

    /// YouTube's own cookies and the Google sign-in cookies behind them.
    static func isYouTubeDomain(_ domain: String) -> Bool {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
            || ["google.com", "www.google.com", "accounts.google.com"].contains(host)
    }

    /// Netscape cookie file format, which yt-dlp reads with --cookies,
    /// readable by this user only.
    private static func saveCookieFile(_ lines: [String]) {
        let data = Data((["# Netscape HTTP Cookie File"] + lines).joined(separator: "\n").appending("\n").utf8)
        let staging = Paths.cookies.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: staging)
        guard FileManager.default.createFile(atPath: staging.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? FileManager.default.replaceItemAt(Paths.cookies, withItemAt: staging)
        if !FileManager.default.fileExists(atPath: Paths.cookies.path) {
            try? FileManager.default.moveItem(at: staging, to: Paths.cookies)
        }
    }

    /// yt-dlp writes its cookie jar back when it exits, so each run gets a
    /// private copy and parallel downloads never write the same file.
    static func withCookies<T>(_ body: ([String]) -> T) -> T {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-zero-\(UUID().uuidString).txt")
        guard (try? FileManager.default.copyItem(at: Paths.cookies, to: copy)) != nil else { return body([]) }
        defer { try? FileManager.default.removeItem(at: copy) }
        return body(["--cookies", copy.path])
    }

    static func loadCookies() -> [String: String] {
        guard let text = try? String(contentsOf: Paths.cookies, encoding: .utf8) else { return [:] }
        var cookies: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            var line = String(raw)
            if line.hasPrefix("#HttpOnly_") { line.removeFirst("#HttpOnly_".count) }
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7, [".youtube.com", "www.youtube.com"].contains(String(fields[0])) else { continue }
            cookies[String(fields[5])] = String(fields[6])
        }
        return cookies
    }

    private static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private static func sapisidHash(_ cookies: [String: String]) -> String {
        let sapisid = cookies["SAPISID"] ?? cookies["__Secure-3PAPISID"] ?? ""
        let ts = String(Int(Date().timeIntervalSince1970))
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) https://www.youtube.com".utf8))
        return "SAPISIDHASH \(ts)_" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: HTTP

    private static func fetch(_ request: URLRequest) -> (Data?, Int) {
        let done = DispatchSemaphore(value: 0)
        var result: (Data?, Int) = (nil, 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    private static let clientVersionLock = NSLock()
    nonisolated(unsafe) private static var cachedClientVersion: (value: String, fetched: Date)?

    private static func clientVersion() -> String {
        clientVersionLock.lock()
        defer { clientVersionLock.unlock() }
        if let cached = cachedClientVersion, Date().timeIntervalSince(cached.fetched) < 3600 { return cached.value }
        var request = URLRequest(url: URL(string: "https://www.youtube.com")!, timeoutInterval: 10)
        request.setValue(Session.userAgent, forHTTPHeaderField: "User-Agent")
        let page = fetch(request).0.map { String(decoding: $0, as: UTF8.self) } ?? ""
        if let version = firstMatch(#""clientVersion":"([\d.]+)""#, in: page)?[1] {
            cachedClientVersion = (version, Date())
            return version
        }
        log("[youtube] client version lookup failed")
        return cachedClientVersion?.value ?? "2.20250101.00.00"
    }

    /// POSTs to YouTube's web client API as the signed-in Safari user.
    private static func innertube(_ endpoint: String, _ body: [String: Any], tag: String) -> [String: Any]? {
        let cookies = loadCookies()
        var payload = body
        payload["context"] = ["client": ["clientName": "WEB", "clientVersion": clientVersion()]]
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)")!,
                                 timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue(cookieHeader(cookies), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sapisidHash(cookies), forHTTPHeaderField: "Authorization")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, status) = fetch(request)
        guard let data, status == 200 else {
            log("[\(tag)] HTTP \(status): \(String(decoding: (data ?? Data()).prefix(500), as: UTF8.self))")
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Lists

    private static func videoFields(_ channelField: String = "channel") -> String {
        "%(id)s\t%(title)s\t%(duration)s\t%(timestamp)s\t%(\(channelField))s"
    }

    private static func parseVideos(_ stdout: String) -> [Video] {
        stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5 else { return nil }
            return Video(id: parts[0], title: parts[1], duration: Int(parts[2]) ?? 0,
                         timestamp: Int(parts[3]), channel: parts[4] == "NA" ? "" : parts[4])
        }
    }

    private static func failed(_ tag: String, _ result: RunResult) {
        log("[load] \(tag) failed:\n\(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1000))")
    }

    /// Watch Later in playlist order.
    static func fetchWatchLater() -> [Video]? {
        let result = withCookies { cookies in run(Tools.ytDlp, ["--ignore-config"] + cookies + [
            "--flat-playlist",
            // The playlist only carries relative dates ("3 years ago"); this
            // option converts them to approximate timestamps.
            "--extractor-args", "youtubetab:approximate_date",
            "--print", videoFields(), "https://www.youtube.com/playlist?list=WL",
        ], timeout: 90) }
        guard result.ok else { failed("Watch Later", result); return nil }
        return parseVideos(result.stdout)
    }

    /// Uploads from the subscriptions feed in the past `days` days, newest first.
    static func fetchSubscriptions(days: Int) -> (videos: [Video]?, reachedEnd: Bool) {
        let cutoff = Int(Date().timeIntervalSince1970) - days * 86400
        let maxVideos = days * subscriptionsVideosPerDay
        let result = withCookies { cookies in run(Tools.ytDlp, ["--ignore-config"] + cookies + [
            "--flat-playlist", "--playlist-end", String(maxVideos),
            "--extractor-args", "youtubetab:approximate_date",
            // The feed is newest first, so stop at the first video past the
            // cutoff. ">=?" lets entries without a date (live streams) through.
            "--break-match-filters", "timestamp>=?\(cutoff)",
            "--print", videoFields(), "https://www.youtube.com/feed/subscriptions",
        ], timeout: 120) }
        // 101 is yt-dlp's exit code for stopping at --break-match-filters,
        // which means older uploads exist.
        guard result.status == 0 || result.status == 101 else { failed("subscriptions", result); return (nil, false) }
        let videos = parseVideos(result.stdout)
        return (videos, result.status == 0 && videos.count < maxVideos)
    }

    static func fetchChannelVideos(_ channelID: String, count: Int) -> (videos: [Video]?, reachedEnd: Bool) {
        let result = withCookies { cookies in run(Tools.ytDlp, ["--ignore-config"] + cookies + [
            "--flat-playlist", "--playlist-end", String(count),
            "--extractor-args", "youtubetab:approximate_date",
            // Channel tab entries leave "channel" empty.
            "--print", videoFields("playlist_channel"),
            "https://www.youtube.com/channel/\(channelID)/videos",
        ], timeout: 120) }
        guard result.ok else { failed("channel \(channelID)", result); return (nil, false) }
        let videos = parseVideos(result.stdout)
        return (videos, videos.count < count)
    }

    /// Subscribed channels sorted by name.
    static func fetchChannels() -> [Channel]? {
        let result = withCookies { cookies in run(Tools.ytDlp, ["--ignore-config"] + cookies + [
            "--flat-playlist",
            "--print", "%(channel_id)s\t%(title)s\t%(thumbnails.-1.url)s",
            "https://www.youtube.com/feed/channels",
        ], timeout: 90) }
        guard result.ok else { failed("channels", result); return nil }
        let channels: [Channel] = result.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { return nil }
            var avatar = parts[2]
            if avatar.hasPrefix("//") { avatar = "https:" + avatar }
            return Channel(id: parts[0], name: parts[1], avatar: avatar == "NA" ? "" : avatar)
        }
        return sortChannels(channels)
    }

    static func sortChannels(_ channels: [Channel]) -> [Channel] {
        channels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Maps each video to its Watch Later entry id, which removal needs.
    static func fetchSetVideoIDs() -> [String: String]? {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/playlist?list=WL")!, timeoutInterval: 20)
        request.setValue(cookieHeader(loadCookies()), forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, status) = fetch(request)
        guard let data, status == 200 else {
            log("[load] Watch Later page returned HTTP \(status)")
            return nil
        }
        let page = String(decoding: data, as: UTF8.self) as NSString
        guard let renderer = try? NSRegularExpression(pattern: #""playlistVideoRenderer":\{"videoId":"([^"]+)""#),
              let setID = try? NSRegularExpression(pattern: #""setVideoId":"([^"]+)""#) else { return nil }
        let found = renderer.matches(in: page as String, range: NSRange(location: 0, length: page.length))
        var mappings: [String: String] = [:]
        for (i, match) in found.enumerated() {
            let end = i + 1 < found.count ? found[i + 1].range.location : page.length
            let chunk = NSRange(location: match.range.location, length: end - match.range.location)
            if let svid = setID.firstMatch(in: page as String, range: chunk) {
                mappings[page.substring(with: match.range(at: 1))] = page.substring(with: svid.range(at: 1))
            }
        }
        return mappings
    }

    /// The signed-in account's name, handle, and picture.
    static func fetchAccount() -> Account? {
        let actions = innertube("account/account_menu", [:], tag: "account")?["actions"] as? [[String: Any]]
        let popup = (actions?.first?["openPopupAction"] as? [String: Any])?["popup"] as? [String: Any]
        let header = ((popup?["multiPageMenuRenderer"] as? [String: Any])?["header"] as? [String: Any])?[
            "activeAccountHeaderRenderer"] as? [String: Any]
        func text(_ key: String) -> String? {
            guard let field = header?[key] as? [String: Any] else { return nil }
            if let simple = field["simpleText"] as? String { return simple }
            return (field["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        guard let name = text("accountName") else { return nil }
        let thumbnails = (header?["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let photo = (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:))
        return Account(name: name, handle: text("channelHandle") ?? "", photo: photo)
    }

    // MARK: Edits

    private static func editWatchLater(_ action: [String: Any], tag: String) -> Bool {
        let response = innertube("browse/edit_playlist", ["actions": [action], "playlistId": "WL"], tag: tag)
        let status = response?["status"] as? String
        if response != nil && status != "STATUS_SUCCEEDED" { log("[\(tag)] unexpected status: \(status ?? "none")") }
        return status == "STATUS_SUCCEEDED"
    }

    static func addToWatchLater(_ videoID: String) -> Bool {
        editWatchLater(["addedVideoId": videoID, "action": "ACTION_ADD_VIDEO"], tag: "add")
    }

    static func removeFromWatchLater(_ videoID: String, setVideoID: String) -> Bool {
        editWatchLater(["setVideoId": setVideoID, "removedVideoId": videoID, "action": "ACTION_REMOVE_VIDEO"],
                       tag: "remove")
    }

    /// Returns true when YouTube confirms the new subscription state.
    static func setSubscribed(_ channelID: String, _ subscribed: Bool) -> Bool {
        let endpoint = subscribed ? "subscription/subscribe" : "subscription/unsubscribe"
        let actions = innertube(endpoint, ["channelIds": [channelID]], tag: "subscribe")?["actions"] as? [[String: Any]]
        for action in actions ?? [] {
            if let update = action["updateSubscribeButtonAction"] as? [String: Any] {
                return update["subscribed"] as? Bool == subscribed
            }
        }
        log("[subscribe] no subscription state in response for \(channelID)")
        return false
    }

    // MARK: Local files

    /// The final merged mp4 for every download, by video id.
    static func localFiles() -> [String: URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.downloads.path)) ?? []
        var files: [String: URL] = [:]
        for name in names {
            if let id = firstMatch(#"\[([a-zA-Z0-9_-]{11})\]\.mp4$"#, in: name)?[1] {
                files[id] = Paths.downloads.appendingPathComponent(name)
            }
        }
        return files
    }

    /// Deletes the video and every leftover file yt-dlp wrote for it.
    static func deleteLocalFiles(_ videoID: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.downloads.path)) ?? []
        for name in names where name.contains("[\(videoID)]") {
            try? FileManager.default.removeItem(at: Paths.downloads.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: Paths.transcripts.appendingPathComponent("\(videoID).json"))
    }
}

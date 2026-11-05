import AppKit
import Foundation

struct ChannelPage {
    var id: String?
    var videos: [Video] = []
    var end = false
    var loading = false
    var loadingMore = false
    var failed = false
    var subscribing = false
}

private struct ChannelCacheEntry {
    var videos: [Video]
    var count: Int
    var end: Bool
    var fetchedAt: Date
}

/// Watch Later, subscriptions, channels, downloads, and saved preferences.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    static let autoRefreshInterval: TimeInterval = 300
    static let downloadConcurrency = 3
    static let channelsMaxAge: TimeInterval = 3600
    static let channelPageSize = 30
    static let channelVideosMaxAge: TimeInterval = 600

    @Published var settings: Settings { didSet { if settings != oldValue { savePrefs() } } }
    @Published var positions: [String: Double]

    @Published var watchLater: [Video] = []
    @Published var subscriptions: [Video] = []
    @Published var subscriptionDays = YouTube.subscriptionsDays
    @Published var subscriptionsEnd = false
    @Published var loading = false
    @Published var loadingMore = false
    @Published var error: String?
    @Published var needsSignIn = false
    @Published var cookieSource: YouTube.CookieSource?
    @Published var showSignIn = false
    @Published var account: Account?

    @Published var channels: [Channel]?
    @Published var channelsLoading = false
    @Published var channelsFailed = false
    @Published var channelPage = ChannelPage()

    @Published var downloads: [String: DownloadStatus] = [:]
    @Published var otherDownloads: [String: Video]
    @Published var local: [String: URL] = [:]
    @Published var playing: Video?
    var pendingPlay: String?

    private var channelsFetchedAt: Date?
    private var channelCache: [String: ChannelCacheEntry] = [:]
    private var channelRequest = 0
    private var setVideoIDs: [String: String] = [:]
    private var active: [String: Download] = [:]
    private var queue: [(id: String, token: UUID)] = []
    private var tokens: [String: UUID] = [:]
    private var timer: Timer?
    private var cookieTask: Task<YouTube.CookieSource?, Never>?
    private let sessionKeeper = SessionKeeper()
    private var sessionRefreshedAt: Date?
    private static let sessionRefreshInterval: TimeInterval = 6 * 3600

    private init() {
        Paths.prepare()
        let prefs = readJSON(Prefs.self, from: Paths.prefs)
        settings = prefs?.settings ?? Settings()
        positions = prefs?.positions ?? [:]
        otherDownloads = readJSON([String: Video].self, from: Paths.otherDownloads) ?? [:]
        local = YouTube.localFiles()
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        loadChannels()
        if settings.section == .channel { loadChannelVideos() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.autoRefreshInterval, repeats: true) { _ in
            Task { @MainActor in Library.shared.refresh() }
        }
    }

    // MARK: Preferences

    private func savePrefs() {
        writeJSON(Prefs(settings: settings, positions: positions), to: Paths.prefs)
    }

    func setPosition(_ videoID: String, _ seconds: Double?) {
        positions[videoID] = seconds.map { ($0 * 10).rounded() / 10 }
        savePrefs()
    }

    // MARK: Derived lists

    func videos(for section: Section) -> [Video] {
        let list: [Video]
        switch section {
        case .subscriptions: list = subscriptions
        case .channel: list = channelPage.videos
        case .watchLater: list = watchLater
        case .downloaded:
            let inWatchLater = Set(watchLater.map(\.id))
            list = (watchLater + otherDownloads.values.filter { !inWatchLater.contains($0.id) }.sorted { $0.title < $1.title })
                .filter { local[$0.id] != nil || downloads[$0.id] != nil }
        }
        return sortVideos(list, settings.sort(for: section))
    }

    func inWatchLater(_ id: String) -> Bool { watchLater.contains { $0.id == id } }

    func find(_ id: String) -> Video? {
        let cached = channelCache.values.flatMap(\.videos)
        return (watchLater + subscriptions + channelPage.videos + cached + Array(otherDownloads.values))
            .first { $0.id == id }
    }

    var activeDownloadCount: Int { downloads.values.filter(\.isActive).count }

    var isRefreshing: Bool {
        loading || (settings.section == .channel && channelPage.loading && !channelPage.loadingMore)
    }

    // MARK: Sign-in

    /// Rewrites the cookie file from the first working sign-in when it is
    /// stale or `force` is set. Calls made while an update runs share its result.
    @discardableResult
    func updateCookies(force: Bool = false) async -> YouTube.CookieSource? {
        if let cookieTask { return await cookieTask.value }
        if !force, cookieSource != nil, YouTube.cookiesAreFresh() { return cookieSource }
        let task = Task { await prepareCookies() }
        cookieTask = task
        let source = await task.value
        cookieTask = nil
        return source
    }

    private func prepareCookies() async -> YouTube.CookieSource? {
        var appCookies = await Session.cookies()
        let due = sessionRefreshedAt.map { Date().timeIntervalSince($0) > Self.sessionRefreshInterval } ?? true
        if Session.isSignedIn(appCookies), due {
            await sessionKeeper.refresh()
            sessionRefreshedAt = Date()
            appCookies = await Session.cookies()
        }
        let snapshot = appCookies
        let source = await background { YouTube.prepareCookies(appCookies: snapshot) }
        if source != cookieSource || account == nil {
            account = source == nil ? nil : await background { YouTube.fetchAccount() }
        }
        cookieSource = source
        needsSignIn = source == nil
        log("[cookies] using \(source?.name ?? "no sign-in")")
        return source
    }

    func finishSignIn() {
        showSignIn = false
        sessionRefreshedAt = Date()
        Task {
            await updateCookies(force: true)
            refreshAll()
        }
    }

    func signOut() {
        Task {
            await Session.signOut()
            await updateCookies(force: true)
            refreshAll()
        }
    }

    /// Runs a signed-in request, and once more with fresh cookies if it fails,
    /// because Google rotates session cookies.
    private func withSignIn(_ work: @escaping () -> Bool) async -> Bool {
        await updateCookies()
        if await background(work) { return true }
        await updateCookies(force: true)
        return await background(work)
    }

    // MARK: Refresh

    func refresh() {
        guard !loading else { return }
        loading = true
        let days = subscriptionDays
        Task {
            defer {
                loading = false
                local = YouTube.localFiles()
            }
            guard await updateCookies() != nil else {
                error = nil
                return
            }
            var result = await fetchLibrary(days: days)
            if result.watchLater == nil {
                await updateCookies(force: true)
                result = await fetchLibrary(days: days)
            }
            if let list = result.watchLater { watchLater = list }
            if let list = result.subscriptions.0 { setSubscriptions(days, list, result.subscriptions.1) }
            if let ids = result.setIDs { setVideoIDs = ids }
            error = result.watchLater == nil ? "Watch Later did not load. Check that you are signed in to YouTube." : nil
            log("[load] \(watchLater.count) Watch Later, \(subscriptions.count) subscription uploads")
        }
    }

    private func fetchLibrary(days: Int) async
        -> (watchLater: [Video]?, subscriptions: ([Video]?, Bool), setIDs: [String: String]?) {
        await background {
            let watchLater = YouTube.fetchWatchLater()
            let subscriptions = YouTube.fetchSubscriptions(days: days)
            let setIDs = YouTube.fetchSetVideoIDs()
            if setIDs == nil { log("[load] setVideoIds failed") }
            return (watchLater, subscriptions, setIDs)
        }
    }

    func refreshAll() {
        refresh()
        loadChannels(force: true)
        if settings.section == .channel { loadChannelVideos(.refresh) }
    }

    private func setSubscriptions(_ days: Int, _ list: [Video], _ reachedEnd: Bool) {
        // A fetch for a shorter window than the current one is out of date.
        guard days == subscriptionDays else { return }
        subscriptions = list
        subscriptionsEnd = reachedEnd
    }

    func loadMoreSubscriptions() {
        guard !loadingMore, !subscriptionsEnd else { return }
        loadingMore = true
        subscriptionDays += YouTube.subscriptionsMoreDays
        let days = subscriptionDays
        Task {
            let (list, end) = await background { YouTube.fetchSubscriptions(days: days) }
            if let list { setSubscriptions(days, list, end) }
            loadingMore = false
        }
    }

    // MARK: Channels

    func loadChannels(force: Bool = false) {
        let stale = channelsFetchedAt.map { Date().timeIntervalSince($0) > Self.channelsMaxAge } ?? true
        guard !channelsLoading, force || channels == nil || stale else { return }
        channelsLoading = true
        Task {
            await updateCookies()
            let list = await background { YouTube.fetchChannels() }
            if let list {
                channels = list
                channelsFetchedAt = Date()
            }
            channelsFailed = list == nil
            channelsLoading = false
        }
    }

    func openChannel(_ channel: Channel) {
        settings.channel = channel
        settings.section = .channel
        loadChannelVideos()
    }

    enum ChannelLoad { case cached, more, refresh }

    func loadChannelVideos(_ mode: ChannelLoad = .cached) {
        guard let id = settings.channel?.id else { return }
        if channelPage.id != id { channelPage = ChannelPage(id: id) }
        let entry = channelCache[id]
        if mode == .cached, let entry, Date().timeIntervalSince(entry.fetchedAt) < Self.channelVideosMaxAge {
            channelPage.videos = entry.videos
            channelPage.end = entry.end
            return
        }
        var count = entry?.count ?? Self.channelPageSize
        if mode == .more, entry != nil { count += Self.channelPageSize }
        channelRequest += 1
        let request = channelRequest
        channelPage.loading = true
        channelPage.loadingMore = mode == .more
        Task {
            await updateCookies()
            let (videos, end) = await background { YouTube.fetchChannelVideos(id, count: count) }
            if let videos { channelCache[id] = ChannelCacheEntry(videos: videos, count: count, end: end, fetchedAt: Date()) }
            guard request == channelRequest else { return }
            channelPage.loading = false
            channelPage.loadingMore = false
            channelPage.failed = videos == nil
            if let videos {
                channelPage.videos = videos
                channelPage.end = end
            }
        }
    }

    func isSubscribed(_ channelID: String) -> Bool { channels?.contains { $0.id == channelID } ?? false }

    func setSubscribed(_ subscribed: Bool) {
        guard let channel = settings.channel else { return }
        channelPage.subscribing = true
        Task {
            let ok = await withSignIn { YouTube.setSubscribed(channel.id, subscribed) }
            if ok {
                var list = (channels ?? []).filter { $0.id != channel.id }
                if subscribed { list.append(channel) }
                channels = YouTube.sortChannels(list)
            } else {
                error = "\(subscribed ? "Subscribing" : "Unsubscribing") failed. Check that you are signed in to YouTube."
            }
            channelPage.subscribing = false
        }
    }

    // MARK: Watch Later

    func addToWatchLater(_ id: String) {
        guard let video = find(id), !inWatchLater(id) else { return }
        watchLater.append(video)
        forgetOtherDownload(id)
        Task {
            if await !withSignIn({ YouTube.addToWatchLater(id) }) { log("[add] failed: \(id)") }
        }
    }

    func removeFromWatchLater(_ id: String) {
        let setID = setVideoIDs.removeValue(forKey: id)
        // A downloaded video stays in Downloaded after it leaves Watch Later.
        if let video = watchLater.first(where: { $0.id == id }), local[id] != nil || downloads[id] != nil {
            otherDownloads[id] = video
            writeJSON(otherDownloads, to: Paths.otherDownloads)
        }
        watchLater.removeAll { $0.id == id }
        Task {
            let removed = await withSignIn {
                if let setID, YouTube.removeFromWatchLater(id, setVideoID: setID) { return true }
                guard let fresh = YouTube.fetchSetVideoIDs()?[id] else { return false }
                return YouTube.removeFromWatchLater(id, setVideoID: fresh)
            }
            if !removed { log("[remove] failed: \(id)") }
        }
    }

    // MARK: Downloads

    func deleteDownload(_ id: String) {
        downloads[id] = nil
        forgetOtherDownload(id)
        deleteFiles(id)
    }

    private func deleteFiles(_ id: String) {
        YouTube.deleteLocalFiles(id)
        local = YouTube.localFiles()
    }

    private func forgetOtherDownload(_ id: String) {
        if otherDownloads.removeValue(forKey: id) != nil { writeJSON(otherDownloads, to: Paths.otherDownloads) }
    }

    func download(_ id: String, saveToWatchLater: Bool) {
        if let status = downloads[id], status.isActive { return }
        guard active[id] == nil, local[id] == nil else { return }
        if saveToWatchLater {
            addToWatchLater(id)
        } else if let video = find(id), !inWatchLater(id) {
            otherDownloads[id] = video
            writeJSON(otherDownloads, to: Paths.otherDownloads)
        }
        let token = UUID()
        tokens[id] = token
        downloads[id] = .queued
        queue.append((id, token))
        startQueued()
    }

    func downloadAll() {
        for video in watchLater { download(video.id, saveToWatchLater: true) }
    }

    func cancel(_ id: String) {
        if pendingPlay == id { pendingPlay = nil }
        downloads[id] = nil
        tokens[id] = nil
        forgetOtherDownload(id)
        active[id]?.cancel()
    }

    /// Stops every download and waits for yt-dlp to exit, so partial files
    /// can be deleted before the app quits.
    func cancelAll() {
        let jobs = Array(active.values)
        jobs.forEach { $0.cancel() }
        jobs.forEach { $0.waitForExit() }
        jobs.forEach { YouTube.deleteLocalFiles($0.videoID) }
    }

    private func startQueued() {
        while active.count < Self.downloadConcurrency, !queue.isEmpty {
            let (id, token) = queue.removeFirst()
            guard tokens[id] == token else { continue }
            downloads[id] = .downloading(progress: nil)
            let job = Download(videoID: id) { percent in
                Task { @MainActor in
                    let library = Library.shared
                    if library.tokens[id] == token, case .downloading = library.downloads[id] {
                        library.downloads[id] = .downloading(progress: percent)
                    }
                }
            }
            active[id] = job
            Task {
                let (ok, output) = await background { job.run() }
                finish(id, token: token, job: job, ok: ok, output: output)
            }
        }
    }

    private func finish(_ id: String, token: UUID, job: Download, ok: Bool, output: String) {
        active[id] = nil
        defer { startQueued() }
        local = YouTube.localFiles()
        if job.cancelled || tokens[id] != token { return }
        tokens[id] = nil
        if ok {
            downloads[id] = nil
            if pendingPlay == id, playing == nil {
                pendingPlay = nil
                play(id)
            }
        } else {
            downloads[id] = .failed
            log("[download] failed \(id):\n\(output.suffix(1500))")
        }
    }

    // MARK: Playback

    func open(_ id: String) {
        if local[id] != nil {
            play(id)
        } else {
            pendingPlay = id
            download(id, saveToWatchLater: settings.section != .channel)
        }
    }

    private func play(_ id: String) {
        playing = find(id) ?? Video(id: id, title: "", duration: 0, timestamp: nil, channel: "")
    }

    func openOnYouTube(_ id: String) {
        NSWorkspace.shared.open(URL(string: "https://www.youtube.com/watch?v=\(id)")!)
    }
}

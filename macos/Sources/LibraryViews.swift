import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: Library
    @StateObject private var player = PlayerModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar()
                LibraryView()
            }
            .background(Palette.mist)
            if library.playing != nil {
                PlayerView(model: player).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: library.playing?.id)
        .onChange(of: library.playing?.id) {
            if let video = library.playing, let file = library.local[video.id] { player.open(video, file: file) }
        }
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 600)
        .font(rubik(15))
        .foregroundStyle(Palette.ink)
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                Text("YT Zero").font(rubik(22, 700)).kerning(-0.2).foregroundStyle(Palette.signal)
                    .lineLimit(1).fixedSize()
            }
            .padding(.leading, 10)
            .padding(.bottom, 30)
            .onTapGesture { library.settings.section = .watchLater }

            VStack(spacing: 4) {
                ForEach([Section.subscriptions, .watchLater, .downloaded], id: \.self) { section in
                    SectionRow(section: section)
                }
            }

            Text("Channels").font(rubik(13.5, 500)).foregroundStyle(Palette.slate)
                .padding(.leading, 14).padding(.top, 26).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if let note = channelNote {
                        Text(note).font(rubik(13.5)).foregroundStyle(Palette.slate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    } else {
                        ForEach(library.channels ?? []) { ChannelRow(channel: $0) }
                    }
                }
            }
            .scrollIndicators(.never)
            AccountRow()
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(width: 222)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.paper))
        .padding(.top, Layout.contentTop)
        .padding([.bottom, .leading], 14)
    }

    private var channelNote: String? {
        if let list = library.channels, !list.isEmpty { return nil }
        if library.channelsLoading { return "Loading..." }
        if library.channelsFailed { return "Did not load. Refresh to try again." }
        return library.channels == nil ? nil : "No subscriptions"
    }
}

/// The signed-in YouTube account, with a menu to sign in or out.
struct AccountRow: View {
    @EnvironmentObject var library: Library
    @State private var hovering = false

    var body: some View {
        if let source = library.cookieSource {
            let account = library.account
            Menu {
                SwiftUI.Section(source == .app ? "Signed in to YT Zero" : "Using your sign-in from \(source.name)") {
                    if source == .app {
                        Button("Sign Out of YouTube") { library.signOut() }
                    } else {
                        Button("Sign In to YouTube…") { library.showSignIn = true }
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(Palette.signal)
                        Text(String((account?.name ?? "Y").prefix(1))).font(rubik(13, 600)).foregroundStyle(.white)
                        if let photo = account?.photo { RemoteImage(urls: [photo]) }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account?.name ?? "Signed in").font(rubik(14.5, 500)).foregroundStyle(Palette.ink)
                        Text(account?.handle.isEmpty == false ? account!.handle : "YouTube account")
                            .font(rubik(12.5)).foregroundStyle(Palette.slate)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovering ? Palette.mist : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focusable(false)
            .onHover { hovering = $0 }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.mist).frame(height: 1).padding(.horizontal, 6)
            }
        }
    }
}

struct SectionRow: View {
    let section: Section
    @EnvironmentObject var library: Library
    @State private var hovering = false

    var body: some View {
        let current = library.settings.section == section
        let count = library.videos(for: section).count
        Button { library.settings.section = section } label: {
            HStack {
                Text(section.title).font(rubik(16, 500))
                Spacer(minLength: 8)
                if count > 0 {
                    Text("\(count)").font(rubik(12.5, 500)).monospacedDigit()
                        .foregroundStyle(current ? .white : Palette.slate)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .frame(minWidth: 28)
                        .background(Capsule().fill(current ? Palette.signal : Palette.mist))
                }
            }
            .foregroundStyle(current ? Palette.paper : hovering ? Palette.ink : Palette.slate)
            .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 9)
            .background(Capsule().fill(current ? Palette.ink : hovering ? Palette.mist : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

struct ChannelRow: View {
    let channel: Channel
    @EnvironmentObject var library: Library
    @State private var hovering = false

    var body: some View {
        let current = library.settings.section == .channel && library.settings.channel?.id == channel.id
        Button { library.openChannel(channel) } label: {
            HStack(spacing: 10) {
                RemoteImage(urls: URL(string: channel.avatar).map { [$0] } ?? [])
                    .frame(width: 26, height: 26)
                    .background(Palette.hover)
                    .clipShape(Circle())
                Text(channel.name).font(rubik(16, 500)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(current ? Palette.paper : hovering ? Palette.ink : Palette.slate)
            .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
            .background(Capsule().fill(current ? Palette.ink : hovering ? Palette.mist : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

// MARK: Library

struct LibraryView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        let section = library.settings.section
        let videos = library.videos(for: section)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Toolbar().padding(.bottom, 28)
                    if !Tools.missing.isEmpty {
                        ToolsNotice()
                    } else if library.needsSignIn {
                        SignInNotice()
                    } else if videos.isEmpty {
                        Text(emptyText(section)).font(rubik(17)).foregroundStyle(Palette.slate)
                            .lineSpacing(3).frame(maxWidth: 440, alignment: .leading)
                    } else {
                        VideoList(videos: videos)
                    }
                    LoadMore()
                }
                .padding(.top, Layout.contentTop).padding(.leading, 30).padding(.trailing, 36).padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("top")
            }
            .onChange(of: section) { proxy.scrollTo("top", anchor: .top) }
            .onChange(of: library.settings.channel?.id) { proxy.scrollTo("top", anchor: .top) }
        }
    }

    private func emptyText(_ section: Section) -> String {
        if library.isRefreshing { return "Loading..." }
        switch section {
        case .channel:
            return library.channelPage.failed ? "Videos did not load. Refresh to try again." : "This channel has no videos."
        case .subscriptions:
            return "No uploads from your subscriptions in the past \(library.subscriptionDays) days."
        case .watchLater:
            return "Watch Later is empty. Save videos on YouTube or from Subscriptions to see them here."
        case .downloaded:
            return "Nothing downloaded yet. Click a video in Watch Later to download and play it."
        }
    }
}

struct Toolbar: View {
    @EnvironmentObject var library: Library

    var body: some View {
        let settings = library.settings
        let section = settings.section
        let onChannel = section == .channel
        let sort = settings.sort(for: section)
        HStack(spacing: 18) {
            Text(onChannel ? settings.channel?.name ?? "" : section.title)
                .font(rubik(38, 700)).kerning(-0.76).lineLimit(1)
            if onChannel, library.channels != nil, let channel = settings.channel {
                let subscribed = library.isSubscribed(channel.id)
                let busy = library.channelPage.subscribing
                PillButton(
                    title: busy ? (subscribed ? "Unsubscribing..." : "Subscribing...") : (subscribed ? "Unsubscribe" : "Subscribe"),
                    background: subscribed ? Palette.paper : Palette.signal,
                    foreground: subscribed ? Palette.ink : .white,
                    hoverBackground: subscribed ? Palette.ink : Palette.caseRed,
                    hoverForeground: subscribed ? Palette.paper : .white,
                    disabled: busy
                ) { library.setSubscribed(!subscribed) }
            }
            Text(status).font(rubik(15)).foregroundStyle(library.error != nil ? Palette.caseRed : Palette.slate)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            HStack(spacing: 10) {
                Pill {
                    if onChannel, let channel = settings.channel {
                        IconButton(icon: .youtube, help: "Open channel on YouTube") {
                            NSWorkspace.shared.open(URL(string: "https://www.youtube.com/channel/\(channel.id)")!)
                        }
                    }
                    if section == .watchLater {
                        IconButton(icon: .downloadAll, help: "Download every Watch Later video") {
                            library.downloadAll()
                        }
                    }
                    IconButton(icon: .refresh, help: "Refresh", spinning: library.isRefreshing) {
                        library.refreshAll()
                    }
                }
                Pill {
                    IconButton(icon: .grid, help: "Grid", size: 34, active: settings.view == .grid) {
                        library.settings.view = .grid
                    }
                    IconButton(icon: .list, help: "List", size: 34, active: settings.view == .list) {
                        library.settings.view = .list
                    }
                }
                Pill {
                    SortMenu(section: section, sort: sort)
                    IconButton(icon: sort.ascending ? .up : .down,
                               help: "Reverse order", size: 34) {
                        library.settings.sorts[section.rawValue] = SortOrder(key: sort.key, ascending: !sort.ascending)
                    }
                }
            }
            .fixedSize()
        }
    }

    private var status: String {
        if let error = library.error { return error }
        if library.isRefreshing && (library.loading || !library.channelPage.videos.isEmpty) {
            return "Refreshing from YouTube..."
        }
        let active = library.activeDownloadCount
        return active > 0 ? "Downloading \(active) \(active == 1 ? "video" : "videos")" : ""
    }
}

struct SortMenu: View {
    let section: Section
    let sort: SortOrder
    @EnvironmentObject var library: Library
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(SortKey.allCases.filter { $0 != .added || !section.isFeed }, id: \.self) { key in
                Button {
                    library.settings.sorts[section.rawValue] = SortOrder(key: key, ascending: sort.ascending)
                } label: {
                    if key == sort.key { Label(key.label, systemImage: "checkmark") } else { Text(key.label) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(sort.key.label).font(rubik(15, 500)).foregroundStyle(Palette.ink)
                Chevron().stroke(Palette.slate, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 7, height: 8.5)
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 34)
            .background(Capsule().fill(hovering ? Palette.hover : .clear))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .focusable(false)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

struct LoadMore: View {
    @EnvironmentObject var library: Library

    var body: some View {
        let section = library.settings.section
        let onChannel = section == .channel
        let hasVideos = !library.videos(for: section).isEmpty
        let show = onChannel
            ? !library.channelPage.end && hasVideos
            : section == .subscriptions && !library.subscriptionsEnd && !(library.loading && !hasVideos)
        let busy = onChannel ? library.channelPage.loadingMore : library.loadingMore
        if show && Tools.missing.isEmpty && !library.needsSignIn {
            PillButton(title: busy ? "Loading..." : "Load more",
                       background: Palette.paper, foreground: busy ? Palette.slate : Palette.ink,
                       hoverBackground: Palette.ink, hoverForeground: Palette.paper,
                       height: 42, disabled: busy) {
                if onChannel { library.loadChannelVideos(.more) } else { library.loadMoreSubscriptions() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }
}

struct NoticeCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(rubik(22, 600)).foregroundStyle(Palette.ink).padding(.bottom, 8)
            content
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 28)
        .frame(maxWidth: 540, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.paper))
    }
}

struct SignInNotice: View {
    @EnvironmentObject var library: Library

    var body: some View {
        NoticeCard(title: "Sign in to YouTube") {
            Text("YT Zero needs your YouTube account to show Watch Later, your subscriptions, and your channels.")
                .font(rubik(16)).foregroundStyle(Palette.slate).lineSpacing(4).padding(.bottom, 22)
            PillButton(title: "Sign in", height: 42, weight: 600) { library.showSignIn = true }
                .padding(.bottom, 22)
            Text("YT Zero also uses your YouTube sign-in from Chrome, Brave, Edge, or Firefox. "
                 + "To use Safari's, turn on Full Disk Access for YT Zero, then refresh.")
                .font(rubik(14)).foregroundStyle(Palette.slate).lineSpacing(3).padding(.bottom, 12)
            PillButton(title: "Open Full Disk Access settings", background: Palette.mist, foreground: Palette.ink,
                       hoverBackground: Palette.hover, hoverForeground: Palette.ink, height: 34) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
    }
}

struct ToolsNotice: View {
    var body: some View {
        NoticeCard(title: "Install yt-dlp and ffmpeg") {
            Text("YT Zero uses yt-dlp to read your library and download videos, and ffmpeg to read transcripts. "
                 + "Install them with Homebrew, then quit YT Zero and open it again.")
                .font(rubik(16)).foregroundStyle(Palette.slate).lineSpacing(4).padding(.bottom, 16)
            Text("brew install yt-dlp ffmpeg")
                .font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.mist))
        }
    }
}

// MARK: Videos

struct VideoList: View {
    let videos: [Video]
    @EnvironmentObject var library: Library

    var body: some View {
        if library.settings.view == .grid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 22, alignment: .top)],
                      alignment: .leading, spacing: 30) {
                ForEach(videos) { VideoCard(video: $0, layout: .grid) }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(videos) { VideoCard(video: $0, layout: .list) }
            }
        }
    }
}

struct VideoCard: View {
    let video: Video
    let layout: Layout
    @EnvironmentObject var library: Library
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if layout == .grid {
            VStack(alignment: .leading, spacing: 10) {
                thumbnail
                info(titleSize: 15.5, reserveTitle: true)
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                thumbnail.frame(width: 200)
                info(titleSize: 17, reserveTitle: false).padding(.top, 6)
            }
        }
    }

    private var status: DownloadStatus? { library.downloads[video.id] }
    private var isLocal: Bool { library.local[video.id] != nil }

    private var thumbnail: some View {
        let watched = library.positions[video.id].map { video.duration > 0 ? min(1, $0 / Double(video.duration)) : 0 } ?? 0
        return Palette.ink
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { RemoteImage(urls: thumbnailURLs(video.id)) }
            .overlay(alignment: .bottomTrailing) {
                if video.duration > 0 {
                    Text(formatDuration(Double(video.duration))).font(rubik(12.5, 500)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.scrim))
                        .padding(.trailing, 8).padding(.bottom, watched > 0 ? 13 : 9)
                }
            }
            .overlay(alignment: .bottom) {
                if watched > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.4))
                            UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                                .fill(Palette.signal).frame(width: geo.size.width * watched)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .overlay {
                if let status, status.isActive {
                    ZStack {
                        Palette.night.opacity(0.55)
                        Stopwatch(fraction: progressFraction(status))
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: status?.isActive)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Palette.ink.opacity(hovering ? 0.35 : 0), radius: 9, y: 8)
            .offset(y: hovering && !reduceMotion ? -3 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { library.open(video.id) }
    }

    private func info(titleSize: CGFloat, reserveTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(video.title).font(rubik(titleSize, 500)).lineSpacing(1)
                .lineLimit(2, reservesSpace: reserveTitle)
                .help(video.title)
                .contentShape(Rectangle())
                .onTapGesture { library.open(video.id) }
            HStack(spacing: 8) {
                meta
                Spacer(minLength: 0)
                actions.padding(.trailing, -6)
            }
        }
    }

    private func progressFraction(_ status: DownloadStatus) -> Double? {
        if case .downloading(let progress?) = status { return progress / 100 }
        return nil
    }

    private var meta: some View {
        let text: String
        var failed = false
        var percent: Int?
        switch status {
        case .queued: text = "Queued"
        case .downloading(let progress):
            percent = progress.map { Int($0) }
            text = percent.map { "Downloading \($0)%" } ?? "Downloading..."
        case .failed:
            text = "Download failed. Click to retry."
            failed = true
        case nil: text = [video.channel, formatAge(video.timestamp)].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return Text(text).font(rubik(13)).monospacedDigit()
            .foregroundStyle(failed ? Palette.caseRed : Palette.slate)
            .lineLimit(1).truncationMode(.tail)
            .contentTransition(.numericText(value: Double(percent ?? 0)))
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: percent)
    }

    /// The same three buttons in every section: YouTube, Watch Later, and download.
    @ViewBuilder private var actions: some View {
        let id = video.id
        HStack(spacing: 0) {
            IconButton(icon: .youtube, help: "Open on YouTube", size: 34) { library.openOnYouTube(id) }
            // Each toggle keeps one shape: an outline when off, filled green when
            // on, and red on hover when clicking would undo it.
            if library.inWatchLater(id) {
                IconButton(icon: .inWatchLater, help: "Remove from Watch Later", size: 34, color: Palette.done,
                           hoverColor: Palette.caseRed) { library.removeFromWatchLater(id) }
            } else {
                IconButton(icon: .watchLater, help: "Add to Watch Later", size: 34) { library.addToWatchLater(id) }
            }
            if let status, status.isActive {
                DownloadProgressButton(fraction: progressFraction(status)) { library.cancel(id) }
            } else if isLocal {
                IconButton(icon: .downloaded, help: "Delete download", size: 34, color: Palette.done,
                           hoverColor: Palette.caseRed) { library.deleteDownload(id) }
            } else {
                IconButton(icon: .download, help: "Download", size: 34) {
                    library.download(id, saveToWatchLater: library.settings.section != .channel)
                }
            }
        }
    }
}

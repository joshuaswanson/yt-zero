import CoreGraphics
import Foundation

struct Video: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var duration: Int
    var timestamp: Int?
    var channel: String
}

struct Account: Equatable {
    var name: String
    var handle: String
    var photo: URL?
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatar: String
}

enum Section: String, Codable {
    case subscriptions, watchLater, downloaded, channel

    var title: String {
        switch self {
        case .subscriptions: "Subscriptions"
        case .watchLater: "Watch Later"
        case .downloaded: "Downloaded"
        case .channel: ""
        }
    }

    var isFeed: Bool { self == .subscriptions || self == .channel }

    var defaultSort: SortOrder {
        isFeed ? SortOrder(key: .published, ascending: false) : SortOrder(key: .added, ascending: true)
    }
}

enum SortKey: String, Codable, CaseIterable {
    case added, published, title, duration

    var label: String {
        switch self {
        case .added: "Date added"
        case .published: "Date published"
        case .title: "Title"
        case .duration: "Length"
        }
    }
}

struct SortOrder: Codable, Equatable {
    var key: SortKey
    var ascending: Bool
}

enum Layout: String, Codable {
    case grid, list

    /// Leaves room for the window's close, minimize, and zoom buttons.
    static let contentTop: CGFloat = 40
}

struct Settings: Codable, Equatable {
    var section: Section = .watchLater
    var view: Layout = .grid
    var sorts: [String: SortOrder] = [:]
    var speed: Double = 1
    var captions = false
    var transcript = false
    var channel: Channel?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        section = (try? c.decodeIfPresent(Section.self, forKey: .section)) ?? .watchLater
        view = (try? c.decodeIfPresent(Layout.self, forKey: .view)) ?? .grid
        sorts = (try? c.decodeIfPresent([String: SortOrder].self, forKey: .sorts)) ?? [:]
        speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? 1
        captions = (try? c.decodeIfPresent(Bool.self, forKey: .captions)) ?? false
        transcript = (try? c.decodeIfPresent(Bool.self, forKey: .transcript)) ?? false
        channel = try? c.decodeIfPresent(Channel.self, forKey: .channel)
        if section == .channel && channel == nil { section = .watchLater }
    }

    func sort(for section: Section) -> SortOrder {
        sorts[section.rawValue] ?? section.defaultSort
    }
}

struct Prefs: Codable {
    var settings: Settings?
    var positions: [String: Double]
}

enum DownloadStatus: Equatable {
    case queued
    case downloading(progress: Double?)
    case failed

    var isActive: Bool { self != .failed }
}

struct TranscriptLine: Identifiable {
    let id: Int
    let start: Double
    let text: String
    let newSpeaker: Bool
}

struct Chapter {
    let start: Double
    let title: String
}

struct Transcript {
    var lines: [TranscriptLine] = []
    var chapters: [Chapter] = []
}

func sortVideos(_ videos: [Video], _ order: SortOrder) -> [Video] {
    let up = order.ascending
    switch order.key {
    case .title:
        return videos.sorted {
            let c = $0.title.localizedStandardCompare($1.title)
            return up ? c == .orderedAscending : c == .orderedDescending
        }
    case .duration:
        return videos.sorted { up ? $0.duration < $1.duration : $0.duration > $1.duration }
    case .published:
        let dated = videos.filter { $0.timestamp != nil }.sorted {
            up ? $0.timestamp! < $1.timestamp! : $0.timestamp! > $1.timestamp!
        }
        return dated + videos.filter { $0.timestamp == nil }
    case .added:
        return up ? videos : videos.reversed()
    }
}

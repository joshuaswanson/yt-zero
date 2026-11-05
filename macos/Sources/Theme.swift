import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let mist = Color(hex: 0xe6eaee)
    static let paper = Color(hex: 0xf4f6f8)
    static let ink = Color(hex: 0x15202a)
    static let slate = Color(hex: 0x5b6975)
    static let hover = Color(hex: 0xd6dde3)
    static let signal = Color(hex: 0xff0033)
    static let caseRed = Color(hex: 0xc20027)
    static let done = Color(hex: 0x1f9d55)
    static let night = Color(hex: 0x0d1419)
    static let nightRaised = Color(hex: 0x18222a)
    static let nightHover = Color(hex: 0x26323c)
    static let nightLineHover = Color(hex: 0x222e38)
    static let nightRule = Color(hex: 0x2a3640)
    static let nightTrack = Color(hex: 0x34414b)
    static let nightInk = Color(hex: 0xdce3e8)
    static let nightSlate = Color(hex: 0x8795a1)
    static let scrim = Color(hex: 0x0d1419, opacity: 0.82)
}

/// Rubik is a variable font, so each weight is a value on its "wght" axis.
/// It loads from the bundled file because the file names its family "Rubik Light".
private let rubikDescriptor: CTFontDescriptor? = Bundle.main.url(forResource: "Rubik", withExtension: "ttf")
    .flatMap { (CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor])?.first }

@MainActor private var fontCache: [Int: NSFont] = [:]

@MainActor func rubik(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
    let key = Int(size * 100) * 10_000 + Int(weight)
    if let font = fontCache[key] { return Font(font) }
    var font = NSFont.systemFont(ofSize: size)
    if let rubikDescriptor {
        let descriptor = CTFontDescriptorCreateCopyWithVariation(rubikDescriptor, 0x7767_6874 as CFNumber, weight)
        font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
    fontCache[key] = font
    return Font(font)
}

func formatDuration(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.isFinite ? seconds : 0))
    let h = s / 3600, m = (s % 3600) / 60, r = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
}

func formatAge(_ timestamp: Int?) -> String {
    guard let timestamp else { return "" }
    let days = Int((Date().timeIntervalSince1970 - Double(timestamp)) / 86400)
    if days <= 0 { return "today" }
    if days == 1 { return "yesterday" }
    for (size, unit) in [(365, "year"), (30, "month"), (7, "week")] where days >= size {
        let n = days / size
        return "\(n) \(unit)\(n > 1 ? "s" : "") ago"
    }
    return "\(days) days ago"
}

import AppKit
import SwiftUI

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, NSImage>()
    private var failed: Set<URL> = []

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    /// The first of `urls` that loads.
    func load(_ urls: [URL]) async -> NSImage? {
        for url in urls where !failed.contains(url) {
            if let image = cached(url) { return image }
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) {
                cache.setObject(image, forKey: url as NSURL)
                return image
            }
            failed.insert(url)
        }
        return nil
    }
}

struct RemoteImage: View {
    let urls: [URL]
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = image ?? urls.lazy.compactMap({ ImageStore.shared.cached($0) }).first {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .task(id: urls) { image = await ImageStore.shared.load(urls) }
    }
}

func thumbnailURLs(_ id: String) -> [URL] {
    ["hq720", "mqdefault"].compactMap { URL(string: "https://i.ytimg.com/vi/\(id)/\($0).jpg") }
}

struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let icon: Icon
    let help: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 21
    var color = Palette.slate
    var hoverColor = Palette.ink
    var hoverBackground = Palette.hover
    var background = Color.clear
    var active = false
    var activeColor = Palette.paper
    var activeBackground = Palette.ink
    var hoverIcon: Icon?
    var spinning = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !spinning || reduceMotion)) { context in
                IconView(icon: hovering ? (hoverIcon ?? icon) : icon, size: iconSize)
                    .rotationEffect(.degrees(spinning && !reduceMotion
                        ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
            }
                .foregroundStyle(active ? activeColor : hovering ? hoverColor : color)
                .frame(width: size, height: size)
                .background(Circle().fill(active ? activeBackground : hovering ? hoverBackground : background))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PillButton: View {
    let title: String
    var background = Palette.signal
    var foreground = Color.white
    var hoverBackground = Palette.caseRed
    var hoverForeground = Color.white
    var height: CGFloat = 36
    var weight: CGFloat = 500
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let hot = hovering && !disabled
        Button(action: action) {
            Text(title)
                .font(rubik(15, weight))
                .foregroundStyle(hot ? hoverForeground : foreground)
                .padding(.horizontal, height / 2)
                .frame(height: height)
                .background(Capsule().fill(hot ? hoverBackground : background))
                .contentShape(Capsule())
                .opacity(disabled ? 0.7 : 1)
        }
        .buttonStyle(PressScale(scale: disabled ? 1 : 0.96))
        .focusable(false)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

struct Pill<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background(Capsule().fill(Palette.paper))
    }
}

/// A zero with a play button inside, from the app icon.
struct BrandMark: View {
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11.5, style: .continuous).fill(Palette.signal)
            PlayTriangle()
                .fill(.white)
                .frame(width: 8, height: 9.5)
                .offset(x: 1.2)
                .scaleEffect(scale)
        }
        .frame(width: 23, height: 30)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.25)) { scale = 0.55 }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.25)) { scale = 1.15 }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.2)) { scale = 1 }
        }
    }
}

struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.18
        var path = Path()
        let a = CGPoint(x: rect.minX, y: rect.minY)
        let b = CGPoint(x: rect.maxX, y: rect.midY)
        let c = CGPoint(x: rect.minX, y: rect.maxY)
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(tangent1End: a, tangent2End: b, radius: r)
        path.addArc(tangent1End: b, tangent2End: c, radius: r)
        path.addArc(tangent1End: c, tangent2End: a, radius: r)
        path.closeSubpath()
        return path
    }
}

/// Download progress as a stopwatch whose red wedge fills as bytes arrive.
/// Progress arrives in uneven bursts. A spring retargets on each update
/// without losing its speed, so the wedge and hand move continuously.
struct Stopwatch: View {
    let fraction: Double?
    @State private var spunWhileWaiting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spinPeriod = 1.2

    var body: some View {
        TimelineView(.animation(paused: fraction != nil || reduceMotion)) { context in
            dial(handDegrees: handDegrees(at: context.date))
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: fraction)
        .onAppear { if fraction == nil { spunWhileWaiting = true } }
    }

    /// After spinning, the hand keeps turning forward into its first position.
    private func handDegrees(at date: Date) -> Double {
        if let fraction { return fraction * 360 + (spunWhileWaiting ? 360 : 0) }
        guard !reduceMotion else { return 0 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.spinPeriod) / Self.spinPeriod * 360
    }

    private func dial(handDegrees: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 12, height: 9).offset(y: -29.5)
            Circle().fill(.white).frame(width: 56, height: 56).offset(y: 4)
            Circle().fill(Palette.ink).frame(width: 42, height: 42).offset(y: 4)
            Wedge(fraction: fraction ?? 0).fill(Palette.signal).frame(width: 40, height: 40).offset(y: 4)
            Capsule().fill(.white).frame(width: 3, height: 20)
                .rotationEffect(.degrees(handDegrees), anchor: UnitPoint(x: 0.5, y: 0.925))
                .offset(y: -4.5)
            Circle().fill(.white).frame(width: 7, height: 7).offset(y: 4)
        }
        .frame(width: 60, height: 68)
        .scaleEffect(46 / 60)
        .frame(width: 46, height: 52)
    }
}

struct Wedge: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

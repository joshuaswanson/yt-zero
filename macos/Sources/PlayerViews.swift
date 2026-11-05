import AVFoundation
import SwiftUI

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @EnvironmentObject var library: Library

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconButton(icon: .back, help: "Back to library (Esc)", color: Palette.nightSlate,
                           hoverColor: Palette.nightInk, hoverBackground: Palette.nightRaised) { model.close() }
                Text(model.video?.title ?? "").font(rubik(20, 600)).lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                if let chapter = model.chapter(at: model.time), !chapter.title.isEmpty {
                    Text(chapter.title).font(rubik(15, 500)).foregroundStyle(Palette.nightSlate)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.nightRaised))
                        .help("Current chapter")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 12)

            HStack(spacing: 14) {
                Screen(model: model)
                if library.settings.transcript {
                    TranscriptPanel(model: model).frame(width: 380)
                }
            }
            .padding(.horizontal, 18)

            Controls(model: model)
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
        }
        .foregroundStyle(Palette.nightInk)
        .background(Palette.night)
    }
}

struct Screen: View {
    @ObservedObject var model: PlayerModel
    @EnvironmentObject var library: Library

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                VideoSurface(player: model.player)
                if let caption = model.caption {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(rubik(max(17, geo.size.height * 0.04), 500))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.black.opacity(0.72))
                            .frame(maxWidth: geo.size.width * 0.8)
                            .padding(.bottom, geo.size.height * 0.06)
                    }
                }
                if let flash = model.flash {
                    FlashView(flash: flash, size: geo.size).id(flash.id)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.toggleFromScreen() }
    }
}

struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

struct FlashView: View {
    let flash: Flash
    let size: CGSize
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let x: CGFloat = switch flash.position {
        case .center: 0.5
        case .back: 0.18
        case .forward: 0.82
        }
        Group {
            if let icon = flash.icon {
                IconView(icon: icon, size: 34)
            } else {
                Text(flash.text ?? "").font(rubik(20, 600)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(minWidth: 76, minHeight: 76)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .scaleEffect(reduceMotion ? 1 : shown ? 1.25 : 0.85)
        .opacity(shown ? 0 : 1)
        .position(x: size.width * x, y: size.height / 2)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: PlayerModel.flashDuration)) { shown = true }
        }
    }
}

// MARK: Controls

struct Controls: View {
    @ObservedObject var model: PlayerModel
    @EnvironmentObject var library: Library
    @State private var playHover = false

    var body: some View {
        HStack(spacing: 6) {
            Button { model.toggle() } label: {
                IconView(icon: model.isPlaying ? .pause : .play, size: 22)
                    .foregroundStyle(playHover ? .white : Palette.nightInk)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(playHover ? Palette.signal : Palette.nightRaised))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .focusable(false)
            .onHover { playHover = $0 }
            .help("Play or pause (Space)")
            .padding(.trailing, 6)

            timeLabel(model.time)
            Scrubber(model: model)
            timeLabel(model.duration)

            controlButton(.captions, help: library.settings.captions ? "Hide subtitles" : "Show subtitles",
                          active: library.settings.captions) { library.settings.captions.toggle() }
                .disabled(model.transcriptLoaded && model.lines.isEmpty)
                .opacity(model.transcriptLoaded && model.lines.isEmpty ? 0.35 : 1)
                .padding(.leading, 10)
            controlButton(.transcript, help: library.settings.transcript ? "Hide transcript" : "Show transcript",
                          active: library.settings.transcript) {
                library.settings.transcript.toggle()
                if library.settings.transcript { model.followPaused = false }
            }

            HStack(spacing: 10) {
                RangeSlider(value: library.settings.speed, range: 0.5...3, step: 0.25,
                            fill: Palette.nightInk) { model.setSpeed($0) }
                    .frame(width: 130)
                Text("\(library.settings.speed.formatted(.number.precision(.fractionLength(0...2))))x")
                    .font(rubik(13, 500)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .frame(minWidth: 44)
                    .background(Capsule().fill(Palette.nightRaised))
            }
            .padding(.leading, 8)
        }
    }

    private func timeLabel(_ seconds: Double) -> some View {
        Text(formatDuration(seconds)).font(rubik(13.5)).monospacedDigit()
            .foregroundStyle(Palette.nightSlate).frame(minWidth: 52)
    }

    private func controlButton(_ icon: Icon, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        IconButton(icon: icon, help: help, size: 46, iconSize: 22,
                   color: active ? Palette.signal : Palette.nightSlate,
                   hoverColor: active ? Palette.signal : Palette.nightInk,
                   hoverBackground: Palette.nightHover, background: Palette.nightRaised, action: action)
    }
}

/// The track, fill, and thumb shared by the scrubber and the speed slider.
struct SliderTrack: View {
    let fraction: Double
    let fill: Color
    let hovering: Bool
    var marks: [Double] = []
    /// The scrubber passes the hovered fraction so the segment under the pointer grows.
    var hoverFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(0, width - 16)
            let f = min(1, max(0, fraction.isFinite ? fraction : 0))
            let inner = marks.filter { $0 > 0 && $0 < 1 }.sorted()
            let x = { (mark: Double) in 8 + travel * mark }
            let edges = [0] + inner.map(x) + [width]
            let hovered = hoverFraction.map { h in inner.filter { $0 <= h }.count }
            ZStack(alignment: .leading) {
                ForEach(0..<edges.count - 1, id: \.self) { i in
                    TrackSegment(width: edges[i + 1] - edges[i], filled: x(f) - edges[i], fill: fill,
                                 raised: hovered == i, roundLeading: i == 0, roundTrailing: i == edges.count - 2)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered == i)
                        .offset(x: edges[i])
                }
                ForEach(Array(inner.enumerated()), id: \.offset) { _, mark in
                    Rectangle().fill(Palette.night).frame(width: 3, height: 14)
                        .offset(x: x(mark) - 1.5)
                }
                Circle().fill(Palette.nightInk).frame(width: 16, height: 16)
                    .scaleEffect(hovering ? 1.2 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                    .offset(x: travel * f)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
    }
}

struct TrackSegment: View {
    let width: CGFloat
    let filled: CGFloat
    let fill: Color
    let raised: Bool
    let roundLeading: Bool
    let roundTrailing: Bool

    var body: some View {
        let height: CGFloat = raised ? 12 : 6
        let leading = roundLeading ? height / 2 : 0
        let trailing = roundTrailing ? height / 2 : 0
        ZStack(alignment: .leading) {
            Palette.nightTrack
            fill.frame(width: min(max(0, filled), width))
        }
        .frame(width: max(0, width), height: height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                          bottomTrailingRadius: trailing, topTrailingRadius: trailing))
    }
}

struct RangeSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let fill: Color
    let onChange: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            SliderTrack(fraction: (value - range.lowerBound) / (range.upperBound - range.lowerBound),
                        fill: fill, hovering: hovering)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = min(1, max(0, (drag.location.x - 8) / max(1, geo.size.width - 16)))
                    let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    let stepped = (raw / step).rounded() * step
                    if stepped != value { onChange(stepped) }
                })
                .onHover { hovering = $0 }
        }
        .frame(height: 22)
    }
}

struct Scrubber: View {
    @ObservedObject var model: PlayerModel
    @State private var hoverX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(1, width - 16)
            let fraction = model.duration > 0 ? model.time / model.duration : 0
            let timeAt = { (x: CGFloat) -> Double in
                Double(min(1, max(0, (x - 8) / travel))) * model.duration
            }
            let marks = model.duration > 0 ? model.chapters.map { $0.start / model.duration } : []
            SliderTrack(fraction: fraction, fill: Palette.signal, hovering: hoverX != nil, marks: marks,
                        hoverFraction: hoverX.map { Double(min(1, max(0, ($0 - 8) / travel))) })
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        model.scrubbing = true
                        model.seek(to: timeAt(drag.location.x))
                        hoverX = drag.location.x
                        model.requestPreview(timeAt(drag.location.x))
                    }
                    .onEnded { _ in model.scrubbing = false })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverX = point.x
                        if model.duration > 0 { model.requestPreview(timeAt(point.x)) }
                    case .ended:
                        hoverX = nil
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let hoverX, model.duration > 0 {
                        let window = geo.frame(in: .global)
                        let half = PlayerModel.previewWidth / 2 + 4
                        let windowWidth = NSApp.keyWindow?.contentView?.bounds.width ?? .infinity
                        let x = min(max(hoverX, half - window.minX), windowWidth - window.minX - half)
                        ScrubPreview(model: model, time: timeAt(hoverX))
                            .offset(x: x - PlayerModel.previewWidth / 2, y: -34)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(height: 22)
        .frame(minWidth: 80)
    }
}

struct ScrubPreview: View {
    @ObservedObject var model: PlayerModel
    let time: Double

    var body: some View {
        VStack(spacing: 6) {
            if let title = model.chapter(at: time)?.title, !title.isEmpty {
                Text(title).font(rubik(13, 600)).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.scrim))
                    .frame(width: PlayerModel.previewWidth)
            }
            frame
        }
    }

    private var frame: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let image = model.previewImage {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
            }
            Text(formatDuration(time)).font(rubik(13, 500)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(Capsule().fill(Palette.scrim))
                .padding(.bottom, 6)
        }
        .frame(width: PlayerModel.previewWidth, height: PlayerModel.previewWidth / model.videoAspect)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.nightInk, lineWidth: 2))
        .shadow(color: .black.opacity(0.8), radius: 12, y: 10)
    }
}

// MARK: Transcript

struct TranscriptPanel: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !model.transcriptLoaded || model.lines.isEmpty {
                            Text(model.transcriptLoaded ? "This video has no transcript." : "Loading transcript...")
                                .font(rubik(15)).foregroundStyle(Palette.nightSlate)
                                .padding(.horizontal, 12).padding(.vertical, 20)
                        }
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { position, row in
                            TranscriptRowView(row: row, first: position == 0,
                                              current: model.currentLine == row.id && !isChapter(row)) {
                                model.seek(to: row.start)
                                model.followPaused = false
                            }
                            .id(row.id)
                        }
                    }
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 40)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { model.followPaused = true }
                }
                .onChange(of: model.currentLine) { follow(proxy, animated: true) }
                .onChange(of: model.followPaused) { if !model.followPaused { follow(proxy, animated: true) } }
                .onChange(of: model.rows.count) { follow(proxy, animated: false) }
                .onAppear { follow(proxy, animated: false) }
            }
            if model.followPaused {
                PillButton(title: "Back to current line", height: 32) { model.followPaused = false }
                    .shadow(color: .black.opacity(0.7), radius: 8, y: 6)
                    .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.nightRaised))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func isChapter(_ row: TranscriptRow) -> Bool {
        if case .chapter = row { return true }
        return false
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !model.followPaused, let line = model.currentLine else { return }
        let scroll = { proxy.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.33)) }
        if animated && !reduceMotion { withAnimation(.easeInOut(duration: 0.35), scroll) } else { scroll() }
    }
}

struct TranscriptRowView: View {
    let row: TranscriptRow
    let first: Bool
    let current: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        switch row {
        case .chapter(_, let chapter):
            content(at: chapter.start, text: chapter.title, chapter: true)
                .padding(.top, first ? 6 : 22)
        case .line(let line, let speakerBreak):
            content(at: line.start, text: line.text, chapter: false)
                .overlay(alignment: .top) {
                    if speakerBreak {
                        Rectangle().fill(Palette.nightRule).frame(height: 1)
                            .padding(.leading, 12).padding(.trailing, 10).offset(y: -7)
                    }
                }
                .padding(.top, speakerBreak ? 12 : 0)
        }
    }

    private func content(at: Double, text: String, chapter: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatDuration(at)).font(rubik(12.5)).monospacedDigit()
                .foregroundStyle(current ? Palette.signal : Palette.nightSlate)
                .frame(width: 52, alignment: .leading)
            Text(text).font(chapter ? rubik(18, 600) : rubik(15)).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(chapter || current || hovering ? Palette.nightInk : Palette.nightSlate)
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(current ? Palette.signal.opacity(0.16) : hovering ? Palette.nightLineHover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

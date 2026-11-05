import Foundation
import SwiftUI

struct IconShape: Shape {
    let icon: Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 256
        let transform = CGAffineTransform(translationX: rect.midX - 128 * scale, y: rect.midY - 128 * scale)
            .scaledBy(x: scale, y: scale)
        return SVGPath.parse(icon.pathData).applying(transform)
    }
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 21

    var body: some View {
        IconShape(icon: icon).frame(width: size, height: size)
    }
}

/// Builds a Path from SVG path data with the commands Phosphor uses:
/// M L H V C A Z in absolute and relative forms.
enum SVGPath {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Path] = [:]

    static func parse(_ data: String) -> Path {
        if let cached = lock.withLock({ cache[data] }) { return cached }
        var parser = Parser(data)
        let path = parser.build()
        lock.withLock { cache[data] = path }
        return path
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero

        init(_ data: String) { chars = Array(data) }

        mutating func build() -> Path {
            var command: Character = "M"
            while true {
                skipSeparators()
                guard i < chars.count else { break }
                if chars[i].isLetter {
                    command = chars[i]
                    i += 1
                    if command == "Z" || command == "z" {
                        path.closeSubpath()
                        current = start
                        continue
                    }
                }
                let relative = command.isLowercase
                let base = relative ? current : .zero
                switch command.uppercased() {
                case "M":
                    let p = point(base)
                    path.move(to: p)
                    current = p
                    start = p
                    command = relative ? "l" : "L"
                case "L":
                    let p = point(base)
                    path.addLine(to: p)
                    current = p
                case "H":
                    let x = number() + (relative ? current.x : 0)
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                case "V":
                    let y = number() + (relative ? current.y : 0)
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                case "C":
                    let c1 = point(base), c2 = point(base), p = point(base)
                    path.addCurve(to: p, control1: c1, control2: c2)
                    current = p
                case "A":
                    let rx = number(), ry = number(), rotation = number()
                    let large = flag(), sweep = flag()
                    let p = point(base)
                    addArc(to: p, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                    current = p
                default:
                    return path
                }
            }
            return path
        }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 }
        }

        mutating func number() -> CGFloat {
            skipSeparators()
            var text = ""
            var seenDot = false, seenExp = false
            while i < chars.count {
                let c = chars[i]
                if c == "-" || c == "+" {
                    if !text.isEmpty && text.last != "e" && text.last != "E" { break }
                } else if c == "." {
                    if seenDot || seenExp { break }
                    seenDot = true
                } else if c == "e" || c == "E" {
                    if seenExp { break }
                    seenExp = true
                } else if !c.isNumber {
                    break
                }
                text.append(c)
                i += 1
            }
            return CGFloat(Double(text) ?? 0)
        }

        /// Arc flags can be written without separators ("a12,12,0,0,1-12,12" or "0,01").
        mutating func flag() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let value = chars[i] == "1"
            i += 1
            return value
        }

        mutating func point(_ base: CGPoint) -> CGPoint {
            let x = number(), y = number()
            return CGPoint(x: base.x + x, y: base.y + y)
        }

        /// SVG endpoint arcs converted to center form, then to cubic Béziers
        /// (SVG 1.1 appendix F.6.5).
        mutating func addArc(to end: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
            var rx = abs(rx), ry = abs(ry)
            guard rx > 0, ry > 0, end != current else { return path.addLine(to: end) }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (current.x - end.x) / 2, dy = (current.y - end.y) / 2
            let x1 = cosPhi * dx + sinPhi * dy
            let y1 = -sinPhi * dx + cosPhi * dy
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 {
                rx *= sqrt(lambda)
                ry *= sqrt(lambda)
            }
            let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
            var coefficient = sqrt(max(0, numerator / denominator))
            if large == sweep { coefficient = -coefficient }
            let cx1 = coefficient * rx * y1 / ry
            let cy1 = -coefficient * ry * x1 / rx
            let cx = cosPhi * cx1 - sinPhi * cy1 + (current.x + end.x) / 2
            let cy = sinPhi * cx1 + cosPhi * cy1 + (current.y + end.y) / 2

            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
                return a
            }
            let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
            var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
            if !sweep && delta > 0 { delta -= 2 * .pi }
            if sweep && delta < 0 { delta += 2 * .pi }

            let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
            let step = delta / CGFloat(segments)
            let k = 4 / 3 * tan(step / 4)
            func pointAt(_ t: CGFloat) -> (CGPoint, CGPoint) {
                let x = rx * cos(t), y = ry * sin(t)
                let p = CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
                let tx = -rx * sin(t), ty = ry * cos(t)
                let d = CGPoint(x: cosPhi * tx - sinPhi * ty, y: sinPhi * tx + cosPhi * ty)
                return (p, d)
            }
            var t = theta1
            for _ in 0..<segments {
                let (p0, d0) = pointAt(t)
                let (p1, d1) = pointAt(t + step)
                path.addCurve(to: p1,
                              control1: CGPoint(x: p0.x + k * d0.x, y: p0.y + k * d0.y),
                              control2: CGPoint(x: p1.x - k * d1.x, y: p1.y - k * d1.y))
                t += step
            }
            path.addLine(to: end)
        }
    }
}

/// The small chevron on the sort menu, stroked like the web version's.
struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3))
        return path
    }
}

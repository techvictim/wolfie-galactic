import SwiftUI
@preconcurrency import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns words into outline paths, so the title can have a thick metal edge.
@MainActor
enum TitleGlyphs {
    struct Glyphs {
        let path: CGPath
        let bounds: CGRect
    }

    private static var cache: [String: Glyphs] = [:]

    /// The word set in the system's rounded, heaviest weight, with letters pulled close together.
    static func glyphs(for text: String, kern: CGFloat = -0.045) -> Glyphs {
        let key = "\(text)|\(kern)"
        if let cached = cache[key] { return cached }

        let size: CGFloat = 200
        #if os(macOS)
        var font = NSFont.systemFont(ofSize: size, weight: .black)
        if let rounded = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: size) {
            font = f
        }
        #else
        var font = UIFont.systemFont(ofSize: size, weight: .black)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: size)
        }
        #endif

        let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: kern * size])
        let line = CTLineCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName as String] else { continue }
            let runFont = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                // Glyphs are drawn y-up; flip them for the screen.
                let transform = CGAffineTransform(translationX: positions[i].x, y: -positions[i].y).scaledBy(x: 1, y: -1)
                path.addPath(glyph, transform: transform)
            }
        }
        let result = Glyphs(path: path, bounds: path.boundingBoxOfPath)
        cache[key] = result
        return result
    }
}

/// A word's outline, scaled to fit its frame with room left around it for the stroke.
struct GlyphShape: Shape {
    let outline: Path
    let bounds: CGRect
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let area = rect.insetBy(dx: inset, dy: inset)
        let scale = min(area.width / bounds.width, area.height / bounds.height)
        let x = area.midX - bounds.midX * scale
        let y = area.midY - bounds.midY * scale
        let transform = CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
        return outline.applying(transform)
    }
}

/// A title word with a coloured face, a thick chrome edge and a light that sweeps across it.
struct MetalWord: View {
    let text: String
    let face: [Color]
    /// Seconds to wait before this word's shimmer, so the two words shine one after the other.
    var shimmerDelay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Visible width of the chrome edge, as a share of the word's frame height.
    static let strokeShare: CGFloat = 0.1
    private static let insetShare: CGFloat = strokeShare + 0.02

    private static let chrome = LinearGradient(
        stops: [
            .init(color: Color(red: 1.0, green: 1.0, blue: 1.0), location: 0.0),
            .init(color: Color(red: 0.78, green: 0.82, blue: 0.88), location: 0.2),
            .init(color: Color(red: 0.4, green: 0.43, blue: 0.53), location: 0.44),
            .init(color: Color(red: 0.95, green: 0.96, blue: 0.99), location: 0.56),
            .init(color: Color(red: 0.55, green: 0.58, blue: 0.67), location: 0.78),
            .init(color: Color(red: 0.89, green: 0.91, blue: 0.95), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let glyphs = TitleGlyphs.glyphs(for: text)
        let inner = 1 - 2 * MetalWord.insetShare
        let aspect = inner * glyphs.bounds.width / max(glyphs.bounds.height, 1) + 2 * MetalWord.insetShare

        GeometryReader { geo in
            let edge = geo.size.height * MetalWord.strokeShare
            let shape = GlyphShape(outline: Path(glyphs.path), bounds: glyphs.bounds, inset: geo.size.height * MetalWord.insetShare)
            let round = StrokeStyle(lineWidth: edge * 2, lineCap: .round, lineJoin: .round)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let sweep = reduceMotion ? -1 : MetalWord.sweep(at: timeline.date, delay: shimmerDelay)
                ZStack {
                    // Dark outer edge so the chrome stands out from the sky.
                    shape.stroke(Color(red: 0.07, green: 0.04, blue: 0.16), style: StrokeStyle(lineWidth: edge * 2 + max(4, edge * 0.35), lineCap: .round, lineJoin: .round))
                    // Chrome edge.
                    shape.stroke(MetalWord.chrome, style: round)
                    // Moving shine, only on the chrome.
                    MetalWord.band(sweep)
                        .mask(shape.stroke(style: round))
                    // Coloured face with a glossy top.
                    shape.fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
                    // Bright line where chrome meets colour.
                    shape.stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(1, edge * 0.12), lineJoin: .round))
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityLabel(text)
    }

    /// Where the shine is: sweeps across over 1.4 seconds, then rests, every 4.5 seconds.
    static func sweep(at date: Date, delay: Double) -> Double {
        let period = 4.5
        let t = (date.timeIntervalSinceReferenceDate - delay).truncatingRemainder(dividingBy: period)
        let progress = (t < 0 ? t + period : t) / 1.4
        return progress > 1 ? -1 : -0.25 + progress * 1.5
    }

    static func band(_ position: Double) -> LinearGradient {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0), location: clamp(position - 0.14)),
                .init(color: Color.white.opacity(0.95), location: clamp(position)),
                .init(color: Color.white.opacity(0), location: clamp(position + 0.14))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// WOLFIE over GALACTIC, set tight.
struct GameTitle: View {
    var body: some View {
        VStack(spacing: -10) {
            MetalWord(
                text: "WOLFIE",
                face: [Color(red: 0.62, green: 0.99, blue: 1.0), Color(red: 0.2, green: 0.76, blue: 0.68)]
            )
            MetalWord(
                text: "GALACTIC",
                face: [Color(red: 1.0, green: 0.55, blue: 0.88), Color(red: 0.5, green: 0.32, blue: 1.0)],
                shimmerDelay: 0.35
            )
            .padding(.horizontal, 6)
        }
        .shadow(color: Color(red: 0.54, green: 0.36, blue: 1.0).opacity(0.55), radius: 24)
    }
}

/// Wolfie World, its mountains, lakes and canyons forming a wolf's face. Floats gently.
/// The picture is Resources/wolfie-world.png, painted by Tools/make_title_planet.py.
struct PlanetEmblem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Group {
                if let image = PlanetEmblem.image {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Circle()
                        .fill(Color(red: 0.31, green: 0.82, blue: 0.69))
                        .padding(40)
                }
            }
            .shadow(color: Color(red: 0.37, green: 0.94, blue: 1.0).opacity(0.3 + 0.15 * sin(t * 1.3)), radius: 34)
            .offset(y: CGFloat(sin(t * 0.8)) * 8)
            .rotationEffect(.degrees(sin(t * 0.33) * 2))
        }
        .accessibilityLabel("Wolfie World")
    }

    static let image: Image? = {
        guard let url = Bundle.main.url(forResource: "wolfie-world", withExtension: "png") else { return nil }
        #if os(macOS)
        guard let picture = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: picture)
        #else
        guard let picture = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: picture)
        #endif
    }()
}

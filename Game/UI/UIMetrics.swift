import SwiftUI

/// One type scale for every device. Apple TV's built-in text styles are very large and
/// iPhone screens are small, so the game sets its own sizes and scales them per device.
enum UIMetrics {
    /// How much bigger or smaller than the iPad design everything is drawn.
    static let scale: CGFloat = {
        #if os(tvOS)
        return 1.45          // read from the couch, on a 1920-point-wide screen
        #elseif os(macOS)
        return 1.0
        #else
        return UIDevice.current.userInterfaceIdiom == .phone ? 0.78 : 1.0
        #endif
    }()

    static func points(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded()
    }
}

extension Font {
    /// Rounded game text at an iPad-sized point size, scaled for this device.
    static func game(_ size: CGFloat) -> Font {
        .system(size: UIMetrics.points(size), design: .rounded)
    }

    /// Symbol sizes, scaled the same way.
    static func gameIcon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIMetrics.points(size), weight: weight)
    }
}

extension View {
    /// Keep a prompt on one line, shrinking it a little rather than wrapping.
    func oneLine() -> some View {
        lineLimit(1).minimumScaleFactor(0.6)
    }
}

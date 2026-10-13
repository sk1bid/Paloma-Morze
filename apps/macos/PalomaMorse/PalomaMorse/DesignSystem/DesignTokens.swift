import SwiftUI

/// Spacing, type and semantic colors shared by all feature views.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32

    /// Width of the parameter column on the left of Reception and Transmission.
    static let parameterColumn: CGFloat = 214
    /// Outer margin of the window content.
    static let windowMargin: CGFloat = 20
}

enum Radius {
    static let key: CGFloat = 9
    static let tile: CGFloat = 14
    static let panel: CGFloat = 18
}

extension Font {
    static let letterCard = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let keySign = Font.system(size: 19, weight: .medium, design: .rounded)
    static let decodedText = Font.system(size: 52, weight: .semibold)
    static let radiogram = Font.system(size: 28, weight: .heavy)
    /// Uppercase captions of the parameter column (УРОК, СКОРОСТЬ ЗНАКА…).
    static let parameterLabel = Font.caption.weight(.semibold)
}

/// Semantic signal colors. Dot / dash / too-long follow the released tape legend
/// (green, pink, red); correct / wrong follow the released answer feedback.
enum SignalPalette {
    static let dot = Color.green
    /// Light pink of the released tape, distinct from the red too-long mark.
    static let dash = Color(red: 1.0, green: 0.47, blue: 0.78)
    static let tooLong = Color.red
    static let correct = Color.green
    static let wrong = Color.red
    static let collision = Color.red
    static let start = Color.green
    static let stop = Color.red
    /// Cyan of the released accent glow (#00d2ff): cursor glow, ambient light.
    static let glow = Color(red: 0, green: 0.82, blue: 1)
}

/// A readable, opaque content surface (lesson header, keyboard, text panel).
/// Liquid Glass is reserved for controls: toolbar, mode tabs, Start/Stop.
struct ContentSurface: ViewModifier {
    var radius: CGFloat = Radius.panel

    @Environment(\.colorScheme) private var colorScheme

    /// Dark: a faint fill over the translucent window. Light: a white panel with
    /// a hairline and a very soft shadow on the grey window, as Apple's light
    /// apps do — glass controls on it read by their rims and shadows.
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .background(.fill.quinary, in: .rect(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(.separator.opacity(0.7), lineWidth: 0.5)
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    func contentSurface(radius: CGFloat = Radius.panel) -> some View {
        modifier(ContentSurface(radius: radius))
    }
}

extension Duration {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension EnvironmentValues {
    /// Growth of the work area with the window: 1 at 1000 × 700 pt, up to 2.
    /// Cards, keys, the lesson header, the tape and the radiogram scale with it;
    /// system controls keep their native size.
    @Entry var uiScale: CGFloat = 1
}

extension CGFloat {
    /// Controls (tabs, parameter column) grow less than the work area.
    var controlScale: CGFloat { Swift.min(self, 1.5) }
}

enum UIScale {
    static func forWindow(_ size: CGSize) -> CGFloat {
        let scale = min(size.width / 1000, size.height / 700)
        return min(2, max(1, (scale * 20).rounded() / 20))
    }
}

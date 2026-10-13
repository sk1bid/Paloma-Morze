import SwiftUI

/// Draws dots and dashes as shapes instead of punctuation characters.
/// `pulse` highlights the element currently sounding (engine `PULSE` events).
struct MorsePatternView: View {
    var patterns: [String]
    var unit: CGFloat = 8
    var pulse: Pulse = .none
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: unit * 1.5) {
            ForEach(Array(patterns.enumerated()), id: \.offset) { _, pattern in
                HStack(spacing: unit * 0.6) {
                    ForEach(Array(pattern.enumerated()), id: \.offset) { _, element in
                        Capsule()
                            .fill(fill(for: element))
                            .frame(width: element == "-" ? unit * 3 : unit, height: unit)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Self.spokenPattern(patterns))
    }

    private func fill(for element: Character) -> Color {
        switch (pulse, element) {
        case (.dot, "."), (.dash, "-"): tint
        case (.none, _): tint.opacity(0.85)
        default: tint.opacity(0.35)
        }
    }

    static func spokenPattern(_ patterns: [String]) -> String {
        patterns
            .map { $0.map { $0 == "-" ? "тире" : "точка" }.joined(separator: " ") }
            .joined(separator: ", ")
    }
}

#Preview("Pattern") {
    VStack(spacing: 20) {
        MorsePatternView(patterns: [".-.."])
        MorsePatternView(patterns: ["--.-", "-..", ".--"], unit: 6)
        MorsePatternView(patterns: [".-.."], unit: 12, pulse: .dash, tint: .accentColor)
    }
    .padding()
}

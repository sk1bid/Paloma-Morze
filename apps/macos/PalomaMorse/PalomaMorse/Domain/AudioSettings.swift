import Foundation

enum Waveform: String, CaseIterable, Identifiable, Codable {
    case sine
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sine: "Синус"
        case .square: "Меандр"
        }
    }
}

/// User-facing audio parameters (UI-SERVICE `AudioSettings`). Bounds follow
/// `ui/src/audioSettings.js` and audio-protocol-v1. Output is always clean.
struct AudioSettings: Equatable, Codable {
    static let toneClock = 11025.0
    static let speedRange = 30...150
    static let speedStep = 5
    static let tonePeriodRange = 8...38
    static let volumeRange = 0...100
    static let dashRatioRange = 2.0...4.5
    static let pauseFactorRange = 1.0...6.0
    static let halfStep = 0.5
    static let frontRange = 0...12

    var speed = 50
    /// Tone is chosen on the engine grid: frequency = 11025 / period.
    var tonePeriod = 23
    var volumePercent = 50
    var dashRatio = 3.0
    var pauseFactor = 3.0
    var front = 6
    var waveform: Waveform = .sine

    var toneHz: Double { Self.toneClock / Double(tonePeriod) }

    func normalized() -> AudioSettings {
        var copy = self
        copy.speed = Int((Double(speed.clamped(to: Self.speedRange)) / Double(Self.speedStep)).rounded()) * Self.speedStep
        copy.tonePeriod = tonePeriod.clamped(to: Self.tonePeriodRange)
        copy.volumePercent = volumePercent.clamped(to: Self.volumeRange)
        copy.dashRatio = dashRatio.clamped(to: Self.dashRatioRange)
        copy.pauseFactor = pauseFactor.clamped(to: Self.pauseFactorRange)
        copy.front = front.clamped(to: Self.frontRange)
        return copy
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

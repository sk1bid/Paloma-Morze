import SwiftUI

/// A small status line with a colored indicator, used in the sidebar footer,
/// inspectors and settings. Text always states the condition; color only supports it.
struct StatusIndicator: View {
    enum Tone {
        case positive, neutral, caution, critical

        var color: Color {
            switch self {
            case .positive: .green
            case .neutral: .secondary
            case .caution: .orange
            case .critical: .red
            }
        }
    }

    var title: String
    var systemImage: String
    var tone: Tone

    var body: some View {
        Label {
            Text(title)
                .lineLimit(2)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
        }
    }
}

extension AudioCoordinator {
    var engineIndicator: StatusIndicator {
        switch (adapterKind, engineState) {
        case (.demo, .ready):
            StatusIndicator(title: "Демо-движок · без звука", systemImage: "waveform.slash", tone: .caution)
        case (_, .ready(let rate)):
            StatusIndicator(title: "Звук готов · \(rate / 1000) кГц", systemImage: "waveform", tone: .positive)
        case (_, .starting):
            StatusIndicator(title: "Движок запускается…", systemImage: "hourglass", tone: .neutral)
        case (_, .failed(let reason)):
            StatusIndicator(title: "Ошибка движка: \(reason)", systemImage: "exclamationmark.triangle.fill", tone: .critical)
        case (_, .unavailable):
            StatusIndicator(title: "Движок не подключён", systemImage: "speaker.slash", tone: .caution)
        case (_, .notStarted), (_, .stopped):
            StatusIndicator(title: "Движок остановлен", systemImage: "speaker.slash", tone: .neutral)
        }
    }

    var keyIndicator: StatusIndicator {
        switch hardware {
        case .connected(let name):
            StatusIndicator(title: "Ключ: \(name)", systemImage: "cable.connector", tone: .positive)
        case .searching:
            StatusIndicator(title: "Поиск USB-ключа…", systemImage: "cable.connector", tone: .neutral)
        case .reconnecting:
            StatusIndicator(title: "Переподключение ключа…", systemImage: "cable.connector", tone: .caution)
        case .permissionDenied:
            StatusIndicator(title: "Нет доступа к ключу", systemImage: "lock.trianglebadge.exclamationmark", tone: .critical)
        case .disconnected:
            StatusIndicator(title: "USB-ключ не подключён", systemImage: "cable.connector.slash", tone: .neutral)
        case .unknown:
            StatusIndicator(title: "Ключ: нет данных", systemImage: "questionmark.circle", tone: .neutral)
        }
    }
}

/// Visible marker that the window shows demo or fixture data, not a live engine.
struct PreviewModeBadge: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "theatermasks")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(.orange.opacity(0.12), in: .capsule)
            .accessibilityLabel("Режим демонстрации: \(text)")
    }
}

/// Large figure + caption, used in result sheets and stats rows.
struct StatTile: View {
    var value: String
    var caption: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

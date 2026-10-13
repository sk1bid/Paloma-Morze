import SwiftUI

/// Session report of the released client: "Результаты сессии" with the signs
/// answered wrong (exercises 2–3), or "Текст контрольной" with the numbered
/// groups, five per row, to check the paper copy (exercise 4).
struct ReceptionResultsView: View {
    var results: ReceptionResults
    var catalog: MorseCatalog
    var alphabet: Alphabet
    var overrides: [String: MorseOverride] = [:]
    var onRepeat: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            VStack(spacing: Spacing.xxs) {
                Text(results.exercise == .exam ? "Текст контрольной" : "Результаты сессии")
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if results.exercise == .exam {
                examBody
            } else {
                gradedBody
            }

            HStack {
                Button("Ещё раз", action: onRepeat)
                Spacer()
                Button("Закрыть", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.l)
        .frame(width: results.exercise == .exam ? 600 : 440)
    }

    private var summary: String {
        var parts = ["Урок \(results.lessonID)", "\(results.exercise.rawValue). \(results.exercise.title)"]
        if results.exercise == .exam {
            parts.append("\(results.radiogramGroups.count) групп")
        } else {
            parts.append("\(results.total) знаков")
            parts.append("ошибок: \(results.wrongAnswers)")
            if let accuracy { parts.append(accuracy) }
        }
        parts.append(Duration.clock(results.duration))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var gradedBody: some View {
        if results.errors.isEmpty {
            Label("Ошибок нет", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SignalPalette.correct)
                .padding(.vertical, Spacing.s)
        } else {
            VStack(spacing: Spacing.s) {
                Text("Ошибки в следующих знаках:")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Spacing.xs)], spacing: Spacing.xs) {
                    ForEach(results.errors, id: \.self) { sign in
                        VStack(spacing: Spacing.xxs) {
                            Text(sign)
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignalPalette.wrong)
                            MorsePatternView(patterns: catalog.patterns(for: sign, overrides: overrides), unit: 5, tint: .secondary)
                            Text(catalog.mnemonic(for: sign, alphabet: alphabet, overrides: overrides))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(Spacing.xs)
                        .frame(maxWidth: .infinity)
                        .contentSurface(radius: Radius.tile)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var examBody: some View {
        ScrollView {
            Grid(horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
                ForEach(Array(stride(from: 0, to: results.radiogramGroups.count, by: 5)), id: \.self) { start in
                    GridRow {
                        ForEach(start..<min(start + 5, results.radiogramGroups.count), id: \.self) { index in
                            let group = results.radiogramGroups[index]
                            VStack(spacing: 2) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(group)
                                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.tint)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, Spacing.xs)
                            .frame(maxWidth: .infinity)
                            .contentSurface(radius: Radius.key)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Группа \(index + 1): \(group.map(String.init).joined(separator: " "))")
                        }
                    }
                }
            }
            .padding(2)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accuracy: String? {
        guard results.total > 0 else { return nil }
        let value = max(0, Double(results.total - results.wrongAnswers) / Double(results.total))
        return "точность " + value.formatted(.percent.precision(.fractionLength(0)))
    }
}

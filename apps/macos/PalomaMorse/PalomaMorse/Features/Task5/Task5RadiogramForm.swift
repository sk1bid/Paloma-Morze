import SwiftUI

/// Presentation only: the protocol continues to use the radiogram's wireText.
struct Task5RadiogramFormLayout {
    struct HeaderField: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
    static let columns = 5
    let radiogram: Task5Radiogram
    let requestedPart: Task5RadiogramRepair.Part?

    var headerLine: String { radiogram.header + " =" }
    var addressLine: String { radiogram.urgencyCode + " " + radiogram.address + " =" }
    var closingLine: String { radiogram.majorFormat == true ? "К" : radiogram.operatorGroup + " К" }
    var headerFields: [HeaderField] {
        let date = Task5Validator.tokens(radiogram.dateTime)
        var fields: [HeaderField] = []
        if radiogram.majorFormat == true { fields.append(.init(label: "Из", value: radiogram.originCallsign)) }
        fields += [
            .init(label: "№", value: radiogram.number),
            .init(label: "Групп", value: String(radiogram.declaredGroupCount)),
            .init(label: "День", value: date.first ?? ""),
            .init(label: "Время", value: date.dropFirst().joined(separator: " ")),
            .init(label: "Повтор №", value: radiogram.number + " =")
        ]
        return fields
    }
    var rows: [[Int]] {
        stride(from: 0, to: radiogram.groups.count, by: Self.columns).map { start in
            Array(start..<min(start + Self.columns, radiogram.groups.count))
        }
    }
    func isRequested(_ index: Int) -> Bool { requestedPart == .group(index) }
    var isHeaderRequested: Bool { requestedPart == .header }
    var shortReply: String? {
        switch requestedPart {
        case .group(let index)? where radiogram.groups.indices.contains(index): return radiogram.groups[index] + " К"
        case .header?: return Task5RepeatRequest.header.reply(for: radiogram)
        default: return nil
        }
    }
}

struct Task5RadiogramForm: View {
    let layout: Task5RadiogramFormLayout
    @Environment(\.uiScale) private var uiScale
    private let rule = Color(nsColor: .separatorColor)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            form
            ScrollView(.horizontal) { form.fixedSize(horizontal: true, vertical: false) }
        }
        .frame(maxWidth: 720 * uiScale, alignment: .leading)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(layout.headerFields) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.label).font(.system(size: 10 * uiScale)).foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(field.value).font(.system(size: 15 * uiScale, weight: .medium))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 7 * uiScale)
                        .frame(maxWidth: .infinity, minHeight: 42 * uiScale, alignment: .leading)
                        .overlay(alignment: .trailing) { Rectangle().fill(rule).frame(width: 0.5) }
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.5) }
                HStack(spacing: 8 * uiScale) {
                    Text("Адрес").font(.system(size: 10 * uiScale)).foregroundStyle(.secondary)
                    Text(layout.addressLine).font(.system(size: 16 * uiScale, weight: .medium))
                }
                .padding(.horizontal, 7 * uiScale)
                .frame(maxWidth: .infinity, minHeight: 30 * uiScale, alignment: .leading)
            }
            .background(layout.isHeaderRequested ? Color.accentColor.opacity(0.14) : .clear)
            .overlay {
                if layout.isHeaderRequested { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1) }
            }
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, indices in
                    GridRow {
                        ForEach(indices, id: \.self) { index in
                            Text(layout.radiogram.groups[index])
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity, minHeight: 24 * uiScale, alignment: .center)
                                .padding(.horizontal, 5 * uiScale)
                                .background(layout.isRequested(index) ? Color.accentColor.opacity(0.14) : .clear)
                                .overlay { Rectangle().strokeBorder(rule, lineWidth: 0.5) }
                                .overlay {
                                    if layout.isRequested(index) { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                                }
                                .accessibilityLabel("Группа \(index + 1): \(layout.radiogram.groups[index])" + (layout.isRequested(index) ? ". Запрошен повтор" : ""))
                                .id(index)
                        }
                        // Keep a five-column form for historical short variants.
                        ForEach(indices.count..<Task5RadiogramFormLayout.columns, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, minHeight: 24 * uiScale)
                                .overlay { Rectangle().strokeBorder(rule, lineWidth: 0.5) }
                        }
                    }
                }
            }
            Text(layout.closingLine)
                .padding(.horizontal, 7 * uiScale)
                .frame(maxWidth: .infinity, minHeight: 24 * uiScale, alignment: .leading)
        }
        .font(.system(size: 16 * uiScale, weight: .medium))
        .foregroundStyle(.primary)
        .background(.background)
        .overlay { Rectangle().strokeBorder(rule, lineWidth: 0.75) }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

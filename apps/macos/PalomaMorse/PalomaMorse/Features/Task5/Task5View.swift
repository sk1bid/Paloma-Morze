import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Task5View: View {
    @Bindable var session: Task5Session
    @Binding var parametersCollapsed: Bool
    @State private var showsCallsignEditor = false
    @State private var fileError: String?
    @State private var fileErrorTitle = "Не удалось сохранить"
    @FocusState private var keyFocused: Bool
    @Environment(\.uiScale) private var uiScale
    @Environment(\.openWindow) private var openWindow

    init(session: Task5Session, parametersCollapsed: Binding<Bool> = .constant(false)) {
        self.session = session
        _parametersCollapsed = parametersCollapsed
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            controls
            VStack(spacing: Spacing.s) {
                RhythmTape(rhythm: session.rhythm, label: nil)
                    .frame(height: 104 * uiScale)
                VStack(spacing: 0) {
                    statusLine
                    if session.isSessionActive {
                        let notice = session.errorMessage ?? session.correctionNotice
                        Label(notice ?? " ", systemImage: session.errorMessage == nil ? "arrow.counterclockwise" : "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 36 * uiScale.controlScale, alignment: .center)
                            .padding(.horizontal, Spacing.m)
                            .opacity(notice == nil ? 0 : 1)
                            .accessibilityHidden(notice == nil)
                            .help(notice ?? "")
                            .accessibilityElement(children: .combine)
                    }
                    workspace
                }
                .frame(minHeight: 300 * uiScale,
                    maxHeight: session.outgoingRadiogram == nil ? 300 * uiScale : .infinity)
                .contentSurface()
                if session.outgoingRadiogram == nil { Spacer(minLength: 0) }
                workspaceFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if session.variant == nil { session.generate() } }
        .onDisappear {
            session.releaseKey()
            if session.isDeveloperReview { session.developerFreeze() }
        }
        .onChange(of: session.currentStep?.id) { _, _ in
            keyFocused = session.currentStep?.direction == .transmit
        }
        .onChange(of: session.inputText) { _, _ in session.saveDraft() }
        .onChange(of: session.receptionDraft) { _, _ in session.saveDraft() }
        .focusedSceneValue(\.task5FileActions, Task5FileActions(
            open: importTraining, save: export,
            canOpen: !session.isDeveloperReview && !session.isSessionActive,
            canSave: !session.isDeveloperReview && !session.isSessionActive && !isIdle && session.variant != nil))
        .sheet(isPresented: $showsCallsignEditor) {
            Task5CallsignEditor(session: session, ownCallsign: ownCallsignForEditing, botCallsign: botCallsignForEditing)
        }
        .alert(fileErrorTitle, isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("ОК", role: .cancel) { fileError = nil }
        } message: { Text(fileError ?? "") }
    }

    private var controls: some View {
        ParameterColumn(isCollapsed: parametersCollapsed) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    optionsForm.disabled(session.isSessionActive)
                    Divider().padding(.vertical, 2)
                    ParameterGroup(title: "Позывные") {
                        ParameterActionButton(title: "Вы · \(session.variant?.ownCallsign ?? "—")", titleColor: .accentColor) {
                            showsCallsignEditor = true
                        }
                        ParameterActionButton(title: "Бот · \(session.variant?.botCallsign ?? "—")") {
                            showsCallsignEditor = true
                        }
                    }
                    .disabled(session.isSessionActive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } rail: {
            if session.isSessionActive {
                RailValue(caption: "БОТ", value: String(session.configuration.botSpeed), title: "Скорость бота")
            } else {
                RailValue(caption: "БОТ", value: String(session.configuration.botSpeed), title: "Скорость бота")
                RailValue(caption: "ГРУПП", value: String(session.configuration.length.transmittedGroups), title: "Передать групп")
            }
        } footer: {
            if session.isSessionActive {
                ParameterActionButton(title: isPaused ? "Продолжить" : "Пауза") {
                    isPaused ? session.resume() : session.pause()
                }
            }
            StartStopButton(isRunning: session.isSessionActive,
                            disabledReason: session.startBlockReason,
                            runningHelp: "Остановить тренировку") {
                session.isSessionActive ? session.stop() : session.startRadioExchange()
            }
        }
    }

    private var optionsForm: some View {
        Group {
            ParameterGroup(title: "Ваша станция") {
                ParameterActionButton(title: session.configuration.role.title) {
                    session.configuration.role = session.configuration.role.counterpart
                }
                .accessibilityHint("Переключить главную и подчинённую станцию")
            }
            ParameterGroup(title: "Текст радиограммы") {
                ParameterActionButton(title: (session.configuration.radiogramCharset ?? .letters).title) {
                    session.configuration.radiogramCharset = (session.configuration.radiogramCharset ?? .letters) == .letters ? .digits : .letters
                }
            }
            ParameterGroup(title: "Передать групп") {
                ValueStepper("Чистых групп на передачу каждого участника",
                             value: Binding(get: { session.configuration.length.transmittedGroups },
                                            set: { session.configuration.length = $0 == 30 ? .thirty : .full }),
                             in: 30...60, step: 30)
            }
            Divider().padding(.vertical, 2)
            ParameterGroup(title: "Скорость бота") {
                ValueStepper("Скорость бота в знаках в минуту", value: $session.configuration.botSpeed,
                             in: AudioSettings.speedRange, step: AudioSettings.speedStep)
            }
            ParameterGroup(title: "Приём") {
                ParameterActionButton(title: session.configuration.receptionMode == .typed ? "Ввод" : "Бумага") {
                    session.configuration.receptionMode = session.configuration.receptionMode == .typed ? .paper : .typed
                }
                .accessibilityHint("Переключить ввод в приложении и приём на бумаге")
            }
        }
    }

    private var ownCallsignForEditing: String {
        session.configuration.ownCallsign.isEmpty ? (session.variant?.ownCallsign ?? "") : session.configuration.ownCallsign
    }
    private var botCallsignForEditing: String {
        session.configuration.botCallsign.isEmpty ? (session.variant?.botCallsign ?? "") : session.configuration.botCallsign
    }

    private var statusLine: some View {
        HStack {
            if session.isSessionActive {
                Text(botStatus)
                Spacer()
                Text(Duration.clock(Double(session.elapsedSeconds))).monospacedDigit()
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.m)
        .padding(.top, session.isSessionActive ? Spacing.s : 0)
    }

    private var workspaceFooter: some View {
        HStack(spacing: Spacing.s) {
            RhythmLegend()
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .contentSurface(radius: 12)
            Spacer(minLength: Spacing.s)
            Button("Подсказка", systemImage: "questionmark.circle") { openWindow(id: "task5-guide") }
                .buttonStyle(.glass)
            if session.isSessionActive { keyButton }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var workspace: some View {
        if session.isSessionActive {
            activeWorkspace
        } else if !isIdle {
            resultWorkspace
        } else {
            VStack(spacing: Spacing.s) {
                (Text("Нажмите ").foregroundStyle(.secondary) + Text("Старт").foregroundStyle(Color.accentColor))
                    .font(.system(size: 42 * uiScale, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let error = session.errorMessage {
                    Text(error).font(.body).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activeWorkspace: some View {
        Group {
            if session.currentStep?.kind == .receive && session.receptionReceipt != nil {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if session.configuration.receptionMode == .typed {
                        TextEditor(text: $session.receptionDraft)
                            .font(.system(size: 22 * uiScale, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Запись приёма")
                            .disabled(isPaused)
                    } else {
                        Text("Приём на бумаге")
                            .font(.system(size: 32 * uiScale, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !session.inputText.isEmpty {
                        Text(session.inputText)
                            .font(.system(size: 18 * uiScale, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Task5CodeGuidance(outgoing: session.preparedServiceTransmission,
                        meanings: session.displayedCodeMeanings)
                }
                .padding(Spacing.m)
            } else if let radiogram = session.outgoingRadiogram {
                let layout = Task5RadiogramFormLayout(radiogram: radiogram, requestedPart: session.radiogramRepair?.part)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let reply = layout.shortReply {
                        Text(reply)
                            .font(.system(size: 18 * uiScale, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .textSelection(.enabled)
                            .padding(.horizontal, Spacing.m)
                            .accessibilityLabel("Ответ на запрошенный повтор: \(reply)")
                    }
                ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        Task5RadiogramForm(layout: layout)
                        if !session.inputText.isEmpty {
                            Text(session.inputText)
                                .font(.system(size: 22 * uiScale, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
                }
                .onChange(of: session.radiogramRepair?.part) { _, part in
                    if case .group(let index)? = part { scroll.scrollTo(index, anchor: .center) }
                }
                }
                }
            } else {
                ScrollView {
                    VStack(spacing: Spacing.s) {
                    Text(serviceTransmissionText)
                        .font(.system(size: 42 * uiScale, weight: .semibold))
                        .foregroundStyle(session.inputText.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 180 * uiScale)
                        .padding(.horizontal, Spacing.l)
                    Task5CodeGuidance(outgoing: session.preparedServiceTransmission,
                        meanings: session.displayedCodeMeanings)
                    }
                }
            }
        }
    }

    private var serviceTransmissionText: String {
        if session.currentStep?.kind == .pause {
            if session.isAuthenticationWait { return "Ожидание ответа" }
            let seconds = session.pauseRemainingSeconds
            return "Ожидание \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        if !session.inputText.isEmpty { return session.inputText }
        if !session.lastTransmissionText.isEmpty { return session.lastTransmissionText }
        if session.isWaitingForBot { return "Ожидание ответа" }
        return session.status == .playing ? "Приём" : "Передача"
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = session.errorMessage {
            Text(error).font(.body).foregroundStyle(.orange)
        } else if let result = session.lastCheckFeedback {
            Text(result.text)
                .font(.body.weight(.medium))
                .foregroundStyle(result.isCorrect ? SignalPalette.correct : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let error = session.storageError {
            Text("Не сохранено: \(error)").font(.body).foregroundStyle(.orange)
        }
    }

    private var keyButton: some View {
        HoldToKeyButton(isDown: session.isKeyDown, isPaused: !session.canSubmit && !session.isKeyDown,
                        keyLabel: session.transmissionKeyLabel) {
            keyFocused = true
            session.keyDown(from: .pointer)
        } onRelease: {
            session.keyUp(from: .pointer)
        }
        .focusable()
        .focused($keyFocused)
    }

    private var resultWorkspace: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(resultTitle).font(.title2.weight(.medium))
            Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xs) {
                resultRow("Время", Duration.clock(Double(session.elapsedSeconds)))
                resultRow("Шаги", "\(session.completedSteps) / \(session.variant?.steps.count ?? 0)")
                resultRow("Передано групп", "\(session.completedGroups(in: .transmit)) / \(session.totalGroups(in: .transmit))")
                resultRow("Принято без ошибок", session.configuration.receptionMode == .paper ? "Не проверено" : "\(session.completedGroups(in: .receive)) / \(session.totalGroups(in: .receive))")
                resultRow("Неудачные проверки", String(session.attempts.filter { !$0.correct }.count))
                resultRow("Повторы", String(session.repeatCount))
                resultRow("Подсказки", String(session.hintCount))
                resultRow("Готовые служебные фразы", String(session.automaticGuidanceCount))
            }
            if session.variant?.configuration.receptionMode == .paper {
                Text(session.usesRadioFlow ? "Приём на бумаге · точность не проверена" : "Приём на бумаге · самопроверка").font(.body).foregroundStyle(.secondary)
            }
            if session.variant?.configuration.rehearsal == true {
                if let comparison = session.timeComparison { Text(comparison).font(.body).foregroundStyle(.secondary) }
            }
            feedback
            ViewThatFits(in: .horizontal) {
                HStack { resultActions }
                VStack(alignment: .leading, spacing: Spacing.s) { resultActions }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var resultActions: some View {
        Button("Повторить этот вариант") { session.restartSameVariant() }.buttonStyle(.borderedProminent)
        Button("Новая тренировка") { session.generateNewVariant() }
        Button("Сохранить результат…", action: export).disabled(session.isDeveloperReview)
    }

    private func resultRow(_ title: String, _ value: String) -> some View {
        GridRow { Text(title).foregroundStyle(.secondary); Text(value).monospacedDigit() }.font(.body)
    }

    private var isIdle: Bool { session.status == .idle }
    private var isPaused: Bool { session.status == .paused }
    private var botStatus: String {
        return switch session.status {
        case .playing: session.isWaitingForBot ? "Ожидание ответа…" : "Бот передаёт…"
        case .running: "В эфире"
        case .paused: "Пауза"
        default: "Бот"
        }
    }
    private var resultTitle: String {
        return switch session.status {
        case .completed: "Тренировка завершена"
        case .interrupted: "Тренировка прервана"
        default: "Тренировка остановлена"
        }
    }

    private func export() {
        do {
            let data = try session.exportData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Задача-5-\(session.variant?.seed ?? 0).json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch { fileErrorTitle = "Не удалось сохранить"; fileError = error.localizedDescription }
    }
    private func importTraining() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try session.restore(data: Data(contentsOf: url))
            try session.useRadioFlowForRestoredSession()
        }
        catch { fileErrorTitle = "Не удалось открыть"; fileError = error.localizedDescription }
    }
}

struct Task5CodeGuidance: View {
    let outgoing: String?
    let meanings: [Task5CodeMeaning]
    var body: some View {
        VStack(spacing: Spacing.s) {
            if let outgoing {
                Text(outgoing).font(.title2.monospaced()).textSelection(.enabled)
                    .accessibilityLabel("Готовая передача: \(outgoing)")
            }
            if !meanings.isEmpty {
                ScrollView {
                    Text(meanings.map(\.display).joined(separator: "\n"))
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .frame(maxHeight: 80)
            }
        }
    }
}

struct Task5DeveloperControls: View {
    @Bindable var session: Task5Session

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("DEV · Задача №5").font(.caption.weight(.semibold))
                Picker("Этап", selection: Binding(get: { session.currentStep?.id ?? "" }, set: { id in
                    guard let index = session.variant?.steps.firstIndex(where: { $0.id == id }) else { return }
                    session.developerInspectStage(to: index)
                })) {
                    ForEach(session.developerStages) { step in
                        Text(step.title + " · " + step.id).tag(step.id)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200, maxWidth: .infinity)
                .accessibilityLabel("DEV: перейти к этапу")
                Toggle("Звук", isOn: $session.developerAudioEnabled).toggleStyle(.checkbox)
            }
            HStack(spacing: Spacing.s) {
                Button("Назад") { session.developerBack() }
                Button("Далее") { session.developerNext() }
                Button("Запустить этап") { session.developerRunStage() }
                if session.isDeveloperAutoPreview {
                    Button("Стоп") { session.developerFreeze() }
                } else {
                    Button("Автопросмотр") { session.developerStartPreview() }
                }
                Button("Ошибка группы") { session.developerShowGroupError() }
                Spacer(minLength: 0)
                Text("Без сохранения").font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!session.hasSidetone)
        }
        .controlSize(.small)
        .padding(Spacing.s)
        .contentSurface()
        .onChange(of: session.configuration.role) { _, _ in session.developerInspectStage(to: session.currentStepIndex) }
        .onChange(of: session.developerAudioEnabled) { _, _ in session.developerInspectStage(to: session.currentStepIndex) }
    }
}

/// A separate controller for the existing isolated session. Closing this window
/// only stops automatic navigation; audible playback belongs to the main view.
struct Task5DeveloperController: View {
    let session: Task5Session
    var body: some View {
        Group {
            if session.isDeveloperReview {
                Task5DeveloperControls(session: session)
                    .padding(Spacing.m)
            } else {
                ContentUnavailableView("DEV-просмотр не включён", systemImage: "wrench.and.screwdriver")
            }
        }
        .frame(minWidth: 680, minHeight: 112)
        .onDisappear { session.developerControllerClosed() }
    }
}

private struct Task5CallsignEditor: View {
    @Bindable var session: Task5Session
    @State var ownCallsign: String
    @State var botCallsign: String
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Позывные").font(.headline)
            Form {
                TextField("Свой позывной", text: $ownCallsign)
                TextField("Позывной бота", text: $botCallsign)
            }
            .formStyle(.columns)
            if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    let oldConfiguration = session.configuration
                    session.configuration.ownCallsign = ownCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    session.configuration.botCallsign = botCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    session.generate()
                    if session.variant != nil { dismiss() }
                    else {
                        let validationError = session.errorMessage
                        session.configuration = oldConfiguration
                        session.generate()
                        errorMessage = validationError
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.body)
        .controlSize(.regular)
        .padding(Spacing.l)
        .frame(width: 430)
    }
}


/// A separate reference window; it never exposes an unheard incoming text.
struct Task5GuideView: View {
    @Bindable var session: Task5Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Порядок работы").font(.title2.weight(.semibold))
                Text("Примите дежурство и документы, получите разрешение на передачу и проверьте назначенную рабочую частоту до старта. Бот отвечает на передачу ключом; завершение определяется формой сообщения, без кнопки проверки. Доклад и сдача дежурства выполняются самостоятельно.")
                Text("Если ошиблись при передаче, передайте восемь точек подряд без межбуквенных пауз. В радиограмме перебой отменяет текущую или последнюю группу, сохраняя предыдущие группы и разделы. В служебной фразе отменяется сообщение целиком. Более длинная серия точек также принимается.")
                if session.variant?.profileID == "task5.photos.v8.final-k" {
                    Text("В этой учебной версии каждое отдельное сообщение заканчивается К: после вопроса, кодов паролирования, каждой части сигнала и при завершении связи. Пауза между частями сигнала остаётся 10 секунд.")
                }
                Text("Связь → ЩСА → паролирование → одна исходящая и одна входящая радиограмма → два сигнала с отдельными докладами → ЩБЕ / ОК ЩБЕ.")
                if ["task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(session.variant?.profileID ?? "") {
                    Text("При паролировании: ОК АС <минуты> К. После команды бота дождитесь ответа: обычно около минуты. Ваша команда не блокирует передачу. Значения принятых З-кодов появляются после вашей верной квитанции ОК АС <минуты> К.")
                }
                Text("Передача радиограммы: ЩТЦ <код категории> К → ЩРЖ К → свой позывной, номер, количество, дата и время, повтор номера = категория и адрес = текст К → Р <номер> К. Объём — 30 или 60 групп текста; поле количества также включает две адресные группы. Между заголовком, адресом и текстом подтверждений нет.")
                if let callsign = session.variant?.signals.first?.networkCallsign {
                    Text("Позывной сети для сигналов: \(callsign). ЬЬЬ — дважды, позывной — дважды, сигнал — дважды; пауза 10 секунд; полный повтор с окончанием К. Квитанция по учебной памятке: свой позывной Р <сигнал> К. После каждого сигнала — самостоятельный доклад.")
                }
                Divider()
                if let step = session.currentStep, session.isSessionActive {
                    Text(step.title).font(.headline)
                    if let variant = session.variant,
                       let format = Task5Validator.qualityFormat(for: step, variant: variant) {
                        Text("Выберите свою оценку от 1 до 5. Число 3 в примере майора — пример оценки.")
                        Text(format).font(.body.monospaced()).textSelection(.enabled)
                    } else {
                        if Task5Validator.isWaitCommand(step) {
                            Text(step.direction == .transmit ? "Передайте ОК АС <минуты> К. После квитанции можно сразу продолжать передачу." : "Примите ОК АС 1 К и дождитесь ответа бота.")
                        } else if session.isAuthenticationWait {
                            Text("Дождитесь ответа бота.")
                        } else if session.preparedServiceTransmission != nil {
                            Text("Передайте готовое сообщение ключом и завершите К.")
                        } else { Text(step.instruction) }
                    }
                    if let receipt = session.receptionReceipt {
                        Text("Запишите принятое. При необходимости передайте РПТ К. После приёма передайте квитанцию:")
                        Text(receipt.expectedMessages.first ?? "").font(.body.monospaced()).textSelection(.enabled)
                    } else if step.direction == .transmit,
                              session.variant.flatMap({ Task5Validator.qualityFormat(for: step, variant: $0) }) == nil {
                        Text(step.expectedMessages.first ?? "").font(.body.monospaced()).textSelection(.enabled)
                    }
                    if let error = session.errorMessage { Text(error).foregroundStyle(.orange) }
                    if session.canReveal && step.direction == .receive {
                        Button("Открыть эталон для сверки") { session.revealReference() }
                    }
                    if let reference = session.revealedReference {
                        Text(reference).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
                Divider()
                Text("Повтор: РПТ К. Медленнее: ЩРС К. Быстрее: ЩРЩ К. После ошибочного сообщения бот запрашивает повтор; следующую передачу начинайте заново.")
                Text("Во время приёма запись и передача ключом разделены. Для клавиатурного ключа переведите фокус из записи на «Ключ». Запись проверяется при отправке квитанции; ошибки доступны в результате. Бумажный приём автоматически не оценивается.")
                    .foregroundStyle(.secondary)
                Text("Паролирование: ответ = |50 − принятое число|; 17 → 33, 73 → 23, 50 → 00. Программа готовит З-коды для передачи ключом. Значения принятых кодов открываются после верной квитанции ОК АС <минуты> К. Такую квитанцию можно передать и после предложения радиограммы; она не заменяет готовность или квитанцию приёма. Этот режим не проверяет физическую подготовку рабочего места и не выставляет нормативную оценку.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .onAppear { session.isGuideVisible = true; session.recordGuideUse() }
        .onDisappear { session.isGuideVisible = false }
        .onChange(of: session.currentStep?.id) { _, _ in session.recordGuideUse() }
        .frame(minWidth: 420, minHeight: 420)
    }
}

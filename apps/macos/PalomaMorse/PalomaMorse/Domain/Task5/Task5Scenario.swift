import Foundation

/// Stable generator: a seed replays material without depending on Swift's Hasher.
private struct Task5Random {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ count: Int) -> Int { Int(next() % UInt64(count)) }
    mutating func pick<T>(_ values: [T]) -> T { values[int(values.count)] }
    mutating func shuffled<T>(_ values: [T]) -> [T] {
        var result = values
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, through: 1, by: -1) { result.swapAt(i, int(i + 1)) }
        return result
    }
    mutating func digits(_ count: Int) -> String { (0..<count).map { _ in String(int(10)) }.joined() }
}

enum Task5Scenario {
    static func authenticationAnswer(to challenge: Int) -> Int { abs(50 - challenge) }

    enum GenerationError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
    }

    static func generate(configuration: Task5Configuration, seed: UInt64, reference: Task5Reference, catalog: MorseCatalog, profileID: String = "task5.photos.v8.final-k") throws -> Task5Variant {
        guard ["task5.photos.v1.cell-lookup", "task5.photos.v2.checked-receipts", "task5.photos.v3.major-quality", "task5.photos.v4.major-authentication", "task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(profileID) else {
            throw GenerationError.invalid("Неизвестный профиль тренировки")
        }
        let finalK = profileID == "task5.photos.v8.final-k"
        let timedWait = profileID == "task5.photos.v7.timed-wait" || finalK
        let updatedRadioData = profileID == "task5.photos.v6.callsigns-tdr" || timedWait
        let major = profileID == "task5.photos.v5.major-complete" || updatedRadioData
        let isMain = configuration.role == .main
        let checkedReception = profileID != "task5.photos.v1.cell-lookup"
        guard (30...150).contains(configuration.botSpeed), (30...150).contains(configuration.keySpeed) else {
            throw GenerationError.invalid("Скорость: от 30 до 150 знаков/мин")
        }
        guard reference.cells.count == 100,
              Set(reference.cells.map(\.number)).count == 100,
              reference.cells.allSatisfy({ (0...9).contains($0.row) && (0...9).contains($0.column) }) else {
            throw GenerationError.invalid("Нужна полная таблица ТДР 00–99")
        }
        var random = Task5Random(state: seed)
        let letters = Array("АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ").map(String.init)
        func normal(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        func validCall(_ s: String) -> Bool {
            (3...8).contains(s.count) && s.allSatisfy { char in
                char.isLetter || char.isNumber
            } && s.allSatisfy { !catalog.patterns(for: String($0)).isEmpty }
        }
        func signature(_ s: String) -> [String] { s.flatMap { $0 == "0" ? ["-----"] : catalog.patterns(for: String($0)) } }
        var own = normal(configuration.ownCallsign)
        var bot = normal(configuration.botCallsign)
        if !own.isEmpty && !validCall(own) { throw GenerationError.invalid("Свой позывной: 3–8 знаков азбуки Морзе") }
        if !bot.isEmpty && !validCall(bot) { throw GenerationError.invalid("Позывной бота: 3–8 знаков азбуки Морзе") }
        if updatedRadioData {
            for call in [own, bot] where !call.isEmpty {
                guard call.filter({ "0123456789".contains($0) }).count == 1 else {
                    throw GenerationError.invalid("В позывном должна быть ровно одна цифра 0–9")
                }
            }
        }
        func generatedCall() -> String {
            var signs = (0..<4).map { _ in random.pick(letters) }
            if updatedRadioData { signs[random.int(4)] = random.digits(1) }
            return signs.joined()
        }
        if own.isEmpty {
            repeat { own = generatedCall() } while !bot.isEmpty && signature(own) == signature(bot)
        }
        if bot.isEmpty {
            repeat { bot = generatedCall() } while signature(own) == signature(bot)
        }
        guard signature(own) != signature(bot) else { throw GenerationError.invalid("Позывные должны различаться в Морзе") }

        func axis(_ random: inout Task5Random, excludeZe: Bool = false) -> [String] {
            let shuffled = random.shuffled(excludeZe ? letters.filter { $0 != "З" } : letters)
            return (0..<10).map { shuffled[$0 * 2] + shuffled[$0 * 2 + 1] }
        }
        let tdr = Task5TDR(cells: reference.cells.sorted { $0.number < $1.number }, rowKeys: axis(&random, excludeZe: updatedRadioData), columnKeys: axis(&random))
        let radio = Task5RadioData(
            mainFrequency: String(4000 + random.int(2000)),
            reserveFrequency: String(6500 + random.int(1500)),
            networkNumber: random.digits(3), operatorName: "Радист")
        let dateTime = String(format: "%02d %02d %02d", 1 + random.int(28), random.int(24), random.int(60))
        let categories = [("monolith", "Монолит"), ("air", "Воздух"), ("rocket", "Ракета"), ("plane", "Самолёт")]
        var radiograms: [Task5Radiogram] = []
        var usedNumbers: Set<String> = []
        for index in 0..<(major ? 2 : 4) {
            let direction: Task5Direction = (index % 2 == 0) == isMain ? .transmit : .receive
            let charset: Task5Charset = major ? (configuration.radiogramCharset ?? .letters) : (index < 2 ? .letters : .digits)
            var number: String
            repeat { number = random.digits(3) } while usedNumbers.contains(number)
            usedNumbers.insert(number)
            let category = random.pick(categories)
            let codes = tdr.codes(forExpressionID: category.0)
            guard !codes.isEmpty else { throw GenerationError.invalid("В ТДР нет категории \(category.1)") }
            let groups = (0..<(major ? configuration.length.transmittedGroups : configuration.length.groupsPerRadiogram)).map { _ in
                charset == .digits ? random.digits(5) : (0..<5).map { _ in random.pick(letters) }.joined()
            }
            let day = String(dateTime.prefix(2))
            let operatorGroup = day + String(format: "%03d", groups.count + 1)
            radiograms.append(Task5Radiogram(id: "rg-\(index)", number: number, charset: charset, direction: direction,
                groups: groups, urgency: category.1, urgencyCode: random.pick(codes), address: random.digits(6) + " " + random.digits(3), operatorGroup: operatorGroup,
                dateTime: dateTime, originCallsign: direction == .transmit ? own : bot, recipientCallsign: direction == .transmit ? bot : own, majorFormat: major ? true : nil))
        }
        let signalDirections: [Task5Direction] = isMain ? [.transmit, .receive] : [.receive, .transmit]
        var networkCallsign: String? = nil
        if major {
            repeat { networkCallsign = generatedCall() }
            while updatedRadioData && (signature(networkCallsign!) == signature(own) || signature(networkCallsign!) == signature(bot))
        }
        let signals = signalDirections.enumerated().map { index, direction in
            Task5Signal(id: "signal-\(index)", direction: direction, group: random.digits(5), originCallsign: direction == .transmit ? own : bot,
                        recipientCallsign: direction == .transmit ? bot : own, networkCallsign: networkCallsign, terminatesFirstPart: finalK ? true : nil)
        }

        let passwordCells = tdr.cells(forExpressionID: "password")
        guard passwordCells.count >= 2 else { throw GenerationError.invalid("В ТДР нет ячеек пароля") }
        let peerChallenge = random.pick(passwordCells)
        let ownChallenge = random.pick(passwordCells)
        let peerAnswer = random.pick(tdr.codes(for: peerChallenge))
        let ownAnswer = random.pick(tdr.codes(for: ownChallenge))

        var steps: [Task5Step] = [
            .init(id: "duty", title: "Дежурство", instruction: "Примите дежурство.", kind: .administrative),
            .init(id: "setup", title: "Подготовка", instruction: "Подготовьте рабочее место.", kind: .administrative),
            .init(id: "call", title: "Вызов", instruction: "Вызовите корреспондента.", kind: .transmit, expectedMessages: ["\(bot) ДЕ \(own) К"], direction: .transmit),
            .init(id: "call-reply", title: "Ответ", instruction: "Примите ответ корреспондента.", kind: .listen, botMessage: "\(own) ДЕ \(bot) К", direction: .receive),
            .init(id: "quality", title: "Качество связи", instruction: "Запросите силу и разборчивость сигналов.", kind: .transmit, expectedMessages: ["ЩСА? ЩРК? К", "ЩСА ? ЩРК ? К"], direction: .transmit),
            .init(id: "quality-reply", title: "Оценка сигналов", instruction: "Примите оценку сигналов.", kind: checkedReception ? .receive : .listen, expectedMessages: checkedReception ? ["ЩСА 5 ЩРК 5 К"] : [], botMessage: "ЩСА 5 ЩРК 5 К", direction: .receive),
            .init(id: "auth-peer", title: "Пароль корреспондента", instruction: "Передайте учебный запрос: ПАРОЛЬ \(peerChallenge.number) К.", kind: .transmit, expectedMessages: ["ПАРОЛЬ \(peerChallenge.number) К"], direction: .transmit),
            .init(id: "auth-peer-reply", title: "Проверка пароля", instruction: "Примите код пароля.", kind: .receive,
                  expectedMessages: ["\(peerAnswer) К"], botMessage: "\(peerAnswer) К", direction: .receive, tdrExpressionID: "password", tdrCellNumber: peerChallenge.number),
            .init(id: "auth-self", title: "Встречный пароль", instruction: "Передайте ответ на пароль.", kind: .transmit,
                  expectedMessages: ["\(ownAnswer) К"], botMessage: "ПАРОЛЬ \(ownChallenge.number) К", direction: .transmit, tdrExpressionID: "password", tdrCellNumber: ownChallenge.number)
        ]
        if !isMain {
            steps = Array(steps.prefix(2)) + [
                .init(id: "call", title: "Вызов главной станции", instruction: "Примите вызов главной станции.", kind: .listen, botMessage: "\(own) ДЕ \(bot) К", direction: .receive),
                .init(id: "call-reply", title: "Ответ на вызов", instruction: "Ответьте главной станции.", kind: .transmit, expectedMessages: ["\(bot) ДЕ \(own) К"], direction: .transmit),
                .init(id: "quality", title: "Запрос качества связи", instruction: "Примите запрос силы и разборчивости.", kind: .listen, botMessage: "ЩСА? ЩРК? К", direction: .receive),
                .init(id: "quality-reply", title: "Оценка сигналов", instruction: "Передайте силу и разборчивость принятых сигналов по шкале 1–5.", kind: .transmit,
                      expectedMessages: (1...5).flatMap { strength in (1...5).map { readability in "ЩСА \(strength) ЩРК \(readability) К" } }, direction: .transmit),
                .init(id: "auth-self", title: "Запрос пароля", instruction: "Примите запрос и передайте ответ по ТДР.", kind: .transmit, expectedMessages: ["\(ownAnswer) К"], botMessage: "ПАРОЛЬ \(ownChallenge.number) К", direction: .transmit, tdrExpressionID: "password", tdrCellNumber: ownChallenge.number),
                .init(id: "auth-peer", title: "Встречный пароль", instruction: "Передайте учебный запрос: ПАРОЛЬ \(peerChallenge.number) К.", kind: .transmit, expectedMessages: ["ПАРОЛЬ \(peerChallenge.number) К"], direction: .transmit),
                .init(id: "auth-peer-reply", title: "Проверка пароля", instruction: "Примите код пароля главной станции.", kind: .receive, expectedMessages: ["\(peerAnswer) К"], botMessage: "\(peerAnswer) К", direction: .receive, tdrExpressionID: "password", tdrCellNumber: peerChallenge.number)
            ]
        }
        if ["task5.photos.v3.major-quality", "task5.photos.v4.major-authentication", "task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(profileID),
           let qualityIndex = steps.firstIndex(where: { $0.id == "quality" }) {
            // Only the clearly transcribed journal rows J06–J08. Other protocol
            // sections remain educational until their handwritten codes are resolved.
            let qualitySteps: [Task5Step] = isMain ? [
                .init(id: "quality", title: "Проверка силы сигналов", instruction: "Запросите силу сигналов: ЩСА?", kind: .transmit, expectedMessages: ["ЩСА?", "ЩСА ?"], direction: .transmit),
                .init(id: "quality-reply", title: "Оценка и встречный запрос", instruction: "Примите оценку и встречный запрос силы сигналов.", kind: .listen, botMessage: "ЩСА 3 К ЩСА?", direction: .receive),
                .init(id: "quality-report", title: "Ответ о силе сигналов", instruction: "Передайте оценку по примеру майора: ЩСА 3.", kind: .transmit, expectedMessages: ["ЩСА 3"], direction: .transmit)
            ] : [
                .init(id: "quality", title: "Запрос силы сигналов", instruction: "Примите запрос главной станции.", kind: .listen, botMessage: "ЩСА?", direction: .receive),
                .init(id: "quality-reply", title: "Оценка и встречный запрос", instruction: "Передайте оценку и встречный запрос по примеру: ЩСА 3 К ЩСА?", kind: .transmit, expectedMessages: ["ЩСА 3 К ЩСА?", "ЩСА 3 К ЩСА ?"], direction: .transmit),
                .init(id: "quality-report", title: "Оценка главной станции", instruction: "Примите ответ о силе сигналов.", kind: .listen, botMessage: "ЩСА 3", direction: .receive)
            ]
            steps.replaceSubrange(qualityIndex...(qualityIndex + 1), with: qualitySteps)
        }
        if major || profileID == "task5.photos.v4.major-authentication" {
            let firstNumber = random.int(100)
            let secondNumber = random.int(100)
            func number(_ value: Int) -> String { String(format: "%02d", value) }
            func encoded(_ rules: [String]) -> String {
                rules.map { rule in
                    if rule == "password" { return random.pick(tdr.codes(forExpressionID: "password")) }
                    if let cell = tdr.cells.first(where: { $0.number == rule }) { return random.pick(tdr.codes(for: cell)) }
                    return rule
                }.joined(separator: " ")
            }
            let requestRules = ["password", number(firstNumber)]
            let counterRules = ["password", number(authenticationAnswer(to: firstNumber)), number(secondNumber)]
            let finalRules = ["password", number(authenticationAnswer(to: secondNumber)), "К"]
            let request = encoded(requestRules)
            let counter = encoded(counterRules)
            let answer = encoded(finalRules)
            // The user's clarified classroom sequence; literal groups depend on this variant's TDR keys.
            let exchange: [(String, Bool, String, String, [String])] = [
                ("auth-peer", true, "Запрос пароля", request, requestRules),
                ("auth-request-echo", false, "Проверка принятого запроса", request + " Ц? К", requestRules + ["Ц?", "К"]),
                ("auth-request-confirm", true, "Подтверждение запроса", "Ц К", ["Ц", "К"]),
                ("auth-request-wait", false, "Запрос принят", "ОК АС", ["ОК", "АС"]),
                ("auth-counter", false, "Ответ и встречный запрос", counter, counterRules),
                ("auth-counter-echo", true, "Проверка ответа и встречного запроса", counter + " Ц? К", counterRules + ["Ц?", "К"]),
                ("auth-peer-reply", false, "Подтверждение встречного запроса", "Ц К", ["Ц", "К"]),
                ("auth-counter-wait", true, "Встречный запрос принят", "ОК АС", ["ОК", "АС"]),
                ("auth-self", true, "Ответ на встречный пароль", answer, finalRules)
            ]
            let authentication = exchange.flatMap { id, mainTransmits, title, message, rules in
                let transmits = mainTransmits == isMain
                let waits = timedWait && ["auth-request-wait", "auth-counter-wait"].contains(id)
                let minutes = 1 + Int((seed / (id == "auth-request-wait" ? 1 : 3)) % 2)
                let actualMessage = waits ? "ОК АС \(minutes) К" : message
                let step = Task5Step(id: id, title: title,
                    instruction: waits ? "Передайте ОК АС, время ожидания в минутах и К. Затем выдержите указанное время." : transmits ? "Передайте сообщение по ТДР. Ответное число — разность большего и меньшего из 50 и принятого числа." : "Примите сообщение корреспондента.",
                    kind: transmits ? .transmit : .listen, expectedMessages: [actualMessage],
                    botMessage: transmits ? nil : actualMessage, direction: transmits ? .transmit : .receive,
                    authenticationTokens: waits ? nil : rules)
                guard waits else { return [step] }
                return [step, Task5Step(id: id + "-pause", title: "Ожидание по АС",
                    instruction: "Выдержите переданное время ожидания. Обмен продолжится автоматически.",
                    kind: .pause, requiredPauseSeconds: Double(minutes * 60))]
            }
            if let first = steps.firstIndex(where: { $0.id.hasPrefix("auth-") }),
               let last = steps.lastIndex(where: { $0.id.hasPrefix("auth-") }) {
                steps.replaceSubrange(first...last, with: authentication)
            }
        }
        for rg in radiograms {
            let label = "\(rg.direction.title) · \(rg.charset.title.lowercased())"
            if rg.direction == .transmit {
                steps.append(.init(id: rg.id + "-offer", title: "Предложение радиограммы", instruction: "Предложите радиограмму: ЩТЦ, код категории, К.", kind: .transmit, expectedMessages: ["ЩТЦ \(rg.urgencyCode) К"], radiogramID: rg.id, direction: .transmit))
                steps.append(.init(id: rg.id + "-ready", title: "Готовность корреспондента", instruction: "Примите согласие на передачу.", kind: .listen, botMessage: "ЩРЖ К", direction: .receive))
                steps.append(.init(id: rg.id, title: label, instruction: "Передайте радиограмму по бланку.", kind: .transmit, expectedMessages: [rg.wireText], radiogramID: rg.id, direction: .transmit, bodyGroups: rg.groupCount))
                steps.append(.init(id: rg.id + "-receipt", title: "Квитанция радиограммы", instruction: "Примите квитанцию.", kind: checkedReception ? .receive : .listen, expectedMessages: checkedReception ? [rg.receipt] : [], botMessage: rg.receipt, radiogramID: rg.id, direction: .receive))
            } else {
                steps.append(.init(id: rg.id + "-offer", title: "Предложение радиограммы", instruction: "Примите предложение корреспондента.", kind: .listen, botMessage: "ЩТЦ \(rg.urgencyCode) К", direction: .receive))
                steps.append(.init(id: rg.id + "-ready", title: "Готовность к приёму", instruction: "Подтвердите готовность: ЩРЖ К.", kind: .transmit, expectedMessages: major ? ["ЩРЖ К"] : ["ЩРЖ К", "ЩОИ К"], direction: .transmit))
                steps.append(.init(id: rg.id, title: label, instruction: "Примите заголовок, адресную часть и группы.", kind: .receive, expectedMessages: [rg.wireText], botMessage: rg.wireText, radiogramID: rg.id, direction: .receive, bodyGroups: rg.groupCount))
                steps.append(.init(id: rg.id + "-receipt", title: "Квитанция радиограммы", instruction: "Подтвердите приём радиограммы.", kind: .receipt, expectedMessages: [rg.receipt], radiogramID: rg.id, direction: .transmit))
            }
        }
        for signal in signals {
            let tx = signal.direction == .transmit
            steps.append(.init(id: signal.id + "-first", title: tx ? "Передача сигнала" : "Приём сигнала", instruction: tx ? "Передайте первую часть сигнала." : "Примите первую часть сигнала.", kind: tx ? .signal : .listen, expectedMessages: tx ? [signal.firstPart] : [], botMessage: tx ? nil : signal.firstPart, direction: signal.direction))
            steps.append(.init(id: signal.id + "-pause", title: "Пауза", instruction: "Выдержите паузу между частями сигнала.", kind: .pause, direction: signal.direction, requiredPauseSeconds: Task5Signal.pauseSeconds))
            steps.append(.init(id: signal.id + "-second", title: "Вторая часть сигнала", instruction: tx ? "Повторите сигнал и завершите К." : "Запишите обе части сигнала.", kind: tx ? .signal : .receive, expectedMessages: [tx ? signal.secondPart : signal.wireText], botMessage: tx ? nil : signal.secondPart, direction: signal.direction))
            steps.append(.init(id: signal.id + "-receipt", title: "Квитанция сигнала", instruction: tx ? "Примите подтверждение сигнала." : "Подтвердите принятый сигнал.", kind: tx ? (checkedReception ? .receive : .listen) : .receipt, expectedMessages: tx && !checkedReception ? [] : [signal.receipt], botMessage: tx ? signal.receipt : nil, direction: tx ? .receive : .transmit))
            if major {
                steps.append(.init(id: signal.id + "-report", title: "Доклад по сигналу", instruction: "Доложите о \(tx ? "передаче" : "приёме") сигнала и внесите запись в аппаратный журнал.", kind: .administrative))
            }
        }
        steps += [
            .init(id: "report", title: "Доклад", instruction: "Оформите доклад о выполненном обмене.", kind: .administrative),
            .init(id: "close", title: "Окончание связи", instruction: isMain ? "Завершите связь: СК." : "Примите окончание связи главной станции. Ответ не требуется.", kind: isMain ? .transmit : .listen, expectedMessages: isMain ? ["СК", "СК К"] : [], botMessage: isMain ? nil : "СК", direction: isMain ? .transmit : .receive),
            .init(id: "journal", title: "Сдача дежурства", instruction: "Сдайте дежурство.", kind: .administrative)
        ]
        if major {
            steps.removeAll { $0.id == "report" }
            if let closeIndex = steps.firstIndex(where: { $0.id == "close" }) {
                steps.replaceSubrange(closeIndex...closeIndex, with: [
                    .init(id: "close", title: "Выключение по приказу", instruction: isMain ? "Передайте ЩБЕ — выключаюсь по приказу." : "Примите сообщение о выключении по приказу.", kind: isMain ? .transmit : .listen, expectedMessages: ["ЩБЕ"], botMessage: isMain ? nil : "ЩБЕ", direction: isMain ? .transmit : .receive),
                    .init(id: "close-reply", title: "Подтверждение окончания работы", instruction: isMain ? "Примите подтверждение ОК ЩБЕ." : "Подтвердите: ОК ЩБЕ.", kind: isMain ? .listen : .transmit, expectedMessages: ["ОК ЩБЕ"], botMessage: isMain ? "ОК ЩБЕ" : nil, direction: isMain ? .receive : .transmit)
                ])
            }
        }
        if finalK {
            steps = steps.map { original in
                var step = original
                step.expectedMessages = step.expectedMessages.map(terminated)
                step.botMessage = step.botMessage.map(terminated)
                if let rules = step.authenticationTokens, rules.last != "К" {
                    step.authenticationTokens = rules + ["К"]
                }
                return step
            }
        }
        return Task5Variant(seed: seed, profileID: profileID, configuration: configuration, ownCallsign: own, botCallsign: bot,
                            radioData: radio, tdr: tdr, radiograms: radiograms, signals: signals, steps: steps)
    }
    static func terminated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Task5Validator.tokens(trimmed).last == "К" ? trimmed : trimmed + " К"
    }

}

enum Task5Validator {
    /// RU/EN aliases share a Morse pattern, not a visual shape. In particular
    /// Latin B is Б, whereas Cyrillic В shares W's pattern. Digits, unknown
    /// symbols and field boundaries remain intact; zero is never treated as Т.
    private static let latinAliases: [Character: Character] = [
        "A": "А", "B": "Б", "C": "Ц", "D": "Д", "E": "Е", "F": "Ф",
        "G": "Г", "H": "Х", "I": "И", "J": "Й", "K": "К", "L": "Л",
        "M": "М", "N": "Н", "O": "О", "P": "П", "Q": "Щ", "R": "Р",
        "S": "С", "T": "Т", "U": "У", "V": "Ж", "W": "В", "X": "Ь",
        "Y": "Ы", "Z": "З"
    ]
    private static let cyrillicLetters = Set("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")

    static func tokens(_ text: String) -> [String] {
        let canonical = text.map { character -> String in
            let uppercase = String(character).uppercased()
            guard uppercase.count == 1, let sign = uppercase.first else { return String(character) }
            if let alias = latinAliases[sign] { return String(alias) }
            return cyrillicLetters.contains(sign) ? uppercase : String(character)
        }.joined()
        return canonical.replacingOccurrences(of: "=", with: " = ").split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Only the operator's challenge is free; echoes and answers remain bound
    /// to the numbers actually exchanged. Generated variants stay immutable.
    static func chosenPasswordIndex(for step: Task5Step, variant: Task5Variant) -> Int? {
        guard ["task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(variant.profileID), step.direction == .transmit else { return nil }
        if step.id == "auth-peer" { return 1 }
        if step.id == "auth-counter" { return 2 }
        return nil
    }

    static func resolvedStep(_ original: Task5Step, variant: Task5Variant, attempts: [Task5Attempt]) -> Task5Step {
        guard ["task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(variant.profileID) else { return original }
        if original.direction == .receive, ["quality-reply", "quality-report"].contains(original.id) {
            var step = original
            let rating = Int(variant.seed % 5) + 1
            let message = original.id == "quality-reply"
                ? "ЩСА \(rating) К ЩСА?" + (variant.profileID == "task5.photos.v8.final-k" ? " К" : "")
                : "ЩСА \(rating) К"
            step.botMessage = message
            if !step.expectedMessages.isEmpty { step.expectedMessages = [message] }
            return step
        }
        if original.id == "quality-report", original.direction == .transmit {
            var step = original
            step.expectedMessages = (1...5).map { "ЩСА \($0) К" }
            return step
        }
        if ["task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(variant.profileID), original.id.hasSuffix("-wait-pause") {
            let commandID = String(original.id.dropLast("-pause".count))
            if let attempt = attempts.last(where: { $0.stepID == commandID && $0.correct }),
               let minutes = waitMinutes(attempt.input) {
                var step = original
                step.requiredPauseSeconds = Double(minutes * 60)
                return step
            }
        }
        guard original.authenticationTokens != nil else { return original }
        func sent(_ id: String) -> [String]? {
            attempts.last(where: { $0.stepID == id && $0.correct && $0.inputMethod != "service" }).map {
                var groups = tokens($0.input)
                if variant.profileID == "task5.photos.v8.final-k", groups.last == "К" { groups.removeLast() }
                return groups
            }
        }
        func code(_ number: String) -> String? {
            guard let cell = variant.tdr.cells.first(where: { $0.number == number }) else { return nil }
            return variant.tdr.codes(for: cell).first
        }
        func answer(_ group: String) -> String? {
            guard let number = variant.tdr.decode(group)?.number, let value = Int(number) else { return nil }
            return String(format: "%02d", Task5Scenario.authenticationAnswer(to: value))
        }
        var step = original
        var rules = original.authenticationTokens!
        var wire = tokens(original.expectedMessages.first ?? original.botMessage ?? "")
        if original.id == "auth-request-echo", let request = sent("auth-peer"), request.count == 2,
           let number = variant.tdr.decode(request[1])?.number {
            rules[1] = number
            wire = request + ["Ц?", "К"]
        }
        if ["auth-counter", "auth-counter-echo"].contains(original.id),
           let request = sent("auth-peer"), request.count == 2,
           let number = answer(request[1]), let encoded = code(number) {
            rules[1] = number
            wire[1] = encoded
        }
        if original.id == "auth-counter-echo", let counter = sent("auth-counter"), counter.count == 3,
           let response = variant.tdr.decode(counter[1])?.number,
           let challenge = variant.tdr.decode(counter[2])?.number {
            rules[1] = response; rules[2] = challenge
            wire = counter + ["Ц?", "К"]
        }
        if original.id == "auth-self", let counter = sent("auth-counter"), counter.count == 3,
           let number = answer(counter[2]), let encoded = code(number) {
            rules[1] = number
            wire[1] = encoded
        }
        step.authenticationTokens = rules
        step.expectedMessages = [wire.joined(separator: " ")]
        if original.botMessage != nil { step.botMessage = step.expectedMessages[0] }
        return step
    }

    static func qualityFormat(for step: Task5Step, variant: Task5Variant) -> String? {
        guard ["task5.photos.v5.major-complete", "task5.photos.v6.callsigns-tdr", "task5.photos.v7.timed-wait", "task5.photos.v8.final-k"].contains(variant.profileID), step.direction == .transmit else { return nil }
        switch step.id {
        case "quality-report": return "ЩСА <оценка 1–5> К"
        case "quality-reply": return "ЩСА <оценка 1–5> К ЩСА?" + (variant.profileID == "task5.photos.v8.final-k" ? " К" : "")
        default: return nil
        }
    }

    static func isTimedWait(_ step: Task5Step, variant: Task5Variant) -> Bool {
        isWaitCommand(step)
    }

    static func isWaitCommand(_ step: Task5Step) -> Bool {
        ["auth-request-wait", "auth-counter-wait"].contains(step.id)
    }

    /// Two-digit positive minutes are the trainer's supported input range.
    static func waitMinutes(_ text: String) -> Int? {
        let groups = tokens(text)
        guard groups.count == 4, groups[0] == "ОК", groups[1] == "АС", groups[3] == "К",
              groups[2].count <= 2, groups[2].allSatisfy({ "0123456789".contains($0) }),
              let minutes = Int(groups[2]), (1...99).contains(minutes) else { return nil }
        return minutes
    }

    /// Recover only spacing, and only when the resulting message passes the
    /// normal semantic checks. Never repair a letter, number or missing K.
    static func normalizedTransmission(_ text: String, for step: Task5Step, variant: Task5Variant) -> String {
        let original = tokens(text).joined(separator: " ")
        if validateStrict(original, for: step, variant: variant).isCorrect { return original }
        var candidates: [String] = []
        let punctuation = original.replacingOccurrences(of: #"\s*\?\s*"#, with: "? ", options: .regularExpression)
        candidates.append(punctuation)
        if original.hasSuffix("К") {
            candidates.append(String(original.dropLast()) + " К")
        }
        // Service phrases have a known structure. A radiogram's five-sign
        // groups must retain their boundaries; joining those would hide errors.
        if step.bodyGroups == 0 {
            let compact = tokens(original).joined()
            if isTimedWait(step, variant: variant) {
                candidates.append(compact.replacingOccurrences(of: #"^ОКАС([0-9]{1,2})К$"#,
                    with: "ОК АС $1 К", options: .regularExpression))
            }
            candidates += step.expectedMessages.filter { tokens($0).joined() == compact }
            if let rules = step.authenticationTokens {
                let lengths = rules.map { $0 == "password" || Int($0) != nil ? 3 : $0.count }
                if compact.count == lengths.reduce(0, +) {
                    var rest = compact[...]
                    var groups: [String] = []
                    for length in lengths {
                        groups.append(String(rest.prefix(length)))
                        rest = rest.dropFirst(length)
                    }
                    candidates.append(groups.joined(separator: " "))
                }
            }
            if qualityFormat(for: step, variant: variant) != nil {
                candidates.append(compact.replacingOccurrences(of: #"^ЩСА([1-5])К(ЩСА\?К?)?$"#,
                    with: "ЩСА $1 К $2", options: .regularExpression).replacingOccurrences(of: "?К", with: "? К"))
            }
        }
        return candidates.first { validateStrict($0, for: step, variant: variant).isCorrect }
            .map { tokens($0).joined(separator: " ") } ?? original
    }

    static func validate(_ text: String, for step: Task5Step, variant: Task5Variant) -> Task5Validation {
        validateStrict(normalizedTransmission(text, for: step, variant: variant), for: step, variant: variant)
    }

    private static func validateStrict(_ text: String, for step: Task5Step, variant: Task5Variant) -> Task5Validation {
        if step.kind == .administrative { return .correct }
        guard !step.expectedMessages.isEmpty else { return .wrong("Дождитесь окончания приёма") }
        let input = tokens(text)
        if variant.profileID == "task5.photos.v8.final-k", input.last != "К" {
            return .wrong("Завершите сообщение знаком К.")
        }
        if isTimedWait(step, variant: variant) {
            return waitMinutes(text) != nil ? .correct : .wrong("Передайте ОК АС <минуты> К. Поддерживается ожидание от 1 до 99 минут.")
        }
        guard !input.isEmpty else { return .wrong("Введите сообщение") }
        if let format = qualityFormat(for: step, variant: variant) {
            guard input.count >= 2, input[0] == "ЩСА" else { return .wrong("Форма ответа: \(format).") }
            guard (1...5).map(String.init).contains(input[1]) else {
                return .wrong("Оценку выбираете вы: передайте целое число от 1 до 5.")
            }
            var suffix = Array(input.dropFirst(2))
            if variant.profileID == "task5.photos.v8.final-k", step.id == "quality-reply", suffix.last == "К" {
                suffix.removeLast()
            }
            let valid = step.id == "quality-report"
                ? suffix == ["К"]
                : suffix == ["К", "ЩСА?"] || suffix == ["К", "ЩСА", "?"]
            return valid ? .correct : .wrong("Проверьте окончание. Форма ответа: \(format).")
        }
        if let rules = step.authenticationTokens {
            guard input.count == rules.count else {
                return .wrong("Паролирование: ожидается \(rules.count) групп, принято \(input.count).")
            }
            for (index, pair) in zip(input, rules).enumerated() {
                let (actual, rule) = pair
                if rule == "password" {
                    guard variant.tdr.decode(actual)?.expressionId == "password" else {
                        return .wrong("Группа \(index + 1): нужен код «Сообщите (аю) пароль» по ТДР.")
                    }
                } else if Int(rule) != nil {
                    guard let cell = variant.tdr.decode(actual) else {
                        return .wrong("Группа \(index + 1): не удалось раскодировать число по ТДР.")
                    }
                    guard index == chosenPasswordIndex(for: step, variant: variant) || cell.number == rule else {
                        return .wrong("Группа \(index + 1): неверное число по ТДР. Для ответа используйте |50 − принятое число|.")
                    }
                } else if actual != rule {
                    return .wrong("Группа \(index + 1): принято «\(actual)», ожидается «\(rule)».")
                }
            }
            return .correct
        }
        if let expression = step.tdrExpressionID {
            guard input.count == 2, input.last == "К", let cell = variant.tdr.decode(input[0]), cell.expressionId == expression else {
                return .wrong("Проверьте код ячейки и окончание К")
            }
            if let number = step.tdrCellNumber, cell.number != number { return .wrong("Ответьте кодом заданной ячейки ТДР") }
            return .correct
        }
        if step.id.hasSuffix("-offer"), let id = step.radiogramID, let rg = variant.radiograms.first(where: { $0.id == id }) {
            guard input.count == 3, input[0] == "ЩТЦ", input[2] == "К", let cell = variant.tdr.decode(input[1]),
                  cell.expressionId == variant.tdr.decode(rg.urgencyCode)?.expressionId else { return .wrong("Проверьте ЩТЦ, код категории и К") }
            return .correct
        }
        if step.bodyGroups > 0, let id = step.radiogramID, let rg = variant.radiograms.first(where: { $0.id == id }) {
            return validateRadiogram(input, radiogram: rg, tdr: variant.tdr)
        }
        if step.expectedMessages.contains(where: { tokens($0) == input }) { return .correct }
        let expected = step.expectedMessages.map(tokens).min { left, right in
            mismatchCount(input, left) < mismatchCount(input, right)
        } ?? []
        let mismatches = mismatchCount(input, expected)
        let first = (0..<max(input.count, expected.count)).first {
            $0 >= input.count || $0 >= expected.count || input[$0] != expected[$0]
        } ?? 0
        let detail: String
        if first >= input.count {
            detail = step.direction == .transmit ? "Не передана группа \(first + 1): «\(expected[first])»." : "Не записана группа \(first + 1)."
        } else if first >= expected.count {
            detail = "Лишняя группа \(first + 1): «\(input[first])»."
        } else if step.direction == .transmit {
            detail = "Группа \(first + 1): принято «\(input[first])», ожидается «\(expected[first])»."
        } else {
            detail = "Ошибка в группе \(first + 1): записано «\(input[first])»."
        }
        return .wrong(detail, errors: mismatches)
    }

    private static func mismatchCount(_ input: [String], _ expected: [String]) -> Int {
        zip(input, expected).filter { $0 != $1 }.count + abs(input.count - expected.count)
    }

    static func validateRadiogram(_ input: [String], radiogram rg: Task5Radiogram, tdr: Task5TDR) -> Task5Validation {
        let separators = input.indices.filter { input[$0] == "=" }
        guard separators.count == 2 else { return .wrong("Нужны два раздела =") }
        let first = separators[0], second = separators[1]
        guard Array(input[..<first]) == tokens(rg.header) else { return .wrong("Проверьте номер, число групп, время и повтор номера") }
        let address = Array(input[(first + 1)..<second])
        let expectedExpression = tdr.decode(rg.urgencyCode)?.expressionId
        guard address.count == 3, let category = tdr.decode(address[0]), category.expressionId != nil,
              category.expressionId == expectedExpression, Array(address.dropFirst()) == tokens(rg.address) else {
            return .wrong("Проверьте категорию и адресные группы")
        }
        guard input.last == "К" else { return .wrong("Завершите радиограмму знаком К") }
        let suffixCount = rg.majorFormat == true ? 1 : 2
        if rg.majorFormat != true {
            guard input.count >= second + 3, input[input.count - 2] == rg.operatorGroup else { return .wrong("Проверьте группу радиста перед К") }
        }
        guard second + 1 <= input.count - suffixCount else { return .wrong("Отсутствует текст радиограммы") }
        let groups = Array(input[(second + 1)..<(input.count - suffixCount)])
        guard groups.count == rg.groupCount else { return .wrong("Число групп не совпадает с заголовком", errors: abs(groups.count - rg.groupCount)) }
        guard groups.allSatisfy({ $0.count == 5 }) else { return .wrong("В каждой группе должно быть пять знаков") }
        let errors = zip(groups, rg.groups).reduce(0) { result, pair in
            result + zip(pair.0, pair.1).filter { $0 != $1 }.count
        }
        guard errors > 0 else { return .correct }
        let wrongGroup = groups.indices.first { groups[$0] != rg.groups[$0] } ?? 0
        return .wrong("Ошибка в группе текста \(wrongGroup + 1): «\(groups[wrongGroup])». Несовпадений знаков: \(errors).", errors: errors)
    }
}

enum Task5RepeatRequest: Equatable {
    case all, header, number, group(String), after(String), before(String), between(String, String)

    static func parse(_ text: String) -> Self? {
        var words = Task5Validator.tokens(text)
        if words.last == "К" { words.removeLast() }
        guard words.first == "РПТ" else { return nil }
        words.removeFirst()
        if words.isEmpty || words == ["АЛ"] { return .all }
        if words == ["ПБЛ"] { return .header }
        if words == ["НР"] { return .number }
        if words.count == 2, words[0] == "ГР" { return .group(words[1]) }
        if words.count == 2, words[0] == "АА" { return .after(words[1]) }
        if words.count == 2, words[0] == "АБ" { return .before(words[1]) }
        if words.count == 3, words[0] == "БН" { return .between(words[1], words[2]) }
        return nil
    }

    func reply(for rg: Task5Radiogram) -> String? {
        func index(_ locator: String) -> Int? {
            let matches = rg.groups.indices.filter { rg.groups[$0] == locator }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
            if locator.count <= 3, let number = Int(locator), number > 0, number <= rg.groups.count { return number - 1 }
            return nil
        }
        switch self {
        case .all: return rg.wireText
        case .header: return rg.header + " = \(rg.urgencyCode) \(rg.address) = К"
        case .number: return "НР \(rg.number) К"
        case .group(let locator):
            guard let i = index(locator) else { return nil }
            return rg.groups[i] + " К"
        case .after(let locator):
            guard let i = index(locator), i + 1 < rg.groups.count else { return nil }
            return rg.groups[(i + 1)...].joined(separator: " ") + " К"
        case .before(let locator):
            guard let i = index(locator), i > 0 else { return nil }
            return rg.groups[..<i].joined(separator: " ") + " К"
        case .between(let left, let right):
            guard let a = index(left), let b = index(right), a + 1 < b else { return nil }
            return rg.groups[(a + 1)..<b].joined(separator: " ") + " К"
        }
    }
}

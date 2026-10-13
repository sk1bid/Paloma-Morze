import SwiftUI

/// Эфир, in the released layout (no parameter column): sign-in card, the
/// operator bar with the channel list, the room card, the live channel with two
/// tapes. The model guarantees only one state is active; nothing here invents
/// participants — sample rooms exist only in preview fixtures.
struct RadioView: View {
    @Bindable var model: RadioModel

    var body: some View {
        Group {
            switch model.screen {
            case .signedOut(let phase):
                SignInView(model: model, phase: phase)
            case .lobby(let phase):
                VStack(spacing: Spacing.m) {
                    OperatorBar(model: model, showsNewChannel: true)
                    LobbyView(model: model, phase: phase)
                }
            case .room(let session):
                if session.phase == .live {
                    LiveChannelView(model: model, session: session)
                } else {
                    VStack(spacing: Spacing.m) {
                        OperatorBar(model: model, showsNewChannel: false)
                        RoomWaitingView(model: model, session: session)
                    }
                }
            case .connectionLost(let loss):
                ConnectionLostView(model: model, loss: loss)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Ошибка эфира", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.dismissActionError() } })) {
                Button("OK") { model.dismissActionError() }
            } message: {
                Text(model.actionError ?? "")
            }
    }
}

// MARK: - Signed out

struct SignInView: View {
    var model: RadioModel
    var phase: SignInPhase

    @State private var callsign = ""
    @State private var password = ""
    @State private var registering = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.xxs) {
                Text(registering ? "Регистрация" : "Авторизация")
                    .font(.title.weight(.semibold))
                Text(registering ? "Выберите позывной и пароль" : "Введите ваш позывной для выхода в эфир")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Spacing.s) {
                field(systemImage: "person") {
                    TextField("Позывной", text: $callsign)
                        .textContentType(.username)
                }
                field(systemImage: "lock") {
                    SecureField("Пароль", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                }
            }
            .frame(width: 300)

            if case .failed(let reason) = phase {
                Label(reason, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if !model.isNetworkAvailable {
                Label(UnavailableNetworkService.reason, systemImage: "network.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Button {
                model.signIn(callsign: callsign, password: password, register: registering)
            } label: {
                HStack {
                    if phase == .submitting { ProgressView().controlSize(.small) }
                    Text(registering ? "Зарегистрироваться" : "Войти")
                    Image(systemName: "arrow.right")
                }
                .font(.body.weight(.semibold))
                .frame(width: 280)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isNetworkAvailable || callsign.isEmpty || password.isEmpty || phase == .submitting)

            Button(registering ? "Уже есть позывной? Вход" : "Нет позывного? Регистрация") {
                registering.toggle()
            }
            .buttonStyle(.link)
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .contentSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func field<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            content()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
        }
    }
}

// MARK: - Operator bar

/// Callsign, online count and the lobby actions of the released "Эфир" bar.
struct OperatorBar: View {
    var model: RadioModel
    var showsNewChannel: Bool

    @State private var creatingRoom = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let callsign = model.callsign {
                Label {
                    Text(callsign).font(.headline)
                } icon: {
                    Circle().fill(.tint).frame(width: 8, height: 8)
                }
            }
            if let online = model.onlineCount {
                Text("В сети: \(online)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let latency = model.latency {
                Text("\(latency) мс")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Задержка до ретранслятора")
            }
            Spacer()
            Button("Выйти из сети", systemImage: "rectangle.portrait.and.arrow.right", action: model.signOut)
                .labelStyle(.iconOnly)
                .help("Выйти из аккаунта")
            Button("Обновить", systemImage: "arrow.clockwise", action: model.refreshRooms)
                .labelStyle(.iconOnly)
                .help("Обновить список каналов")
            if showsNewChannel {
                Button("Новый канал", systemImage: "plus") { creatingRoom = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .contentSurface()
        .sheet(isPresented: $creatingRoom) {
            CreateRoomSheet { name, password in
                model.createRoom(name: name, password: password)
            }
        }
    }
}

// MARK: - Room list

struct LobbyView: View {
    var model: RadioModel
    var phase: LobbyPhase

    @State private var creatingRoom = false
    @State private var joiningRoom: RadioRoom?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheet(isPresented: $creatingRoom) {
                CreateRoomSheet { name, password in
                    model.createRoom(name: name, password: password)
                }
            }
            .sheet(item: $joiningRoom) { room in
                RoomPasswordSheet(room: room) { password in
                    model.join(room, password: password)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Поиск каналов…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            ContentUnavailableView {
                Label("Список каналов недоступен", systemImage: "exclamationmark.icloud")
            } description: {
                Text(reason)
            } actions: {
                Button("Повторить", action: model.refreshRooms)
            }
        case .loaded(let rooms) where rooms.isEmpty:
            ContentUnavailableView {
                Label("Активных каналов нет", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Создайте канал и дождитесь корреспондента.")
            } actions: {
                Button("Новый канал") { creatingRoom = true }
                    .buttonStyle(.glassProminent)
            }
        case .loaded(let rooms):
            VStack(spacing: Spacing.xs) {
                HStack {
                    Text("АКТИВНЫЕ КАНАЛЫ")
                    Spacer()
                    Text("СТАТУС")
                }
                .font(.parameterLabel)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.m)
                .accessibilityHidden(true)

                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(rooms) { room in
                            RoomRow(room: room) {
                                if room.isPrivate { joiningRoom = room } else { model.join(room, password: nil) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RoomRow: View {
    var room: RadioRoom
    var onJoin: () -> Void

    var body: some View {
        let isFull = room.participantCount.map { $0 >= room.capacity } ?? false
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.headline)
                Text("Оператор: \(room.owner)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: room.isPrivate ? "lock.fill" : "lock.open")
                .foregroundStyle(room.isPrivate ? Color.red : Color.green)
                .help(room.isPrivate ? "Закрытый канал, нужен пароль" : "Открытый канал")
            Text(room.participantCount.map { "\($0) / \(room.capacity)" } ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44)
            Button(isFull ? "Занят" : "Войти", action: onJoin)
                .disabled(isFull)
                .frame(width: 76)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .contentSurface(radius: Radius.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.name), оператор \(room.owner)\(room.isPrivate ? ", закрытый" : ""), \(room.participantCount.map { "\($0) из \(room.capacity)" } ?? "число участников неизвестно")")
    }
}

struct CreateRoomSheet: View {
    var onCreate: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isPrivate = false
    @State private var password = ""

    var body: some View {
        Form {
            Section("Новый канал") {
                TextField("Название", text: $name)
                Toggle("Закрытый канал", isOn: $isPrivate)
                if isPrivate {
                    SecureField("Пароль", text: $password)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Создать") {
                    onCreate(name, isPrivate ? password : nil)
                    dismiss()
                }
                .disabled(name.isEmpty || (isPrivate && password.isEmpty))
            }
        }
    }
}

struct RoomPasswordSheet: View {
    var room: RadioRoom
    var onJoin: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                SecureField("Пароль", text: $password)
            } header: {
                Text("Канал «\(room.name)» защищён паролем")
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Подключиться") {
                    onJoin(password)
                    dismiss()
                }
                .disabled(password.isEmpty)
            }
        }
    }
}

// MARK: - In room (before the session)

struct RoomWaitingView: View {
    var model: RadioModel
    var session: RoomSession

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: "person.2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(session.room.name)
                    .font(.title3.weight(.semibold))
                Text("Оператор канала: \(session.owner)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(session.participants) { participant in
                    let isSelf = participant.callsign.caseInsensitiveCompare(model.callsign ?? "") == .orderedSame
                    HStack(spacing: Spacing.xs) {
                        Circle().fill(.tint).frame(width: 7, height: 7)
                        Text(participant.callsign)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isSelf ? Color.accentColor : Color.primary)
                        if isSelf { Text("вы").foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentSurface(radius: Radius.key)
                }
                if session.participants.count < session.room.capacity {
                    Text("Свободное место")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.key)
                                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                }
            }

            phaseView
                .frame(minHeight: 44)

            Button("Покинуть канал", role: .destructive, action: model.leave)
                .buttonStyle(.borderless)
        }
        .padding(Spacing.l)
        .frame(width: 400)
        .contentSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var phaseView: some View {
        switch session.phase {
        case .waitingForCorrespondent:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Ожидание корреспондента…")
            }
            .foregroundStyle(.secondary)
        case .readyToLaunch:
            Button {
                model.launchSession()
            } label: {
                Label("Запустить сессию", systemImage: "bolt.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
        case .waitingForOwner:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Ожидание запуска оператором канала…")
            }
            .foregroundStyle(.secondary)
        case .live:
            EmptyView()
        }
    }
}

// MARK: - Live channel

struct LiveChannelView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    var model: RadioModel
    var session: RoomSession

    @FocusState private var isFocused: Bool

    var body: some View {
        let collision = model.channel == .collision
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Label("Прямой эфир", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Divider().frame(height: 18)
                Label(model.correspondent ?? "…", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Text(session.room.name)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Покинуть канал", systemImage: "xmark", role: .destructive, action: model.leave)
                    .labelStyle(.iconOnly)
                    .help("Покинуть канал")
            }
            .controlSize(.large)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .contentSurface()

            RhythmTape(rhythm: model.localRhythm, label: "Вы · \(model.callsign ?? "")", isHighlighted: collision)
            Image(systemName: "arrow.left.arrow.right")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            RhythmTape(rhythm: model.remoteRhythm, label: model.correspondent ?? "Корреспондент", isHighlighted: collision)

            HStack {
                RhythmLegend()
                Spacer()
                ChannelStatusView(channel: model.channel, correspondent: model.correspondent ?? "…")
                Spacer()
                HoldToKeyButton(isDown: model.localRhythm.isDown, isPaused: false, keyLabel: model.transmissionKeyLabel) {
                    model.keyDown()
                } onRelease: {
                    model.keyUp()
                }
            }
            .padding(.top, Spacing.xs)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onDisappear { model.keyUp() }
        .onChange(of: controlActiveState) { _, state in if state != .key { model.keyUp() } }
    }
}

/// Simplex channel state line of the released live panel.
struct ChannelStatusView: View {
    var channel: ChannelState
    var correspondent: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(channel == .collision ? SignalPalette.collision : (channel == .clear ? .secondary : .primary))
            .lineLimit(1)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var text: String {
        switch channel {
        case .clear: "Симплекс: эфир свободен"
        case .transmitting: "Вы в эфире"
        case .receiving: "Приём: в эфире \(correspondent)"
        case .collision: "Накладка: вы перебиваете друг друга!"
        }
    }

    private var symbol: String {
        switch channel {
        case .clear: "antenna.radiowaves.left.and.right"
        case .transmitting: "dot.radiowaves.right"
        case .receiving: "dot.radiowaves.left.and.right"
        case .collision: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Connection lost

struct ConnectionLostView: View {
    var model: RadioModel
    var loss: ConnectionLoss

    var body: some View {
        ContentUnavailableView {
            Label("Связь с ретранслятором потеряна", systemImage: "wifi.exclamationmark")
        } description: {
            VStack(spacing: Spacing.xs) {
                Text(loss.reason)
                if let room = loss.roomName {
                    Text("Канал «\(room)» будет закрыт для вас до восстановления связи.")
                }
                if loss.attempt > 0 {
                    HStack(spacing: Spacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Переподключение, попытка \(loss.attempt)…")
                    }
                }
            }
        } actions: {
            Button("Переподключиться", action: model.reconnect)
                .buttonStyle(.glassProminent)
            Button("Выйти из сети", action: model.signOut)
        }
    }
}

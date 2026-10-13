import Foundation
import AppKit

/// The sole live audio transport. PCM and USB remain in the bundled C++ engine.
final class ProcessAudioService: AudioService {
    let kind = AudioAdapterKind.live
    let events: AsyncStream<AudioEvent>
    private let continuation: AsyncStream<AudioEvent>.Continuation
    private let executable: URL
    private let arguments: [String]
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var nextID = 1
    private var active = Set<PlaybackRequestID>()
    private var settings = AudioSettings()
    private var ready = false
    private var startupTimer: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init(executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/morze_engine"), arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
        (events, continuation) = AsyncStream.makeStream(of: AudioEvent.self)
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopEngine() }
        }
    }

    func startEngine() {
        guard process == nil else { return }
        continuation.yield(.engine(.starting))
        continuation.yield(.hardware(.searching))
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        let epoch = UUID()
        generation = epoch
        buffer.removeAll()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                self.consume(data)
            }
        }
        errors?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch, !data.isEmpty else { return }
                let line = String(decoding: data, as: UTF8.self)
                if line.contains("EACCES") { self.continuation.yield(.hardware(.permissionDenied(line))) }
            }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                self.generation = UUID()
                self.dispose()
                self.failRequests("Audio helper exited (\(status))")
                self.continuation.yield(.hardwareKey(pressed: false))
                self.continuation.yield(.hardware(.disconnected))
                self.continuation.yield(.engine(.failed("Audio helper exited (\(status))")))
            }
        }
        do {
            try child.run()
            startupTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, generation == epoch, !ready else { return }
                stopEngine()
                continuation.yield(.engine(.failed("Audio helper readiness timeout")))
            }
        }
        catch {
            dispose()
            continuation.yield(.engine(.failed(error.localizedDescription)))
        }
    }

    func stopEngine() {
        write("RESET", requireReady: false)
        generation = UUID()
        let child = process
        dispose()
        if child?.isRunning == true { child?.terminate() }
        let ids = active; active.removeAll()
        for id in ids { continuation.yield(.playback(id, .finished(cancelled: true))) }
        continuation.yield(.hardwareKey(pressed: false))
        continuation.yield(.hardware(.unknown))
        continuation.yield(.engine(.stopped))
    }

    private func dispose() {
        startupTimer?.cancel(); startupTimer = nil
        ready = false
        output?.readabilityHandler = nil
        errors?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        try? errors?.close()
        input = nil; output = nil; errors = nil; process = nil
        buffer.removeAll()
    }

    private func failRequests(_ reason: String) {
        let ids = active
        active.removeAll()
        for id in ids { continuation.yield(.playback(id, .failed(reason))) }
    }

    func updateSettings(_ settings: AudioSettings) {
        self.settings = settings.normalized()
        sendSettings()
    }

    private func sendSettings() {
        write("S \(settings.toneHz) \(settings.volumePercent) \(settings.front) \(settings.waveform == .square ? 1 : 0) 0")
    }

    func play(_ tokens: [PlaybackToken], spacing: SpacingMode) -> PlaybackRequestID {
        let id = PlaybackRequestID(rawValue: nextID)
        nextID += 1
        guard ready, !tokens.isEmpty, tokens.allSatisfy({ $0.patterns.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "." || $0 == "-" } } }) else {
            continuation.yield(.playback(id, .failed("Engine not ready or invalid pattern")))
            return id
        }
        active.insert(id)
        let patterns = tokens.map { $0.isGroupGap ? "/" : $0.patterns.joined(separator: ",") }.joined(separator: "|")
        write("P \(id.rawValue) \(settings.speed) \(settings.tonePeriod) \(Int((settings.dashRatio * 10).rounded())) \(Int((settings.pauseFactor * 10).rounded())) \(settings.front) \(settings.waveform == .square ? 1 : 0) 0 \(spacing.rawValue) \(patterns)")
        return id
    }

    func cancel(_ id: PlaybackRequestID) { write("STOP \(id.rawValue)") }
    func stopAll() { write("RESET") }
    func setLocalKey(_ pressed: Bool) { write("K local \(pressed ? 1 : 0)") }
    func setRemoteKey(_ pressed: Bool) { write("K remote \(pressed ? 1 : 0)") }
    func setSidetoneMuted(_ muted: Bool) { write(muted ? "M1" : "M0") }
    func notifyConnection(_ connected: Bool) { write(connected ? "N 1" : "N 0") }

    private func write(_ command: String, requireReady: Bool = true) {
        guard (!requireReady || ready), process?.isRunning == true else { return }
        do { try input?.write(contentsOf: Data((command + "\n").utf8)) }
        catch {
            failRequests(error.localizedDescription)
            continuation.yield(.engine(.failed(error.localizedDescription)))
        }
    }

    /// Byte buffering preserves UTF-8 and split stdout lines. Logs are not errors.
    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            consumeLine(line)
        }
        if buffer.count > 1_048_576 { buffer.removeAll() }
    }

    private func consumeLine(_ line: String) {
        if ProcessInfo.processInfo.environment["PALOMA_AUDIO_TRACE"] == "1", line.hasPrefix("AUDIO") { try? FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8)) }
        let fields = line.split(separator: " ")
        if fields.count == 4, fields[0] == "AUDIO", fields[1] == "READY", fields[2] == "1", let rate = Int(fields[3]) {
            startupTimer?.cancel(); startupTimer = nil
            ready = true
            continuation.yield(.engine(.ready(sampleRate: rate)))
            sendSettings()
            return
        }
        if fields.count >= 4, fields[0] == "AUDIO", let raw = Int(fields[2]) {
            let id = PlaybackRequestID(rawValue: raw)
            guard active.contains(id) else { return }
            let value = Int(fields[3])
            let event: PlaybackEvent
            switch fields[1] {
            case "START": guard let value else { return }; event = .started(totalFrames: value)
            case "CHAR": guard let value else { return }; event = .token(value)
            case "PULSE": guard let value, (0...2).contains(value) else { return }; event = .pulse(value == 1 ? .dot : value == 2 ? .dash : .none)
            case "DONE": guard let value else { return }; active.remove(id); event = .finished(cancelled: value != 0)
            case "ERROR": active.remove(id); event = .failed(fields.dropFirst(3).joined(separator: " "))
            default: return
            }
            continuation.yield(.playback(id, event))
        } else if line == "1" || line == "0" {
            continuation.yield(.hardwareKey(pressed: line == "1"))
        } else if line.contains("EACCES") {
            continuation.yield(.hardware(.permissionDenied(line)))
        } else if line.contains("Connected to"), line.contains("Auth OK") {
            continuation.yield(.hardware(.connected(line)))
        } else if line.localizedCaseInsensitiveContains("reconnecting") {
            continuation.yield(.hardware(.reconnecting))
        } else if line.localizedCaseInsensitiveContains("disconnected") || line.localizedCaseInsensitiveContains("port lost") {
            continuation.yield(.hardwareKey(pressed: false))
            continuation.yield(.hardware(.disconnected))
        }
    }
}

import Foundation
import Testing
@testable import PalomaMorse

struct LiveAudioTests {
    @Test func bundledHelperStartsPlaysCancelsAndRestarts() async throws {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/morze_engine")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            Issue.record("Run Tools/build-native.sh before live integration tests: helper missing")
            return
        }
        let service = ProcessAudioService(executable: helper, arguments: ["--test-mode", "headless"])
        let audio = AudioCoordinator(service: service)
        var settings = AudioSettings(); settings.volumePercent = 0; settings.speed = 150
        for _ in 0..<3 {
            audio.startEngine(with: settings)
            for _ in 0..<100 where !audio.isReady { try await Task.sleep(for: .milliseconds(20)) }
            #expect(audio.isReady)
            var finished = false, sawPulse = false
            let id = audio.play([PlaybackToken(display: "A", patterns: [".-"])], spacing: .text) { _, event in
                if case .pulse(.dot) = event { sawPulse = true }
                if case .finished(cancelled: false) = event { finished = true }
            }
            #expect(id != nil)
            for _ in 0..<100 where !finished { try await Task.sleep(for: .milliseconds(20)) }
            #expect(finished && sawPulse)
            var cancelled = false
            let long = audio.play(Array(repeating: PlaybackToken(display: "A", patterns: [".-"]), count: 100), spacing: .text) { _, event in
                if case .finished(cancelled: true) = event { cancelled = true }
            }
            if let long { audio.cancel(long) }
            for _ in 0..<100 where !cancelled { try await Task.sleep(for: .milliseconds(20)) }
            #expect(cancelled)
            service.stopEngine()
            await settle()
            #expect(audio.engineState == .stopped)
        }
    }
}

struct ProcessFailureTests {
    @Test func unexpectedDeathIsVisibleAndRestartDoesNotDuplicateFailures() async throws {
        let service = ProcessAudioService(executable: URL(fileURLWithPath: "/usr/bin/false"))
        var failures = 0
        let listener = Task {
            for await event in service.events {
                if case .engine(.failed) = event { failures += 1 }
            }
        }
        defer { listener.cancel(); service.stopEngine() }
        for count in 1...3 {
            service.startEngine()
            for _ in 0..<100 where failures < count { try await Task.sleep(for: .milliseconds(10)) }
            #expect(failures == count)
        }
        service.stopEngine()
        try await Task.sleep(for: .milliseconds(30))
        #expect(failures == 3)
    }
}

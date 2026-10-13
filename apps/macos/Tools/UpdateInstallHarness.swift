// CI-only standalone application. Never compiled into PalomaMorse.
import AppKit
import Sparkle

@MainActor final class Driver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { fail(error); acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { fail(error); acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() {}
    private func fail(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "update-test-error")
        UserDefaults.standard.synchronize()
        fputs("Sparkle update test failed: \(error)\n",stderr)
        NSApp.terminate(nil)
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var driver: Driver?
    var updater: SPUUpdater?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences=UserDefaults.standard
        if Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "2" {
            preferences.set(preferences.string(forKey:"preserved-setting") == "retained" ? "PASS" : "LOST SETTINGS", forKey:"update-test-result")
            preferences.synchronize()
            NSApp.terminate(nil)
            return
        }
        preferences.set("retained",forKey:"preserved-setting")
        preferences.synchronize()
        let driver=Driver();self.driver=driver
        let updater=SPUUpdater(hostBundle:Bundle.main,applicationBundle:Bundle.main,userDriver:driver,delegate:nil)
        self.updater=updater
        do { try updater.start(); updater.checkForUpdates() }
        catch { fputs("Failed to start updater: \(error)\n",stderr);NSApp.terminate(nil) }
    }
}
@main enum Harness {
    @MainActor static func main() {
        let app=NSApplication.shared
        let delegate=Delegate()
        app.delegate=delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

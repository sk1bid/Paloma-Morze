import AppKit
import SwiftUI
import XCTest
@testable import PalomaMorse

/// Explicit review harness. It renders only windows owned by this test host;
/// no desktop or other application's pixels are captured.
@MainActor
final class Task5VisualReviewTests: XCTestCase {
    func testSixtyGroupRadiogramFormRendering() throws {
        let variant = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 2483,
            reference: Task5Reference.load(), catalog: loadCatalog())
        let radiogram = try XCTUnwrap(variant.radiograms.first { $0.direction == .transmit })
        XCTAssertEqual(radiogram.groups.count, 60)
        let layout = Task5RadiogramFormLayout(radiogram: radiogram, requestedPart: .group(59))
        XCTAssertEqual(layout.rows.count, 12)
        for scheme in [ColorScheme.light, .dark] {
            let view = Task5RadiogramForm(layout: layout)
                .padding(16)
                .frame(width: 500, height: 480, alignment: .topLeading)
                .background(scheme == .light ? Color.white : Color.black)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let cg = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(cg.width, 500); XCTAssertEqual(cg.height, 480)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            // Sample an empty area inside a ruled cell, rather than the outer
            // test backdrop: a fixed light sheet must fail the dark-mode test.
            let surface = try XCTUnwrap(bitmap.colorAt(x: 20, y: 210)?.usingColorSpace(.deviceRGB))
            let brightness = (surface.redComponent + surface.greenComponent + surface.blueComponent) / 3
            if scheme == .dark { XCTAssertLessThan(brightness, 0.45) }
            else { XCTAssertGreaterThan(brightness, 0.75) }
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let name = "task5-radiogram-60-\(scheme == .light ? "light" : "dark").png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try png.write(to: url)
            print("TASK5_RADIOGRAM_RENDER: \(url.path)")
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testSeparateDeveloperControllerRendering() async throws {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        let session = Task5Session(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
            archiveDirectory: nil, developerReview: true)
        session.isEnabled = true; session.seedText = "2483"; session.developerAudioEnabled = false
        engine.startEngine(); await settle(); session.developerInspectStage(to: 0)
        for width in [900.0, 680.0] {
            let view = Task5DeveloperController(session: session)
                .frame(width: width, height: 140)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let cg = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let name = "task5-dev-controller-\(Int(width)).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try png.write(to: url)
            print("TASK5_DEV_RENDER: \(url.path)")
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        session.stop()
    }

    func testDeveloperMainCanvasUsesTheOrdinaryTask5Layout() async throws {
        let engine = ScriptedAudioService(), audio = AudioCoordinator(service: engine)
        let session = Task5Session(catalog: try loadCatalog(), audio: audio, settings: SettingsStore(defaults: nil),
            archiveDirectory: nil, developerReview: true)
        session.isEnabled = true; session.seedText = "2483"; session.developerAudioEnabled = false
        engine.startEngine(); await settle(); session.developerInspectStage(to: 0)
        let index = try XCTUnwrap(session.variant?.steps.firstIndex { $0.id == "call" })
        session.developerInspectStage(to: index)
        let view = Task5View(session: session).padding(12)
            .frame(width: 900, height: 620)
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor))
        // ImageRenderer omits the native controls inside ScrollView. Use the
        // owned-window harness, as for the existing feature canvas review.
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 620)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Task5 main canvas review"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.orderFront(nil)
        defer { session.stop(); window.close() }
        try await Task.sleep(for: .milliseconds(180))
        window.contentView?.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
        XCTAssertEqual(hosting.bounds.width, 900); XCTAssertEqual(hosting.bounds.height, 620)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("task5-main-without-dev-controls.png")
        try png.write(to: url)
        print("TASK5_MAIN_RENDER: \(url.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "task5-main-without-dev-controls"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPreparedCodeGuidanceRendering() throws {
        let catalog = try loadCatalog()
        let variant = try Task5Scenario.generate(configuration: Task5Configuration(), seed: 2483,
            reference: Task5Reference.load(), catalog: catalog)
        for scheme in [ColorScheme.light, .dark] {
            let cell = try XCTUnwrap(variant.tdr.cells.first { $0.expressionId == "password" })
            let code = try XCTUnwrap(variant.tdr.codes(for: cell).first)
            let view = Task5CodeGuidance(outgoing: "\(code) К",
                meanings: [Task5CodeMeaning(code: code, number: cell.number, expression: cell.expression)])
                .padding(16)
                .frame(width: 720, height: 240)
                .background(scheme == .light ? Color.white : Color.black)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let cg = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let name = "task5-codes-\(scheme == .light ? "light" : "dark").png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try png.write(to: url)
            print("TASK5_CODES_RENDER: \(url.path)")
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testTask5FeatureCanvases() async throws {
        guard ProcessInfo.processInfo.environment["PALOMA_TASK5_VISUAL_REVIEW"] == "1" else {
            throw XCTSkip("Set PALOMA_TASK5_VISUAL_REVIEW=1 for the opt-in layout review")
        }

        let sizes = [CGSize(width: 900, height: 620), CGSize(width: 1440, height: 900)]
        let themes: [(name: String, appearance: NSAppearance.Name, scheme: ColorScheme)] = [
            ("light", .aqua, .light), ("dark", .darkAqua, .dark)
        ]
        for fixture in ["task5.setup", "task5.duty"] {
            for size in sizes {
                for theme in themes {
                    try await capture(fixture: fixture, size: size, theme: theme)
                }
            }
        }
    }

    private func capture(
        fixture: String,
        size: CGSize,
        theme: (name: String, appearance: NSAppearance.Name, scheme: ColorScheme)
    ) async throws {
        let model = PreviewFixtures.appModel(for: fixture, catalog: try loadCatalog())
        let view = RootView(model: model)
            .environment(\.colorScheme, theme.scheme)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.wantsLayer = true

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Task 5 · Visual Review"
        window.appearance = NSAppearance(named: theme.appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setContentSize(size)
        window.orderFront(nil)
        defer {
            model.task5.stop()
            model.audio.service.stopEngine()
            window.close()
        }

        // The duty fixture starts after the demo engine's ready event. Allow
        // that task and SwiftUI's geometry/appearance passes to settle first.
        for _ in 0..<75 {
            await Task.yield()
            if fixture != "task5.duty" || model.task5.isSessionActive { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(180))
        for _ in 0..<5 { await Task.yield() }
        window.contentView?.layoutSubtreeIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        XCTAssertEqual(hosting.bounds.width, size.width, accuracy: 0.5)
        XCTAssertEqual(hosting.bounds.height, size.height, accuracy: 0.5)
        XCTAssertEqual(model.task5.variant?.tdr.cells.count, 100)
        if fixture == "task5.duty" {
            XCTAssertTrue(model.task5.isSessionActive, "The duty fixture must have reached its active state")
        }

        let bitmap = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
            "AppKit could not allocate a bitmap for the owned feature view")
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]),
                                "AppKit did not produce a PNG")
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        XCTAssertGreaterThan(png.count, 1_000, "The captured feature view is unexpectedly empty")

        if let pixels = bitmap.bitmapData {
            let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
            let distinct = Set(stride(from: 0, to: byteCount, by: 97).map { pixels[$0] })
            XCTAssertGreaterThan(distinct.count, 2, "The bitmap appears uniform; layout was not visually captured")
        } else {
            XCTFail("The PNG has no inspectable bitmap pixels")
        }

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(fixture)_\(Int(size.width))x\(Int(size.height))_\(theme.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

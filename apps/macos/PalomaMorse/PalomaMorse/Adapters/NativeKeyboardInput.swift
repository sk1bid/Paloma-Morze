import AppKit

/// Uses physical macOS scan codes so a remapped key works in RU and EN layouts.
/// The monitor belongs to the main window's lifecycle; it never monitors globally.
final class NativeKeyboardInput {
    private weak var model: AppModel?
    private var monitor: Any?
    private var focusObserver: NSObjectProtocol?
    private var held = false
    private var heldScan: UInt16?
    private var windowObserver: NSObjectProtocol?
    init(model: AppModel) {
        self.model = model
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        focusObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
    }
    func stop() {
        release()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }; focusObserver = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }; windowObserver = nil
    }
    private func release() {
        held = false; heldScan = nil
        model?.transmission.releaseKey(); model?.radio.keyUp()
    }
    func handle(_ event: NSEvent, in window: NSWindow? = NSApp.keyWindow) -> NSEvent? {
        guard let model else { return event }
        if event.type == .keyUp, held, event.keyCode == heldScan { release(); return nil }
        guard window?.title == "Paloma Morse", window?.attachedSheet == nil,
              !(window?.firstResponder is NSTextView),
              Self.browserCode(for: event.keyCode) == model.settings.transmissionKey else { return event }
        // App commands and text editing take priority over ordinary letter keys.
        // A modifier explicitly chosen as the key still handles its flagsChanged.
        if event.type != .flagsChanged,
           !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
        let down: Bool
        if event.type == .flagsChanged {
            let flag: NSEvent.ModifierFlags
            switch event.keyCode {
            case 56, 60: flag = .shift
            case 58, 61: flag = .option
            case 59, 62: flag = .control
            case 54, 55: flag = .command
            case 57: flag = .capsLock
            default: flag = .function
            }
            down = event.modifierFlags.contains(flag)
        } else { down = event.type == .keyDown }
        if !down {
            guard held else { return event }
            release(); return nil
        }
        guard !event.isARepeat, !held else { return nil }
        if model.section == .transmission {
            held = true; heldScan = event.keyCode; model.transmission.keyDown(from: .keyboard); return nil
        } else if model.section == .radio, model.radio.isLive {
            held = true; heldScan = event.keyCode; model.radio.keyDown(); return nil
        }
        return event
    }
    static func browserCode(for scan: UInt16) -> String? {
        codes[scan]
    }
    private static let codes: [UInt16: String] = [
        0:"KeyA",1:"KeyS",2:"KeyD",3:"KeyF",4:"KeyH",5:"KeyG",6:"KeyZ",7:"KeyX",8:"KeyC",9:"KeyV",11:"KeyB",
        12:"KeyQ",13:"KeyW",14:"KeyE",15:"KeyR",16:"KeyY",17:"KeyT",18:"Digit1",19:"Digit2",20:"Digit3",21:"Digit4",
        22:"Digit6",23:"Digit5",24:"Equal",25:"Digit9",26:"Digit7",27:"Minus",28:"Digit8",29:"Digit0",30:"BracketRight",
        31:"KeyO",32:"KeyU",33:"BracketLeft",34:"KeyI",35:"KeyP",36:"Enter",37:"KeyL",38:"KeyJ",39:"Quote",40:"KeyK",
        41:"Semicolon",42:"Backslash",43:"Comma",44:"Slash",45:"KeyN",46:"KeyM",47:"Period",48:"Tab",49:"Space",50:"Backquote",
        51:"Backspace",53:"Escape",54:"MetaRight",55:"MetaLeft",56:"ShiftLeft",57:"CapsLock",58:"AltLeft",59:"ControlLeft",
        60:"ShiftRight",61:"AltRight",62:"ControlRight",63:"Fn",65:"NumpadDecimal",67:"NumpadMultiply",69:"NumpadAdd",
        71:"NumLock",75:"NumpadDivide",76:"NumpadEnter",78:"NumpadSubtract",81:"NumpadEqual",82:"Numpad0",83:"Numpad1",
        84:"Numpad2",85:"Numpad3",86:"Numpad4",87:"Numpad5",88:"Numpad6",89:"Numpad7",91:"Numpad8",92:"Numpad9",
        10:"IntlBackslash",64:"F17",79:"F18",80:"F19",90:"F20",93:"IntlYen",94:"IntlRo",95:"NumpadComma",
        102:"Lang2",104:"Lang1",105:"F13",106:"F16",107:"F14",113:"F15",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"PageUp",
        117:"Delete",118:"F4",119:"End",120:"F2",121:"PageDown",122:"F1",123:"ArrowLeft",124:"ArrowRight",125:"ArrowDown",126:"ArrowUp"
    ]
}

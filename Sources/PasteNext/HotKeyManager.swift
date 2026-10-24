import AppKit
import Carbon
import Foundation
import SwiftUI

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32 = 9 // V
    var carbonModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    static var stored: Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "activationShortcut"),
              let value = try? JSONDecoder().decode(Shortcut.self, from: data) else { return Shortcut() }
        return value
    }
    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "activationShortcut")
    }
    var display: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + KeyNames.name(for: keyCode)
    }
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }
}

enum KeyNames {
    static func name(for code: UInt32) -> String {
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`",36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",123:"←",124:"→",125:"↓",126:"↑"]
        return names[code] ?? "Key \(code)"
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    var onActivate: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x504E5854, id: 1) // PNXT

    func register(_ shortcut: Shortcut = .stored) {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onActivate?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = { value in
            shortcut = value
            value.save()
            HotKeyManager.shared.register(value)
            isRecording = false
        }
        view.onCancel = { isRecording = false }
        return view
    }
    func updateNSView(_ view: RecorderView, context: Context) {
        view.recording = isRecording
        if isRecording { view.window?.makeFirstResponder(view) }
        view.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var onRecord: ((Shortcut) -> Void)?
    var onCancel: (() -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if recording { window?.makeFirstResponder(self) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        guard let shortcut = Shortcut.from(event) else { NSSound.beep(); return }
        onRecord?(shortcut)
    }
}

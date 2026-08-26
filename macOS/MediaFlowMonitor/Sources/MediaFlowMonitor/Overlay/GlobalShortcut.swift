import AppKit
import Carbon.HIToolbox

/// Înregistrează Cmd+Shift+M ca hotkey global (Carbon HotKey API —
/// funcționează chiar și fără accessibility permissions, spre deosebire
/// de NSEvent global monitor).
final class GlobalShortcut {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register()
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: OSType("MFMM".fourCharCode), id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 0x2E // 'M'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            shortcut.onTrigger()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    deinit { unregister() }
}

private extension String {
    var fourCharCode: FourCharCode {
        utf8.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}

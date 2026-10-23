import Carbon

/// System-wide keyboard shortcuts through Carbon, which needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    var isEmpty: Bool { references.isEmpty }

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(actions.count + 1)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E42_4559), id: id) // "NBEY"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return }
        references.append(reference)
        actions[id] = action
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}

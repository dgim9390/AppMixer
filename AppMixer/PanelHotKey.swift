import Carbon.HIToolbox
import os

/// ⌃⌥X 전역 단축키. Carbon 단축키 API는 키 위치로 인식해 입력 소스와 무관하고, 손쉬운 사용 권한이 필요 없다.
@MainActor
enum PanelHotKey {
    private static var action: (() -> Void)?

    static func install(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { PanelHotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef? // 앱이 살아 있는 동안 유지하므로 해제하지 않는다
        let id = EventHotKeyID(signature: OSType(0x414D_5852), id: 1) // "AMXR"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_X), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Logger(subsystem: "com.dgim9390.AppMixer", category: "hotkey").error("단축키 등록 실패: \(status)")
        }
    }
}

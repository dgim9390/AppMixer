import ServiceManagement
import os

/// 로그인 시 자동 실행. SMAppService는 macOS 13+의 공식 로그인 항목 API.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Logger(subsystem: "com.dgim9390.AppMixer", category: "login").error("로그인 항목 변경 실패: \(error)")
        }
        // 사용자가 시스템 설정에서 직접 허용해야 하는 경우 그 화면을 연다
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

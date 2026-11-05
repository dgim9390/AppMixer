import CoreAudio
import AudioToolbox

/// 실제 엔진 (Process Tap 방식). 지금은 빈 껍데기라 아무 소리도 바꾸지 않는다.
/// Core Audio C API는 Swift에서 바로 호출하므로 브릿징 헤더는 없다 (README §6).
@MainActor
final class CoreAudioEngine: AudioEngine {
    private(set) var masterVolume: Float = 0
    private(set) var isMasterMuted = false
    private(set) var apps: [AudioApp] = []
    var onChange: (() -> Void)?

    // 4단계: 기본 출력 장치(kAudioHardwarePropertyDefaultOutputDevice)의
    // kAudioHardwareServiceDeviceProperty_VirtualMainVolume / kAudioDevicePropertyMute 읽기·쓰기 + 변경 리스너
    func setMasterVolume(_ volume: Float) {}
    func setMasterMuted(_ muted: Bool) {}

    // 5단계: kAudioHardwarePropertyProcessObjectList + kAudioProcessPropertyIsRunningOutput 리스너로 apps 갱신

    // 6단계: 앱별 CATapDescription(.mutedWhenTapped) → AudioHardwareCreateProcessTap
    // → aggregate 장치 → IOProc에서 gain 곱하기. 볼륨 100%이고 음소거가 아니면 탭을 없앤다.
    func setVolume(_ volume: Float, for app: AudioApp.ID) {}
    func setMuted(_ muted: Bool, for app: AudioApp.ID) {}
}

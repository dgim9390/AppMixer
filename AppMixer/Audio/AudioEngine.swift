import Foundation

struct AudioApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleID: String?
    var volume: Float // 0.0 ... 1.0
    var isMuted: Bool // volume과 별개라서 음소거를 풀면 이전 볼륨이 그대로 남아 있음
}

/// UI는 이 프로토콜만 안다. 구현체(Mock / Core Audio)는 AppMixerApp에서 주입.
@MainActor
protocol AudioEngine: AnyObject {
    var masterVolume: Float { get }
    var isMasterMuted: Bool { get }
    var apps: [AudioApp] { get }
    /// 앱 목록이나 외부(볼륨 키 등) 변경이 생기면 호출. 메인 스레드에서 호출할 것.
    var onChange: (() -> Void)? { get set }

    func setMasterVolume(_ volume: Float)
    func setMasterMuted(_ muted: Bool)
    func setVolume(_ volume: Float, for app: AudioApp.ID)
    func setMuted(_ muted: Bool, for app: AudioApp.ID)
}

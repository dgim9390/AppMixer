import Foundation

/// 메모리에만 상태를 두는 가짜 엔진. 실제 소리는 바뀌지 않는다.
@MainActor
final class MockAudioEngine: AudioEngine {
    private(set) var masterVolume: Float = 0.5
    private(set) var isMasterMuted = false
    private(set) var apps: [AudioApp] = [
        AudioApp(id: 101, name: "Spotify", bundleID: "com.spotify.client", volume: 0.8, isMuted: false),
        AudioApp(id: 102, name: "Safari", bundleID: "com.apple.Safari", volume: 0.6, isMuted: false),
        AudioApp(id: 103, name: "Discord", bundleID: "com.hnc.Discord", volume: 1.0, isMuted: false),
    ]
    var onChange: (() -> Void)?

    func setMasterVolume(_ volume: Float) { masterVolume = volume }
    func setMasterMuted(_ muted: Bool) { isMasterMuted = muted }

    func setVolume(_ volume: Float, for app: AudioApp.ID) {
        if let i = apps.firstIndex(where: { $0.id == app }) { apps[i].volume = volume }
    }

    func setMuted(_ muted: Bool, for app: AudioApp.ID) {
        if let i = apps.firstIndex(where: { $0.id == app }) { apps[i].isMuted = muted }
    }
}

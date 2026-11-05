import Observation

@MainActor
@Observable
final class MixerViewModel {
    private(set) var masterVolume: Float = 0
    private(set) var isMasterMuted = false
    private(set) var apps: [AudioApp] = []

    @ObservationIgnored private let engine: any AudioEngine

    init(engine: any AudioEngine) {
        self.engine = engine
        engine.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func setMasterVolume(_ volume: Float) {
        engine.setMasterVolume(clamp(volume))
        refresh()
    }

    func toggleMasterMute() {
        engine.setMasterMuted(!isMasterMuted)
        refresh()
    }

    func setVolume(_ volume: Float, for app: AudioApp.ID) {
        engine.setVolume(clamp(volume), for: app)
        refresh()
    }

    func toggleMute(for app: AudioApp.ID) {
        guard let current = apps.first(where: { $0.id == app }) else { return }
        engine.setMuted(!current.isMuted, for: app)
        refresh()
    }

    private func refresh() {
        masterVolume = engine.masterVolume
        isMasterMuted = engine.isMasterMuted
        apps = engine.apps
    }

    private func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }
}

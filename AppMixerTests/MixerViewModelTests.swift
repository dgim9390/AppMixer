import Testing
@testable import AppMixer

@MainActor
struct MixerViewModelTests {
    @Test func muteKeepsVolumeAndUnmuteRestoresIt() {
        let vm = MixerViewModel(engine: MockAudioEngine())
        let id = vm.apps[0].id

        vm.setVolume(0.3, for: id)
        vm.toggleMute(for: id)
        #expect(vm.apps[0].isMuted)
        #expect(vm.apps[0].volume == 0.3)

        vm.toggleMute(for: id)
        #expect(!vm.apps[0].isMuted)
        #expect(vm.apps[0].volume == 0.3)
    }

    @Test func realEngineShellPlugsIn() {
        let vm = MixerViewModel(engine: CoreAudioEngine())
        #expect(vm.apps.isEmpty)
    }

    @Test func masterVolumeAndMute() {
        let vm = MixerViewModel(engine: MockAudioEngine())
        vm.setMasterVolume(1.5)
        #expect(vm.masterVolume == 1)
        vm.toggleMasterMute()
        #expect(vm.isMasterMuted)
    }
}

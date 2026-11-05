import SwiftUI

@main
struct AppMixerApp: App {
    // 엔진 교체 지점: MockAudioEngine() ↔ CoreAudioEngine()
    @State private var viewModel = MixerViewModel(engine: MockAudioEngine())

    var body: some Scene {
        MenuBarExtra("AppMixer", systemImage: "slider.horizontal.3") {
            MixerView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

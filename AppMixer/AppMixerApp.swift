import SwiftUI

@main
struct AppMixerApp: App {
    // 엔진 교체 지점: CoreAudioEngine() ↔ MockAudioEngine() (UI만 볼 때)
    @State private var viewModel = MixerViewModel(engine: CoreAudioEngine())

    var body: some Scene {
        MenuBarExtra("AppMixer", systemImage: "slider.horizontal.3") {
            MixerView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

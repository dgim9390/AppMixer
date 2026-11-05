import SwiftUI

struct MixerView: View {
    let viewModel: MixerViewModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VolumeRow(
                title: "마스터",
                icon: Image(systemName: "hifispeaker.fill"),
                volume: viewModel.masterVolume,
                isMuted: viewModel.isMasterMuted,
                onVolumeChange: viewModel.setMasterVolume,
                onToggleMute: viewModel.toggleMasterMute
            )
            Divider()
            if viewModel.apps.isEmpty {
                Text("소리를 내는 앱이 없습니다").foregroundStyle(.secondary)
            }
            ForEach(viewModel.apps) { app in
                VolumeRow(
                    title: app.name,
                    icon: appIcon(bundleID: app.bundleID),
                    volume: app.volume,
                    isMuted: app.isMuted,
                    onVolumeChange: { viewModel.setVolume($0, for: app.id) },
                    onToggleMute: { viewModel.toggleMute(for: app.id) }
                )
            }
            Divider()
            HStack {
                Toggle("로그인 시 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { LoginItem.setEnabled($0); launchAtLogin = LoginItem.isEnabled }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                // Dock 아이콘이 없는 앱이라 여기 말고는 종료할 방법이 없다
                Button("AppMixer 종료") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}

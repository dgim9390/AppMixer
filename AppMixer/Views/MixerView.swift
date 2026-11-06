import SwiftUI

struct MixerView: View {
    let viewModel: MixerViewModel
    @State private var launchAtLogin = LoginItem.isEnabled
    /// 키보드로 조절할 행. 0 = 마스터, 1... = apps 순서
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VolumeRow(
                title: "Main",
                icon: Image(systemName: "speaker.wave.3.fill"),
                volume: viewModel.masterVolume,
                isMuted: viewModel.isMasterMuted,
                onVolumeChange: viewModel.setMasterVolume,
                onToggleMute: viewModel.toggleMasterMute
            )
            .selectable(currentRow == 0) { select(0) }
            Divider()
            if viewModel.apps.isEmpty {
                Text("소리를 내는 앱이 없습니다").foregroundStyle(.secondary)
            }
            ForEach(Array(viewModel.apps.enumerated()), id: \.element.id) { index, app in
                VolumeRow(
                    title: app.name,
                    icon: appIcon(bundleID: app.bundleID),
                    volume: app.volume,
                    isMuted: app.isMuted,
                    onVolumeChange: { viewModel.setVolume($0, for: app.id) },
                    onToggleMute: { viewModel.toggleMute(for: app.id) }
                )
                .selectable(currentRow == index + 1) { select(index + 1) }
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
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        // ←→ 1%, Cmd+←→ 5%. Ctrl+←→는 macOS 기본값이 데스크탑 전환이라 쓰지 않는다.
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            let step: Float = press.modifiers.contains(.command) ? 0.05 : 0.01
            switch press.key {
            case .upArrow: select(currentRow - 1)
            case .downArrow: select(currentRow + 1)
            case .leftArrow: nudge(-step)
            default: nudge(step)
            }
            return .handled
        }
    }

    /// 앱 목록이 줄어도 범위를 벗어나지 않게
    private var currentRow: Int { min(selected, viewModel.apps.count) }

    private func select(_ row: Int) {
        selected = min(max(row, 0), viewModel.apps.count)
        focused = true
    }

    private func nudge(_ delta: Float) {
        if currentRow == 0 {
            if !viewModel.isMasterMuted { viewModel.setMasterVolume(viewModel.masterVolume + delta) }
        } else {
            let app = viewModel.apps[currentRow - 1]
            if !app.isMuted { viewModel.setVolume(app.volume + delta, for: app.id) }
        }
    }
}

private extension View {
    /// 선택된 행 배경 강조 + 클릭으로 선택
    func selectable(_ isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onTapGesture(perform: onSelect)
            .padding(.horizontal, -6)
    }
}

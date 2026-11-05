import SwiftUI

/// 아이콘 · 이름 · 슬라이더 · 음소거 버튼 한 줄. 마스터와 앱 행이 같이 쓴다.
struct VolumeRow: View {
    let title: String
    let icon: Image
    let volume: Float
    let isMuted: Bool
    let onVolumeChange: (Float) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            icon.resizable().scaledToFit().frame(width: 20, height: 20)
            Text(title).lineLimit(1).frame(width: 110, alignment: .leading)
            TickSlider(value: volume, onChange: onVolumeChange)
                .disabled(isMuted)
                .opacity(isMuted ? 0.4 : 1)
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(isMuted ? "음소거 해제" : "음소거")
            .accessibilityLabel(isMuted ? "\(title) 음소거 해제" : "\(title) 음소거")
        }
    }
}

/// 25%마다 눈금이 있는 슬라이더. SwiftUI Slider는 눈금을 넣으면 그 값에만 멈춰서 NSSlider를 쓴다.
struct TickSlider: NSViewRepresentable {
    let value: Float
    let onChange: (Float) -> Void

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = 5
        slider.refusesFirstResponder = true // 방향키는 패널의 행 선택이 받는다
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        slider.floatValue = value
        slider.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject {
        var onChange: (Float) -> Void
        init(onChange: @escaping (Float) -> Void) { self.onChange = onChange }
        @MainActor @objc func changed(_ slider: NSSlider) { onChange(slider.floatValue) }
    }
}

/// 설치된 앱이면 실제 아이콘, 아니면 SF Symbol. Core Audio와 무관한 AppKit 조회.
func appIcon(bundleID: String?) -> Image {
    if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }
    return Image(systemName: "app.fill")
}

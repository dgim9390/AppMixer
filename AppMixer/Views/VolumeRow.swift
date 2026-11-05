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
            Slider(value: Binding(get: { volume }, set: { onVolumeChange($0) }), in: 0...1)
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

/// 설치된 앱이면 실제 아이콘, 아니면 SF Symbol. Core Audio와 무관한 AppKit 조회.
func appIcon(bundleID: String?) -> Image {
    if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }
    return Image(systemName: "app.fill")
}

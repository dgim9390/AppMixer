import AppKit
import SwiftUI

@main
@MainActor
enum AppMixerApp {
    static func main() {
        let app = NSApplication.shared
        // 엔진 교체 지점: CoreAudioEngine() ↔ MockAudioEngine() (UI만 볼 때)
        let panel = MenuBarPanel(viewModel: MixerViewModel(engine: CoreAudioEngine()))
        PanelHotKey.install { panel.toggle() }
        withExtendedLifetime(panel) { app.run() }
    }
}

/// 메뉴바 아이콘과 패널. MenuBarExtra는 코드로 패널을 여는 API가 없어서 단축키를 쓰려면 AppKit으로 직접 만들어야 한다.
@MainActor
final class MenuBarPanel: NSObject {
    private let viewModel: MixerViewModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
        super.init()
        popover.behavior = .transient // 바깥을 클릭하면 닫힌다
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "AppMixer")
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: .leftMouseDown) // 마우스를 뗄 때 동작하면 바깥 클릭으로 닫힌 패널이 다시 열린다
        }
    }

    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        // 열 때마다 새로 만들어서 첫 행 선택과 키보드 포커스가 항상 처음 상태로 시작한다
        let content = NSHostingController(rootView: MixerView(viewModel: viewModel))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        content.view.window?.makeKey()
    }
}

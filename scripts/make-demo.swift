// README용 데모 GIF(docs/demo.gif) 생성. 실제 MixerView에 가짜 엔진을 연결하므로 시스템 볼륨, 저장된 설정, 오디오를 건드리지 않는다.
// 빌드: swiftc -parse-as-library -o /tmp/make-demo scripts/make-demo.swift AppMixer/Audio/AudioEngine.swift AppMixer/MixerViewModel.swift AppMixer/LoginItem.swift AppMixer/Views/*.swift
// 실행: /tmp/make-demo docs/demo.gif [프레임 PNG 폴더]
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DemoEngine: AudioEngine {
    var masterVolume: Float = 0.7
    var isMasterMuted = false
    var apps = [
        AudioApp(id: 1, name: "Google Chrome", bundleID: "com.google.Chrome", volume: 0.8, isMuted: false),
        AudioApp(id: 2, name: "Music", bundleID: "com.apple.Music", volume: 0.6, isMuted: false),
        AudioApp(id: 3, name: "Safari", bundleID: "com.apple.Safari", volume: 1, isMuted: false),
    ]
    var onChange: (() -> Void)?
    func setMasterVolume(_ volume: Float) { masterVolume = volume }
    func setMasterMuted(_ muted: Bool) { isMasterMuted = muted }
    func setVolume(_ volume: Float, for app: AudioApp.ID) { apps[Int(app) - 1].volume = volume }
    func setMuted(_ muted: Bool, for app: AudioApp.ID) { apps[Int(app) - 1].isMuted = muted }
}

/// 앱을 활성화하지 않고도 활성 창처럼 그려지고 키 입력을 받게 한다.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@main
struct MakeDemo {
    @MainActor static func main() {
        let args = CommandLine.arguments
        NSApplication.shared.setActivationPolicy(.accessory)
        let vm = MixerViewModel(engine: DemoEngine())
        let host = NSHostingView(rootView: MixerView(viewModel: vm).background(Color(white: 0.13)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame.size = NSSize(width: ceil(host.fittingSize.width), height: floor(host.fittingSize.height))
        let window = KeyWindow(contentRect: NSRect(x: -5000, y: -5000, width: host.frame.width, height: host.frame.height),
                               styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.13, alpha: 1)
        window.contentView = host
        window.orderFrontRegardless()
        window.makeKey()
        spin(0.3)

        var frames: [(CGImage, Double)] = []
        func capture(_ caption: String, delay: Double = 0.08) {
            spin(0.04)
            window.displayIfNeeded()
            frames.append((render(host, caption: caption), delay))
        }
        func press(_ code: UInt16, _ text: String, cmd: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: cmd ? [.command, .numericPad, .function] : [.numericPad, .function],
                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                         characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            window.sendEvent(event)
        }
        let (down, left, right) = (UInt16(125), UInt16(123), UInt16(124))
        let (dn, lf, rt) = ("\u{F701}", "\u{F702}", "\u{F703}")

        capture("Click the menu bar icon to open the panel", delay: 1.4)
        press(down, dn); capture("↓  Select a row", delay: 0.9)
        for _ in 0..<8 { press(left, lf); capture("←  1% at a time") }
        capture("←  1% at a time", delay: 0.6)
        for _ in 0..<5 { press(left, lf, cmd: true); capture("⌘ ←  5% at a time", delay: 0.22) }
        capture("⌘ ←  5% at a time", delay: 0.6)
        press(down, dn); capture("↓  Select a row", delay: 0.9)
        for _ in 0..<4 { press(right, rt, cmd: true); capture("⌘ →  5% at a time", delay: 0.22) }
        capture("⌘ →  5% at a time", delay: 0.6)
        for i in 1...12 { vm.setVolume(1 - 0.05 * Float(i), for: 3); capture("Drag a slider") }
        capture("Drag a slider", delay: 0.6)
        vm.toggleMute(for: 3); capture("Mute an app", delay: 1.1)
        vm.toggleMute(for: 3); capture("Unmute: the previous volume comes back", delay: 1.6)

        let url = URL(fileURLWithPath: args[1]) as CFURL
        let gif = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("GIF 저장 실패") }
        if args.count > 2 {
            for i in [0, 1, 6, 12, 20, 28, 40, frames.count - 2, frames.count - 1] where i < frames.count {
                let rep = NSBitmapImageRep(cgImage: frames[i].0)
                try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(args[2])/f\(i).png"))
            }
        }
        print("프레임 \(frames.count)개")
    }

    @MainActor static func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// 패널 아래에 지금 하는 동작 설명을 붙인 2배 해상도 프레임 한 장
    @MainActor static func render(_ view: NSView, caption: String) -> CGImage {
        let scale = 2
        func bitmap(_ size: NSSize) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            return rep
        }
        let panel = bitmap(view.bounds.size)
        view.cacheDisplay(in: view.bounds, to: panel)

        let captionHeight: CGFloat = 34
        let frame = bitmap(NSSize(width: view.bounds.width, height: view.bounds.height + captionHeight))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: frame)
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(origin: .zero, size: frame.size).fill()
        panel.draw(in: NSRect(x: 0, y: captionHeight, width: view.bounds.width, height: view.bounds.height))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: caption, attributes: attrs)
        text.draw(at: NSPoint(x: (frame.size.width - text.size().width) / 2, y: 10))
        NSGraphicsContext.restoreGraphicsState()
        return frame.cgImage!
    }
}

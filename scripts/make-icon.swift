// 앱 아이콘을 그려 AppIcon.appiconset에 크기별 PNG로 저장한다.
// 사용: swift scripts/make-icon.swift
// SF Symbols는 라이선스상 앱 아이콘에 쓸 수 없어서 슬라이더를 직접 그린다.
import AppKit

let out = URL(fileURLWithPath: "AppMixer/Assets.xcassets/AppIcon.appiconset")

/// 1024 기준 좌표로 그리고, 크기별로 축소해서 다시 그린다 (작은 크기도 선명하게).
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixels) / 1024
    ctx.cgContext.scaleBy(x: s, y: s)

    // macOS 아이콘 격자: 1024 캔버스 안의 824 둥근 사각형 + 그림자
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(srgbRed: 0.33, green: 0.56, blue: 1.00, alpha: 1),
        ending: NSColor(srgbRed: 0.45, green: 0.30, blue: 0.95, alpha: 1)
    )!.draw(in: shape, angle: -60)

    // 슬라이더 3개: 트랙(반투명) + 채워진 부분 + 손잡이. AppKit 좌표는 아래에서부터.
    let left: CGFloat = 260, right: CGFloat = 764
    for (y, knobX) in [(684 as CGFloat, 620 as CGFloat), (512, 380), (340, 560)] {
        func bar(_ from: CGFloat, _ to: CGFloat, _ alpha: CGFloat) {
            NSColor(white: 1, alpha: alpha).setFill()
            NSBezierPath(roundedRect: NSRect(x: from - 22, y: y - 22, width: to - from + 44, height: 44), xRadius: 22, yRadius: 22).fill()
        }
        bar(left, right, 0.32)
        bar(left, knobX, 0.95)

        NSGraphicsContext.saveGraphicsState()
        let knobShadow = NSShadow()
        knobShadow.shadowColor = NSColor(white: 0, alpha: 0.25)
        knobShadow.shadowOffset = NSSize(width: 0, height: -6)
        knobShadow.shadowBlurRadius = 14
        knobShadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX - 62, y: y - 62, width: 124, height: 124)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try render(pixels: pixels).write(to: out.appendingPathComponent(name))
        images.append(#"{"idiom":"mac","size":"\#(points)x\#(points)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
let contents = #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
try contents.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try #"{"info":{"author":"xcode","version":1}}"#.write(
    to: out.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

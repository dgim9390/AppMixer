// DMG 창 배경을 그린다: 화살표 + 사용 안내. 1x/2x PNG를 만든 뒤 build.sh가 TIFF 하나로 합친다.
// 사용: swift dmg/make-background.swift <출력 폴더>
// 좌표는 dmg/settings.py의 창 크기·아이콘 위치와 맞춰야 한다.
import AppKit

let size = NSSize(width: 540, height: 360)
let iconY: CGFloat = 150 // Finder 기준(위에서부터) 아이콘 중심 y

func render(scale: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 중간 회색: Finder 아이콘 이름이 다크 모드(흰 글씨)와 라이트 모드(검은 글씨) 모두에서 읽힌다
    NSGradient(starting: NSColor(white: 0.47, alpha: 1), ending: NSColor(white: 0.40, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // 화살표: AppMixer(왼쪽) → Applications(오른쪽)
    let y = size.height - iconY
    NSColor(white: 1, alpha: 0.85).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 222, y: y))
    arrow.line(to: NSPoint(x: 318, y: y))
    arrow.move(to: NSPoint(x: 304, y: y + 12))
    arrow.line(to: NSPoint(x: 318, y: y))
    arrow.line(to: NSPoint(x: 304, y: y - 12))
    arrow.stroke()

    let center = NSMutableParagraphStyle()
    center.alignment = .center
    func text(_ s: String, _ font: NSFont, _ alpha: CGFloat, top: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: center,
        ]
        NSString(string: s).draw(in: NSRect(x: 20, y: size.height - top - 22, width: size.width - 40, height: 22), withAttributes: attrs)
    }
    text("AppMixer를 Applications 폴더로 끌어다 놓으세요", .systemFont(ofSize: 15, weight: .semibold), 1, top: 252)
    text("처음 실행할 때 경고가 뜨면  시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기", .systemFont(ofSize: 12), 0.85, top: 286)
    text("실행 후 메뉴바의 슬라이더 아이콘을 클릭하면 볼륨 패널이 열립니다", .systemFont(ofSize: 12), 0.85, top: 308)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
render(scale: 1, to: out.appendingPathComponent("background.png"))
render(scale: 2, to: out.appendingPathComponent("background@2x.png"))

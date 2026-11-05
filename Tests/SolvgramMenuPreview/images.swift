import AppKit
import AVFoundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let asset = AVURLAsset(url: directory.appendingPathComponent("menu-walkthrough.mov"))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 400, height: 900)
let duration = try await asset.load(.duration).seconds
for seconds in [2.0, 5.5, 8.5, 11.5, 14.5, 23.5, 26.5] where seconds < duration {
    let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    let data = NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:])!
    try data.write(to: directory.appendingPathComponent("frame-\(seconds).png"))
}

func compose(names: [String], labels: [String], output: String, subtitle: String) throws {
    let width = 1320, height = 1180
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    let base = NSGraphicsContext(bitmapImageRep: bitmap)!
    let cg = base.cgContext
    let previousContext = NSGraphicsContext.current
    cg.saveGState()
    cg.translateBy(x: 0, y: CGFloat(height)); cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.97, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
    func text(_ string: String, _ point: CGPoint, _ font: NSFont, _ color: NSColor) {
        (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
    text("Solvgram · Настройки", CGPoint(x: 44, y: 32), .systemFont(ofSize: 32, weight: .bold), NSColor(calibratedWhite: 0.12, alpha: 1))
    text(subtitle, CGPoint(x: 44, y: 80), .systemFont(ofSize: 17), NSColor(calibratedWhite: 0.4, alpha: 1))
    for (index, name) in names.enumerated() {
        let x = 44.0 + Double(index) * 422.0
        text(labels[index], CGPoint(x: x, y: 126), .systemFont(ofSize: 18, weight: .semibold), NSColor(calibratedWhite: 0.12, alpha: 1))
        let image = NSImage(contentsOf: directory.appendingPathComponent(name))!
        let targetWidth = 388.0
        let targetHeight = min(970, targetWidth * image.size.height / image.size.width)
        let rect = CGRect(x: x, y: 166, width: targetWidth, height: targetHeight)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    cg.restoreGState()
    NSGraphicsContext.current = previousContext
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(output))
}
try compose(names: ["01-root-light.png", "02-privacy-on.png", "05-messages.png"],
    labels: ["Главное меню", "Карточка и выбор галочками", "Настройки без лишних иконок"],
    output: "overview.png", subtitle: "Реальные экраны UIKit · светлая тема")
try compose(names: ["03-privacy-off.png", "08-privacy-dark.png", "09-privacy-large-text.png"],
    labels: ["Режим выключен", "Тёмная тема", "Крупный системный шрифт"],
    output: "states.png", subtitle: "Проверка зависимых параметров и адаптации")
try compose(names: ["frame-5.5.png", "frame-8.5.png", "frame-11.5.png"],
    labels: ["Кадр · 5,5 с", "Кадр · 8,5 с", "Кадр · 11,5 с"],
    output: "recorded-frames.png", subtitle: "Кадры записи симулятора · проверка переходов")
print("Saved screenshot overviews and recorded frames.")

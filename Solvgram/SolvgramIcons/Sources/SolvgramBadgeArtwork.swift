import UIKit

public enum SolvgramBadgeArtwork {
    public static let ghost = "solvgram.badge.ghost"
    public static let none = "solvgram.badge.none"
    public static func normalized(_ value: String) -> String { value == none ? value : "Components/AppBadge" }
    public static func image(value: String, defaultImage: UIImage?) -> UIImage? {
        switch normalized(value) {
        case none: return nil
        default: return defaultImage
        }
    }
    public static func drawSettingsIcon(in context: CGContext) {
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(UIBezierPath(roundedRect: CGRect(x: 6, y: 10, width: 20, height: 12), cornerRadius: 6).cgPath)
        context.fillPath()
        context.restoreGState()
    }
    public static func microphone(active: Bool, color: UIColor) -> UIImage? {
        guard let symbol = UIImage(systemName: active ? "mic" : "mic.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)) else { return nil }
        let side = min(30, UIFontMetrics(forTextStyle: .body).scaledValue(for: 24))
        let visible = side * 20 / 24
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(visible / symbol.size.width, visible / symbol.size.height)
            let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: CGRect(x: (side-size.width)/2, y: (side-size.height)/2, width: size.width, height: size.height))
        }
    }
}

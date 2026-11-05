import UIKit
import AsyncDisplayKit
import Display
import MultiScaleTextNode
import InvisibleInkDustNode
import SGSimpleSettings

/// Uses Telegram's dust renderer, attached to each scaled text state so it
/// follows the profile header's existing transforms and crossfades.
final class SolvgramPhoneSpoiler {
    private var dust: [Int: InvisibleInkDustNode] = [:]

    func update(node: MultiScaleTextNode, range: NSRange?, revealed: Bool, color: UIColor) {
        for key in [0, 1] {
            guard let textNode = node.stateNode(forKey: key) as? ImmediateTextNode else { continue }
            if revealed {
                self.dust[key]?.update(revealed: true, animated: !UIAccessibility.isReduceMotionEnabled)
                continue
            }
            guard let range, let original = textNode.attributedText,
                  range.length > 0, NSMaxRange(range) <= original.length else {
                self.dust.removeValue(forKey: key)?.removeFromSupernode()
                continue
            }
            let text = NSMutableAttributedString(attributedString: original)
            let marker = NSAttributedString.Key("SolvgramPhoneSpoilerRange")
            text.addAttribute(marker, value: true, range: range)
            text.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
            textNode.attributedText = text
            let size = textNode.updateLayout(textNode.bounds.size)
            let rects = textNode.attributeRects(name: marker.rawValue, at: range.location) ?? []
            let dust: InvisibleInkDustNode
            if let current = self.dust[key] {
                dust = current
            } else {
                dust = InvisibleInkDustNode(textNode: nil, enableAnimations: !UIAccessibility.isReduceMotionEnabled)
                dust.isUserInteractionEnabled = false
                self.dust[key] = dust
                textNode.addSubnode(dust)
            }
            dust.frame = CGRect(origin: .zero, size: size)
            dust.update(revealed: false, animated: false)
            dust.update(size: size, color: color, textColor: color, rects: rects, wordRects: rects)
            textNode.accessibilityLabel = (original.string as NSString).replacingCharacters(in: range, with: SolvgramSettings.isRussian ? "Номер скрыт" : "Phone number hidden")
        }
    }
}

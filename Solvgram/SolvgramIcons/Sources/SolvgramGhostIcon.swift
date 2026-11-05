import UIKit

/// The approved Ghost Mode silhouette, shared by settings, the chat list and
/// chat quick settings. Coordinates match design/solvgram-icons/v8/ghost.svg.
public enum SolvgramGhostIcon {
    public static func draw(in context: CGContext, color: UIColor, outlined: Bool = false) {
        context.saveGState()
        if outlined {
            context.translateBy(x: 12.0, y: 12.0)
            context.scaleBy(x: 1.08, y: 1.0)
            context.translateBy(x: -12.0, y: -12.0)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4.5, y: 17.8))
        path.addLine(to: CGPoint(x: 4.5, y: 10))
        path.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 4.5, y: 5.8578644), control2: CGPoint(x: 7.8578644, y: 2.5))
        path.addCurve(to: CGPoint(x: 19.5, y: 10), control1: CGPoint(x: 16.1421356, y: 2.5), control2: CGPoint(x: 19.5, y: 5.8578644))
        path.addLine(to: CGPoint(x: 19.5, y: 17.8))
        path.addCurve(to: CGPoint(x: 17, y: 20.3), control1: CGPoint(x: 19.5, y: 19.1807119), control2: CGPoint(x: 18.3807119, y: 20.3))
        path.addCurve(to: CGPoint(x: 14.5, y: 17.8), control1: CGPoint(x: 15.6192881, y: 20.3), control2: CGPoint(x: 14.5, y: 19.1807119))
        path.addCurve(to: CGPoint(x: 12, y: 20.3), control1: CGPoint(x: 14.5, y: 19.1807119), control2: CGPoint(x: 13.3807119, y: 20.3))
        path.addCurve(to: CGPoint(x: 9.5, y: 17.8), control1: CGPoint(x: 10.6192881, y: 20.3), control2: CGPoint(x: 9.5, y: 19.1807119))
        path.addCurve(to: CGPoint(x: 7, y: 20.3), control1: CGPoint(x: 9.5, y: 19.1807119), control2: CGPoint(x: 8.3807119, y: 20.3))
        path.addCurve(to: CGPoint(x: 4.5, y: 17.8), control1: CGPoint(x: 5.6192881, y: 20.3), control2: CGPoint(x: 4.5, y: 19.1807119))
        path.closeSubpath()
        if outlined {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.25)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(path)
            context.strokePath()
        }
        let eyes = CGMutablePath()
        eyes.addEllipse(in: CGRect(x: 8.35, y: 8.7, width: 2.5, height: 3.6))
        eyes.addEllipse(in: CGRect(x: 13.15, y: 8.7, width: 2.5, height: 3.6))
        context.setFillColor(color.cgColor)
        if !outlined { context.addPath(path) }
        context.addPath(eyes)
        context.drawPath(using: outlined ? .fill : .eoFill)
        context.restoreGState()
    }

    public static func image(color: UIColor, side: CGFloat = 26, outlined: Bool = false) -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            renderer.cgContext.scaleBy(x: side / 24, y: side / 24)
            self.draw(in: renderer.cgContext, color: color, outlined: outlined)
        }
    }
}

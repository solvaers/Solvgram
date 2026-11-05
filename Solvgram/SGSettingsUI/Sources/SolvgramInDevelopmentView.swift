import UIKit
import SGSimpleSettings

/// Placeholder for screens whose server side is not available yet.
func solvgramInDevelopmentView(symbol: String) -> UIView {
    let ru = SolvgramSettings.isRussian
    let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)))
    icon.tintColor = .secondaryLabel
    icon.contentMode = .scaleAspectFit

    let title = UILabel()
    title.text = ru ? "В разработке" : "In Development"
    title.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
    title.adjustsFontForContentSizeCategory = true
    title.textAlignment = .center

    let subtitle = UILabel()
    subtitle.text = ru ? "Эта функция появится в одном из следующих обновлений." : "This feature will arrive in a future update."
    subtitle.font = .preferredFont(forTextStyle: .body)
    subtitle.adjustsFontForContentSizeCategory = true
    subtitle.textColor = .secondaryLabel
    subtitle.textAlignment = .center
    subtitle.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 10
    stack.setCustomSpacing(16, after: icon)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let container = UIView()
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
    ])
    return container
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = self.fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

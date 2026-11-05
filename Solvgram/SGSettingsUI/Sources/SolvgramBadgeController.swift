import UIKit
import SolvgramIcons
import SGSimpleSettings

/// A native destination in Solvgram's settings navigation stack.
final class SolvgramBadgeController: UIViewController {
    private var selection: String
    private let apply: (String) -> Void
    private var appearanceStyle: UIUserInterfaceStyle?
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    private let values = ["Components/AppBadge", SolvgramBadgeArtwork.none]
    init(selection: String, apply: @escaping (String) -> Void) {
        self.selection = SolvgramBadgeArtwork.normalized(selection)
        self.apply = apply
        super.init(nibName: nil, bundle: nil)
        self.navigationItem.backButtonDisplayMode = .minimal
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func text(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = text("App Badge", "Бейдж приложения")
        view.backgroundColor = .systemGroupedBackground
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24), stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        let names = ["Solvgram", text("No Badge", "Без бейджа")]
        for (index, name) in names.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            var configuration = UIButton.Configuration.plain()
            button.accessibilityLabel = name
            configuration.baseForegroundColor = .label
            configuration.titleAlignment = .center
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var result = incoming
                result.foregroundColor = UIColor.label
                result.font = UIFont.preferredFont(forTextStyle: .headline)
                return result
            }
            button.configuration = configuration
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.layer.cornerRadius = 28
            button.layer.borderWidth = 0
            button.clipsToBounds = true
            button.layer.cornerCurve = .circular
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            let effect: UIVisualEffect
            if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
                let glass = UIGlassEffect(style: .regular); glass.isInteractive = true; effect = glass
            } else { effect = UIBlurEffect(style: .systemMaterial) }
            let background = UIVisualEffectView(effect: effect)
            background.contentView.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits).withAlphaComponent(0.75) : .clear
            }
            background.isUserInteractionEnabled = false; background.translatesAutoresizingMaskIntoConstraints = false
            background.layer.cornerRadius = 28; background.clipsToBounds = true
            button.insertSubview(background, at: 0)
            NSLayoutConstraint.activate([background.leadingAnchor.constraint(equalTo: button.leadingAnchor), background.trailingAnchor.constraint(equalTo: button.trailingAnchor), background.topAnchor.constraint(equalTo: button.topAnchor), background.bottomAnchor.constraint(equalTo: button.bottomAnchor)])
            let thumbnail = UIImageView(); thumbnail.contentMode = .scaleAspectFit; thumbnail.tintColor = .label; thumbnail.translatesAutoresizingMaskIntoConstraints = false
            let isNone = values[index] == SolvgramBadgeArtwork.none
            thumbnail.image = (isNone ? UIImage(systemName: "minus.circle") : SolvgramBadgeArtwork.image(value: values[index], defaultImage: UIImage(named: "Components/AppBadge")))?.withRenderingMode(isNone ? .alwaysTemplate : .alwaysOriginal)
            button.addSubview(thumbnail)
            NSLayoutConstraint.activate([thumbnail.centerXAnchor.constraint(equalTo: button.centerXAnchor), thumbnail.centerYAnchor.constraint(equalTo: button.centerYAnchor), thumbnail.widthAnchor.constraint(equalToConstant: isNone ? 28 : (thumbnail.image?.size.width ?? 94)), thumbnail.heightAnchor.constraint(equalToConstant: 28)])
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tag = 800; check.tintColor = .label; check.contentMode = .scaleAspectFit; check.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(check)
            NSLayoutConstraint.activate([check.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -18), check.centerYAnchor.constraint(equalTo: button.centerYAnchor), check.widthAnchor.constraint(equalToConstant: 16), check.heightAnchor.constraint(equalToConstant: 16)])
            button.addTarget(self, action: #selector(selectBadge(_:)), for: .touchUpInside)
            buttons.append(button); stack.addArrangedSubview(button)
        }
        let help = UILabel(); help.numberOfLines = 0; help.font = .preferredFont(forTextStyle: .footnote); help.adjustsFontForContentSizeCategory = true; help.textColor = .secondaryLabel
        help.text = text("The badge appears at the top of Solvgram. Your choice is applied immediately and saved.", "Бейдж отображается в верхней части Solvgram. Выбор применяется сразу и сохраняется.")
        stack.addArrangedSubview(help)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        accessibilityChanged()
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func accessibilityChanged() {
        let effect: UIVisualEffect?
        if UIAccessibility.isReduceTransparencyEnabled { effect = nil }
        else if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.6)
            effect = glass
        }
        else { effect = UIBlurEffect(style: .systemMaterial) }
        for button in buttons { (button.subviews.first(where: { $0 is UIVisualEffectView }) as? UIVisualEffectView)?.effect = effect }
        refresh()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if appearanceStyle != traitCollection.userInterfaceStyle {
            appearanceStyle = traitCollection.userInterfaceStyle
            accessibilityChanged()
        }
        stack.layoutIfNeeded()
        for button in buttons {
            let radius = button.bounds.height / 2
            button.layer.cornerRadius = radius
            for background in button.subviews.compactMap({ $0 as? UIVisualEffectView }) {
                background.layer.cornerRadius = radius
                background.layer.cornerCurve = .circular
            }
        }
    }
    @objc private func selectBadge(_ sender: UIButton) {
        let value = values[sender.tag]
        guard value != selection else { return }
        selection = value; apply(value)
        UISelectionFeedbackGenerator().selectionChanged()
        refresh()
    }
    private func refresh() {
        for (index, button) in buttons.enumerated() {
            let selected = values[index] == selection
            button.backgroundColor = UIAccessibility.isReduceTransparencyEnabled ? .secondarySystemGroupedBackground : .clear
            button.viewWithTag(800)?.isHidden = !selected
            button.tintColor = .label
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}

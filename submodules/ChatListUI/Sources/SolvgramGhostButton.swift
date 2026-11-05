import Foundation
import UIKit
import Display
import TelegramPresentationData
import ChatListHeaderComponent
import SGSimpleSettings
import SolvgramIcons

// MARK: Solvgram — the chat list's Ghost Mode switch, in its own glass circle next to Edit
// (ChatListHeaderComponent shows SolvgramChatListAccessory.view there). The same
// ghost silhouette is used throughout Solvgram; its tint indicates the state.

final class SolvgramGhostButton: UIButton {
    static let ghostModeKey = SolvgramSettings.Key.ghostMode

    private let iconView = UIImageView()
    var ghostToggled: ((Bool) -> Void)?

    private var textColor: UIColor = .white
    private var accentColor: UIColor = .systemBlue
    private var displayedState: (isOn: Bool, color: UIColor)?
    private var defaultsObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.iconView.isUserInteractionEnabled = false
        self.iconView.contentMode = .center
        self.addSubview(self.iconView)
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)

        // Ghost Mode also changes from the Solvgram menu.
        self.defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateIcon()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let defaultsObserver = self.defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            self.iconView.alpha = self.isHighlighted ? 0.55 : 1.0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.iconView.frame = self.bounds
    }

    private var isGhostModeOn: Bool {
        return UserDefaults.standard.bool(forKey: SolvgramGhostButton.ghostModeKey)
    }

    func update(textColor: UIColor, accentColor: UIColor, accessibilityLabel: String) {
        self.textColor = textColor
        self.accentColor = accentColor
        self.accessibilityLabel = accessibilityLabel
        self.updateIcon()
    }

    private func updateIcon() {
        let isOn = self.isGhostModeOn
        let color = isOn ? self.accentColor : self.textColor
        if let displayedState = self.displayedState, displayedState.isOn == isOn, displayedState.color.isEqual(color) {
            return
        }
        let animated = !UIAccessibility.isReduceMotionEnabled && self.displayedState != nil && self.displayedState?.isOn != isOn
        self.displayedState = (isOn, color)
        let image = SolvgramGhostIcon.image(color: color, outlined: true)
        if animated {
            UIView.transition(with: self.iconView, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.iconView.image = image
            })
        } else {
            self.iconView.image = image
        }
        self.accessibilityTraits = isOn ? [.button, .selected] : [.button]
    }

    @objc private func pressed() {
        let isOn = !self.isGhostModeOn
        UserDefaults.standard.set(isOn, forKey: SolvgramGhostButton.ghostModeKey)
        self.updateIcon()
        UISelectionFeedbackGenerator().selectionChanged()
        self.ghostToggled?(isOn)
    }
}

// Each chat list header makes its own button (see SolvgramChatListAccessory); they share the theme it is given
// and the toggle action, which shows the toast in the root chat list.
private var solvgramGhostToggled: ((Bool) -> Void)?

func solvgramUpdateChatListGhostButton(presentationData: PresentationData, ghostToggled: @escaping (Bool) -> Void) {
    solvgramGhostToggled = ghostToggled
    if SolvgramChatListAccessory.makeView != nil {
        return
    }
    SolvgramChatListAccessory.makeView = {
        let button = SolvgramGhostButton(frame: CGRect(origin: CGPoint(), size: CGSize(width: 44.0, height: 44.0)))
        button.ghostToggled = { isOn in
            solvgramGhostToggled?(isOn)
        }
        return button
    }
    SolvgramChatListAccessory.updateView = { view, theme, _ in
        guard let button = view as? SolvgramGhostButton else {
            return
        }
        let isRussian = SolvgramSettings.isRussian
        button.update(
            textColor: theme.rootController.navigationBar.primaryTextColor,
            accentColor: theme.rootController.navigationBar.accentTextColor,
            accessibilityLabel: isRussian ? "Режим призрака" : "Ghost Mode"
        )
    }
}

import UIKit

/// The settings header selects the same alternate icons as Telegram's Appearance screen.
final class SolvgramAppIconHeaderView: UIView, UIScrollViewDelegate {
    private struct Icon {
        let name: String
        let en: String
        let ru: String
        var alternateName: String? { self.name == "SolvDefault" ? nil : self.name }
    }
    private static let allIcons = [
        Icon(name: "SolvDefault", en: "Default", ru: "Стандартная"),
        Icon(name: "SolvBlackBlue", en: "Dark", ru: "Тёмная"),
        Icon(name: "SolvBlue", en: "Blue", ru: "Синяя"),
        Icon(name: "SolvSilver", en: "Silver", ru: "Серебряная"),
        Icon(name: "SolvBlack", en: "Black", ru: "Чёрная"),
        Icon(name: "SolvWhite", en: "White", ru: "Белая"),
    ]
    private var icons: [Icon] = []
    private let scene = SolvgramIconScene()
    private let sceneViewport = SolvgramIconViewport()
    private var edgeFade: CAGradientLayer { self.sceneViewport.edgeFade }
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let pages = UIPageControl()
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private let images = (-2...2).map { _ in UIImageView() }
    private var index = 0
    private var russian = false
    private var initialized = false
    private var lastObservedName: String?
    private var dragging = false
    private var coasting = false
    private var scrollingToSelection = false
    private var scrollTarget: Int?
    private var redirectingScroll = false
    private var pendingSelection = false
    private var applyingName: String?
    private var applying = false
    private var idleApply: DispatchWorkItem?
    private var geometryWidth: CGFloat = 0
    private var itemSpacing: CGFloat = 112
    private var lastFeedbackSlot: Int?
    private var suppressFeedback = false
    private let slotCount = 600
    private var imageCache: [String: UIImage] = [:]
    private var failed = false
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private(set) var activeName: String?
    private var onSelect: ((String?, @escaping (Bool) -> Void) -> Void)?
    private var moving: Bool { self.dragging || self.coasting || self.scrollingToSelection || self.scene.isTracking || self.scene.isDecelerating }
    private var selectedName: String? { self.icons[self.index].alternateName }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.scene.clipsToBounds = true
        // Mask a stationary viewport, not the scrolling layer: the mist must
        // stay at the edges even as the scroll view's bounds origin changes.
        self.scene.translatesAutoresizingMaskIntoConstraints = false
        self.sceneViewport.addSubview(self.scene)
        NSLayoutConstraint.activate([
            self.scene.topAnchor.constraint(equalTo: self.sceneViewport.topAnchor),
            self.scene.bottomAnchor.constraint(equalTo: self.sceneViewport.bottomAnchor),
            self.scene.leadingAnchor.constraint(equalTo: self.sceneViewport.leadingAnchor),
            self.scene.trailingAnchor.constraint(equalTo: self.sceneViewport.trailingAnchor),
        ])
        self.scene.onLayout = { [weak self] in self?.updateGeometry() }
        self.scene.delegate = self
        self.scene.decelerationRate = .normal
        self.scene.isDirectionalLockEnabled = true
        self.scene.showsHorizontalScrollIndicator = false
        self.scene.showsVerticalScrollIndicator = false
        self.scene.alwaysBounceVertical = false
        self.scene.contentInsetAdjustmentBehavior = .never
        self.scene.isAccessibilityElement = true
        self.scene.accessibilityTraits = .adjustable
        self.scene.adjust = { [weak self] direction in
            guard let self else { return }
            self.selectIcon(at: self.wrapped(self.index + direction))
        }
        for image in self.images {
            image.bounds = CGRect(x: 0, y: 0, width: 116, height: 116)
            image.contentMode = .scaleAspectFill
            image.layer.cornerRadius = 26
            image.layer.cornerCurve = .continuous
            image.clipsToBounds = true
            image.isAccessibilityElement = false
            self.scene.addSubview(image)
        }
        self.scene.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:))))
        for label in [self.titleLabel, self.authorLabel, self.statusLabel, self.hintLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        self.titleLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle).withTraits(.traitBold)
        self.authorLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.authorLabel.text = "by solvaer's"
        self.authorLabel.textColor = .secondaryLabel
        self.statusLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.statusLabel.textColor = .secondaryLabel
        self.hintLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        self.hintLabel.textColor = .secondaryLabel
        self.pages.currentPageIndicatorTintColor = .label
        self.pages.pageIndicatorTintColor = .tertiaryLabel
        self.pages.allowsContinuousInteraction = false
        self.pages.addTarget(self, action: #selector(self.pageChanged), for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [self.sceneViewport, self.titleLabel, self.authorLabel, self.pages, self.statusLabel, self.hintLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(14, after: self.sceneViewport)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            self.sceneViewport.heightAnchor.constraint(equalToConstant: 158),
            stack.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { self.idleApply?.cancel() }

    func update(title: String, isRussian: Bool, getActiveName: () -> String?, availableNames: [String], onSelect: @escaping (String?, @escaping (Bool) -> Void) -> Void) {
        self.onSelect = onSelect
        self.russian = isRussian
        self.titleLabel.text = title
        self.hintLabel.text = isRussian ? "Смахните, чтобы сменить иконку" : "Swipe to change the app icon"
        self.scene.accessibilityLabel = isRussian ? "Иконка приложения" : "App icon"
        self.scene.accessibilityHint = isRussian ? "Смахните вверх или вниз, чтобы выбрать другую" : "Swipe up or down to select another icon"
        self.pages.accessibilityLabel = self.scene.accessibilityLabel
        guard !self.moving && !self.pendingSelection && !self.applying else {
            self.refreshStatus()
            return
        }
        let activeName = getActiveName()
        let observed = activeName == "SolvDefault" ? nil : activeName
        let observedChanged = !self.initialized || self.lastObservedName != observed
        self.lastObservedName = observed
        // A normal table refresh is not a new system selection. In particular,
        // an unchanged, stale nil read must not undo an acknowledged icon change.
        if !self.moving && !self.pendingSelection && !self.applying {
            var icons = Self.allIcons.filter { availableNames.contains($0.name) }
            if icons.isEmpty { icons = [Self.allIcons[0]] }
            let optionsChanged = icons.map(\.name) != self.icons.map(\.name)
            self.icons = icons
            if observedChanged || optionsChanged {
                self.activeName = observed
                self.index = self.icons.firstIndex(where: { $0.alternateName == observed }) ?? 0
                self.failed = false
                self.initialized = true
                self.centerSelection()
            }
            self.pages.numberOfPages = self.icons.count
            self.pages.isHidden = self.icons.count < 2
            self.hintLabel.isHidden = self.icons.count < 2
            self.scene.isScrollEnabled = self.icons.count > 1
        }
        self.render()
        self.refreshStatus()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateGeometry()
    }

    private func wrapped(_ slot: Int) -> Int { (slot % self.icons.count + self.icons.count) % self.icons.count }
    private var middleSlot: Int { (self.slotCount / 2 / self.icons.count) * self.icons.count }
    private var nearestSlot: Int { Int((self.scene.contentOffset.x / self.itemSpacing).rounded()) }

    private func centerSelection() {
        guard !self.icons.isEmpty else { return }
        self.suppressFeedback = true
        self.geometryWidth = 0
        self.updateGeometry()
        self.suppressFeedback = false
    }

    private func updateGeometry() {
        guard !self.icons.isEmpty, self.scene.bounds.width > 0 else { return }
        let width = self.scene.bounds.width
        if width != self.geometryWidth {
            let position = self.geometryWidth > 0 ? self.scene.contentOffset.x / self.itemSpacing : CGFloat(self.middleSlot + self.index)
            self.geometryWidth = width
            // A small clear gap remains between the transformed faces, including
            // on a narrow phone and halfway through a turn.
            self.itemSpacing = min(112, max(108, (width - 116) / 2 - 6))
            self.suppressFeedback = true
            self.scene.contentSize = CGSize(width: CGFloat(self.slotCount) * self.itemSpacing + width, height: self.scene.bounds.height)
            self.scene.setContentOffset(CGPoint(x: position * self.itemSpacing, y: 0), animated: false)
            self.lastFeedbackSlot = self.nearestSlot
            self.suppressFeedback = false
        }
        self.render()
    }

    /// Five reused faces are sufficient even for a flick through several turns.
    private func render() {
        guard !self.icons.isEmpty, self.geometryWidth > 0 else { return }
        let position = self.scene.contentOffset.x / self.itemSpacing
        let center = Int(position.rounded())
        if !self.suppressFeedback, let previous = self.lastFeedbackSlot, previous != center {
            self.selectionFeedback.selectionChanged()
        }
        self.lastFeedbackSlot = center
        let index = self.wrapped(center)
        if self.index != index {
            self.index = index
            self.refreshStatus()
        }
        self.pages.currentPage = self.index
        for (i, image) in self.images.enumerated() {
            let slot = center + i - 2
            let icon = self.icons[self.wrapped(slot)]
            if image.layer.name != icon.name {
                image.layer.name = icon.name
                if self.imageCache[icon.name] == nil {
                    self.imageCache[icon.name] = UIImage(named: icon.name, in: .main, compatibleWith: nil) ?? UIImage(named: "SolvgramIcon")
                }
                image.image = self.imageCache[icon.name]
            }
            let distance = CGFloat(slot) - position
            let scale = max(0.5, 1 - abs(distance) * 0.28)
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 650
            transform = CATransform3DRotate(transform, -distance * 0.5, 0, 1, 0)
            image.layer.transform = CATransform3DScale(transform, scale, scale, 1)
            image.center = CGPoint(x: self.scene.bounds.width / 2 + CGFloat(slot) * self.itemSpacing, y: self.scene.bounds.height / 2)
            image.alpha = max(0, 1 - abs(distance) * 0.5)
            image.layer.zPosition = -abs(distance)
        }
    }

    private func refreshStatus() {
        guard !self.icons.isEmpty else { return }
        let icon = self.icons[self.index]
        let name = self.russian ? icon.ru : icon.en
        self.scene.accessibilityValue = name
        if self.applying && self.applyingName == self.selectedName && !self.moving {
            self.statusLabel.text = self.russian ? "Применение…" : "Applying…"
        } else if self.failed {
            self.statusLabel.text = self.russian ? "Не удалось сменить иконку. Нажмите, чтобы повторить." : "Couldn't change the icon. Tap to retry."
        } else {
            let active = !self.moving && !self.pendingSelection && self.selectedName == self.activeName
            self.statusLabel.text = (active ? (self.russian ? "Активна · " : "Active · ") : (self.russian ? "Выбрана · " : "Selected · ")) + name
        }
    }

    func selectIcon(at target: Int, animated: Bool = true) {
        guard self.icons.indices.contains(target) else { return }
        self.cancelIdleApply()
        self.pendingSelection = true
        self.failed = false
        self.coasting = false
        self.selectionFeedback.prepare()
        self.redirectingScroll = true
        self.scene.setContentOffset(self.scene.contentOffset, animated: false)
        self.redirectingScroll = false
        var distance = self.wrapped(target - self.wrapped(self.nearestSlot))
        if distance > self.icons.count / 2 { distance -= self.icons.count }
        self.scrollTo(slot: self.nearestSlot + distance, animated: animated)
    }

    private func scrollTo(slot: Int, animated: Bool) {
        let offset = CGPoint(x: CGFloat(slot) * self.itemSpacing, y: 0)
        self.scrollTarget = slot
        self.scrollingToSelection = animated && !UIAccessibility.isReduceMotionEnabled && self.window != nil && abs(offset.x - self.scene.contentOffset.x) > 0.5
        self.scene.setContentOffset(offset, animated: self.scrollingToSelection)
        if !self.scrollingToSelection { self.finishScrolling() }
    }

    private func finishScrolling() {
        guard !self.icons.isEmpty, !self.moving else { return }
        let slot = self.nearestSlot
        if abs(CGFloat(slot) * self.itemSpacing - self.scene.contentOffset.x) > 0.5 {
            self.scrollTo(slot: slot, animated: true)
            return
        }
        self.render()
        if slot < 100 || slot > self.slotCount - 100 { self.centerSelection() }
        self.pendingSelection = self.selectedName != self.activeName || self.applying
        self.refreshStatus()
        self.scheduleApply()
    }

    private func cancelIdleApply() {
        self.idleApply?.cancel()
        self.idleApply = nil
    }

    /// Only the final choice, after inertia and an uninterrupted quiet interval,
    /// reaches UIApplication. Interaction remains available during a system call.
    private func scheduleApply(after delay: TimeInterval = 0.85) {
        self.cancelIdleApply()
        guard self.pendingSelection, !self.applying, !self.dragging, !self.coasting, !self.scrollingToSelection, !self.scene.isDecelerating else { return }
        let work = DispatchWorkItem { [weak self] in self?.applySelectionIfIdle() }
        self.idleApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applySelectionIfIdle() {
        self.idleApply = nil
        guard self.pendingSelection, !self.applying, !self.icons.isEmpty else { return }
        guard !self.moving else { self.scheduleApply(after: 0.2); return }
        let name = self.selectedName
        guard name != self.activeName else {
            self.pendingSelection = false
            self.refreshStatus()
            return
        }
        self.applying = true
        self.applyingName = name
        self.failed = false
        self.refreshStatus()
        self.onSelect?(name, { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applying = false
                if success { self.activeName = name }
                self.failed = !success && self.selectedName == name
                self.pendingSelection = !self.failed && self.selectedName != self.activeName
                // An older completion never moves the carousel back from a newer choice.
                self.refreshStatus()
                if self.pendingSelection { self.scheduleApply() }
                if UIAccessibility.isVoiceOverRunning && !self.moving {
                    UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
                }
            }
        })
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.cancelIdleApply()
        self.dragging = true
        self.coasting = false
        self.scrollingToSelection = false
        self.scrollTarget = nil
        self.pendingSelection = true
        self.failed = false
        self.selectionFeedback.prepare()
        self.refreshStatus()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { self.render() }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee.x = (targetContentOffset.pointee.x / self.itemSpacing).rounded() * self.itemSpacing
        targetContentOffset.pointee.y = 0
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        self.dragging = false
        self.coasting = decelerate
        if !decelerate { self.finishScrolling() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.coasting = false
        self.finishScrolling()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard !self.redirectingScroll else { return }
        // UIKit can deliver the end callback of an interrupted animation after
        // another swipe/page selection has already supplied a newer target.
        if let target = self.scrollTarget, abs(self.scene.contentOffset.x - CGFloat(target) * self.itemSpacing) > 0.5 { return }
        self.scrollTarget = nil
        self.scrollingToSelection = false
        self.finishScrolling()
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard !self.icons.isEmpty else { return }
        let x = tap.location(in: self.scene).x - self.scene.contentOffset.x - self.scene.bounds.width / 2
        if abs(x) > 58 {
            self.selectIcon(at: self.wrapped(self.index + (x > 0 ? 1 : -1)))
        } else if self.failed { self.selectIcon(at: self.index) }
    }

    @objc private func pageChanged() { self.selectIcon(at: self.pages.currentPage) }
}

private final class SolvgramIconViewport: UIView {
    let edgeFade = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.edgeFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        self.edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        self.edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        self.layer.mask = self.edgeFade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.edgeFade.frame = self.bounds
        let fade = min(0.25, 48 / max(1, self.bounds.width))
        self.edgeFade.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        CATransaction.commit()
    }
}

private final class SolvgramIconScene: UIScrollView {
    var adjust: ((Int) -> Void)?
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        self.onLayout?()
    }
    override func accessibilityIncrement() { self.adjust?(1) }
    override func accessibilityDecrement() { self.adjust?(-1) }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = self.fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: self.pointSize)
    }
}

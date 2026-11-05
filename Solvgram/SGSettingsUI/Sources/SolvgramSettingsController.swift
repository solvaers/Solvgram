// MARK: Solvgram — the Solvgram menu, a native UIKit settings screen (Liquid Glass bars, search,
// switches and sliders on iOS 26 and later), presented by UIKit as a sheet over Telegram from the Settings row.
// Every screen is described declaratively (sections of rows, see SolvSection/SolvRow) and rebuilt from
// the current settings whenever one of them changes, so a screen never holds a stale value.
// Solvgram's own settings are UserDefaults keys read live by the app (SolvgramSettings); Solvgram's go
// through SolvgramMenuBridge, which keeps SGSimpleSettings' cache and the side effects in step.
import Foundation
import UIKit
import AsyncDisplayKit
import MapKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import LocalizedPeerData
import SGSimpleSettings
import SolvgramIcons

// MARK: - Shared state

/// Bumped after every change, so every open menu screen rebuilds.
nonisolated(unsafe) private let solvRefresh = ValuePromise<Int>(0, ignoreRepeated: false)
nonisolated(unsafe) private var solvRefreshCounter = 0
/// A changed setting only applies after a restart: every screen shows the Restart button.
nonisolated(unsafe) private var solvNeedsRestart = false

private func solvChanged(needsRestart: Bool = false) {
    if needsRestart {
        solvNeedsRestart = true
    }
    solvRefreshCounter += 1
    solvRefresh.set(solvRefreshCounter)
}

private func L(_ en: String, _ ru: String) -> String {
    return SolvgramSettings.isRussian ? ru : en
}

private func solvBool(_ keys: [String]) -> Bool {
    return !keys.isEmpty && keys.allSatisfy { UserDefaults.standard.bool(forKey: $0) }
}

private func solvSetBool(_ keys: [String], _ value: Bool) {
    for key in keys {
        UserDefaults.standard.set(value, forKey: key)
    }
}

// MARK: - Icons

private struct SolvIcon: Equatable {
    let symbol: String
    let rgb: UInt32
}

nonisolated(unsafe) private var solvIconCache: [String: UIImage] = [:]

/// An SF Symbol on a rounded tile, like the icons of the current system Settings: one color with a
/// barely-there vertical shading, no gloss, no shadow.
private func solvIconImage(_ icon: SolvIcon) -> UIImage? {
    return solvIconImage(icon, side: 30.0)
}

private func solvIconImage(_ icon: SolvIcon, side: CGFloat) -> UIImage? {
    if icon.symbol.hasPrefix("solvgram.") {
        return SolvgramSettingsIcons.image(named: String(icon.symbol.dropFirst("solvgram.".count)), side: side)
    }
    let key = "\(icon.symbol)|\(icon.rgb)|\(side)"
    if let image = solvIconCache[key] {
        return image
    }
    let base = UIColor(rgb: icon.rgb)
    var hue: CGFloat = 0.0, saturation: CGFloat = 0.0, brightness: CGFloat = 0.0, alpha: CGFloat = 0.0
    base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    let top = UIColor(hue: hue, saturation: saturation * 0.92, brightness: min(1.0, brightness * 1.05), alpha: 1.0)
    let bottom = UIColor(hue: hue, saturation: min(1.0, saturation * 1.04), brightness: brightness * 0.95, alpha: 1.0)
    let rect = CGRect(x: 0.0, y: 0.0, width: side, height: side)
    let image = UIGraphicsImageRenderer(size: rect.size).image { context in
        let cg = context.cgContext
        cg.saveGState()
        UIBezierPath(ovalIn: rect).addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0.0, 1.0]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: side), options: [])
        }
        cg.restoreGState()

        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium)
        guard let glyph = (UIImage(systemName: icon.symbol, withConfiguration: configuration) ?? UIImage(systemName: "gearshape.fill", withConfiguration: configuration))?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
            return
        }
        let scale = min(1.0, (side * 0.6) / max(glyph.size.width, glyph.size.height))
        let size = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
        glyph.draw(in: CGRect(x: (side - size.width) / 2.0, y: (side - size.height) / 2.0, width: size.width, height: size.height))
    }
    solvIconCache[key] = image
    return image
}

private let blue: UInt32 = 0x007AFF
private let green: UInt32 = 0x34C759
private let indigo: UInt32 = 0x5856D6
private let orange: UInt32 = 0xFF9500
private let pink: UInt32 = 0xFF2D55
private let purple: UInt32 = 0xAF52DE
private let red: UInt32 = 0xFF3B30
private let teal: UInt32 = 0x30B0C7
private let gray: UInt32 = 0x8E8E93
private let cyan: UInt32 = 0x32ADE6

// MARK: - Model

private enum SolvRowKind: Equatable {
    case toggle(title: String, subtitle: String?, icon: SolvIcon?, value: Bool, enabled: Bool)
    case disclosure(title: String, label: String, icon: SolvIcon?, peer: EnginePeer?, enabled: Bool)
    case slider(value: Int32, steps: [String]?)
    case input(text: String, placeholder: String, number: Bool)
    case check(title: String, checked: Bool)
    case activity(title: String, subtitle: String?, checked: Bool, enabled: Bool)
    case action(title: String, destructive: Bool)
    /// A large title, or a screen's big icon with its title and description.
    case hero(title: String, subtitle: String?, icon: SolvIcon?)
    /// The menu's header: the app icon and the app's name, large.
    case appHeader(title: String)
}

private struct SolvRow {
    let id: String
    let kind: SolvRowKind
    var onToggle: ((Bool) -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onSlide: ((Int32) -> Void)? = nil
    var onText: ((String) -> Void)? = nil
    /// Drawn one level in, under the row it depends on.
    var indent: Bool = false
    /// Keep an editable dependent field with its matching setting in search results.
    var searchParentID: String? = nil

    /// The text search matches against.
    var searchText: String {
        switch self.kind {
        case let .toggle(title, subtitle, _, _, _):
            return title + " " + (subtitle ?? "")
        case let .disclosure(title, label, _, _, _):
            return title + " " + label
        case let .check(title, _), let .action(title, _):
            return title
        case let .activity(title, subtitle, _, _):
            return title + " " + (subtitle ?? "")
        case .slider, .input, .hero, .appHeader:
            return ""
        }
    }
}

private struct SolvSection {
    var header: String?
    var footer: String?
    var rows: [SolvRow]

    init(_ rows: [SolvRow]) {
        self.header = nil
        self.footer = nil
        self.rows = rows
    }

    init(_ header: String?, footer: String? = nil, _ rows: [SolvRow]) {
        self.header = header
        self.footer = footer
        self.rows = rows
    }
}

// MARK: - Screens

private final class SolvEnv {
    let context: AccountContext
    var bridge: SolvgramMenuBridge!
    weak var navigationController: UINavigationController?
    /// The Telegram screen the menu was opened from.
    weak var host: ViewController?

    init(context: AccountContext) {
        self.context = context
    }

    func push(_ controller: UIViewController) {
        self.navigationController?.pushViewController(controller, animated: true)
    }

    func pop() {
        let _ = self.navigationController?.popViewController(animated: true)
    }

    func present(_ controller: UIViewController) {
        (self.navigationController?.topViewController ?? self.navigationController)?.present(controller, animated: true)
    }

    /// A Telegram screen: the menu sheet goes down, the screen opens in Telegram's navigation, and the sheet
    /// comes back up when that screen is closed.
    func openTelegram(_ controller: ViewController) {
        guard let menu = self.navigationController, let host = self.host, let hostNavigation = host.navigationController as? NavigationController else {
            return
        }
        menu.dismiss(animated: true, completion: { [host, hostNavigation] in
            hostNavigation.pushViewController(controller, animated: true)
            SolvScreenWatcher.watch(controller: controller, in: hostNavigation, closed: { [weak host, weak hostNavigation] in
                if let host, hostNavigation?.topViewController === host,
                   host.presentedViewController == nil, menu.presentingViewController == nil {
                    host.present(menu, animated: true)
                }
            })
        })
    }

    /// Closes the menu.
    func close() {
        self.navigationController?.dismiss(animated: true)
    }
}

/// Observe Telegram's actual stack changes; no polling timer or wakeups while
/// a destination screen stays open. Navigation owns the observer, so releasing
/// the entire navigation stack also disposes the subscription.
private final class SolvScreenWatcher {
    private var disposable: Disposable?
    private var wasShown = false
    private var finished = false

    static func watch(controller: ViewController, in navigation: NavigationController, closed: @escaping () -> Void) {
        let watcher = SolvScreenWatcher()
        objc_setAssociatedObject(navigation, &solvScreenWatcherKey, watcher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        watcher.disposable = (navigation.viewControllersSignal |> deliverOnMainQueue).start(next: { [weak watcher, weak controller, weak navigation] controllers in
            guard let watcher, !watcher.finished else { return }
            if let controller, controllers.contains(where: { $0 === controller }) {
                watcher.wasShown = true
            } else if watcher.wasShown || controller == nil {
                watcher.finished = true
                watcher.disposable?.dispose()
                watcher.disposable = nil
                if let navigation {
                    objc_setAssociatedObject(navigation, &solvScreenWatcherKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
                closed()
            }
        })
    }

    deinit { self.disposable?.dispose() }
}

nonisolated(unsafe) private var solvScreenWatcherKey: UInt8 = 0

private struct SolvBuild {
    let env: SolvEnv
    let peers: [EnginePeer.Id: EnginePeer]
    let query: String
}

private func solvScreen(env: SolvEnv, title: @escaping () -> String, peers: Signal<[EnginePeer.Id: EnginePeer], NoError> = .single([:]), build: @escaping (SolvBuild) -> [SolvSection]) -> UIViewController {
    return SolvTableController(env: env, title: title, isRoot: false, peers: peers, build: build)
}

private func solvAskToRestart(env: SolvEnv) {
    let alert = UIAlertController(title: nil, message: L("Solvgram will close to apply the changes. Open it again from the notification.", "Solvgram закроется, чтобы применить изменения. Откройте его снова из уведомления."), preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: L("Later", "Позже"), style: .cancel))
    alert.addAction(UIAlertAction(title: L("Restart", "Перезапустить"), style: .default, handler: { _ in
        // iOS does not let an app relaunch itself: a notification opens Solvgram again.
        let content = UNMutableNotificationContent()
        content.title = "Solvgram"
        content.body = L("Settings applied. Tap to open Solvgram.", "Настройки применены. Нажмите, чтобы открыть Solvgram.")
        let request = UNNotificationRequest(identifier: "SolvgramRestart", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false))
        UNUserNotificationCenter.current().add(request, withCompletionHandler: { _ in
            DispatchQueue.main.async {
                SolvgramArchiveStorage.shared.flush()
                UserDefaults.standard.synchronize()
                exit(0)
            }
        })
    }))
    env.present(alert)
}

private final class SolvTableController: UITableViewController, UISearchResultsUpdating {
    private let env: SolvEnv
    private let titleText: () -> String
    private let isRoot: Bool
    private let peersSignal: Signal<[EnginePeer.Id: EnginePeer], NoError>
    private let build: (SolvBuild) -> [SolvSection]
    private var peers: [EnginePeer.Id: EnginePeer] = [:]
    private var query = ""
    private var sections: [SolvSection] = []
    private var disposable: Disposable?
    private var updatingRows = false
    private var reloadPending = false

    init(env: SolvEnv, title: @escaping () -> String, isRoot: Bool, peers: Signal<[EnginePeer.Id: EnginePeer], NoError>, build: @escaping (SolvBuild) -> [SolvSection]) {
        self.env = env
        self.titleText = title
        self.isRoot = isRoot
        self.peersSignal = peers
        self.build = build
        super.init(style: .insetGrouped)
        self.title = title()
        self.navigationItem.backButtonDisplayMode = .minimal
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reload()
    }

    @objc private func appBecameActive() {
        self.reload()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(self.appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.tableView.register(SolvCell.self, forCellReuseIdentifier: "cell")
        self.tableView.register(SolvHeroCell.self, forCellReuseIdentifier: "hero")
        self.tableView.register(SolvSliderCell.self, forCellReuseIdentifier: "slider")
        self.tableView.register(SolvInputCell.self, forCellReuseIdentifier: "input")
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 64.0
        if #available(iOS 17.0, *) {
            self.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: SolvTableController, _: UITraitCollection) in
                controller.tableView.reloadData()
            }
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(self.contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        }
        self.navigationItem.largeTitleDisplayMode = .never
        if self.isRoot {
            let searchController = UISearchController(searchResultsController: nil)
            searchController.searchResultsUpdater = self
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.placeholder = L("Search", "Поиск")
            self.navigationItem.searchController = searchController
            self.navigationItem.hidesSearchBarWhenScrolling = false
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.env.close()
            })
        }
        let sharedData = self.env.context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
        |> map { _ -> Void in
            return Void()
        }
        self.disposable = (combineLatest(queue: .mainQueue(), solvRefresh.get(), self.peersSignal, sharedData)
        |> deliverOnMainQueue).start(next: { [weak self] _, peers, _ in
            guard let self else {
                return
            }
            self.peers = peers
            self.reload()
        })
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        if query != self.query {
            self.query = query
            self.reload()
        }
    }

    @objc private func contentSizeChanged() {
        self.tableView.reloadData()
    }

    private func reload() {
        // Keep the data source on one snapshot until UIKit finishes moving its rows.
        // A second tap still saves immediately; its presentation follows this batch.
        guard !self.updatingRows else {
            self.reloadPending = true
            return
        }
        let title = self.titleText()
        if self.title != title {
            self.title = title
        }
        let sections = self.build(SolvBuild(env: self.env, peers: self.peers, query: self.query))
        let previous = self.sections
        let sameSections = sections.count == previous.count && zip(sections, previous).allSatisfy { lhs, rhs in
            return lhs.header == rhs.header
        }
        self.sections = sections
        if sameSections && self.tableView.window != nil {
            // Rows that came or went (a dependent group opening under its switch) are animated; the rest
            // update in place, so a switch keeps its own animation.
            var deleted: [IndexPath] = []
            var inserted: [IndexPath] = []
            var footersChanged = IndexSet()
            for (index, (section, old)) in zip(sections, previous).enumerated() {
                let ids = Set(section.rows.map(\.id))
                let oldIds = Set(old.rows.map(\.id))
                for (row, value) in old.rows.enumerated() where !ids.contains(value.id) {
                    deleted.append(IndexPath(row: row, section: index))
                }
                for (row, value) in section.rows.enumerated() where !oldIds.contains(value.id) {
                    inserted.append(IndexPath(row: row, section: index))
                }
                if section.footer != old.footer {
                    footersChanged.insert(index)
                }
            }
            for cell in self.tableView.visibleCells {
                // Index paths are transitional while a dependent row appears. Bind
                // updates to the row actually displayed by each cell instead.
                if let cell = cell as? SolvRenderedCell, let section = cell.representedSection, section < sections.count,
                   let row = sections[section].rows.first(where: { $0.id == cell.representedRowID }) {
                    let appHeader: Bool
                    if case .appHeader = row.kind { appHeader = true } else { appHeader = false }
                    if appHeader || cell.representedKind != row.kind || cell.representedIndent != row.indent {
                        self.configure(cell, row: row, section: section)
                    }
                }
            }
            for index in footersChanged {
                if let footer = self.tableView.footerView(forSection: index) {
                    var content = footer.defaultContentConfiguration()
                    content.text = sections[index].footer
                    footer.contentConfiguration = content
                }
            }
            if !deleted.isEmpty || !inserted.isEmpty || !footersChanged.isEmpty {
                self.updatingRows = true
                self.tableView.performBatchUpdates({
                    let animation: UITableView.RowAnimation = UIAccessibility.isReduceMotionEnabled ? .none : .fade
                    self.tableView.deleteRows(at: deleted, with: animation)
                    self.tableView.insertRows(at: inserted, with: animation)
                }, completion: { [weak self] _ in
                    guard let self else { return }
                    self.updatingRows = false
                    if self.reloadPending {
                        self.reloadPending = false
                        self.reload()
                    }
                })
            }
        } else {
            self.tableView.reloadData()
        }
        if solvNeedsRestart {
            if self.navigationItem.rightBarButtonItem == nil {
                self.navigationItem.setRightBarButton(UIBarButtonItem(title: L("Restart", "Перезапуск"), primaryAction: UIAction { [weak self] _ in
                    if let env = self?.env {
                        solvAskToRestart(env: env)
                    }
                }), animated: true)
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].header
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = self.sections[indexPath.section].rows[indexPath.row]
        let identifier: String
        switch row.kind {
        case .hero, .appHeader:
            identifier = "hero"
        case .slider:
            identifier = "slider"
        case .input:
            identifier = "input"
        default:
            identifier = "cell"
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        self.configure(cell, row: row, section: indexPath.section)
        return cell
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let row = self.sections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case let .disclosure(_, _, _, _, enabled):
            return enabled
        case let .activity(_, _, _, enabled):
            return enabled
        case .check, .action:
            return true
        default:
            return false
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.view.endEditing(true)
        let row = self.sections[indexPath.section].rows[indexPath.row]
        if case let .activity(_, _, _, enabled) = row.kind, !enabled {
            return
        }
        row.onTap?()
    }

    private func configure(_ cell: UITableViewCell, row: SolvRow, section: Int) {
        let rendered = cell as? SolvRenderedCell
        let sameRow = rendered?.representedRowID == row.id && rendered?.representedSection == section
        let previousKind = sameRow ? rendered?.representedKind : nil
        let sameIndent = rendered?.representedIndent == row.indent
        rendered?.representedRowID = row.id
        rendered?.representedSection = section
        rendered?.representedKind = row.kind
        rendered?.representedIndent = row.indent
        let featured = row.id == "ghost" && !self.isRoot
        if let cell = cell as? SolvCell,
           case let .toggle(title, subtitle, _, value, enabled) = row.kind,
           case let .toggle(oldTitle, oldSubtitle, _, oldValue, oldEnabled) = previousKind,
           title == oldTitle, subtitle == oldSubtitle, enabled == oldEnabled, sameIndent {
            // A user-driven switch has already changed its value. Do not detach
            // it or rebuild unchanged content while its native animation runs.
            if featured && oldValue != value, var content = cell.contentConfiguration as? UIListContentConfiguration {
                content.secondaryText = value ? L("Active", "Активен") : L("Off", "Выключен")
                cell.contentConfiguration = content
            }
            cell.setToggle(value: value, enabled: enabled, accent: featured ? .systemIndigo : nil, animated: true, onToggle: row.onToggle)
            return
        }
        cell.isUserInteractionEnabled = true
        cell.tintColor = self.view.tintColor
        cell.accessibilityTraits = []
        cell.accessibilityValue = nil
        cell.accessibilityHint = nil
        switch row.kind {
        case let .hero(title, subtitle, icon):
            (cell as? SolvHeroCell)?.update(title: title, subtitle: subtitle, icon: icon.flatMap { solvIconImage($0, side: 64.0) }, large: false)
        case let .appHeader(title):
            let bindings = self.env.context.sharedContext.applicationBindings
            (cell as? SolvHeroCell)?.updateAppHeader(title: title, isRussian: SolvgramSettings.isRussian, getActiveName: bindings.getAlternateIconName, availableNames: bindings.getAvailableAlternateIcons().map(\.name), onSelect: { [weak self] name, completion in
                guard let self else { completion(false); return }
                bindings.requestSetAlternateIconName(name, completion)
            })
        case let .slider(value, steps):
            (cell as? SolvSliderCell)?.update(value: value, steps: steps, onSlide: row.onSlide)
        case let .input(text, placeholder, number):
            (cell as? SolvInputCell)?.update(text: text, placeholder: placeholder, number: number, onText: row.onText)
        case let .toggle(title, subtitle, _, value, enabled):
            guard let cell = cell as? SolvCell else {
                return
            }
            let accessibilitySize = self.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            var content = featured ? UIListContentConfiguration.subtitleCell() : UIListContentConfiguration.cell()
            content.text = title
            content.secondaryText = subtitle
            content.secondaryTextProperties.color = .secondaryLabel
            content.textProperties.color = enabled ? .label : .secondaryLabel
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.imageToTextPadding = 0
            if featured {
                if !accessibilitySize {
                    content.image = SolvgramSettingsIcons.image(named: "ghost", side: 48)
                    content.imageProperties.maximumSize = CGSize(width: 48, height: 48)
                    content.imageToTextPadding = 16
                }
                content.textProperties.font = UIFont.preferredFont(forTextStyle: .headline)
                content.secondaryText = value ? L("Active", "Активен") : L("Off", "Выключен")
                content.secondaryTextProperties.numberOfLines = 1
                content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)
            }
            if row.indent {
                content.directionalLayoutMargins.leading += 30.0
            }
            cell.contentConfiguration = content
            cell.setToggle(value: value, enabled: enabled, accent: featured ? .systemIndigo : nil, animated: sameRow, onToggle: row.onToggle)
            cell.accessoryView?.accessibilityLabel = title
            cell.accessoryView?.accessibilityHint = subtitle
        case let .disclosure(title, label, icon, peer, enabled):
            guard let cell = cell as? SolvCell else {
                return
            }
            var content = UIListContentConfiguration.valueCell()
            content.text = title
            content.secondaryText = label
            content.textProperties.color = enabled ? .label : .secondaryLabel
            if let peer {
                content.image = solvInitialsImage(peer.compactDisplayTitle)
            } else if self.isRoot && self.query.isEmpty {
                content.image = icon.flatMap(solvIconImage)
            }
            content.textProperties.numberOfLines = 0
            cell.isUserInteractionEnabled = enabled
            if row.indent {
                content.directionalLayoutMargins.leading += 30.0
            }
            cell.contentConfiguration = content
            cell.setAccessory(.disclosureIndicator)
        case let .check(title, checked):
            guard let cell = cell as? SolvCell else {
                return
            }
            var content = UIListContentConfiguration.cell()
            content.text = title
            if row.indent {
                content.directionalLayoutMargins.leading += 30.0
            }
            cell.contentConfiguration = content
            cell.setAccessory(checked ? .checkmark : .none)
        case let .activity(title, subtitle, checked, enabled):
            guard let cell = cell as? SolvCell else { return }
            var content = UIListContentConfiguration.subtitleCell()
            content.text = title
            content.secondaryText = subtitle
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.textProperties.color = enabled ? .label : .tertiaryLabel
            content.secondaryTextProperties.color = enabled ? .secondaryLabel : .tertiaryLabel
            cell.contentConfiguration = content
            cell.setAccessory(checked ? .checkmark : .none)
            cell.tintColor = enabled ? .systemIndigo : .tertiaryLabel
            cell.isUserInteractionEnabled = enabled
            cell.accessibilityTraits = [.button]
            if checked { cell.accessibilityTraits.insert(.selected) }
            if !enabled { cell.accessibilityTraits.insert(.notEnabled) }
            cell.accessibilityValue = checked ? L("Selected", "Выбрано") : L("Not selected", "Не выбрано")
            cell.accessibilityHint = enabled ? L("Double-tap to change selection", "Двойное касание меняет выбор") : L("Turn on Ghost Mode to change this option", "Включите режим призрака, чтобы изменить этот параметр")
        case let .action(title, destructive):
            guard let cell = cell as? SolvCell else {
                return
            }
            var content = UIListContentConfiguration.cell()
            content.text = title
            content.textProperties.color = destructive ? .systemRed : self.view.tintColor
            cell.contentConfiguration = content
            cell.setAccessory(.none)
        }
    }
}

nonisolated(unsafe) private var solvInitialsCache: [String: UIImage] = [:]

/// A chat's first letter on a gray circle, where an exception's chat is listed.
private func solvInitialsImage(_ title: String) -> UIImage {
    let letter = title.first.map { String($0).uppercased() } ?? "?"
    if let image = solvInitialsCache[letter] {
        return image
    }
    let side: CGFloat = 30.0
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        UIColor.systemGray.setFill()
        UIBezierPath(ovalIn: CGRect(x: 0.0, y: 0.0, width: side, height: side)).fill()
        let string = NSAttributedString(string: letter, attributes: [.font: UIFont.systemFont(ofSize: 14.0, weight: .semibold), .foregroundColor: UIColor.white])
        let size = string.size()
        string.draw(at: CGPoint(x: (side - size.width) / 2.0, y: (side - size.height) / 2.0))
    }
    solvInitialsCache[letter] = image
    return image
}

// MARK: - Cells

private class SolvRenderedCell: UITableViewCell {
    var representedRowID: String?
    var representedSection: Int?
    var representedKind: SolvRowKind?
    var representedIndent = false

    override func prepareForReuse() {
        super.prepareForReuse()
        self.representedRowID = nil
        self.representedSection = nil
        self.representedKind = nil
        self.representedIndent = false
    }
}

private final class SolvCell: SolvRenderedCell {
    private var toggle: UISwitch?
    private var onToggle: ((Bool) -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        self.onToggle = nil
    }

    func setToggle(value: Bool, enabled: Bool, accent: UIColor? = nil, animated: Bool = false, onToggle: ((Bool) -> Void)?) {
        let toggle: UISwitch
        if let current = self.toggle {
            toggle = current
        } else {
            toggle = UISwitch()
            toggle.addTarget(self, action: #selector(self.toggled), for: .valueChanged)
            self.toggle = toggle
        }
        self.onToggle = onToggle
        if toggle.isOn != value {
            toggle.setOn(value, animated: animated && self.accessoryView === toggle && self.window != nil && !UIAccessibility.isReduceMotionEnabled)
        }
        if toggle.isEnabled != enabled {
            toggle.isEnabled = enabled
        }
        if toggle.onTintColor != accent {
            toggle.onTintColor = accent
        }
        if self.accessoryType != .none {
            self.accessoryType = .none
        }
        if self.accessoryView !== toggle {
            self.accessoryView = toggle
        }
        self.selectionStyle = .none
    }

    func setAccessory(_ type: UITableViewCell.AccessoryType) {
        self.onToggle = nil
        if self.accessoryView != nil {
            self.accessoryView = nil
        }
        if self.accessoryType != type {
            self.accessoryType = type
        }
        self.selectionStyle = .default
    }

    @objc private func toggled() {
        if let toggle = self.toggle {
            self.onToggle?(toggle.isOn)
        }
    }
}

private final class SolvHeroCell: SolvRenderedCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()
    private var appIconHeader: SolvgramAppIconHeaderView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundConfiguration = .clear()
        self.selectionStyle = .none
        self.titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.subtitleLabel.textColor = .secondaryLabel
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0
        let stack = self.stack
        [self.iconView, self.titleLabel, self.subtitleLabel].forEach(stack.addArrangedSubview)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6.0
        stack.setCustomSpacing(18.0, after: self.iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 0.0),
            stack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -4.0),
            stack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, subtitle: String?, icon: UIImage?, large: Bool) {
        self.appIconHeader?.isHidden = true
        self.titleLabel.isHidden = false
        self.titleLabel.font = large ? UIFont.systemFont(ofSize: 34.0, weight: .bold) : UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.iconView.image = icon
        self.iconView.isHidden = icon == nil
        self.titleLabel.text = title
        self.subtitleLabel.text = subtitle
        self.subtitleLabel.isHidden = subtitle == nil
    }

    func updateAppHeader(title: String, isRussian: Bool, getActiveName: () -> String?, availableNames: [String], onSelect: @escaping (String?, @escaping (Bool) -> Void) -> Void) {
        let header: SolvgramAppIconHeaderView
        if let current = self.appIconHeader {
            header = current
        } else {
            header = SolvgramAppIconHeaderView()
            self.appIconHeader = header
            self.stack.insertArrangedSubview(header, at: 0)
            header.widthAnchor.constraint(equalTo: self.stack.widthAnchor).isActive = true
        }
        self.iconView.isHidden = true
        self.titleLabel.isHidden = true
        self.subtitleLabel.isHidden = true
        header.isHidden = false
        header.update(title: title, isRussian: isRussian, getActiveName: getActiveName, availableNames: availableNames, onSelect: onSelect)
    }
}

private final class SolvSliderCell: SolvRenderedCell {
    private let slider = UISlider()
    private let minLabel = UILabel()
    private let valueLabel = UILabel()
    private let maxLabel = UILabel()
    private var steps: [String]?
    private var onSlide: ((Int32) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .none
        for label in [self.minLabel, self.maxLabel] {
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
        }
        self.valueLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.valueLabel.textAlignment = .center
        self.maxLabel.textAlignment = .right
        let labels = UIStackView(arrangedSubviews: [self.minLabel, self.valueLabel, self.maxLabel])
        labels.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [labels, self.slider])
        stack.axis = .vertical
        stack.spacing = 8.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor, constant: 4.0),
            stack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor, constant: -2.0),
            stack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
        ])
        self.slider.addTarget(self, action: #selector(self.changed), for: .valueChanged)
        self.slider.disablesInteractiveTransitionGestureRecognizer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(value: Int32, steps: [String]?, onSlide: ((Int32) -> Void)?) {
        self.onSlide = onSlide
        let stepsChanged = self.steps != steps
        self.steps = steps
        if let steps, steps.count > 1 {
            self.slider.minimumValue = 0.0
            self.slider.maximumValue = 1.0
            if stepsChanged {
                if #available(iOS 26.0, *) {
                    self.slider.trackConfiguration = .init(numberOfTicks: steps.count)
                }
            }
            let index = Int(max(1, min(Int32(steps.count), value))) - 1
            if !self.slider.isTracking {
                self.slider.value = Float(index) / Float(steps.count - 1)
            }
            self.slider.accessibilityValue = steps[index]
            self.minLabel.text = steps[0]
            self.maxLabel.text = steps[steps.count - 1]
            self.valueLabel.text = steps[index]
        } else {
            // Keep UIKit on its normalized 0...1 scale in both modes; only
            // convert to percentages/levels at the settings boundary.
            if stepsChanged, #available(iOS 26.0, *) {
                self.slider.trackConfiguration = .init(allowsTickValuesOnly: false, ticks: [])
            }
            self.slider.minimumValue = 0.0
            self.slider.maximumValue = 1.0
            if !self.slider.isTracking {
                self.slider.value = Float(value) / 100.0
            }
            self.slider.accessibilityValue = "\(value)%"
            self.minLabel.text = "0%"
            self.maxLabel.text = "100%"
            self.valueLabel.text = "\(value)%"
        }
    }

    @objc private func changed() {
        if let steps = self.steps, steps.count > 1 {
            let index = Int32(max(0.0, min(Float(steps.count - 1), (self.slider.value * Float(steps.count - 1)).rounded())))
            self.onSlide?(index + 1)
        } else {
            self.onSlide?(Int32((self.slider.value * 100.0).rounded()))
        }
    }
}

private final class SolvInputCell: SolvRenderedCell, UITextFieldDelegate {
    private let textField = UITextField()
    private var onText: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .none
        self.textField.clearButtonMode = .whileEditing
        self.textField.returnKeyType = .done
        self.textField.delegate = self
        self.textField.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.textField)
        NSLayoutConstraint.activate([
            self.textField.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.textField.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0),
            self.textField.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.textField.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
        ])
        self.textField.addTarget(self, action: #selector(self.edited), for: .editingChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, placeholder: String, number: Bool, onText: ((String) -> Void)?) {
        self.onText = onText
        if !self.textField.isFirstResponder {
            self.textField.text = text
        }
        self.textField.placeholder = placeholder
        self.textField.keyboardType = number ? .numberPad : .phonePad
    }

    @objc private func edited() {
        self.onText?(self.textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Rows

private extension SolvEnv {
    /// Ghost activity options are independent selections, stored under the existing keys.
    func activity(_ id: String, _ title: String, _ subtitle: String? = nil, keys: [String], enabled: Bool) -> SolvRow {
        return SolvRow(id: id, kind: .activity(title: title, subtitle: subtitle, checked: solvBool(keys), enabled: enabled), onTap: {
            guard enabled else { return }
            solvSetBool(keys, !solvBool(keys))
            UISelectionFeedbackGenerator().selectionChanged()
            solvChanged()
        })
    }
    /// Solvgram's own switch: UserDefaults keys, all set together.
    func toggle(_ id: String, _ title: String, _ subtitle: String? = nil, keys: [String], enabled: Bool = true) -> SolvRow {
        return SolvRow(id: id, kind: .toggle(title: title, subtitle: subtitle, icon: nil, value: solvBool(keys), enabled: enabled), onToggle: { value in
            solvSetBool(keys, value)
            solvChanged()
        })
    }

    /// A Solvgram switch, through the bridge.
    func sgToggle(_ name: String, _ title: String, _ subtitle: String? = nil, enabled: Bool = true) -> SolvRow {
        let bridge = self.bridge!
        return SolvRow(id: name, kind: .toggle(title: title, subtitle: subtitle, icon: nil, value: bridge.boolValue(name as NSString).boolValue, enabled: enabled), onToggle: { value in
            let needsRestart = bridge.setBool(name as NSString, value: NSNumber(value: value)).boolValue
            solvChanged(needsRestart: needsRestart)
        })
    }

    func sgBool(_ name: String) -> Bool {
        return self.bridge.boolValue(name as NSString).boolValue
    }

    func choiceOptions(_ name: String) -> [(value: String, title: String)] {
        return (self.bridge.choiceOptions(name as NSString) as? [[String]] ?? []).compactMap { option in
            return option.count == 2 ? (option[0], option[1]) : nil
        }
    }

    /// One of several values, picked on a screen of its own.
    func choice(_ name: String, _ title: String, icon: SolvIcon? = nil, enabled: Bool = true) -> SolvRow {
        let current = self.bridge.choiceValue(name as NSString) as String
        let label = self.choiceOptions(name).first(where: { $0.value == current })?.title ?? current
        return SolvRow(id: name, kind: .disclosure(title: title, label: label, icon: icon, peer: nil, enabled: enabled), onTap: { [weak self] in
            guard let self else {
                return
            }
            self.push(self.choiceScreen(name, title: title))
        })
    }

    func choiceScreen(_ name: String, title: String) -> UIViewController {
        return solvScreen(env: self, title: { title }, build: { build in
            let env = build.env
            let current = env.bridge.choiceValue(name as NSString) as String
            return [SolvSection(env.choiceOptions(name).map { option in
                return SolvRow(id: option.value, kind: .check(title: option.title, checked: option.value == current), onTap: {
                    let needsRestart = env.bridge.setChoice(name as NSString, value: option.value as NSString).boolValue
                    solvChanged(needsRestart: needsRestart)
                    env.pop()
                })
            })]
        })
    }

    func open(_ id: String, _ title: String, label: String = "", icon: SolvIcon? = nil, action: @escaping () -> Void) -> SolvRow {
        return SolvRow(id: id, kind: .disclosure(title: title, label: label, icon: icon, peer: nil, enabled: true), onTap: action)
    }

    /// A Telegram or Solvgram screen the bridge opens.
    func openBridge(_ name: String, _ title: String, icon: SolvIcon? = nil) -> SolvRow {
        return self.open(name, title, icon: icon, action: { [weak self] in
            self?.bridge.open(name as NSString)
        })
    }

    func openAppBadge() {
        let context = self.context
        self.push(SolvgramBadgeController(selection: SGSimpleSettings.shared.customAppBadge, apply: { value in
            SGSimpleSettings.shared.customAppBadge = value
            if let view = context.sharedContext.mainWindow?.badgeView {
                let center = view.center
                view.image = SolvgramBadgeArtwork.image(value: value, defaultImage: UIImage(bundleImageName: "Components/AppBadge"))
                view.sizeToFit()
                view.center = center
            }
        }))
    }

    func slider(_ name: String, steps: [String]? = nil) -> SolvRow {
        let bridge = self.bridge!
        return SolvRow(id: name, kind: .slider(value: bridge.sliderValue(name as NSString).int32Value, steps: steps), onSlide: { value in
            if value == bridge.sliderValue(name as NSString).int32Value {
                return
            }
            let _ = bridge.setSlider(name as NSString, value: NSNumber(value: value))
            solvChanged()
        })
    }
}

// MARK: - Categories

private struct SolvCategory {
    let id: String
    let title: String
    let icon: SolvIcon
    let subtitle: String
    let build: (SolvBuild) -> [SolvSection]
}

private func solvCategories() -> [[SolvCategory]] {
    return [
        [
            SolvCategory(id: "privacy", title: L("Privacy", "Конфиденциальность"), icon: SolvIcon(symbol: "solvgram.privacy", rgb: indigo), subtitle: L("Ghost Mode, stories, location, phone number", "Режим призрака, истории, геопозиция, номер"), build: solvPrivacy),
            SolvCategory(id: "messages", title: L("Messages", "Сообщения"), icon: SolvIcon(symbol: "solvgram.messages", rgb: teal), subtitle: L("Saved data, protected content and message menu", "Сохранённые данные, защищённый контент и меню сообщения"), build: solvMessages),
            SolvCategory(id: "cache", title: L("Solvgram Cache", "Кеш Solvgram"), icon: SolvIcon(symbol: "solvgram.cache", rgb: teal), subtitle: L("Deleted messages, edits, disappearing, stories, media", "Удалённые, правки, исчезающие, истории, медиа"), build: solvCache),
            SolvCategory(id: "chats", title: L("Chats", "Чаты"), icon: SolvIcon(symbol: "solvgram.chats", rgb: green), subtitle: L("Chat screen, input field, emoji, channels", "Экран чата, поле ввода, эмодзи, каналы"), build: solvChats),
            SolvCategory(id: "chatList", title: L("Chat List", "Список чатов"), icon: SolvIcon(symbol: "solvgram.chat-list", rgb: cyan), subtitle: L("List, stories, folders, tab bar", "Список, истории, папки, панель вкладок"), build: solvChatList),
            SolvCategory(id: "voice", title: L("Voice and Video Messages", "Голосовые и кружки"), icon: SolvIcon(symbol: "solvgram.voice", rgb: orange), subtitle: L("Voice changer, speech to text, round videos", "Изменение голоса, расшифровка, кружки"), build: solvVoice),
            SolvCategory(id: "media", title: L("Media", "Медиа"), icon: SolvIcon(symbol: "solvgram.media", rgb: pink), subtitle: L("Photo quality, video, upload and download speed", "Качество фото, видео, скорость загрузки"), build: solvMedia),
        ],
        [
            SolvCategory(id: "translation", title: L("Translation", "Перевод"), icon: SolvIcon(symbol: "solvgram.translation-voice", rgb: purple), subtitle: L("Translator and chat translation", "Переводчик и перевод чатов"), build: solvTranslation),
            SolvCategory(id: "profiles", title: L("Profiles", "Профили"), icon: SolvIcon(symbol: "solvgram.profiles", rgb: teal), subtitle: L("ID, data center, dates, name colors", "ID, дата-центр, даты, цвета имён"), build: solvProfiles),
            SolvCategory(id: "locator", title: L("Locator", "Локатор"), icon: SolvIcon(symbol: "solvgram.locator", rgb: teal), subtitle: L("In development", "В разработке"), build: solvLocator),
            SolvCategory(id: "calls", title: L("Calls and Notifications", "Звонки и уведомления"), icon: SolvIcon(symbol: "solvgram.calls-notifications", rgb: green), subtitle: L("Calls, pinned messages, mentions", "Звонки, закреплённые, упоминания"), build: solvCalls),
        ],
    ]
}

private func solvLocator(_ b: SolvBuild) -> [SolvSection] {
    return [SolvSection([b.env.open("locatorServer", L("Locator · Profile Tracking", "Локатор · Отслеживание профилей"), action: {
        b.env.push(SolvgramLocatorController(context: b.env.context))
    })])]
}

private func solvPhoneNumbers(_ b: SolvBuild) -> [SolvRow] {
    let env = b.env
    let own = SolvgramSettings.phoneNumberMode(isOwn: true, legacyHidden: env.sgBool("hidePhoneInSettings"))
    let other = SolvgramSettings.phoneNumberMode(isOwn: false)
    let ownOptions = [("real", L("Real", "Настоящий")), ("hidden", "Hidden"), ("custom", L("Custom", "Свой"))]
    let otherOptions = [("real", L("Show", "Показывать")), ("hidden", "Hidden")]
    var rows = [env.open("phoneMode", L("My Number", "Мой номер"), label: ownOptions.first(where: { $0.0 == own.rawValue })?.1 ?? "", action: {
        env.push(solvPickScreen(env: env, title: L("My Phone Number", "Мой номер телефона"), options: ownOptions, current: {
            SolvgramSettings.phoneNumberMode(isOwn: true, legacyHidden: env.sgBool("hidePhoneInSettings")).rawValue
        }, set: { value in
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.phoneMode)
            let _ = env.bridge.setBool("hidePhoneInSettings", value: NSNumber(value: value == "hidden"))
            NotificationCenter.default.post(name: SolvgramSettings.phoneNumbersDidChange, object: nil)
            solvChanged()
        }))
    })]
    if own == .custom {
        rows.append(SolvRow(id: "customPhone", kind: .input(text: UserDefaults.standard.string(forKey: SolvgramSettings.Key.customPhone) ?? "", placeholder: "+1 234 567 8900", number: false), onText: { text in
            UserDefaults.standard.set(text, forKey: SolvgramSettings.Key.customPhone)
            NotificationCenter.default.post(name: SolvgramSettings.phoneNumbersDidChange, object: nil)
        }, indent: true, searchParentID: "phoneMode"))
    }
    rows.append(env.open("otherPhoneMode", L("Other People's Numbers", "Номера собеседников"), label: otherOptions.first(where: { $0.0 == other.rawValue })?.1 ?? "", action: {
        env.push(solvPickScreen(env: env, title: L("Other People's Numbers", "Номера собеседников"), options: otherOptions, current: {
            SolvgramSettings.phoneNumberMode(isOwn: false).rawValue
        }, set: { value in
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.otherPhoneMode)
            NotificationCenter.default.post(name: SolvgramSettings.phoneNumbersDidChange, object: nil)
            solvChanged()
        }))
    }))
    return rows
}

private func solvPrivacy(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    let ghost = SolvgramSettings.ghostMode
    let exceptionCount = SolvgramSettings.ghostExceptions.count
    let starsCustom = UserDefaults.standard.bool(forKey: SolvgramSettings.Key.visualStars)
    var location = ""
    if UserDefaults.standard.object(forKey: SolvgramSettings.Key.fakeLatitude) != nil {
        location = String(format: "%.4f, %.4f", UserDefaults.standard.double(forKey: SolvgramSettings.Key.fakeLatitude), UserDefaults.standard.double(forKey: SolvgramSettings.Key.fakeLongitude))
    }

    var deviceRows: [SolvRow] = []
    deviceRows.append(env.toggle("visualStars", L("Custom Star Balance", "Свой баланс звёзд"), keys: [SolvgramSettings.Key.visualStars]))
    if starsCustom {
        deviceRows.append(SolvRow(id: "starsAmount", kind: .input(text: "\(UserDefaults.standard.integer(forKey: SolvgramSettings.Key.visualStarsAmount))", placeholder: "0", number: true), onText: { text in
            UserDefaults.standard.set(Int(text.filter(\.isNumber)) ?? 0, forKey: SolvgramSettings.Key.visualStarsAmount)
        }, indent: true, searchParentID: "visualStars"))
    }
    deviceRows.append(env.sgToggle("hideAccountInNotifications", L("Hide Account in Notifications", "Скрыть аккаунт в уведомлениях")))

    let master = env.toggle("ghost", L("Ghost Mode", "Режим призрака"), keys: [SolvgramSettings.Key.ghostMode])
    let activityRows: [SolvRow] = [
        env.activity("online", L("Online Status", "Статус «в сети»"), keys: [SolvgramSettings.Key.hideOnline], enabled: ghost),
        env.activity("typing", L("Typing", "Набор текста"), keys: ["disableTypingStatus"], enabled: ghost),
        env.activity("recording", L("Recording", "Запись"), L("Voice messages and round videos", "Голосовые и кружки"), keys: ["disableRecordingVoiceStatus", "disableRecordingRoundVideoStatus"], enabled: ghost),
        env.activity("uploads", L("Uploads", "Загрузка"), L("Photos, videos, round videos, files", "Фото, видео, кружки, файлы"), keys: ["disableUploadingPhotoStatus", "disableUploadingVideoStatus", "disableUploadingRoundVideoStatus", "disableUploadingFileStatus"], enabled: ghost),
        env.activity("stickers", L("Choosing Stickers", "Выбор стикера"), keys: ["disableChoosingStickerStatus"], enabled: ghost),
        env.activity("games", L("Games and Emoji", "Игры и эмодзи"), L("Playing, emoji reactions, speaking in voice chats", "Игры, реакции эмодзи, речь в видеочатах"), keys: ["disablePlayingGameStatus", "disableEmojiAcknowledgementStatus", "disableEmojiInteractionStatus", "disableSpeakingInGroupCallStatus"], enabled: ghost),
        env.activity("readReceipts", L("Read Receipts", "Прочтение сообщений"), L("Senders won't see you've read or listened to their messages", "Собеседник не увидит прочтение и прослушивание сообщений"), keys: [SolvgramSettings.Key.hideReadReceipts], enabled: ghost),
    ]
    let extraGhostRows: [SolvRow] = [
        SolvRow(id: "readOnAction", kind: .toggle(title: L("Read on Action", "Читать при ответе"), subtitle: L("Writing in a chat marks it read", "Сообщение в чат отмечает его прочитанным"), icon: nil, value: SolvgramSettings.readOnAction, enabled: ghost), onToggle: { value in
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.readOnAction)
            solvChanged()
        }),
        env.open("exceptions", L("Exceptions", "Исключения"), label: exceptionCount == 0 ? "" : "\(exceptionCount)", action: {
            env.push(solvExceptionsScreen(env: env))
        }),
    ]

    return [
        SolvSection(nil, footer: L("The selected options apply while Ghost Mode is on.", "Отмеченные параметры действуют, пока режим призрака включён."), [master]),
        SolvSection(L("What Ghost Mode Hides", "Что скрывает режим призрака"), activityRows),
        SolvSection(nil, footer: L("Use Exceptions, or the settings button in a chat's header, to change Ghost Mode for one chat.", "Для отдельного чата используйте исключения или кнопку настроек в шапке чата."), extraGhostRows),
        SolvSection(L("Stories", "Истории"), footer: L("Works on its own, with or without Ghost Mode.", "Работает и без режима призрака."), [
            env.toggle("storyViews", L("Hide Story Views", "Скрывать просмотр историй"), L("You won't appear in story viewer lists; stories you watched this way get a gray dashed ring", "Вас не будет в списке зрителей; такие истории обводятся серым пунктиром"), keys: [SolvgramSettings.Key.hideStoryViews]),
        ]),
        SolvSection(L("Location", "Геопозиция"), [
            env.toggle("fakeLocation", L("Spoof Location", "Подменять геопозицию"), L("Shares a chosen point instead of your GPS", "Отправляется выбранная точка вместо GPS"), keys: [SolvgramSettings.Key.fakeLocation]),
            env.open("pickOnMap", L("Pick on Map", "Выбрать на карте"), label: location, action: {
                env.push(SolvLocationPickerController())
            }),
        ]),
        SolvSection(L("Phone Numbers", "Номера телефонов"), footer: L("Hidden covers the number with a spoiler. Tap to reveal it. This changes only what you see on this device.", "Hidden скрывает номер под спойлером. Нажмите, чтобы раскрыть. Это меняет только отображение на этом устройстве."), solvPhoneNumbers(b)),
        SolvSection(L("Only on This Device", "Только на этом устройстве"), footer: L("Only you see these: nothing changes on the server, and paying still uses your real balance.", "Это видите только вы: на сервере ничего не меняется, а оплата идёт с настоящего баланса."), deviceRows),
    ]
}

private func solvCache(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [SolvSection(L("Solvgram Cache", "Кеш Solvgram"), SolvgramCacheCategory.allCases.map { category in
        env.open("cache." + category.rawValue, SolvgramCacheController.name(category), action: { env.push(SolvgramCacheController(context: env.context, category: category)) })
    } + [
        env.open("cache.exceptions", L("Saving Exceptions", "Исключения сохранения"), action: { env.push(SolvgramCaptureExceptionsController(context: env.context)) }),
    ])]
}

private func solvMessages(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Server Archive", "Серверный архив"), footer: L("In development.", "В разработке."), [
            env.open("serverArchive", L("Server Archive", "Серверный архив"), action: {
                env.push(SolvgramServerArchiveController(context: env.context))
            }),
        ]),
        SolvSection(L("Saved Data", "Сохранённые данные"), [
            env.open("cache", L("Solvgram Cache", "Кеш Solvgram"), label: L("Saving and clearing on this device", "Сохранение и очистка на устройстве"), action: {
                env.push(SolvgramCacheController(context: env.context))
            }),
        ]),
        SolvSection(L("Protected Content", "Защищённый контент"), [
            env.toggle("protected", L("Allow Saving and Forwarding", "Разрешить сохранение и пересылку"), keys: [SolvgramSettings.Key.allowProtectedContent]),
        ]),
        SolvSection(L("More", "Ещё"), [
            env.open("messageMenu", L("Message Menu", "Меню сообщения"), action: {
                env.push(solvScreen(env: env, title: { L("Message Menu", "Меню сообщения") }, build: solvMessageMenu))
            }),
        ]),
    ]
}

private func solvMessageMenu(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Long-Press Menu", "Меню по долгому нажатию"), footer: L("Items switched off stay in the Solvgram submenu.", "Выключенные пункты остаются в подменю Solvgram."), [
            env.sgToggle("contextShowSaveToCloud", L("Save to Saved Messages", "В «Избранное»")),
            env.sgToggle("contextShowHideForwardName", L("Forward Without Author", "Переслать без автора")),
            env.sgToggle("contextShowSelectFromUser", L("Select from User", "Выбрать от пользователя")),
            env.sgToggle("contextShowRestrict", L("Restrict", "Ограничить")),
            env.sgToggle("contextShowReport", L("Report", "Пожаловаться")),
            env.sgToggle("contextShowReply", L("Reply", "Ответить")),
            env.sgToggle("contextShowPin", L("Pin", "Закрепить")),
            env.sgToggle("contextShowSaveMedia", L("Save to Files", "Сохранить в «Файлы»")),
            env.sgToggle("contextShowMessageReplies", L("View Replies", "Показать ответы")),
            env.sgToggle("contextShowJson", L("Show JSON", "Показать JSON")),
        ]),
    ]
}

private func solvChats(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Chat", "Чат"), [
            env.toggle("hideAds", L("Hide Ads", "Скрыть рекламу"), L("Sponsored messages in channels", "Спонсорские сообщения в каналах"), keys: [SolvgramSettings.Key.hideAds]),
            env.toggle("businessBot", L("Hide Business Bot Bar", "Скрыть панель бизнес-бота"), keys: ["SolvgramHideBusinessBotBar"]),
            env.sgToggle("secondsInMessages", L("Seconds in Time", "Секунды во времени")),
            env.sgToggle("hideReactions", L("Hide Reactions", "Скрыть реакции")),
            env.sgToggle("snapDeletionEffect", L("Deletion Effect", "Эффект удаления"), L("The dust when a message is deleted", "Рассыпание при удалении")),
            env.sgToggle("doubleTapToEdit", L("Double Tap to Edit", "Двойной тап — изменить"), L("On your own messages", "На своих сообщениях")),
        ]),
        SolvSection(L("Input Field", "Поле ввода"), [
            env.sgToggle("inputToolbar", L("Formatting Panel", "Панель форматирования"), L("Above the keyboard", "Над клавиатурой")),
            env.sgToggle("recordingButton", L("Recording Button", "Кнопка записи")),
            env.sgToggle("sendAsButton", L("“Send As” Button", "Кнопка «Отправить как»")),
            env.sgToggle("sendWithReturnKey", L("Send with Return Key", "Отправка клавишей «Ввод»")),
            env.sgToggle("galleryCamera", L("Camera in Attachments", "Камера во вложениях")),
            env.sgToggle("galleryCameraPreview", L("Camera Preview", "Превью камеры"), enabled: env.sgBool("galleryCamera")),
        ]),
        SolvSection(L("Emoji and Stickers", "Эмодзи и стикеры"), [
            env.sgToggle("forceEmojiTab", L("Open Emoji Tab First", "Сначала вкладка эмодзи")),
            env.sgToggle("defaultEmojisFirst", L("Standard Emoji First", "Сначала обычные эмодзи")),
            env.sgToggle("stickerTimestamp", L("Time on Stickers", "Время на стикерах")),
        ]),
        SolvSection(L("Sticker Size", "Размер стикеров"), [
            env.slider("stickerSize"),
        ]),
        SolvSection(L("Channels", "Каналы"), [
            env.sgToggle("wideChannelPosts", L("Wide Channel Posts", "Широкие посты")),
            env.sgToggle("channelBottomButton", L("Bottom Button", "Кнопка внизу"), L("Mute or Discuss under a channel", "«Без звука» или «Обсудить»")),
            env.sgToggle("pullToNextChannel", L("Pull to Next Channel", "Свайп к следующему каналу")),
            env.sgToggle("pullToNextTopic", L("Pull to Next Topic", "Свайп к следующей теме")),
        ]),
    ]
}

private func solvChatList(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    let tabBarShown = !env.sgBool("hideTabBar")
    let restart = L("Applies after a restart.", "Применяется после перезапуска.")
    return [
        SolvSection(L("List", "Список"), [
            env.sgToggle("compactChatList", L("Compact Chat List", "Компактный список"), restart),
            env.sgToggle("compactMessagePreview", L("One-Line Previews", "Превью в одну строку"), restart),
            env.sgToggle("chatSwipeOptions", L("Swipe Actions", "Действия по свайпу"), restart),
            env.sgToggle("deleteChatSwipeOption", L("Delete by Swipe", "Удаление свайпом"), restart, enabled: env.sgBool("chatSwipeOptions")),
        ]),
        SolvSection(L("Stories", "Истории"), [
            env.sgToggle("hideStories", L("Hide Stories Bar", "Скрыть панель историй")),
            env.sgToggle("disableSwipeToRecordStory", L("No Swipe to Record", "Без свайпа для записи")),
            env.sgToggle("warnOnStoriesOpen", L("Ask Before Opening", "Спрашивать перед открытием")),
            env.sgToggle("showRepostToStory", L("“Repost to Story” in Sharing", "«Репост в историю» в меню")),
        ]),
        SolvSection(L("Folders", "Папки"), [
            env.sgToggle("foldersAtBottom", L("Folders at the Bottom", "Папки внизу")),
            env.sgToggle("allChatsHidden", L("Hide “All Chats”", "Скрыть «Все чаты»"), restart),
            env.sgToggle("compactFolderNames", L("Compact Folder Names", "Короткие названия папок"), restart),
            env.choice("allChatsTitleLengthOverride", L("“All Chats” Title", "Название «Все чаты»")),
            env.sgToggle("rememberLastFolder", L("Remember Last Folder", "Запоминать последнюю папку")),
        ]),
        SolvSection(L("Tab Bar", "Панель вкладок"), [
            env.sgToggle("hideTabBar", L("Hide Tab Bar", "Скрыть панель вкладок"), restart),
            env.sgToggle("showContactsTab", L("Contacts Tab", "Вкладка «Контакты»"), enabled: tabBarShown),
            env.sgToggle("showCallsTab", L("Calls Tab", "Вкладка «Звонки»"), enabled: tabBarShown),
            env.sgToggle("showTabNames", L("Tab Names", "Подписи вкладок"), restart, enabled: tabBarShown),
            env.sgToggle("tabBarSearchEnabled", L("Search Button", "Кнопка поиска"), enabled: tabBarShown),
            env.sgToggle("wideTabBar", L("Wide Tab Bar", "Широкая панель"), restart, enabled: tabBarShown),
        ]),
    ]
}

private func solvVoice(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    var changerRows: [SolvRow] = [env.choice("voiceEffect", L("Voice", "Голос"))]
    if SolvgramSettings.voiceEffect != "normal" {
        changerRows.append(env.slider("voiceEffectLevel", steps: [L("Subtle", "Слабо"), L("Light", "Заметно"), L("Medium", "Средне"), L("Strong", "Сильно"), L("Maximum", "Максимум")]))
        changerRows.append(env.slider("voiceSpeed", steps: ["0.6×", "0.8×", "1×", "1.2×", "1.4×"]))
    }
    let sections: [SolvSection] = [
        SolvSection(L("Voice Changer", "Изменение голоса"), footer: L("Changes the voice messages you record; lock the recording to hear it before sending. Each voice keeps its own strength. The settings button in a chat's header turns it on and off with the last voice picked.", "Меняет голос в записанных голосовых; зафиксируйте запись, чтобы послушать перед отправкой. Сила запоминается для каждого голоса. Кнопка настроек в шапке чата включает и выключает его с последним выбранным голосом.") + "\n\n" + L("1× is the standard tempo of the revised voice. Applies only while Voice Changer is on.", "1× — стандартный темп обновлённого голоса. Применяется только при включённом изменении голоса."), changerRows),
        SolvSection(L("Voice Messages", "Голосовые"), [
            env.sgToggle("forceBuiltInMic", L("Built-in Microphone", "Встроенный микрофон"), L("Even with headphones connected", "Даже с подключёнными наушниками")),
            env.choice("transcriptionBackend", L("Speech to Text", "Расшифровка")),
        ]),
        SolvSection(L("Round Videos", "Кружки"), [
            env.choice("roundVideoCamera", L("Camera", "Камера")),
            env.toggle("sendAsVoice", L("Send as Voice Message", "Отправлять голосовым"), L("A recorded round video goes as voice", "Записанный кружок уходит голосовым"), keys: ["LeadSendAsVoice"]),
        ]),
    ]
    return sections
}

private func solvMedia(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Photo Quality", "Качество фото"), [
            env.slider("outgoingPhotoQuality"),
        ]),
        SolvSection(L("Photos", "Фото"), [
            env.sgToggle("sendLargePhotos", L("Send Large Photos", "Отправлять большие фото"), L("Up to 2560 px", "До 2560 px")),
        ]),
        SolvSection(L("Video", "Видео"), [
            env.sgToggle("videoControlsInFooter", L("Video Controls Below", "Управление видео снизу")),
            env.sgToggle("swipeForVideoPIP", L("Swipe Up for Picture in Picture", "Свайп вверх — картинка в картинке")),
        ]),
        SolvSection(L("Speed", "Скорость"), [
            env.sgToggle("uploadSpeedBoost", L("Faster Uploads", "Быстрая отправка")),
            env.choice("downloadSpeedBoost", L("Faster Downloads", "Быстрая загрузка")),
        ]),
    ]
}

private func solvTranslation(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Translation", "Перевод"), footer: L("No Telegram Premium needed.", "Telegram Premium не нужен."), [
            env.choice("translationBackend", L("Translator", "Переводчик")),
            env.sgToggle("quickTranslateButton", L("Quick Translate Button", "Кнопка быстрого перевода")),
            env.openBridge("language", L("Language and Chat Translation", "Язык и перевод чатов")),
        ]),
    ]
}

private func solvProfiles(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Profiles", "Профили"), [
            env.sgToggle("showProfileId", L("Show ID", "Показывать ID")),
            env.sgToggle("showDC", L("Show Data Center", "Показывать дата-центр")),
            env.sgToggle("showRegDate", L("Registration Date", "Дата регистрации"), L("Approximate", "Приблизительная")),
            env.sgToggle("showCreationDate", L("Creation Date", "Дата создания"), L("Of groups and channels", "Групп и каналов")),
        ]),
        SolvSection(L("Name Color Saturation", "Насыщенность цветов имён"), [
            env.slider("accountColorsSaturation"),
        ]),
    ]
}

private func solvCalls(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    return [
        SolvSection(L("Calls", "Звонки"), [
            env.sgToggle("confirmCalls", L("Confirm Before Calling", "Подтверждать звонок")),
            env.sgToggle("enableVoipTcp", L("Calls over TCP", "Звонки через TCP"), L("Only if calls don't connect", "Только если звонки не соединяются")),
        ]),
        SolvSection(L("Notifications", "Уведомления"), [
            env.choice("pinnedMessageNotifications", L("Pinned Messages", "Закреплённые сообщения")),
            env.choice("mentionsAndRepliesNotifications", L("Mentions and Replies", "Упоминания и ответы")),
        ]),
    ]
}

// MARK: - Language

private func solvLanguageLabel() -> String {
    let chosen = UserDefaults.standard.string(forKey: SolvgramSettings.Key.language) ?? "system"
    let name = SolvgramSettings.isRussian ? "Русский" : "English"
    return chosen == "en" || chosen == "ru" ? name : L("System", "Системный") + " · " + name
}

/// "Use System Language", with the languages opening under it, one level in, while it is off.
private func solvLanguage(_ b: SolvBuild) -> [SolvSection] {
    let chosen = UserDefaults.standard.string(forKey: SolvgramSettings.Key.language) ?? "system"
    let followsSystem = chosen != "en" && chosen != "ru"
    let systemIsRussian = NSLocale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
    var rows: [SolvRow] = [
        SolvRow(id: "useSystemLanguage", kind: .toggle(title: L("Use System Language", "Как в системе"), subtitle: systemIsRussian ? "Русский" : "English", icon: SolvIcon(symbol: "iphone", rgb: gray), value: followsSystem, enabled: true), onToggle: { value in
            // Off: keep the language shown now, then it can be changed below.
            UserDefaults.standard.set(value ? "system" : (SolvgramSettings.isRussian ? "ru" : "en"), forKey: SolvgramSettings.Key.language)
            solvChanged()
        }),
    ]
    if !followsSystem {
        for option in [("en", "English", "EN"), ("ru", "Русский", "RU")] {
            var row = SolvRow(id: option.0, kind: .check(title: option.1, checked: chosen == option.0), onTap: {
                UserDefaults.standard.set(option.0, forKey: SolvgramSettings.Key.language)
                solvChanged()
            })
            row.indent = true
            rows.append(row)
        }
    }
    return [
        SolvSection(nil, footer: followsSystem ? L("Solvgram's own screens follow the device language, Russian or English. Turn this off to pick one.", "Экраны Solvgram следуют языку устройства: русский или английский. Выключите, чтобы выбрать язык.") : L("Solvgram's own screens use the language picked above.", "Экраны Solvgram на языке, выбранном выше."), rows),
    ]
}

// MARK: - Root

private func solvRoot(_ b: SolvBuild) -> [SolvSection] {
    let env = b.env
    let query = b.query.trimmingCharacters(in: .whitespaces).lowercased()
    var sections: [SolvSection] = []
    if query.isEmpty {
        sections.append(SolvSection([SolvRow(id: "appHeader", kind: .appHeader(title: "Solvgram"))]))
    }

    if !query.isEmpty {
        // Every row of every screen whose text matches, under "Category · Section".
        var found: [SolvSection] = []
        for category in solvCategories().flatMap({ $0 }) {
            for section in category.build(b) {
                let matches = Set(section.rows.filter { row in
                    return row.searchText.lowercased().contains(query) || (section.header?.lowercased().contains(query) ?? false)
                }.map(\.id))
                let rows = section.rows.filter { row in
                    matches.contains(row.id) || row.searchParentID.map(matches.contains) == true
                }.map { row -> SolvRow in
                    return SolvRow(id: category.id + "." + row.id, kind: row.kind, onToggle: row.onToggle, onTap: row.onTap, onSlide: row.onSlide, onText: row.onText, indent: row.indent, searchParentID: row.searchParentID)
                }
                if !rows.isEmpty {
                    found.append(SolvSection(category.title + (section.header.map { " · " + $0 } ?? ""), rows))
                }
            }
        }
        if found.isEmpty {
            found.append(SolvSection(nil, footer: L("No Results", "Ничего не найдено"), []))
        }
        return sections + found
    }

    var topRows: [SolvRow] = [
        env.open("solvgramLanguage", L("Language", "Язык"), label: solvLanguageLabel(), icon: SolvIcon(symbol: "solvgram.translation-voice", rgb: blue), action: {
            env.push(solvScreen(env: env, title: { L("Language", "Язык") }, build: solvLanguage))
        }),
    ]
    if env.bridge.isAvailable("appBadge").boolValue {
        topRows.append(env.open("appBadge", L("App Badge", "Бейдж приложения"), icon: SolvIcon(symbol: "solvgram.app-badge", rgb: 0xF477A0), action: { env.openAppBadge() }))
    }
    sections.append(SolvSection(topRows))

    for (index, group) in solvCategories().enumerated() {
        var rows = group.map { category in
            return env.open(category.id, category.title, icon: category.icon, action: {
                if category.id == "cache" {
                    env.push(SolvgramCacheController(context: env.context))
                    return
                }
                if category.id == "locator" {
                    env.push(SolvgramLocatorController(context: env.context))
                    return
                }
                env.push(solvScreen(env: env, title: {
                    return solvCategories().flatMap({ $0 }).first(where: { $0.id == category.id })?.title ?? category.title
                }, build: { b in
                    let current = solvCategories().flatMap({ $0 }).first(where: { $0.id == category.id }) ?? category
                    return [SolvSection([SolvRow(id: "hero", kind: .hero(title: current.title, subtitle: current.subtitle, icon: current.icon))])] + category.build(b)
                }))
            })
        }
        if index == 1 {
            rows.append(env.open("sessionBackup", L("Session Backup", "Резервная копия сессий"), icon: SolvIcon(symbol: "solvgram.accounts", rgb: gray), action: {
                env.push(SolvgramSessionBackupController(context: env.context))
            }))
        }
        sections.append(SolvSection(rows))
    }

    // Solvgram has its own major.minor version, separate from the Telegram version it is built on.
    let solvgramVersion = Bundle.main.infoDictionary?["SolvgramVersion"] as? String ?? ""
    let telegramVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    sections.append(SolvSection(nil, footer: "Solvgram \(solvgramVersion) · Telegram \(telegramVersion)", []))
    return sections
}

/// Opens the Solvgram menu over `host`, the Telegram screen it is opened from.
public func solvgramPresentSettings(context: AccountContext, from host: ViewController) {
    let env = SolvEnv(context: context)
    env.host = host
    env.bridge = SolvgramMenuBridge(context: context, openController: { [weak env] controller in
        env?.openTelegram(controller)
    })
    let root = SolvTableController(env: env, title: { L("Settings", "Настройки") }, isRoot: true, peers: .single([:]), build: solvRoot)
    let navigationController = UINavigationController(rootViewController: root)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    navigationController.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
    navigationController.view.tintColor = presentationData.theme.list.itemAccentColor
    // A sheet over Telegram, as the first Solvgram menus were: swiped down to close.
    navigationController.modalPresentationStyle = .pageSheet
    env.navigationController = navigationController
    // The bridge lives as long as the menu.
    objc_setAssociatedObject(navigationController, &solvEnvKey, env, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    host.present(navigationController, animated: true)
}

nonisolated(unsafe) private var solvEnvKey: UInt8 = 0

// MARK: - Choice, Exceptions

/// Picks one of `options`, for settings the bridge does not know.
private func solvPickScreen(env: SolvEnv, title: String, options: [(String, String)], current: @escaping () -> String, set: @escaping (String) -> Void) -> UIViewController {
    return solvScreen(env: env, title: { title }, build: { b in
        let value = current()
        return [SolvSection(options.map { option in
            return SolvRow(id: option.0, kind: .check(title: option.1, checked: option.0 == value), onTap: {
                set(option.0)
                env.pop()
            })
        })]
    })
}

private func solvExceptionsScreen(env: SolvEnv) -> UIViewController {
    let engine = env.context.engine
    let peers = solvRefresh.get()
    |> map { _ -> [Int64] in
        return Array(SolvgramSettings.ghostExceptions.keys).sorted()
    }
    |> distinctUntilChanged
    |> mapToSignal { ids -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
        return engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: solvgramEnginePeerId($0)) }))
        |> map { result -> [EnginePeer.Id: EnginePeer] in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id] = peer
                }
            }
            return peers
        }
    }
    return solvScreen(env: env, title: { L("Exceptions", "Исключения") }, peers: peers, build: { b in
        let presentationData = b.env.context.sharedContext.currentPresentationData.with { $0 }
        let exceptions = SolvgramSettings.ghostExceptions.sorted(by: { $0.key < $1.key })
        var rows: [SolvRow] = []
        for (key, exception) in exceptions {
            let peerId = solvgramEnginePeerId(key)
            let peer = b.peers[peerId]
            let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "\(key)"
            let label = exception == .hide ? L("Always On", "Всегда вкл.") : L("Always Off", "Всегда выкл.")
            rows.append(SolvRow(id: "\(key)", kind: .disclosure(title: title, label: label, icon: nil, peer: peer, enabled: true), onTap: {
                let actionSheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
                let set: (SolvgramSettings.GhostException?) -> Void = { value in
                    SolvgramSettings.setGhostException(value, peerId: key)
                    solvChanged()
                }
                actionSheet.addAction(UIAlertAction(title: L("Ghost Mode Always On", "Призрак всегда включён"), style: .default, handler: { _ in set(.hide) }))
                actionSheet.addAction(UIAlertAction(title: L("Ghost Mode Always Off", "Призрак всегда выключен"), style: .default, handler: { _ in set(.show) }))
                actionSheet.addAction(UIAlertAction(title: L("Remove Exception", "Удалить исключение"), style: .destructive, handler: { _ in set(nil) }))
                actionSheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                if let view = env.navigationController?.topViewController?.view {
                    actionSheet.popoverPresentationController?.sourceView = view
                    actionSheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
                }
                env.present(actionSheet)
            }))
        }
        let footer = L("Chats where Ghost Mode works differently from everywhere else. To add one, open the chat and tap the settings button in its header.", "Чаты, где режим призрака работает не так, как везде. Чтобы добавить чат, откройте его и нажмите на кнопку настроек в шапке.")
        if rows.isEmpty {
            return [SolvSection(nil, footer: L("No exceptions yet. ", "Исключений пока нет. ") + footer, [])]
        }
        return [SolvSection(nil, footer: footer, rows)]
    })
}

// MARK: - Pick on Map

private final class SolvLocationPickerController: UIViewController {
    private let mapView = MKMapView()
    private let pin = MKPointAnnotation()
    private var hasPin = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = L("Pick on Map", "Выбор на карте")
        self.mapView.frame = self.view.bounds
        self.mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.mapView)
        self.mapView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:))))
        self.navigationItem.largeTitleDisplayMode = .never
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("Save", "Сохранить"), style: .done, target: self, action: #selector(self.save))

        let defaults = UserDefaults.standard
        if defaults.object(forKey: SolvgramSettings.Key.fakeLatitude) != nil {
            let coordinate = CLLocationCoordinate2D(latitude: defaults.double(forKey: SolvgramSettings.Key.fakeLatitude), longitude: defaults.double(forKey: SolvgramSettings.Key.fakeLongitude))
            self.place(coordinate)
            self.mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000.0, longitudinalMeters: 3000.0), animated: false)
        }
    }

    private func place(_ coordinate: CLLocationCoordinate2D) {
        self.pin.coordinate = coordinate
        self.pin.title = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        if !self.hasPin {
            self.hasPin = true
            self.mapView.addAnnotation(self.pin)
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        self.place(self.mapView.convert(gesture.location(in: self.mapView), toCoordinateFrom: self.mapView))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func save() {
        guard self.hasPin else {
            let alert = UIAlertController(title: L("No Point Picked", "Точка не выбрана"), message: L("Tap the map where you want to appear.", "Нажмите на карту там, где хотите оказаться."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            self.present(alert, animated: true)
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(self.pin.coordinate.latitude, forKey: SolvgramSettings.Key.fakeLatitude)
        defaults.set(self.pin.coordinate.longitude, forKey: SolvgramSettings.Key.fakeLongitude)
        defaults.set(true, forKey: SolvgramSettings.Key.fakeLocation)
        solvChanged()
        self.navigationController?.popViewController(animated: true)
    }
}

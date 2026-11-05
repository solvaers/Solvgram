import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings

/// One place for everything Solvgram keeps on this device. Counting and clearing go through
/// SolvgramDeviceCache; the server is not involved.
public final class SolvgramCacheController: UITableViewController {
    private enum Section {
        case summary
        case categories
        case saving
        case chatTypes
        case exceptions
        case clear
    }

    private enum Toggle {
        case main
        case second
        case chat(SolvgramSettings.ChatKind)
    }

    private let context: AccountContext
    private let category: SolvgramCacheCategory?
    private var cache: SolvgramDeviceCache { self.context.solvgramDeviceCache }
    private var state: SolvgramDeviceCacheState
    private var statistics: SolvgramDeviceCacheStatistics?
    private var stateDisposable: Disposable?
    private var statisticsDisposable: Disposable?
    private var loading = true
    private var failed = false
    private var completedClear = false

    public init(context: AccountContext, category: SolvgramCacheCategory? = nil) {
        self.context = context
        self.category = category
        self.state = context.solvgramDeviceCache.currentState
        super.init(style: .insetGrouped)
        self.title = category.map(Self.name) ?? Self.text("Solvgram Cache", "Кеш Solvgram")
        self.navigationItem.backButtonDisplayMode = .minimal
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.stateDisposable?.dispose()
        self.statisticsDisposable?.dispose()
    }

    private static func text(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }
    private func text(_ en: String, _ ru: String) -> String { Self.text(en, ru) }

    static func name(_ category: SolvgramCacheCategory) -> String {
        switch category {
        case .deleted: return text("Deleted Messages", "Удалённые сообщения")
        case .edits: return text("Edit History", "История правок")
        case .disappearing: return text("Disappearing Messages", "Исчезающие сообщения")
        case .stories: return text("Stories", "Истории")
        case .media: return text("Media", "Медиа")
        }
    }

    private static func symbol(_ category: SolvgramCacheCategory) -> String {
        switch category {
        case .deleted: return "trash"
        case .edits: return "pencil"
        case .disappearing: return "timer"
        case .stories: return "circle.dashed"
        case .media: return "photo.on.rectangle"
        }
    }

    private static func chatName(_ chat: SolvgramSettings.ChatKind) -> String {
        switch chat {
        case .privateChats: return text("Private Chats", "Личные чаты")
        case .groups: return text("Groups", "Группы")
        case .channels: return text("Channels", "Каналы")
        }
    }

    private var captureKind: SolvgramSettings.CaptureKind? {
        switch self.category {
        case .deleted: return .deleted
        case .edits: return .edits
        default: return nil
        }
    }

    private var sections: [Section] {
        guard let category = self.category else {
            return [.summary, .categories, .exceptions, .clear]
        }
        var result: [Section] = [.summary]
        if category != .media { result.append(.saving) }
        if self.captureKind != nil { result.append(contentsOf: [.chatTypes, .exceptions]) }
        result.append(.clear)
        return result
    }

    private func size(_ value: Int64) -> String {
        value == 0 ? self.text("0 B", "0 Б") : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func summary(_ category: SolvgramCacheCategory) -> String {
        guard let statistics = self.statistics else {
            return self.loading ? self.text("Calculating…", "Подсчёт…") : self.text("Unavailable", "Не удалось подсчитать")
        }
        let value = statistics.categories[category] ?? SolvgramCacheCategoryStatistics()
        let count: String
        switch category {
        case .edits: count = self.text("Versions", "Версий")
        case .stories: count = self.text("Stories", "Историй")
        case .media: count = self.text("Files", "Файлов")
        default: count = self.text("Messages", "Сообщений")
        }
        return "\(count): \(value.count) · \(self.size(value.bytes))"
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 56
        self.stateDisposable = (self.cache.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            let finished = self.state.clearing && !state.clearing
            self.state = state
            if finished {
                self.completedClear = !state.failed
                self.refresh()
                if self.completedClear {
                    UIAccessibility.post(notification: .announcement, argument: self.text("Cleared", "Очищено"))
                }
            }
            self.tableView.reloadData()
        })
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.refresh()
    }

    private func refresh() {
        self.loading = true
        self.statisticsDisposable?.dispose()
        self.statisticsDisposable = (self.cache.statistics() |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self else { return }
            self.loading = false
            self.statistics = value
            self.failed = value == nil
            self.tableView.reloadData()
        })
    }

    // MARK: Toggles

    private func toggleRows() -> [(String, Toggle)] {
        switch self.category {
        case .deleted: return [(self.text("Save Deleted Messages", "Сохранять удалённые сообщения"), .main)]
        case .edits: return [(self.text("Save Edit History", "Сохранять историю правок"), .main)]
        case .disappearing: return [
            (self.text("Keep One-Time Photos and Videos", "Сохранять одноразовые фото и видео"), .main),
            (self.text("Keep Auto-Deleting Messages", "Сохранять сообщения с автоудалением"), .second),
        ]
        case .stories: return [(self.text("Hide Story Views", "Скрывать просмотр историй"), .main)]
        default: return []
        }
    }

    private func value(_ toggle: Toggle) -> Bool {
        switch (self.category, toggle) {
        case (.deleted, .main): return SolvgramSettings.saveDeleted
        case (.edits, .main): return SolvgramSettings.saveEdits
        case (.disappearing, .main): return SolvgramSettings.keepSelfDestructing
        case (.disappearing, .second): return UserDefaults.standard.bool(forKey: "LeadAntiAutoDelete")
        case (.stories, .main): return UserDefaults.standard.bool(forKey: SolvgramSettings.Key.hideStoryViews)
        case let (_, .chat(chat)):
            guard let kind = self.captureKind else { return false }
            return SolvgramSettings.captures(kind, in: chat)
        default: return false
        }
    }

    private func apply(_ toggle: Toggle, _ value: Bool) {
        switch (self.category, toggle) {
        case (.deleted, .main): UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.saveDeleted)
        case (.edits, .main): UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.saveEdits)
        case (.disappearing, .main): UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.keepSelfDestructing)
        case (.disappearing, .second): UserDefaults.standard.set(value, forKey: "LeadAntiAutoDelete")
        case (.stories, .main): UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.hideStoryViews)
        case let (_, .chat(chat)):
            if let kind = self.captureKind { SolvgramSettings.setCaptures(kind, in: chat, value) }
        default: break
        }
        // Marks in open chats follow the switch the next time they are drawn.
        NotificationCenter.default.post(name: Notification.Name("SolvgramCaptureSettingsDidChange"), object: nil)
        self.tableView.reloadData()
    }

    // MARK: Table

    public override func numberOfSections(in tableView: UITableView) -> Int { self.sections.count }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.sections[section] {
        case .summary, .exceptions, .clear: return 1
        case .categories: return SolvgramCacheCategory.allCases.count
        case .saving: return self.toggleRows().count
        case .chatTypes: return SolvgramSettings.ChatKind.allCases.count
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch self.sections[section] {
        case .summary: return self.text("On This Device", "На этом устройстве")
        case .categories: return self.text("Categories", "Категории")
        case .saving: return self.text("Saving", "Сохранение")
        case .chatTypes: return self.text("Save In", "Где сохранять")
        case .exceptions, .clear: return nil
        }
    }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch self.sections[section] {
        case .summary:
            if self.failed {
                return self.text("Could not calculate. Tap the size to retry. You can still clear it.", "Не удалось подсчитать. Нажмите на размер, чтобы повторить. Очистка по-прежнему доступна.")
            }
            return self.text("What Solvgram keeps on this device for the current account.", "То, что Solvgram хранит на этом устройстве для текущего аккаунта.")
        case .categories:
            return self.text("Open a category to set up saving and clear it separately.", "Откройте категорию, чтобы настроить сохранение и очистить её отдельно.")
        case .saving:
            switch self.category {
            case .deleted: return self.text("Messages others delete stay in their chats, in a dashed outline. Off: new ones are not kept and the outline is hidden; kept messages stay until cleared.", "Удалённые собеседником сообщения остаются в чате в пунктирной рамке. Выключено: новые не сохраняются, рамка скрыта; сохранённое остаётся до очистки.")
            case .edits: return self.text("An edited message shows its original text above the current one. Off: new edits are not kept and the original is hidden; saved history stays until cleared.", "Над изменённым сообщением показывается исходный текст. Выключено: новые правки не сохраняются, исходный текст скрыт; сохранённая история остаётся до очистки.")
            case .disappearing: return self.text("One-time photos and videos, and messages with a timer, stay in their chats.", "Одноразовые фото и видео, а также сообщения с таймером остаются в своих чатах.")
            case .stories: return self.text("You don't appear among viewers, and stories watched this way get a gray dashed ring. Off: the rings are hidden; the record stays until cleared.", "Вас нет среди зрителей, а такие истории обводятся серым пунктиром. Выключено: обводка скрыта; записи остаются до очистки.")
            default: return nil
            }
        case .chatTypes:
            return self.text("A chat's own rule in Exceptions comes first.", "Правило отдельного чата в «Исключениях» важнее.")
        case .exceptions:
            return self.text("Chats where saving works differently. You can also set it with the settings button in a chat's header.", "Чаты, где сохранение работает иначе. Это можно настроить и кнопкой настроек в шапке чата.")
        case .clear:
            if self.state.failed { return self.text("Clearing could not finish. Unlock the device, check free storage and retry. An interrupted clear resumes on its own.", "Не удалось завершить очистку. Разблокируйте устройство, проверьте свободное место и повторите. Прерванная очистка продолжится сама.") }
            if self.state.clearing { return self.text("Clearing…", "Идёт очистка…") }
            if self.completedClear { return self.text("Cleared. Removed messages and history will not come back.", "Очищено. Удалённые сообщения и история не вернутся.") }
            return self.text("Clearing removes kept data from the app for good. Ordinary messages stay.", "Очистка удаляет сохранённое из приложения насовсем. Обычные сообщения остаются.")
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        switch self.sections[indexPath.section] {
        case .summary:
            content.text = self.category.map(Self.name) ?? self.text("Solvgram Data", "Данные Solvgram")
            content.secondaryText = self.category.map(self.summary) ?? self.statistics.map { self.size($0.totalBytes) } ?? (self.loading ? self.text("Calculating…", "Подсчёт…") : self.text("Unavailable", "Не удалось подсчитать"))
            if self.loading {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }
            cell.selectionStyle = self.failed ? .default : .none
        case .categories:
            let category = SolvgramCacheCategory.allCases[indexPath.row]
            content.text = Self.name(category)
            content.secondaryText = self.summary(category)
            content.image = UIImage(systemName: Self.symbol(category))
            content.imageProperties.tintColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
        case .saving:
            let (title, toggle) = self.toggleRows()[indexPath.row]
            content.text = title
            cell.accessoryView = self.makeSwitch(title: title, toggle: toggle, enabled: true)
            cell.selectionStyle = .none
        case .chatTypes:
            let chat = SolvgramSettings.ChatKind.allCases[indexPath.row]
            content.text = Self.chatName(chat)
            let enabled = self.value(.main)
            content.textProperties.color = enabled ? .label : .secondaryLabel
            cell.accessoryView = self.makeSwitch(title: content.text ?? "", toggle: .chat(chat), enabled: enabled)
            cell.selectionStyle = .none
        case .exceptions:
            let count = SolvgramSettings.captureExceptions.count
            var value = UIListContentConfiguration.valueCell()
            value.text = self.text("Exceptions", "Исключения")
            value.secondaryText = count == 0 ? nil : "\(count)"
            cell.accessoryType = .disclosureIndicator
            cell.contentConfiguration = value
            return cell
        case .clear:
            content.text = self.category == nil ? self.text("Clear All Solvgram Data", "Очистить все данные Solvgram") : self.text("Clear This Category", "Очистить эту категорию")
            content.textProperties.color = self.state.clearing ? .tertiaryLabel : .systemRed
            cell.isUserInteractionEnabled = !self.state.clearing
            cell.accessibilityTraits = self.state.clearing ? [.button, .notEnabled] : .button
            if self.state.clearing {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    private func makeSwitch(title: String, toggle: Toggle, enabled: Bool) -> UISwitch {
        let control = UISwitch()
        control.isOn = self.value(toggle)
        control.isEnabled = enabled
        control.accessibilityLabel = title
        control.addAction(UIAction(handler: { [weak self, weak control] _ in
            self?.apply(toggle, control?.isOn ?? false)
        }), for: .valueChanged)
        return control
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch self.sections[indexPath.section] {
        case .summary:
            if self.failed { self.refresh() }
        case .categories:
            self.navigationController?.pushViewController(SolvgramCacheController(context: self.context, category: SolvgramCacheCategory.allCases[indexPath.row]), animated: true)
        case .exceptions:
            self.navigationController?.pushViewController(SolvgramCaptureExceptionsController(context: self.context), animated: true)
        case .clear:
            self.confirmClear(sourceView: tableView.cellForRow(at: indexPath))
        case .saving, .chatTypes:
            break
        }
    }

    private func confirmClear(sourceView: UIView?) {
        guard !self.state.clearing else { return }
        let message: String
        switch self.category {
        case .deleted: message = self.text("Kept deleted messages will be removed from the app with their files. They will not come back.", "Сохранённые удалённые сообщения удалятся из приложения вместе с файлами. Они не вернутся.")
        case .edits: message = self.text("Saved original texts will be removed. Current message texts stay.", "Сохранённые исходные тексты удалятся. Текущий текст сообщений останется.")
        case .disappearing: message = self.text("Kept disappearing messages and their files will be removed from the app.", "Сохранённые исчезающие сообщения и их файлы удалятся из приложения.")
        case .stories: message = self.text("The record of stories you viewed anonymously will be removed, with their gray rings.", "Запись анонимно просмотренных историй удалится вместе с серой обводкой.")
        case .media: message = self.text("Downloaded files of kept messages will be removed from this device. Messages stay.", "Скачанные файлы сохранённых сообщений удалятся с устройства. Сообщения останутся.")
        case nil: message = self.text("All kept deleted and disappearing messages, edit history, anonymous story views and their files will be removed from the app. Ordinary messages stay.", "Все сохранённые удалённые и исчезающие сообщения, история правок, анонимные просмотры историй и их файлы удалятся из приложения. Обычные сообщения останутся.")
        }
        let alert = UIAlertController(title: self.text("Clear?", "Очистить?"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: self.text("Clear", "Очистить"), style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            self.completedClear = false
            self.cache.clear(categories: self.category.map { Set([$0]) } ?? Set(SolvgramCacheCategory.allCases))
        }))
        self.present(alert, animated: true)
    }
}

import Foundation
import UIKit
import AccountContext
import TelegramCore
import SGSimpleSettings

/// Server-owned watch list. Dismissing this screen never pauses monitoring.
public final class SolvgramLocatorController: UITableViewController {
    private let context: AccountContext
    private var state: SolvgramLocatorState?
    private var busy = false
    private var failure = false
    private var operation: Task<Void, Never>?
    private var timer: Timer?
    private var pendingReference = ""

    public init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
        self.title = self.text("Locator", "Локатор")
        self.navigationItem.backButtonDisplayMode = .minimal
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.operation?.cancel(); self.timer?.invalidate() }
    private func text(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 64
        guard SolvgramServerArchive.serverFeaturesEnabled else {
            self.tableView.backgroundView = solvgramInDevelopmentView(symbol: "location.magnifyingglass")
            self.tableView.separatorStyle = .none
            return
        }
        self.refreshControl = UIRefreshControl()
        self.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard SolvgramServerArchive.serverFeaturesEnabled else { return }
        self.load()
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.presentedViewController == nil else { return }
                self.load()
            }
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.timer?.invalidate()
        self.timer = nil
    }

    @objc private func refresh() { self.load() }

    private func load(_ body: [String: String]? = nil) {
        guard !self.busy else { self.refreshControl?.endRefreshing(); return }
        guard self.context.solvgramServerArchive.currentState.connected else {
            self.state = nil
            self.tableView.reloadData()
            self.refreshControl?.endRefreshing()
            return
        }
        self.busy = true
        self.tableView.reloadData()
        self.operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.state = try await self.context.solvgramServerArchive.locatorControl(body)
                self.failure = false
            } catch {
                self.failure = true
                if body != nil {
                    let alert = UIAlertController(title: self.text("Could Not Save", "Не удалось сохранить"), message: self.text("Check the connection and profile address, then try again. You can track up to 20 profiles.", "Проверьте подключение и адрес профиля, затем повторите. Можно отслеживать до 20 профилей."), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
            self.busy = false
            self.refreshControl?.endRefreshing()
            self.tableView.reloadData()
        }
    }

    public override func numberOfSections(in tableView: UITableView) -> Int { SolvgramServerArchive.serverFeaturesEnabled ? 3 : 0 }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 1 ? max(1, self.state?.profiles.count ?? 0) : 1
    }
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? self.text("Profiles", "Профили") : nil
    }
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return self.text("The server checks selected profiles about once a minute and sends changes to Saved Messages, even while Solvgram is closed. It tracks names, usernames, photos, bio, emoji status, stories, gifts and other available profile fields. Only data visible to your connected Telegram account can be tracked.", "Сервер проверяет выбранные профили примерно раз в минуту и отправляет изменения в «Избранное», даже когда Solvgram закрыт. Отслеживаются имя, @имя, фото, описание, эмодзи-статус, истории, подарки и другие доступные поля профиля. Доступны только данные, которые Telegram показывает подключённому аккаунту.")
        }
        if section == 1 { return self.text("Tap a profile to pause, resume or remove it. The first check saves its initial state. Telegram rate limits may delay checks.", "Нажмите на профиль, чтобы приостановить, возобновить или удалить отслеживание. Первая проверка сохраняет исходное состояние. Ограничения Telegram могут задерживать проверки.") }
        return nil
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        let connected = self.context.solvgramServerArchive.currentState.connected
        if indexPath.section == 0 {
            content.text = self.text("Locator", "Локатор")
            content.image = SolvgramSettingsIcons.image(named: "locator")
            if !connected { content.secondaryText = self.text("Connect the server to start", "Подключите сервер для начала работы") }
            else if self.failure { content.secondaryText = self.text("Could not refresh. Pull to retry.", "Не удалось обновить. Потяните вниз для повтора.") }
            else if self.busy && self.state == nil { content.secondaryText = self.text("Loading…", "Загрузка…") }
            else { content.secondaryText = self.state?.online == true ? self.text("Server active · Saved Messages", "Сервер работает · Результаты в «Избранном»") : self.text("Server temporarily unavailable", "Сервер временно недоступен") }
        } else if indexPath.section == 1 {
            if let profiles = self.state?.profiles, !profiles.isEmpty {
                let profile = profiles[indexPath.row]
                content.text = profile.title.isEmpty ? profile.reference : profile.title
                var details = profile.enabled == 0 ? self.text("Paused", "Приостановлено") : profile.checkedAt == nil ? self.text("Awaiting first check", "Ожидает первой проверки") : self.text("Tracking", "Отслеживается")
                if let error = profile.error {
                    details = error.hasPrefix("partial:") ? self.text("Tracking · Some fields unavailable", "Отслеживается · Часть данных недоступна") : self.text("Could not check profile. Verify access and address.", "Не удалось проверить профиль. Проверьте доступ и адрес.")
                }
                if let date = profile.checkedAt {
                    details += " · " + DateFormatter.localizedString(from: Date(timeIntervalSince1970: date), dateStyle: .short, timeStyle: .short)
                }
                content.secondaryText = details
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = self.text("No profiles yet", "Профилей пока нет")
                content.secondaryText = self.text("Add a profile to begin tracking changes.", "Добавьте профиль, чтобы отслеживать изменения.")
            }
        } else {
            content.text = connected ? self.text("Add Profile", "Добавить профиль") : self.text("Connect Server", "Подключить сервер")
            content.textProperties.color = self.busy ? .tertiaryLabel : .systemBlue
        }
        let actionable = indexPath.section == 2 || (indexPath.section == 1 && !(self.state?.profiles.isEmpty ?? true))
        cell.isUserInteractionEnabled = !actionable || !self.busy
        cell.selectionStyle = actionable && !self.busy ? .default : .none
        if actionable { cell.accessibilityTraits = self.busy ? [.button, .notEnabled] : .button }
        cell.contentConfiguration = content
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !self.busy else { return }
        if indexPath.section == 2 {
            guard self.context.solvgramServerArchive.currentState.connected else {
                self.navigationController?.pushViewController(SolvgramServerArchiveController(context: self.context), animated: true)
                return
            }
            let alert = UIAlertController(title: self.text("Add Profile", "Добавить профиль"), message: self.text("Enter a @username, t.me link, known user ID, or me for your own profile.", "Введите @имя, ссылку t.me, известный ID пользователя или me для своего профиля."), preferredStyle: .alert)
            alert.addTextField { field in
                field.text = self.pendingReference
                field.placeholder = "@username"
                field.accessibilityLabel = self.text("Profile address", "Адрес профиля")
                field.autocorrectionType = .no
                field.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
            alert.addAction(UIAlertAction(title: self.text("Track", "Отслеживать"), style: .default, handler: { [weak self, weak alert] _ in
                self?.pendingReference = alert?.textFields?.first?.text ?? ""
                self?.load(["action": "add", "reference": self?.pendingReference ?? ""])
            }))
            self.present(alert, animated: true)
        } else if indexPath.section == 1, let profiles = self.state?.profiles, indexPath.row < profiles.count {
            let profile = profiles[indexPath.row]
            let alert = UIAlertController(title: profile.title.isEmpty ? profile.reference : profile.title, message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: profile.enabled == 0 ? self.text("Resume", "Возобновить") : self.text("Pause", "Приостановить"), style: .default, handler: { [weak self] _ in
                self?.load(["action": "set_enabled", "id": profile.id, "enabled": profile.enabled == 0 ? "1" : "0"])
            }))
            alert.addAction(UIAlertAction(title: self.text("Remove", "Удалить"), style: .destructive, handler: { [weak self] _ in self?.load(["action": "remove", "id": profile.id]) }))
            alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
            alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            alert.popoverPresentationController?.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
            self.present(alert, animated: true)
        }
    }
}

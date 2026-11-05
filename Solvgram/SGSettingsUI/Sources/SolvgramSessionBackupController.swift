import Foundation
import UIKit
import AccountContext
import SGSimpleSettings

/// A regular destination inside Solvgram's own UIKit navigation stack.
final class SolvgramSessionBackupController: UITableViewController {
    private let store: SolvgramSessionBackupManaging
    private var sessions: [SolvgramSessionBackupSummary] = []
    private var pendingOperation: String?
    private let formatter = DateFormatter()

    convenience init(context: AccountContext) { self.init(store: SolvgramSessionBackupStore(context: context)) }
    init(store: SolvgramSessionBackupManaging) {
        self.store = store
        super.init(style: .insetGrouped)
        self.formatter.dateStyle = .medium
        self.formatter.timeStyle = .short
        self.formatter.locale = Locale(identifier: SolvgramSettings.isRussian ? "ru_RU" : "en_US")
        self.navigationItem.backButtonDisplayMode = .minimal
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func text(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.text("Session Backup", "Резервная копия сессий")
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 74
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "backup")
        self.store.didUpdate = { [weak self] in self?.reload() }
        self.store.didFinish = { [weak self] result, error in
            guard let self else { return }
            let operation = self.pendingOperation
            self.pendingOperation = nil
            if error != nil {
                self.showMessage(self.text("Couldn't complete the operation. Please try again.", "Не удалось выполнить операцию. Попробуйте ещё раз."))
            } else if let result, let operation {
                self.showMessage(operation == "restore" ? self.text("Sessions restored: ", "Восстановлено сессий: ") + result : self.text("Sessions backed up: ", "Сохранено сессий: ") + result)
            }
        }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); self.store.start(); self.reload() }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if self.isMovingFromParent || self.navigationController == nil || self.navigationController?.isBeingDismissed == true { self.store.stop() } }
    deinit { self.store.stop() }

    private func reload() {
        self.sessions = self.store.sessions
        self.tableView.reloadData()
        if self.store.busy {
            let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating()
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else { self.navigationItem.rightBarButtonItem = nil }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : section == 1 ? max(1, self.sessions.count) : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 1 ? self.text("Saved Sessions", "Сохранённые сессии") : nil }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return self.text("Backups are kept in this device's Keychain. Only sessions that are still active on Telegram can be restored.", "Копии хранятся в Связке ключей устройства. Восстановить можно только сессии, которые ещё активны в Telegram.") }
        if section == 1 { return self.text("Tap a saved session to manage its backup and account.", "Нажмите на сессию, чтобы управлять её копией и аккаунтом.") }
        return nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "backup", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = !self.store.busy
        content.textProperties.color = .label
        if indexPath.section == 0 {
            content.text = indexPath.row == 0 ? self.text("Create Backup", "Создать резервную копию") : self.text("Restore Sessions", "Восстановить сессии")
            content.textProperties.color = .systemBlue
            if indexPath.row == 1 && self.sessions.isEmpty { cell.isUserInteractionEnabled = false; content.textProperties.color = .secondaryLabel }
        } else if indexPath.section == 1 {
            if self.sessions.isEmpty {
                content.text = self.text("No Saved Sessions", "Нет сохранённых сессий")
                content.secondaryText = self.text("Create a backup of the accounts added to Solvgram.", "Создайте копию аккаунтов, добавленных в Solvgram.")
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
                cell.isUserInteractionEnabled = false
            } else {
                let session = self.sessions[indexPath.row]
                content.text = session.name
                content.secondaryText = (session.loggedIn ? self.text("Added to Solvgram", "Добавлен в Solvgram") : self.text("Available to restore", "Можно восстановить")) + "\n" + self.formatter.string(from: session.date)
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            content.text = self.text("Delete All Backups", "Удалить все резервные копии")
            content.textProperties.color = self.sessions.isEmpty ? .secondaryLabel : .systemRed
            cell.isUserInteractionEnabled = !self.store.busy && !self.sessions.isEmpty
        }
        if self.store.busy { content.textProperties.color = .secondaryLabel }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !self.store.busy else { return }
        if indexPath.section == 0 {
            if indexPath.row == 0 { self.pendingOperation = "backup"; self.store.createBackup() }
            else if !self.sessions.isEmpty { self.pendingOperation = "restore"; self.store.restoreBackups() }
        } else if indexPath.section == 1, self.sessions.indices.contains(indexPath.row) {
            self.showSession(self.sessions[indexPath.row])
        } else if indexPath.section == 2, !self.sessions.isEmpty {
            self.confirm(title: self.text("Delete all backups?", "Удалить все резервные копии?"), message: self.text("Accounts stay signed in to Solvgram. Their saved copies will be deleted from Keychain.", "Аккаунты останутся в Solvgram. Их сохранённые копии будут удалены из Связки ключей.")) { [weak self] in self?.store.deleteBackup(id: nil) }
        }
    }

    private func showSession(_ session: SolvgramSessionBackupSummary) {
        let sheet = UIAlertController(title: session.name, message: "ID: \(session.userId)\n" + self.formatter.string(from: session.date), preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: self.text("Delete Backup", "Удалить резервную копию"), style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            self.confirm(title: self.text("Delete this backup?", "Удалить эту резервную копию?"), message: self.text("The account stays signed in to Solvgram.", "Аккаунт останется в Solvgram.")) { [weak self] in self?.store.deleteBackup(id: session.id) }
        }))
        if session.loggedIn {
            sheet.addAction(UIAlertAction(title: self.text("Remove Account from App", "Убрать аккаунт из приложения"), style: .destructive, handler: { [weak self] _ in
                guard let self else { return }
                self.confirm(title: self.text("Remove account from Solvgram?", "Убрать аккаунт из Solvgram?"), message: self.text("The backup stays in Keychain. You can restore the account while this session remains active on Telegram.", "Копия останется в Связке ключей. Аккаунт можно восстановить, пока эта сессия активна в Telegram.")) { [weak self] in self?.store.removeFromApp(id: session.id) }
            }))
        }
        sheet.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
        self.present(sheet, animated: true)
    }
    private func confirm(title: String, message: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: self.text("Delete", "Удалить"), style: .destructive, handler: { _ in action() }))
        if let presented = self.presentedViewController {
            presented.dismiss(animated: true) { [weak self] in self?.present(alert, animated: true) }
        } else { self.present(alert, animated: true) }
    }
    private func showMessage(_ message: String) {
        guard self.viewIfLoaded?.window != nil, self.presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}

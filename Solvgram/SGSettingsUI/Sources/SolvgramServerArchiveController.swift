import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings

/// Native account-scoped connection UI. The pairing code is never persisted.
public final class SolvgramServerArchiveController: UITableViewController {
    private let context: AccountContext
    private let archive: SolvgramServerArchive
    private var state: SolvgramServerArchiveState
    private var disposable: Disposable?

    public init(context: AccountContext) {
        self.context = context
        self.archive = context.solvgramServerArchive
        self.state = self.archive.currentState
        super.init(style: .insetGrouped)
        self.title = self.text("Server Archive", "Серверный архив")
        self.navigationItem.backButtonDisplayMode = .minimal
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { self.disposable?.dispose() }

    private func text(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 56
        guard SolvgramServerArchive.serverFeaturesEnabled else {
            self.tableView.backgroundView = solvgramInDevelopmentView(symbol: "externaldrive.badge.icloud")
            self.tableView.separatorStyle = .none
            return
        }
        self.disposable = (self.archive.state |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.state = value
            self?.tableView.reloadData()
        })
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard SolvgramServerArchive.serverFeaturesEnabled else { return }
        self.archive.refreshCacheStats()
    }

    public override func numberOfSections(in tableView: UITableView) -> Int { SolvgramServerArchive.serverFeaturesEnabled ? 4 : 0 }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return self.state.connected ? 4 : 1
        case 2: return 2
        default: return self.state.connected ? 2 : 1
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return self.text("Server Archive", "Серверный архив")
        case 1: return self.text("Connection", "Подключение")
        case 2: return self.text("Archive Cache", "Кеш архива")
        default: return nil
        }
    }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return self.text("The server keeps records for 24 hours after the last captured change. Open Solvgram at least once a day to sync. Downloaded archive data stays in this device's separate cache until you clear it.", "Сервер хранит записи 24 часа после последнего сохранённого изменения. Открывайте Solvgram хотя бы раз в сутки для синхронизации. Скачанный архив остаётся в отдельном кеше на этом устройстве до его очистки.")
        case 1:
            if let error = self.state.error {
                switch error {
                case "invalidPairing": return self.text("The code expired, was already used, or belongs to another Telegram account. Get a new code and try again.", "Код истёк, уже использован или относится к другому аккаунту Telegram. Получите новый код и повторите подключение.")
                case "unauthorized": return self.text("Device access expired or was revoked. Connect again with a new code.", "Доступ устройства истёк или отозван. Подключитесь заново с новым кодом.")
                case "invalidEndpoint": return self.text("Enter an HTTPS server address without a path, query or login.", "Введите HTTPS-адрес сервера без пути, параметров и логина.")
                case "keychain": return self.text("Could not save the access key. Unlock the device and try again.", "Не удалось сохранить ключ доступа. Разблокируйте устройство и повторите попытку.")
                case "collectorOffline": return self.text("The server is disconnected from Telegram. Existing records are available, but recording needs to be restarted on the server.", "Сервер не подключён к Telegram. Сохранённый архив доступен, но запись новых сообщений нужно возобновить на сервере.")
                case "localArchive": return self.text("Could not save or clear the device archive. Check available storage, unlock the device and try again.", "Не удалось сохранить или очистить архив на устройстве. Проверьте свободное место, разблокируйте устройство и повторите попытку.")
                case "archiveFormat": return self.text("Could not read the server archive. Tap Sync Now to retry.", "Не удалось прочитать архив сервера. Нажмите «Синхронизировать», чтобы повторить попытку.")
                default: return self.text("Could not finish syncing. Check your connection and tap Sync Now to retry.", "Не удалось завершить синхронизацию. Проверьте соединение и нажмите «Синхронизировать».")
                }
            }
            return self.text("Access is linked to this Telegram account. Get a single-use connection code from the server owner. Connecting enables keeping deleted messages, edits and disappearing media on this device.", "Доступ привязан к этому аккаунту Telegram. Получите одноразовый код подключения у владельца сервера. Подключение включает сохранение удалённых сообщений, правок и исчезающих медиа на этом устройстве.")
        case 2:
            return self.text("This size covers downloads from the server. Solvgram Cache also includes local saves and lets you clear each category separately. Saved messages appear in their chats.", "Здесь показаны скачанные с сервера данные. В «Кеше Solvgram» также учтены локальные сохранения; каждую категорию можно очистить отдельно. Сохранённые сообщения отображаются в своих чатах.")
        default:
            return self.state.connected ? self.text("Disconnecting this device does not stop recording on the server or remove already restored messages.", "Отключение устройства не останавливает запись на сервере и не удаляет уже восстановленные сообщения.") : nil
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            content.text = self.text("Server Archive", "Серверный архив")
            content.secondaryText = self.text("Deleted · Edited · Disappearing", "Удалённые · Изменённые · Исчезающие")
            content.image = UIImage(systemName: "externaldrive.badge.icloud")
            content.imageProperties.tintColor = .systemBlue
        } else if indexPath.section == 1 {
            switch indexPath.row {
            case 0:
                content.text = self.text("Status", "Состояние")
                if self.state.busy {
                    content.secondaryText = self.state.clearing ? self.text("Clearing Archive…", "Очистка архива…") : self.state.connected ? self.text("Syncing…", "Синхронизация…") : self.text("Connecting…", "Подключение…")
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    spinner.accessibilityLabel = content.secondaryText
                    cell.accessoryView = spinner
                } else if self.state.error != nil {
                    content.secondaryText = self.text("Needs attention", "Требуется внимание")
                } else {
                    content.secondaryText = self.state.connected ? self.text("Connected", "Подключён") : self.text("Not connected", "Не подключён")
                }
            case 1:
                content.text = self.text("Last Sync", "Последняя синхронизация")
                content.secondaryText = self.state.lastSync.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium) } ?? self.text("Not yet synced", "Ещё не было")
            case 2:
                content.text = self.text("Restored This Session", "Восстановлено за сеанс")
                content.secondaryText = String(self.state.restored)
            default:
                content.text = self.text("Server", "Сервер")
                content.secondaryText = self.state.endpoint
            }
        } else if indexPath.section == 2 {
            if indexPath.row == 0 {
                content.text = self.text("On This Device", "На этом устройстве")
                let size = ByteCountFormatter.string(fromByteCount: self.state.cacheBytes, countStyle: .file)
                content.secondaryText = size + " · " + self.text("Records: ", "Записей: ") + String(self.state.cacheCount)
            } else {
                content.text = self.text("Manage Solvgram Cache", "Управление кешем Solvgram")
                content.secondaryText = self.text("All local saves · Clear by category", "Все локальные сохранения · Очистка по категориям")
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                cell.accessibilityTraits = .button
            }
        } else {
            let reconnect = !self.state.connected || self.state.error == "unauthorized"
            if indexPath.row == 0 {
                content.text = reconnect ? self.text("Connect with Code", "Подключить по коду") : self.text("Sync Now", "Синхронизировать")
                content.textProperties.color = self.state.busy ? .tertiaryLabel : .systemBlue
            } else {
                content.text = self.text("Disconnect This Device", "Отключить устройство")
                content.textProperties.color = self.state.busy ? .tertiaryLabel : .systemRed
            }
            cell.selectionStyle = self.state.busy ? .none : .default
            cell.isUserInteractionEnabled = !self.state.busy
            cell.accessibilityTraits = self.state.busy ? [.button, .notEnabled] : .button
        }
        cell.contentConfiguration = content
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2, indexPath.row == 1 {
            self.navigationController?.pushViewController(SolvgramCacheController(context: self.context), animated: true)
            return
        }
        guard !self.state.busy, indexPath.section == 3 else { return }
        if indexPath.row == 1 {
            let alert = UIAlertController(title: self.text("Disconnect This Device?", "Отключить устройство?"), message: self.text("The server will keep recording. Messages already restored stay on this device.", "Сервер продолжит запись. Уже восстановленные сообщения останутся на устройстве."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
            alert.addAction(UIAlertAction(title: self.text("Disconnect", "Отключить"), style: .destructive, handler: { [weak self] _ in self?.archive.disconnect() }))
            self.present(alert, animated: true)
        } else if !self.state.connected || self.state.error == "unauthorized" {
            self.askToConnect()
        } else {
            self.archive.syncNow()
        }
    }

    private func askToConnect() {
        let alert = UIAlertController(title: self.text("Connect Archive", "Подключить архив"), message: self.text("Enter your server address and a single-use code. Telegram login codes and passwords are not needed here.", "Введите адрес сервера и одноразовый код подключения. Код входа и пароль Telegram здесь не нужны."), preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.state.endpoint
            field.placeholder = self.text("HTTPS server address", "HTTPS-адрес сервера")
            field.accessibilityLabel = field.placeholder
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = self.text("Connection code", "Код подключения")
            field.accessibilityLabel = field.placeholder
            field.textContentType = .oneTimeCode
            field.keyboardType = .asciiCapable
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: self.text("Cancel", "Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: self.text("Connect", "Подключить"), style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            self.archive.connect(endpoint: fields[0].text ?? "", code: fields[1].text ?? "")
        }))
        self.present(alert, animated: true)
    }
}

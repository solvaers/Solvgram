import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import SGSimpleSettings

private func captureText(_ en: String, _ ru: String) -> String { SolvgramSettings.isRussian ? ru : en }

private func capturePeerTitle(_ peer: EnginePeer?, fallback: Int64, context: AccountContext) -> String {
    guard let peer else { return "\(fallback)" }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
}

/// Rules for one chat (save or don't save deleted messages and edits there), and clearing one chat.
private func presentCaptureActions(for peerId: Int64, title: String, context: AccountContext, from controller: UIViewController, sourceView: UIView?, changed: @escaping () -> Void) {
    let current = SolvgramSettings.captureException(peerId: peerId)
    let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    let set: (SolvgramSettings.CaptureException?) -> Void = { value in
        SolvgramSettings.setCaptureException(value, peerId: peerId)
        NotificationCenter.default.post(name: Notification.Name("SolvgramCaptureSettingsDidChange"), object: nil)
        changed()
    }
    let mark: (SolvgramSettings.CaptureException?) -> String = { $0 == current ? " ✓" : "" }
    sheet.addAction(UIAlertAction(title: captureText("Always Save Here", "Всегда сохранять здесь") + mark(.save), style: .default, handler: { _ in set(.save) }))
    sheet.addAction(UIAlertAction(title: captureText("Never Save Here", "Не сохранять здесь") + mark(.skip), style: .default, handler: { _ in set(.skip) }))
    if current != nil {
        sheet.addAction(UIAlertAction(title: captureText("Remove Exception", "Удалить исключение"), style: .default, handler: { _ in set(nil) }))
    }
    sheet.addAction(UIAlertAction(title: captureText("Clear Saved Data in This Chat", "Очистить сохранённое в этом чате"), style: .destructive, handler: { [weak controller] _ in
        guard let controller else { return }
        let alert = UIAlertController(title: captureText("Clear This Chat?", "Очистить этот чат?"), message: captureText("Kept deleted and disappearing messages, edit history and anonymous story views of this chat will be removed from the app. They will not come back.", "Сохранённые удалённые и исчезающие сообщения, история правок и анонимные просмотры историй этого чата удалятся из приложения. Они не вернутся."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: captureText("Cancel", "Отмена"), style: .cancel))
        alert.addAction(UIAlertAction(title: captureText("Clear", "Очистить"), style: .destructive, handler: { _ in
            context.solvgramDeviceCache.clear(categories: Set(SolvgramCacheCategory.allCases), peerId: solvgramEnginePeerId(peerId), completion: { success in
                UIAccessibility.post(notification: .announcement, argument: success ? captureText("Cleared", "Очищено") : captureText("Could not clear", "Не удалось очистить"))
            })
        }))
        controller.present(alert, animated: true)
    }))
    sheet.addAction(UIAlertAction(title: captureText("Cancel", "Отмена"), style: .cancel))
    if let sourceView {
        sheet.popoverPresentationController?.sourceView = sourceView
        sheet.popoverPresentationController?.sourceRect = sourceView.bounds
    }
    controller.present(sheet, animated: true)
}

/// Saving exceptions, styled like Privacy: chats with their own rule; add, change, remove.
public final class SolvgramCaptureExceptionsController: UITableViewController {
    private let context: AccountContext
    private var ids: [Int64] = []
    private var peers: [EnginePeer.Id: EnginePeer] = [:]
    private var peersDisposable: Disposable?

    public init(context: AccountContext) {
        self.context = context
        super.init(style: .insetGrouped)
        self.title = captureText("Exceptions", "Исключения")
        self.navigationItem.backButtonDisplayMode = .minimal
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction(handler: { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(SolvgramCaptureChatPickerController(context: self.context, picked: { [weak self] in
                self?.reload()
            }), animated: true)
        }))
        self.navigationItem.rightBarButtonItem?.accessibilityLabel = captureText("Add Chat", "Добавить чат")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.peersDisposable?.dispose() }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reload()
    }

    private func reload() {
        self.ids = SolvgramSettings.captureExceptions.keys.sorted()
        self.tableView.reloadData()
        self.peersDisposable?.dispose()
        self.peersDisposable = (self.context.engine.data.get(EngineDataMap(self.ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: solvgramEnginePeerId($0)) }))
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else { return }
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer { peers[id] = peer }
            }
            self.peers = peers
            self.tableView.reloadData()
        })
    }

    public override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.ids.count }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let footer = captureText("A chat's rule applies to deleted messages and edits and comes before the chat-type switches. Swipe to remove one.", "Правило чата действует для удалённых сообщений и правок и важнее переключателей по типу чата. Смахните, чтобы удалить.")
        return self.ids.isEmpty ? captureText("No exceptions yet. Tap + to add a chat. ", "Исключений пока нет. Нажмите +, чтобы добавить чат. ") + footer : footer
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = self.ids[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        content.text = capturePeerTitle(self.peers[solvgramEnginePeerId(id)], fallback: id, context: self.context)
        content.secondaryText = SolvgramSettings.captureException(peerId: id) == .save ? captureText("Always Save", "Сохранять") : captureText("Never Save", "Не сохранять")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = self.ids[indexPath.row]
        let title = capturePeerTitle(self.peers[solvgramEnginePeerId(id)], fallback: id, context: self.context)
        presentCaptureActions(for: id, title: title, context: self.context, from: self, sourceView: tableView.cellForRow(at: indexPath), changed: { [weak self] in
            self?.reload()
        })
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        SolvgramSettings.setCaptureException(nil, peerId: self.ids[indexPath.row])
        NotificationCenter.default.post(name: Notification.Name("SolvgramCaptureSettingsDidChange"), object: nil)
        self.ids.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}

/// Recent chats of the main list, to add an exception.
private final class SolvgramCaptureChatPickerController: UITableViewController {
    private let context: AccountContext
    private let picked: () -> Void
    private var peers: [EnginePeer] = []
    private var disposable: Disposable?

    init(context: AccountContext, picked: @escaping () -> Void) {
        self.context = context
        self.picked = picked
        super.init(style: .insetGrouped)
        self.title = captureText("Add Chat", "Добавить чат")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.disposable?.dispose() }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.disposable = (self.context.engine.messages.solvgramRecentChatPeers() |> deliverOnMainQueue).start(next: { [weak self] peers in
            guard let self else { return }
            let accountPeerId = self.context.account.peerId
            self.peers = peers.filter { $0.id != accountPeerId }
            self.tableView.reloadData()
        })
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.peers.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let peer = self.peers[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        content.text = capturePeerTitle(peer, fallback: peer.id.toInt64(), context: self.context)
        switch SolvgramSettings.captureException(peerId: peer.id.toInt64()) {
        case .save: content.secondaryText = captureText("Always Save", "Сохранять")
        case .skip: content.secondaryText = captureText("Never Save", "Не сохранять")
        case nil: content.secondaryText = nil
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let peer = self.peers[indexPath.row]
        presentCaptureActions(for: peer.id.toInt64(), title: capturePeerTitle(peer, fallback: peer.id.toInt64(), context: self.context), context: self.context, from: self, sourceView: tableView.cellForRow(at: indexPath), changed: { [weak self] in
            guard let self else { return }
            self.picked()
            self.navigationController?.popViewController(animated: true)
        })
    }
}

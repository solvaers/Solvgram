import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import ContextUI
import TelegramPresentationData
import ObjectiveC
import UndoUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import SolvgramIcons

// MARK: Solvgram — the chat's Solvgram button: a settings glyph in a glass circle of its own, left of the avatar. It opens this chat's quick settings: Ghost Mode here (as everywhere, always
// hide, never hide), Read Now, and the Voice Changer on or off with the last voice picked.

final class SolvgramChatShieldNode: ASDisplayNode {
    private let imageNode = ASImageNode()
    private var color: UIColor?

    override init() {
        super.init()
        self.imageNode.displaysAsynchronously = false
        self.imageNode.isUserInteractionEnabled = false
        self.addSubnode(self.imageNode)
    }

    /// The glyph alone, in the color of the bar's other glyphs (the back arrow, the attach and mic buttons).
    func update(color: UIColor) {
        guard self.color != color else {
            return
        }
        self.color = color
        // A thin settings glyph, the weight of the attach and back glyphs.
        self.imageNode.image = generateTintedImage(image: UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0, weight: .light)), color: color)
        self.setNeedsLayout()
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 44.0, height: 44.0)
    }

    override func layout() {
        super.layout()
        let size = self.imageNode.image?.size ?? CGSize(width: 24.0, height: 24.0)
        self.imageNode.frame = CGRect(origin: CGPoint(x: floor((self.bounds.width - size.width) / 2.0), y: floor((self.bounds.height - size.height) / 2.0)), size: size)
    }
}

private final class SolvgramShieldReferenceSource: ContextReferenceContentSource {
    private let view: UIView

    init(view: UIView) {
        self.view = view
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.view, contentAreaInScreenSpace: mainWindowScreenBounds)
    }
}

nonisolated(unsafe) private var solvgramShieldItemKey: UInt8 = 0

extension ChatControllerImpl {
    /// The shield item for this chat, nil where it has no place (no peer, a selection, a search).
    func solvgramShieldBarButtonItem() -> UIBarButtonItem? {
        guard case .peer = self.chatLocation, self.chatLocation.peerId != nil, self.chatLocation.peerId != self.context.account.peerId else {
            return nil
        }
        guard case .openChatInfo = self.rightNavigationButton?.action else {
            return nil
        }
        let item: UIBarButtonItem
        if let current = objc_getAssociatedObject(self, &solvgramShieldItemKey) as? UIBarButtonItem {
            item = current
        } else {
            let node = SolvgramChatShieldNode()
            item = UIBarButtonItem(customDisplayNode: node)!
            item.target = self
            item.action = #selector(self.solvgramShieldPressed)
            item.accessibilityLabel = "Solvgram"
            // A circle of its own left of the avatar: in the avatar's capsule, the bar's transitions drew the two
            // apart and snapped them back together.
            item.requiresOwnSection = true
            objc_setAssociatedObject(self, &solvgramShieldItemKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        (item.customDisplayNode as? SolvgramChatShieldNode)?.update(color: self.presentationData.theme.chat.inputPanel.panelControlColor)
        return item
    }

    @objc func solvgramShieldPressed() {
        guard let peerId = self.chatLocation.peerId, let item = objc_getAssociatedObject(self, &solvgramShieldItemKey) as? UIBarButtonItem, let sourceView = item.customDisplayNode?.view else {
            return
        }
        let ru = SolvgramSettings.isRussian
        let key = peerId.toInt64()
        let exception = SolvgramSettings.ghostException(peerId: key)
        let checkIcon: (PresentationTheme) -> UIImage? = { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor)
        }
        let noIcon: (PresentationTheme) -> UIImage? = { _ in
            return nil
        }

        let ghostTitle = ru ? "Режим призрака" : "Ghost Mode"
        let ghostOptions: [(SolvgramSettings.GhostException?, String)] = [
            (nil, ru ? "Как везде" : "As Everywhere"),
            (.hide, ru ? "Всегда включён здесь" : "Always On Here"),
            (.show, ru ? "Всегда выключен здесь" : "Always Off Here"),
        ]
        let ghostValue = ghostOptions.first(where: { $0.0 == exception })?.1 ?? ""
        let ghostIcon: (PresentationTheme) -> UIImage? = { theme in
            return SolvgramGhostIcon.image(color: SolvgramSettings.ghostActive(peerId: key) ? theme.list.itemAccentColor : theme.contextMenu.primaryColor, side: min(30, UIFontMetrics(forTextStyle: .body).scaledValue(for: 24)), outlined: true)
        }

        var items: [ContextMenuItem] = []
        items.append(.action(ContextMenuActionItem(text: ghostTitle, textLayout: .secondLineWithValue(ghostValue), icon: ghostIcon, action: { [weak self] c, _ in
            guard let self else {
                return
            }
            var subItems: [ContextMenuItem] = []
            subItems.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Common_Back, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
            }, iconPosition: .left, action: { c, _ in
                c?.popItems()
            })))
            subItems.append(.separator)
            for (value, title) in ghostOptions {
                subItems.append(.action(ContextMenuActionItem(text: title, icon: value == exception ? checkIcon : noIcon, action: { _, f in
                    f(.default)
                    SolvgramSettings.setGhostException(value, peerId: key)
                    if value != exception {
                        self.solvgramShowToast(value == nil ? (ru ? "Режим призрака здесь как везде" : "Ghost Mode here as everywhere") : value == .hide ? (ru ? "В этом чате режим призрака всегда включён" : "Ghost Mode is always on in this chat") : (ru ? "В этом чате режим призрака всегда выключен" : "Ghost Mode is always off in this chat"))
                    }
                })))
            }
            c?.pushItems(items: .single(ContextController.Items(content: .list(subItems))))
        })))
        // MARK: Solvgram — saving in this chat: an exception next to Ghost Mode, and clearing this chat.
        let captureException = SolvgramSettings.captureException(peerId: key)
        let captureOptions: [(SolvgramSettings.CaptureException?, String)] = [
            (nil, ru ? "Как везде" : "As Everywhere"),
            (.save, ru ? "Всегда сохранять здесь" : "Always Save Here"),
            (.skip, ru ? "Не сохранять здесь" : "Never Save Here"),
        ]
        let captureValue = captureOptions.first(where: { $0.0 == captureException })?.1 ?? ""
        items.append(.action(ContextMenuActionItem(text: ru ? "Сохранение сообщений" : "Saving Messages", textLayout: .secondLineWithValue(captureValue), icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "tray.and.arrow.down"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] c, _ in
            guard let self else {
                return
            }
            var subItems: [ContextMenuItem] = []
            subItems.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Common_Back, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
            }, iconPosition: .left, action: { c, _ in
                c?.popItems()
            })))
            subItems.append(.separator)
            for (value, title) in captureOptions {
                subItems.append(.action(ContextMenuActionItem(text: title, icon: value == captureException ? checkIcon : noIcon, action: { _, f in
                    f(.default)
                    SolvgramSettings.setCaptureException(value, peerId: key)
                    if value != captureException {
                        self.solvgramShowToast(value == nil ? (ru ? "Сохранение здесь как везде" : "Saving here as everywhere") : value == .save ? (ru ? "В этом чате удалённые сообщения и правки сохраняются" : "Deleted messages and edits are saved in this chat") : (ru ? "В этом чате удалённые сообщения и правки не сохраняются" : "Deleted messages and edits are not saved in this chat"))
                    }
                })))
            }
            subItems.append(.separator)
            subItems.append(.action(ContextMenuActionItem(text: ru ? "Очистить сохранённое здесь" : "Clear Saved Data Here", textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
            }, action: { _, f in
                f(.default)
                self.solvgramConfirmClearChat(peerId: peerId)
            })))
            c?.pushItems(items: .single(ContextController.Items(content: .list(subItems))))
        })))
        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: ru ? "Прочитать сейчас" : "Read Now", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Read"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] _, f in
            f(.default)
            guard let self else {
                return
            }
            let _ = (self.context.engine.messages.solvgramReadNow(peerId: peerId)
            |> deliverOnMainQueue).startStandalone(next: { [weak self] success in
                self?.solvgramShowToast(success ? (ru ? "Чат отмечен прочитанным" : "Marked as read") : (ru ? "Не удалось отметить прочитанным" : "Couldn't mark as read"))
            })
        })))
        let voiceOn = SolvgramSettings.voiceEffect != "normal"
        // A channel's subscribers send no voice messages there.
        var isBroadcastChannel = false
        if let channel = self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel, case .broadcast = channel.info {
            isBroadcastChannel = true
        }
        if !isBroadcastChannel {
        items.append(.action(ContextMenuActionItem(text: ru ? "Изменение голоса" : "Voice Changer", textLayout: .secondLineWithValue(voiceOn ? (ru ? "Включено" : "On") : (ru ? "Выключено" : "Off")), icon: { theme in
            return SolvgramBadgeArtwork.microphone(active: voiceOn, color: voiceOn ? theme.list.itemAccentColor : theme.contextMenu.primaryColor)
        }, action: { _, f in
            f(.default)
            let defaults = UserDefaults.standard
            if voiceOn {
                defaults.set(SolvgramSettings.voiceEffect, forKey: SolvgramSettings.Key.lastVoiceEffect)
                defaults.set("normal", forKey: SolvgramSettings.Key.voiceEffect)
            } else {
                defaults.set(defaults.string(forKey: SolvgramSettings.Key.lastVoiceEffect) ?? "high", forKey: SolvgramSettings.Key.voiceEffect)
            }
        })))
        }

        let controller = makeContextController(presentationData: self.presentationData, source: .reference(SolvgramShieldReferenceSource(view: sourceView)), items: .single(ContextController.Items(content: .list(items))), recognizer: nil, gesture: nil, disableScreenshots: false)
        self.window?.presentInGlobalOverlay(controller)
    }

    private func solvgramConfirmClearChat(peerId: EnginePeer.Id) {
        let ru = SolvgramSettings.isRussian
        let text = ru ? "Сохранённые удалённые и исчезающие сообщения, история правок и анонимные просмотры историй этого чата удалятся из приложения. Они не вернутся." : "Kept deleted and disappearing messages, edit history and anonymous story views of this chat will be removed from the app. They will not come back."
        self.present(textAlertController(context: self.context, title: ru ? "Очистить этот чат?" : "Clear This Chat?", text: text, actions: [
            TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: ru ? "Очистить" : "Clear", action: { [weak self] in
                guard let self else {
                    return
                }
                self.context.solvgramDeviceCache.clear(categories: Set(SolvgramCacheCategory.allCases), peerId: peerId, completion: { [weak self] success in
                    self?.solvgramShowToast(success ? (ru ? "Сохранённое в этом чате очищено" : "Saved data in this chat cleared") : (ru ? "Не удалось очистить" : "Couldn't clear"))
                })
            })
        ]), in: .window(.root))
    }

    private func solvgramShowToast(_ text: String) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: 2.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

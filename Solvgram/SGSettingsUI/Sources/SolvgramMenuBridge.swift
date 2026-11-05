// MARK: Solvgram — the Swift side of the Solvgram menu (Solvgram/SolvgramMenu, Objective-C).
// The menu shows the settings the Solvgram settings screen used to show. It reads and writes them
// through this bridge, so they go through SGSimpleSettings (whose properties cache their values)
// and keep the side effects the Solvgram screen had: account-manager settings for the tab bar,
// folders and calls, network settings for the download boost, and a restart where one is needed.
// The menu calls it by selector with object arguments only (see LMBridge* in SolvgramMenu.m).
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import SettingsUI
import SGSimpleSettings
import SGStrings
import SGProUI

@objc(SolvgramMenuBridge)
public final class SolvgramMenuBridge: NSObject {
    private let context: AccountContext
    private let openController: (ViewController) -> Void
    private let callListSettings = Atomic<CallListSettings>(value: CallListSettings.defaultSettings)
    private let experimentalUISettings: Atomic<ExperimentalUISettings>
    private var disposable: Disposable?

    public init(context: AccountContext, openController: @escaping (ViewController) -> Void) {
        self.context = context
        self.openController = openController
        self.experimentalUISettings = Atomic(value: context.sharedContext.immediateExperimentalUISettings)
        super.init()

        let callListSettings = self.callListSettings
        let experimentalUISettings = self.experimentalUISettings
        self.disposable = (context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
        |> deliverOnMainQueue).start(next: { sharedData in
            let _ = callListSettings.swap(sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings)
            let _ = experimentalUISettings.swap(sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings)
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    private var lang: String {
        // Solvgram's own language, so the Solvgram option names match the rest of the menu.
        return SolvgramSettings.isRussian ? "ru" : "en"
    }

    // MARK: Switches

    @objc(boolValue:)
    public func boolValue(_ name: NSString) -> NSNumber {
        let s = SGSimpleSettings.shared
        let value: Bool
        switch name as String {
        case "hideStories": value = s.hideStories
        case "voiceEffectEnabled": value = SolvgramSettings.voiceEffect != "normal"
        case "warnOnStoriesOpen": value = s.warnOnStoriesOpen
        case "storyStealthMode": value = s.storyStealthMode
        case "disableSwipeToRecordStory": value = s.disableSwipeToRecordStory
        case "showRepostToStory": value = s.showRepostToStoryV2
        case "hidePhoneInSettings": value = s.hidePhoneInSettings
        case "hideAccountInNotifications": value = s.hideAccountInNotifications
        case "confirmCalls": value = s.confirmCalls
        case "enableVoipTcp": value = self.experimentalUISettings.with { $0.enableVoipTcp }
        case "hideTabBar": value = s.hideTabBar
        case "showContactsTab": value = self.callListSettings.with { $0.showContactsTab }
        case "showCallsTab": value = self.callListSettings.with { $0.showTab }
        case "showTabNames": value = s.showTabNames
        case "tabBarSearchEnabled": value = s.tabBarSearchEnabled
        case "wideTabBar": value = s.wideTabBar
        case "foldersAtBottom": value = self.experimentalUISettings.with { $0.foldersTabAtBottom }
        case "allChatsHidden": value = s.allChatsHidden
        case "compactFolderNames": value = s.compactFolderNames
        case "rememberLastFolder": value = s.rememberLastFolder
        case "compactChatList": value = s.compactChatList
        case "compactMessagePreview": value = s.chatListLines != SGSimpleSettings.ChatListLines.three.rawValue
        case "chatSwipeOptions": value = !s.disableChatSwipeOptions
        case "deleteChatSwipeOption": value = !s.disableDeleteChatSwipeOption
        case "showProfileId": value = s.showProfileId
        case "showDC": value = s.showDC
        case "showRegDate": value = s.showRegDate
        case "showCreationDate": value = s.showCreationDate
        case "quickTranslateButton": value = s.quickTranslateButton
        case "forceBuiltInMic": value = s.forceBuiltInMic
        case "sendLargePhotos": value = s.sendLargePhotos
        case "stickerTimestamp": value = s.stickerTimestamp
        case "startTelescopeWithRearCam": value = s.startTelescopeWithRearCam
        case "videoControlsInFooter": value = s.videoControlsInFooter
        case "swipeForVideoPIP": value = s.videoPIPSwipeDirection == SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue
        case "channelBottomButton": value = !s.hideChannelBottomButton
        case "wideChannelPosts": value = s.wideChannelPosts
        case "secondsInMessages": value = s.secondsInMessages
        case "doubleTapToEdit": value = s.messageDoubleTapActionOutgoing == SGSimpleSettings.MessageDoubleTapAction.edit.rawValue
        case "recordingButton": value = !s.hideRecordingButton
        case "snapDeletionEffect": value = !s.disableSnapDeletionEffect
        case "sendAsButton": value = !s.disableSendAsButton
        case "galleryCamera": value = !s.disableGalleryCamera
        case "galleryCameraPreview": value = !s.disableGalleryCameraPreview
        case "pullToNextChannel": value = !s.disableScrollToNextChannel
        case "pullToNextTopic": value = !s.disableScrollToNextTopic
        case "hideReactions": value = s.hideReactions
        case "uploadSpeedBoost": value = s.uploadSpeedBoost
        case "sendWithReturnKey": value = s.sendWithReturnKey
        case "forceEmojiTab": value = s.forceEmojiTab
        case "defaultEmojisFirst": value = s.defaultEmojisFirst
        case "inputToolbar": value = s.inputToolbar
        case "contextShowSaveToCloud": value = s.contextShowSaveToCloud
        case "contextShowHideForwardName": value = s.contextShowHideForwardName
        case "contextShowSelectFromUser": value = s.contextShowSelectFromUser
        case "contextShowRestrict": value = s.contextShowRestrict
        case "contextShowReport": value = s.contextShowReport
        case "contextShowReply": value = s.contextShowReply
        case "contextShowPin": value = s.contextShowPin
        case "contextShowSaveMedia": value = s.contextShowSaveMedia
        case "contextShowMessageReplies": value = s.contextShowMessageReplies
        case "contextShowJson": value = s.contextShowJson
        default: value = false
        }
        return NSNumber(value: value)
    }

    /// Returns true when the change only applies after a restart.
    @objc(setBool:value:)
    public func setBool(_ name: NSString, value number: NSNumber) -> NSNumber {
        let s = SGSimpleSettings.shared
        let value = number.boolValue
        let accountManager = self.context.sharedContext.accountManager
        var needsRestart = false
        switch name as String {
        case "hideStories": s.hideStories = value
        case "warnOnStoriesOpen": s.warnOnStoriesOpen = value
        case "storyStealthMode": s.storyStealthMode = value
        case "disableSwipeToRecordStory": s.disableSwipeToRecordStory = value
        case "showRepostToStory": s.showRepostToStoryV2 = value
        case "hidePhoneInSettings": s.hidePhoneInSettings = value
        case "hideAccountInNotifications":
            s.hideAccountInNotifications = value
            s.synchronizeShared()
        case "confirmCalls": s.confirmCalls = value
        case "enableVoipTcp":
            let _ = self.experimentalUISettings.modify { var settings = $0; settings.enableVoipTcp = value; return settings }
            let _ = updateExperimentalUISettingsInteractively(accountManager: accountManager, { settings in
                var settings = settings
                settings.enableVoipTcp = value
                return settings
            }).start()
        case "hideTabBar": s.hideTabBar = value; needsRestart = true
        case "showContactsTab":
            let _ = self.callListSettings.modify { $0.withUpdatedShowContactsTab(value) }
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, { $0.withUpdatedShowContactsTab(value) }).start()
        case "showCallsTab":
            let _ = self.callListSettings.modify { $0.withUpdatedShowTab(value) }
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, { $0.withUpdatedShowTab(value) }).start()
        case "showTabNames": s.showTabNames = value; needsRestart = true
        case "tabBarSearchEnabled": s.tabBarSearchEnabled = value
        case "wideTabBar": s.wideTabBar = value; needsRestart = true
        case "foldersAtBottom":
            let _ = self.experimentalUISettings.modify { var settings = $0; settings.foldersTabAtBottom = value; return settings }
            let _ = updateExperimentalUISettingsInteractively(accountManager: accountManager, { settings in
                var settings = settings
                settings.foldersTabAtBottom = value
                return settings
            }).start()
        case "allChatsHidden": s.allChatsHidden = value; needsRestart = true
        case "compactFolderNames": s.compactFolderNames = value; needsRestart = true
        case "rememberLastFolder": s.rememberLastFolder = value
        case "compactChatList": s.compactChatList = value; needsRestart = true
        case "compactMessagePreview":
            s.chatListLines = value ? SGSimpleSettings.ChatListLines.one.rawValue : SGSimpleSettings.ChatListLines.three.rawValue
            needsRestart = true
        case "chatSwipeOptions": s.disableChatSwipeOptions = !value; needsRestart = true
        case "deleteChatSwipeOption": s.disableDeleteChatSwipeOption = !value; needsRestart = true
        case "showProfileId": s.showProfileId = value
        case "showDC": s.showDC = value
        case "showRegDate": s.showRegDate = value
        case "showCreationDate": s.showCreationDate = value
        case "quickTranslateButton": s.quickTranslateButton = value
        case "forceBuiltInMic": s.forceBuiltInMic = value
        case "sendLargePhotos": s.sendLargePhotos = value
        case "stickerTimestamp": s.stickerTimestamp = value
        case "startTelescopeWithRearCam": s.startTelescopeWithRearCam = value
        case "videoControlsInFooter": s.videoControlsInFooter = value
        case "swipeForVideoPIP":
            s.videoPIPSwipeDirection = value ? SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue : SGSimpleSettings.VideoPIPSwipeDirection.none.rawValue
        case "channelBottomButton": s.hideChannelBottomButton = !value
        case "wideChannelPosts": s.wideChannelPosts = value
        case "secondsInMessages": s.secondsInMessages = value
        case "doubleTapToEdit":
            s.messageDoubleTapActionOutgoing = value ? SGSimpleSettings.MessageDoubleTapAction.edit.rawValue : SGSimpleSettings.MessageDoubleTapAction.default.rawValue
        case "recordingButton": s.hideRecordingButton = !value
        case "snapDeletionEffect": s.disableSnapDeletionEffect = !value
        case "sendAsButton": s.disableSendAsButton = !value
        case "galleryCamera": s.disableGalleryCamera = !value
        case "galleryCameraPreview": s.disableGalleryCameraPreview = !value
        case "pullToNextChannel": s.disableScrollToNextChannel = !value
        case "pullToNextTopic": s.disableScrollToNextTopic = !value
        case "hideReactions": s.hideReactions = value
        case "uploadSpeedBoost": s.uploadSpeedBoost = value
        case "sendWithReturnKey": s.sendWithReturnKey = value
        case "forceEmojiTab": s.forceEmojiTab = value
        case "defaultEmojisFirst": s.defaultEmojisFirst = value
        case "inputToolbar": s.inputToolbar = value
        case "contextShowSaveToCloud": s.contextShowSaveToCloud = value
        case "contextShowHideForwardName": s.contextShowHideForwardName = value
        case "contextShowSelectFromUser": s.contextShowSelectFromUser = value
        case "contextShowRestrict": s.contextShowRestrict = value
        case "contextShowReport": s.contextShowReport = value
        case "contextShowReply": s.contextShowReply = value
        case "contextShowPin": s.contextShowPin = value
        case "contextShowSaveMedia": s.contextShowSaveMedia = value
        case "contextShowMessageReplies": s.contextShowMessageReplies = value
        case "contextShowJson": s.contextShowJson = value
        default: break
        }
        return NSNumber(value: needsRestart)
    }

    // MARK: Choices

    /// [[value, title]] for each option of a choice setting.
    @objc(choiceOptions:)
    public func choiceOptions(_ name: NSString) -> NSArray {
        let lang = self.lang
        let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
        var options: [[String]] = []
        switch name as String {
        case "downloadSpeedBoost":
            for value in SGSimpleSettings.DownloadSpeedBoostValues.allCases {
                options.append([value.rawValue, i18n("Settings.DownloadsBoost.\(value.rawValue)", lang)])
            }
        case "allChatsTitleLengthOverride":
            for value in SGSimpleSettings.AllChatsTitleLengthOverride.allCases {
                switch value {
                case .short: options.append([value.rawValue, "\"\(strings.ChatList_Tabs_All)\""])
                case .long: options.append([value.rawValue, "\"\(strings.ChatList_Tabs_AllChats)\""])
                default: options.append([value.rawValue, i18n("Settings.Folders.AllChatsTitle.none", lang)])
                }
            }
        case "translationBackend":
            for value in SGSimpleSettings.TranslationBackend.allCases {
                if value == .system {
                    if #available(iOS 18.0, *) {
                    } else {
                        continue
                    }
                }
                options.append([value.rawValue, i18n("Settings.Translation.Backend.\(value.rawValue)", lang)])
            }
        case "transcriptionBackend":
            for value in SGSimpleSettings.TranscriptionBackend.allCases {
                options.append([value.rawValue, i18n("Settings.Transcription.Backend.\(value.rawValue)", lang)])
            }
        case "voiceEffect":
            let ru = SolvgramSettings.isRussian
            options = [
                ["normal", ru ? "Обычный" : "Normal"],
                ["high", ru ? "Писклявый" : "High-Pitched"],
                ["cartoon", ru ? "Мультяшный" : "Cartoon"],
                ["low", ru ? "Низкий" : "Deep"],
                ["robot", ru ? "Робот" : "Robot"],
            ]
        case "solvgramLanguage":
            options = [
                ["system", SolvgramSettings.isRussian ? "Как в системе" : "System"],
                ["en", "English"],
                ["ru", "Русский"],
            ]
        case "roundVideoCamera":
            let isRussian = SolvgramSettings.isRussian
            options = [
                ["front", isRussian ? "Фронтальная" : "Front"],
                ["rear", isRussian ? "Задняя" : "Back"],
                ["ask", isRussian ? "Спрашивать" : "Ask Every Time"],
            ]
        case "pinnedMessageNotifications":
            for value in SGSimpleSettings.PinnedMessageNotificationsSettings.allCases {
                options.append([value.rawValue, "Notifications.PinnedMessages.value.\(value.rawValue)".i18n(lang)])
            }
        case "mentionsAndRepliesNotifications":
            for value in SGSimpleSettings.MentionsAndRepliesNotificationsSettings.allCases {
                options.append([value.rawValue, "Notifications.MentionsAndReplies.value.\(value.rawValue)".i18n(lang)])
            }
        default:
            break
        }
        return options as NSArray
    }

    @objc(choiceValue:)
    public func choiceValue(_ name: NSString) -> NSString {
        let s = SGSimpleSettings.shared
        switch name as String {
        case "downloadSpeedBoost": return s.downloadSpeedBoost as NSString
        case "solvgramLanguage":
            return (UserDefaults.standard.string(forKey: SolvgramSettings.Key.language) ?? "system") as NSString
        case "voiceEffect":
            return SolvgramSettings.voiceEffect as NSString
        case "roundVideoCamera":
            if SolvgramSettings.roundVideoCameraAsks {
                return "ask"
            }
            return (s.startTelescopeWithRearCam ? "rear" : "front") as NSString
        case "allChatsTitleLengthOverride": return s.allChatsTitleLengthOverride as NSString
        case "translationBackend": return s.translationBackend as NSString
        case "transcriptionBackend": return s.transcriptionBackend as NSString
        case "pinnedMessageNotifications": return s.pinnedMessageNotifications as NSString
        case "mentionsAndRepliesNotifications": return s.mentionsAndRepliesNotifications as NSString
        default: return ""
        }
    }

    /// Returns true when the change only applies after a restart.
    @objc(setChoice:value:)
    public func setChoice(_ name: NSString, value valueString: NSString) -> NSNumber {
        let s = SGSimpleSettings.shared
        let value = valueString as String
        var needsRestart = false
        switch name as String {
        case "downloadSpeedBoost":
            s.downloadSpeedBoost = value
            let enableDownloadX = value != SGSimpleSettings.DownloadSpeedBoostValues.none.rawValue
            let _ = updateNetworkSettingsInteractively(postbox: self.context.account.postbox, network: self.context.account.network, { settings in
                var settings = settings
                settings.useExperimentalDownload = enableDownloadX
                return settings
            }).start()
            needsRestart = true
        case "allChatsTitleLengthOverride": s.allChatsTitleLengthOverride = value
        case "solvgramLanguage":
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.language)
        case "voiceEffect":
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.voiceEffect)
            if value != "normal" {
                UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.lastVoiceEffect)
            }
        case "roundVideoCamera":
            UserDefaults.standard.set(value, forKey: SolvgramSettings.Key.roundVideoCamera)
            if value != "ask" {
                s.startTelescopeWithRearCam = value == "rear"
            }
        case "translationBackend": s.translationBackend = value
        case "transcriptionBackend": s.transcriptionBackend = value
        case "pinnedMessageNotifications":
            s.pinnedMessageNotifications = value
            s.synchronizeShared()
        case "mentionsAndRepliesNotifications":
            s.mentionsAndRepliesNotifications = value
            s.synchronizeShared()
        default:
            break
        }
        return NSNumber(value: needsRestart)
    }

    // MARK: Sliders (0...100)

    @objc(sliderValue:)
    public func sliderValue(_ name: NSString) -> NSNumber {
        let s = SGSimpleSettings.shared
        switch name as String {
        case "outgoingPhotoQuality": return NSNumber(value: s.outgoingPhotoQuality)
        case "stickerSize": return NSNumber(value: s.stickerSize)
        case "accountColorsSaturation": return NSNumber(value: s.accountColorsSaturation)
        case "voiceSpeed": return NSNumber(value: SolvgramSettings.voiceSpeedStep)
        case "voiceEffectLevel": return NSNumber(value: SolvgramSettings.voiceEffectLevel(SolvgramSettings.voiceEffect))
        default: return 0
        }
    }

    @objc(setSlider:value:)
    public func setSlider(_ name: NSString, value number: NSNumber) -> NSNumber {
        let s = SGSimpleSettings.shared
        let value = number.int32Value
        switch name as String {
        case "outgoingPhotoQuality": s.outgoingPhotoQuality = value
        case "stickerSize": s.stickerSize = value
        case "accountColorsSaturation": s.accountColorsSaturation = value
        case "voiceSpeed":
            UserDefaults.standard.set(min(5, max(1, Int(value))), forKey: SolvgramSettings.Key.voiceSpeed)
        case "voiceEffectLevel":
            // Each effect keeps its own strength.
            UserDefaults.standard.set(min(5, max(1, Int(value))), forKey: SolvgramSettings.Key.voiceEffectLevelPrefix + SolvgramSettings.voiceEffect)
        default: break
        }
        return NSNumber(value: false)
    }

    // MARK: Availability and screens

    @objc(isAvailable:)
    public func isAvailable(_ name: NSString) -> NSNumber {
        switch name as String {
        case "storyStealthMode": return NSNumber(value: SGSimpleSettings.shared.canUseStealthMode)
        case "appBadge":
            if #available(iOS 14.0, *) {
                return true
            }
            return false
        default: return true
        }
    }

    @objc(open:)
    public func open(_ name: NSString) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let controller: ViewController?
        switch name as String {
        case "language": controller = self.context.sharedContext.makeLocalizationListController(context: self.context)
        case "messageFilter": controller = sgMessageFilterController(presentationData: presentationData)
        case "appIcons": controller = themeSettingsController(context: self.context, focusOnItemTag: .icon)
        default: controller = nil
        }
        if let controller {
            self.openController(controller)
        }
    }

    /// The menu's own UI strings follow the app language: Russian when it is Russian, English otherwise.
    @objc public var isRussian: NSNumber {
        return NSNumber(value: SolvgramSettings.isRussian)
    }
}

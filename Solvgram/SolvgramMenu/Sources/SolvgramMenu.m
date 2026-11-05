// Legacy Solvgram menu, kept for reference. Telegram now opens the Swift screen in
// Solvgram/SGSettingsUI/Sources/SolvgramSettingsController.swift.
//
// Two kinds of settings live here:
// - Solvgram's own (ghost mode, saved messages, spoofed location, ...): plain NSUserDefaults keys
//   (the Lead tweak's key names, so older settings carry over), read live by the app through
//   SolvgramSettings (Solvgram/SGSimpleSettings);
// - the settings the Solvgram screen used to show: read and written through SolvgramMenuBridge
//   (Solvgram/SGSettingsUI), which keeps SGSimpleSettings' cache and the side effects in step.
//   The Settings screen hands the bridge over with +[LMRootController setSolvgramBridge:] before
//   presenting the menu; it is called by selector with object arguments only.
//
// The menu's text follows the app language: Russian when the app is in Russian, English otherwise.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <MapKit/MapKit.h>
#import <UserNotifications/UserNotifications.h>
#import "SolvgramIcons.h"

static NSString *const kGhostMaster = @"LeadGhostModeEnabled";

#pragma mark - Bridge and language

static id LMBridgeObject;
static BOOL LMRussian;

static id LMBridgeCall(NSString *selector, id a, id b) {
    SEL sel = NSSelectorFromString(selector);
    if (![LMBridgeObject respondsToSelector:sel]) return nil;
    if (b) return ((id (*)(id, SEL, id, id))objc_msgSend)(LMBridgeObject, sel, a, b);
    return ((id (*)(id, SEL, id))objc_msgSend)(LMBridgeObject, sel, a);
}

static void LMBridgeOpen(NSString *name) {
    SEL sel = NSSelectorFromString(@"open:");
    if ([LMBridgeObject respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(LMBridgeObject, sel, name);
}

static NSString *L(NSString *en, NSString *ru) { return LMRussian ? ru : en; }

// The menu's language: the one picked in Appearance, else Russian when the system is Russian,
// English otherwise (the same rule as SolvgramSettings.isRussian on the Swift side).
static NSString *const LMLanguageDidChange = @"LMLanguageDidChange";

static void LMUpdateLanguage(void) {
    NSString *chosen = [NSUserDefaults.standardUserDefaults stringForKey:@"SolvgramLanguage"];
    if ([chosen isEqualToString:@"ru"]) {
        LMRussian = YES;
    } else if ([chosen isEqualToString:@"en"]) {
        LMRussian = NO;
    } else {
        LMRussian = [NSLocale.preferredLanguages.firstObject.lowercaseString hasPrefix:@"ru"];
    }
}

#pragma mark - Model

typedef NS_ENUM(NSInteger, LMKind) {
    LMKindToggle,        // NSUserDefaults keys, all set together
    LMKindBridgeToggle,  // a Solvgram switch, through the bridge
    LMKindChoice,        // one of several values, through the bridge
    LMKindSlider,        // 0...100, or 1...stepTitles.count in steps, through the bridge
    LMKindInput,         // an integer stored under a NSUserDefaults key
    LMKindScreen,        // pushes a view controller class of this file
    LMKindOpen,          // a Telegram screen the bridge opens (the menu closes first)
};

@interface LMItem : NSObject
@property (nonatomic) LMKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, copy) NSArray<NSString *> *keys;  // LMKindToggle
@property (nonatomic, copy) NSString *name;              // bridge setting, input key, screen class or screen name
@property (nonatomic, copy) NSString *dependsOn;         // bridge switch that must be dependsOnValue for this row to be enabled
@property (nonatomic) BOOL dependsOnValue;
@property (nonatomic, copy) NSArray<NSString *> *stepTitles; // LMKindSlider in steps: one title per step, from 1
@end
@implementation LMItem
@end

static LMItem *LMMake(LMKind kind, NSString *title, NSString *subtitle, NSString *symbol, UIColor *color) {
    LMItem *i = [LMItem new];
    i.kind = kind; i.title = title; i.subtitle = subtitle; i.symbol = symbol; i.color = color;
    return i;
}

static LMItem *Toggle(NSString *title, NSString *subtitle, NSString *symbol, UIColor *color, NSArray<NSString *> *keys) {
    LMItem *i = LMMake(LMKindToggle, title, subtitle, symbol, color);
    i.keys = keys;
    return i;
}

static LMItem *Switch(NSString *title, NSString *subtitle, NSString *symbol, UIColor *color, NSString *name) {
    LMItem *i = LMMake(LMKindBridgeToggle, title, subtitle, symbol, color);
    i.name = name;
    return i;
}

static LMItem *Choice(NSString *title, NSString *symbol, UIColor *color, NSString *name) {
    LMItem *i = LMMake(LMKindChoice, title, nil, symbol, color);
    i.name = name;
    return i;
}

static LMItem *Slider(NSString *title, NSString *symbol, UIColor *color, NSString *name) {
    LMItem *i = LMMake(LMKindSlider, title, nil, symbol, color);
    i.name = name;
    return i;
}

// A slider that stops at 1...stepTitles.count, showing the step's title.
static LMItem *StepSlider(NSString *title, NSString *symbol, UIColor *color, NSString *name, NSArray<NSString *> *stepTitles) {
    LMItem *i = Slider(title, symbol, color, name);
    i.stepTitles = stepTitles;
    return i;
}

static NSString *LMSliderText(LMItem *item, NSInteger value) {
    if (item.stepTitles.count) {
        NSInteger index = MIN(MAX(value, 1), (NSInteger)item.stepTitles.count) - 1;
        return [NSString stringWithFormat:@"%ld · %@", (long)(index + 1), item.stepTitles[index]];
    }
    return [NSString stringWithFormat:@"%ld%%", (long)value];
}

static LMItem *Input(NSString *title, NSString *symbol, UIColor *color, NSString *key) {
    LMItem *i = LMMake(LMKindInput, title, nil, symbol, color);
    i.name = key;
    return i;
}

static LMItem *Screen(NSString *title, NSString *subtitle, NSString *symbol, UIColor *color, NSString *className) {
    LMItem *i = LMMake(LMKindScreen, title, subtitle, symbol, color);
    i.name = className;
    return i;
}

static LMItem *Open(NSString *title, NSString *subtitle, NSString *symbol, UIColor *color, NSString *name) {
    LMItem *i = LMMake(LMKindOpen, title, subtitle, symbol, color);
    i.name = name;
    return i;
}

static LMItem *Requires(LMItem *item, NSString *bridgeSwitch, BOOL value) {
    item.dependsOn = bridgeSwitch;
    item.dependsOnValue = value;
    return item;
}

@interface LMSection : NSObject
@property (nonatomic, copy) NSString *header;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, copy) NSArray<LMItem *> *items;
@property (nonatomic) BOOL needsGhostMode;  // greyed out while Ghost Mode is off
@end
@implementation LMSection
@end

static BOOL LMAvailable(LMItem *item) {
    if (item.kind == LMKindScreen) return [NSClassFromString(item.name) isSubclassOfClass:UIViewController.class];
    if (item.kind == LMKindToggle || item.kind == LMKindInput) return YES;
    if (!LMBridgeObject) return NO;
    NSNumber *available = LMBridgeCall(@"isAvailable:", item.name, nil);
    return available ? available.boolValue : YES;
}

static LMSection *Section(NSString *header, NSString *footer, BOOL needsGhostMode, NSArray<LMItem *> *items) {
    LMSection *s = [LMSection new];
    s.header = header; s.footer = footer; s.needsGhostMode = needsGhostMode;
    NSMutableArray *available = [NSMutableArray array];
    for (LMItem *i in items) if (LMAvailable(i)) [available addObject:i];
    s.items = available;
    return s;
}

@interface LMCategory : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, copy) NSArray<LMSection *> *sections;
@end
@implementation LMCategory
@end

static LMCategory *Cat(NSString *title, NSString *subtitle, NSString *iconName, UIColor *color, NSArray<LMSection *> *sections) {
    LMCategory *c = [LMCategory new];
    c.title = title; c.subtitle = subtitle; c.iconName = iconName; c.color = color;
    c.sections = [sections filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"items.@count > 0"]];
    return c;
}

#pragma mark - Contents

// The root screen: groups of categories, like the groups of the iOS Settings app.
static NSArray<NSArray<LMCategory *> *> *LMGroups(void) {
    UIColor *indigo = UIColor.systemIndigoColor, *blue = UIColor.systemBlueColor, *green = UIColor.systemGreenColor,
            *pink = UIColor.systemPinkColor, *orange = UIColor.systemOrangeColor, *red = UIColor.systemRedColor,
            *teal = UIColor.systemTealColor, *gray = UIColor.systemGrayColor, *purple = UIColor.systemPurpleColor,
            *yellow = UIColor.systemYellowColor, *cyan = UIColor.systemCyanColor, *brown = UIColor.systemBrownColor,
            *mint = UIColor.systemMintColor;

    LMCategory *privacy = Cat(L(@"Privacy", @"Конфиденциальность"), L(@"Ghost mode, read receipts", @"Режим призрака, прочтения"), @"privacy", indigo, @[
        Section(nil, L(@"The selected options apply while Ghost Mode is on.", @"Отмеченные параметры действуют, пока режим призрака включён."), NO, @[
            Toggle(L(@"Ghost Mode", @"Режим призрака"), L(@"Turns on the hiding options below", @"Включает скрытие, выбранное ниже"), @"eye.slash.fill", indigo, @[kGhostMaster]),
        ]),
        Section(L(@"What Ghost Mode Hides", @"Что скрывает режим призрака"), nil, YES, @[
            Toggle(L(@"Online Status", @"Статус «в сети»"), L(@"Others won't see when you're online", @"Никто не увидит, что вы в сети"), @"wifi", green, @[@"disableOnlineStatus"]),
            Toggle(L(@"Typing", @"Набор текста"), L(@"No “typing…” while you write", @"Без «печатает…»"), @"keyboard.fill", blue, @[@"disableTypingStatus"]),
            Toggle(L(@"Recording", @"Запись"), L(@"Voice messages and round videos", @"Голосовые и кружки"), @"mic.fill", orange,
                   @[@"disableRecordingVoiceStatus", @"disableRecordingRoundVideoStatus"]),
            Toggle(L(@"Uploads", @"Загрузки"), L(@"Photos, videos, round videos, files", @"Фото, видео, кружки, файлы"), @"square.and.arrow.up.fill", yellow,
                   @[@"disableUploadingPhotoStatus", @"disableUploadingVideoStatus", @"disableUploadingRoundVideoStatus", @"disableUploadingFileStatus"]),
            Toggle(L(@"Choosing Stickers", @"Выбор стикера"), L(@"No “choosing a sticker…”", @"Без «выбирает стикер…»"), @"face.smiling.fill", teal, @[@"disableChoosingStickerStatus"]),
            Toggle(L(@"Games, Emoji, Calls", @"Игры, эмодзи, звонки"), L(@"Playing, emoji taps, speaking in voice chats", @"Игры, нажатия на эмодзи, речь в эфирах"), @"gamecontroller.fill", purple,
                   @[@"disablePlayingGameStatus", @"disableEmojiAcknowledgementStatus", @"disableEmojiInteractionStatus", @"disableSpeakingInGroupCallStatus"]),
            Toggle(L(@"Read Receipts", @"Прочтение сообщений"), L(@"Senders won't see you've read their messages", @"Собеседник не увидит, что вы прочитали"), @"checkmark.bubble.fill", blue, @[@"disableMessageReadReceipt"]),
        ]),
        Section(L(@"Stories", @"Истории"), L(@"Works on its own, with or without Ghost Mode.", @"Работает и без режима призрака."), NO, @[
            Toggle(L(@"Hide Story Views", @"Скрывать просмотр историй"), L(@"You won't appear in story viewer lists", @"Вас не будет в списке зрителей"), @"circle.dashed", pink, @[@"disableStoriesReadReceipt"]),
        ]),
        Section(L(@"On This Device", @"На этом устройстве"), nil, NO, @[
            Switch(L(@"Hide Phone Number", @"Скрыть номер телефона"), L(@"In Settings, for screenshots", @"В настройках, для скриншотов"), @"phone.down.fill", gray, @"hidePhoneInSettings"),
            Switch(L(@"Hide Account in Notifications", @"Не показывать аккаунт в уведомлениях"), L(@"Notifications don't name the account", @"Без имени аккаунта в уведомлениях"), @"bell.slash.fill", red, @"hideAccountInNotifications"),
        ]),
    ]);

    LMCategory *messages = Cat(L(@"Messages", @"Сообщения"), L(@"Deleted, edited, disappearing, filter", @"Удалённые, изменённые, исчезающие, фильтр"), @"messages", teal, @[
        Section(L(@"Keep", @"Сохранять"), L(@"A kept deleted message shows 🗑 next to its time, a kept disappearing photo or video shows ⏱. Long-press an edited message and choose Edit History to see what it said before.",
                                            @"У сохранённого удалённого сообщения рядом со временем 🗑, у сохранённого исчезающего фото или видео ⏱. Чтобы увидеть прежний текст, зажмите изменённое сообщение и выберите «История изменений»."), NO, @[
            Toggle(L(@"Deleted Messages", @"Удалённые сообщения"), L(@"Messages others delete stay in the chat", @"Удалённые собеседником остаются в чате"), @"trash.slash.fill", red, @[@"LeadAntiRevoke"]),
            Toggle(L(@"Edit History", @"История изменений"), L(@"What a message said before each edit", @"Текст сообщения до каждого изменения"), @"pencil.and.list.clipboard", orange, @[@"LeadAntiEdit"]),
            Toggle(L(@"Disappearing Media", @"Исчезающие фото и видео"), L(@"They stay, and the sender isn't told you opened them", @"Остаются, и отправитель не узнает, что вы открыли"), @"timer", purple, @[@"LeadAntiSelfDestruct"]),
            Toggle(L(@"Auto-Deleting Messages", @"Сообщения с автоудалением"), L(@"Messages with a timer stay", @"Не удаляются по таймеру"), @"clock.badge.xmark.fill", indigo, @[@"LeadAntiAutoDelete"]),
        ]),
        Section(nil, L(@"Lets you forward, copy and save from channels and chats that forbid it.", @"Можно пересылать, копировать и сохранять из каналов и чатов, где это запрещено."), NO, @[
            Toggle(L(@"Save Protected Content", @"Сохранять защищённый контент"), L(@"Removes the forwarding and saving restriction", @"Снимает запрет пересылки и сохранения"), @"lock.open.fill", green, @[@"disableForwardRestriction"]),
        ]),
        Section(nil, L(@"Messages with these words are hidden behind a tap.", @"Сообщения с этими словами скрываются, пока не нажмёте."), NO, @[
            Open(L(@"Message Filter", @"Фильтр сообщений"), L(@"Keywords you don't want to see", @"Слова, которые не хотите видеть"), @"line.3.horizontal.decrease.circle.fill", gray, @"messageFilter"),
        ]),
    ]);

    LMCategory *chatList = Cat(L(@"Chat List", @"Список чатов"), L(@"Folders, tabs, swipes", @"Папки, вкладки, свайпы"), @"chat-list", blue, @[
        Section(L(@"Chat List", @"Список чатов"), L(@"Changes marked with ↻ apply after a restart: tap ✓ at the top.", @"Изменения с ↻ применяются после перезапуска: нажмите ✓ вверху."), NO, @[
            Switch(L(@"Compact Chat List ↻", @"Компактный список ↻"), nil, @"rectangle.compress.vertical", blue, @"compactChatList"),
            Switch(L(@"One-Line Previews ↻", @"Превью в одну строку ↻"), nil, @"text.alignleft", teal, @"compactMessagePreview"),
            Switch(L(@"Swipe Actions ↻", @"Действия по свайпу ↻"), nil, @"hand.draw.fill", orange, @"chatSwipeOptions"),
            Requires(Switch(L(@"Delete by Swipe ↻", @"Удаление свайпом ↻"), nil, @"trash.fill", red, @"deleteChatSwipeOption"), @"chatSwipeOptions", YES),
        ]),
        Section(L(@"Folders", @"Папки"), nil, NO, @[
            Switch(L(@"Folders at the Bottom", @"Папки внизу"), nil, @"folder.fill", blue, @"foldersAtBottom"),
            Switch(L(@"Hide “All Chats” ↻", @"Скрыть «Все чаты» ↻"), nil, @"eye.slash", gray, @"allChatsHidden"),
            Switch(L(@"Compact Folder Names ↻", @"Короткие названия папок ↻"), nil, @"textformat.size.smaller", purple, @"compactFolderNames"),
            Choice(L(@"“All Chats” Title", @"Название «Все чаты»"), @"character.cursor.ibeam", indigo, @"allChatsTitleLengthOverride"),
            Switch(L(@"Remember Last Folder", @"Запоминать последнюю папку"), nil, @"bookmark.fill", orange, @"rememberLastFolder"),
        ]),
        Section(L(@"Tab Bar", @"Панель вкладок"), nil, NO, @[
            Switch(L(@"Hide Tab Bar ↻", @"Скрыть панель вкладок ↻"), nil, @"dock.rectangle", gray, @"hideTabBar"),
            Requires(Switch(L(@"Contacts Tab", @"Вкладка «Контакты»"), nil, @"person.crop.circle.fill", orange, @"showContactsTab"), @"hideTabBar", NO),
            Requires(Switch(L(@"Calls Tab", @"Вкладка «Звонки»"), nil, @"phone.fill", green, @"showCallsTab"), @"hideTabBar", NO),
            Requires(Switch(L(@"Tab Names ↻", @"Подписи вкладок ↻"), nil, @"textformat", blue, @"showTabNames"), @"hideTabBar", NO),
            Requires(Switch(L(@"Search Button", @"Кнопка поиска"), nil, @"magnifyingglass", teal, @"tabBarSearchEnabled"), @"hideTabBar", NO),
            Requires(Switch(L(@"Wide Tab Bar ↻", @"Широкая панель ↻"), nil, @"rectangle.expand.vertical", purple, @"wideTabBar"), @"hideTabBar", NO),
        ]),
    ]);

    LMCategory *chats = Cat(L(@"Chats", @"Чаты"), L(@"Chat screen, input field, emoji", @"Экран чата, поле ввода, эмодзи"), @"chats", green, @[
        Section(L(@"Chat", @"Чат"), nil, NO, @[
            Toggle(L(@"Hide Ads", @"Скрыть рекламу"), L(@"Sponsored messages in channels", @"Спонсорские сообщения в каналах"), @"nosign", red, @[@"disableAllAds"]),
            Toggle(L(@"Hide Business Bot Bar", @"Скрыть панель бизнес-бота"), L(@"The bar of the bot that manages your chats", @"Панель бота, управляющего чатами"), @"briefcase.fill", purple, @[@"SolvgramHideBusinessBotBar"]),
            Switch(L(@"Seconds in Time", @"Секунды во времени"), nil, @"clock.fill", blue, @"secondsInMessages"),
            Switch(L(@"Hide Reactions", @"Скрыть реакции"), nil, @"heart.slash.fill", pink, @"hideReactions"),
            Switch(L(@"Deletion Effect", @"Эффект удаления"), L(@"The dust when a message is deleted", @"Рассыпание при удалении"), @"sparkles", yellow, @"snapDeletionEffect"),
            Switch(L(@"Double Tap to Edit", @"Двойной тап — изменить"), L(@"On your own messages", @"На своих сообщениях"), @"hand.tap.fill", orange, @"doubleTapToEdit"),
        ]),
        Section(L(@"Channels", @"Каналы"), nil, NO, @[
            Switch(L(@"Wide Channel Posts", @"Широкие посты"), nil, @"arrow.left.and.right", teal, @"wideChannelPosts"),
            Switch(L(@"Bottom Button", @"Кнопка внизу"), L(@"Mute or Discuss under a channel", @"«Без звука» или «Обсудить»"), @"rectangle.bottomthird.inset.filled", gray, @"channelBottomButton"),
            Switch(L(@"Pull to Next Channel", @"Свайп к следующему каналу"), nil, @"arrow.down.to.line", indigo, @"pullToNextChannel"),
            Switch(L(@"Pull to Next Topic", @"Свайп к следующей теме"), nil, @"arrow.down.to.line.compact", indigo, @"pullToNextTopic"),
        ]),
        Section(L(@"Input Field", @"Поле ввода"), nil, NO, @[
            Switch(L(@"Formatting Panel", @"Панель форматирования"), L(@"Above the keyboard", @"Над клавиатурой"), @"bold.italic.underline", blue, @"inputToolbar"),
            Switch(L(@"Recording Button", @"Кнопка записи"), L(@"Voice and round video", @"Голосовое и кружок"), @"mic.fill", orange, @"recordingButton"),
            Switch(L(@"“Send As” Button", @"Кнопка «Отправить как»"), nil, @"person.2.fill", purple, @"sendAsButton"),
            Switch(L(@"Send with Return Key", @"Отправка клавишей «Ввод»"), nil, @"return", blue, @"sendWithReturnKey"),
            Switch(L(@"Camera in Attachments", @"Камера во вложениях"), nil, @"camera.fill", gray, @"galleryCamera"),
            Requires(Switch(L(@"Camera Preview", @"Превью камеры"), nil, @"camera.viewfinder", gray, @"galleryCameraPreview"), @"galleryCamera", YES),
        ]),
        Section(L(@"Emoji and Stickers", @"Эмодзи и стикеры"), nil, NO, @[
            Switch(L(@"Open Emoji Tab First", @"Сначала вкладка эмодзи"), nil, @"face.smiling.fill", yellow, @"forceEmojiTab"),
            Switch(L(@"Standard Emoji First", @"Сначала обычные эмодзи"), nil, @"face.smiling", orange, @"defaultEmojisFirst"),
            Slider(L(@"Sticker Size", @"Размер стикеров"), @"arrow.up.left.and.arrow.down.right", green, @"stickerSize"),
            Switch(L(@"Time on Stickers", @"Время на стикерах"), nil, @"clock", blue, @"stickerTimestamp"),
        ]),
    ]);

    LMCategory *messageMenu = Cat(L(@"Message Menu", @"Меню сообщения"), L(@"What a long-press shows", @"Что показывать по долгому нажатию"), @"message-menu", indigo, @[
        Section(nil, L(@"Hidden items stay in the “Solvgram” submenu.", @"Выключенные пункты остаются в подменю «Solvgram»."), NO, @[
            Switch(L(@"Save to Saved Messages", @"В «Избранное»"), nil, @"bookmark.fill", blue, @"contextShowSaveToCloud"),
            Switch(L(@"Forward Without Author", @"Переслать без автора"), nil, @"arrowshape.turn.up.right.fill", teal, @"contextShowHideForwardName"),
            Switch(L(@"Select from User", @"Выбрать от пользователя"), nil, @"checkmark.circle.fill", green, @"contextShowSelectFromUser"),
            Switch(L(@"Restrict", @"Ограничить"), nil, @"hand.raised.fill", red, @"contextShowRestrict"),
            Switch(L(@"Report", @"Пожаловаться"), nil, @"exclamationmark.bubble.fill", orange, @"contextShowReport"),
            Switch(L(@"Reply", @"Ответить"), nil, @"arrowshape.turn.up.left.fill", blue, @"contextShowReply"),
            Switch(L(@"Pin", @"Закрепить"), nil, @"pin.fill", yellow, @"contextShowPin"),
            Switch(L(@"Save to Files", @"Сохранить в «Файлы»"), nil, @"folder.fill", cyan, @"contextShowSaveMedia"),
            Switch(L(@"View Replies", @"Показать ответы"), nil, @"bubble.left.and.text.bubble.right.fill", purple, @"contextShowMessageReplies"),
            Switch(L(@"Show JSON", @"Показать JSON"), nil, @"curlybraces", gray, @"contextShowJson"),
        ]),
    ]);

    LMCategory *stories = Cat(L(@"Stories", @"Истории"), L(@"Stories bar, stealth, recording", @"Панель историй, скрытный режим"), @"stories", pink, @[
        Section(nil, nil, NO, @[
            Switch(L(@"Hide Stories Bar", @"Скрыть панель историй"), L(@"At the top of the chat list", @"Вверху списка чатов"), @"circle.dashed", pink, @"hideStories"),
            Switch(L(@"Ask Before Opening", @"Спрашивать перед открытием"), nil, @"questionmark.circle.fill", orange, @"warnOnStoriesOpen"),
            Switch(L(@"No Swipe to Record", @"Без свайпа для записи"), L(@"Swiping the chat list won't open the story camera", @"Свайп по списку не открывает камеру"), @"camera.badge.ellipsis", gray, @"disableSwipeToRecordStory"),
            Switch(L(@"“Repost to Story” in Sharing", @"«Репост в историю» в меню"), nil, @"arrow.2.squarepath", green, @"showRepostToStory"),
        ]),
    ]);

    LMCategory *media = Cat(L(@"Media", @"Медиа"), L(@"Photos, video, voice, speed", @"Фото, видео, голос, скорость"), @"media", orange, @[
        Section(L(@"Photos", @"Фото"), nil, NO, @[
            Slider(L(@"Photo Quality", @"Качество фото"), @"camera.aperture", orange, @"outgoingPhotoQuality"),
            Switch(L(@"Send Large Photos", @"Отправлять большие фото"), L(@"Up to 2560 px", @"До 2560 px"), @"photo.fill", blue, @"sendLargePhotos"),
        ]),
        Section(L(@"Round Videos", @"Кружки"), L(@"Lock the recording to watch it before sending.", @"Зафиксируйте запись, чтобы посмотреть перед отправкой."), NO, @[
            Toggle(L(@"Send as Voice Message", @"Отправлять голосовым"), L(@"A recorded round video goes as voice", @"Записанный кружок уходит голосовым"), @"waveform", orange, @[@"LeadSendAsVoice"]),
            Choice(L(@"Camera", @"Камера"), @"camera.rotate.fill", gray, @"roundVideoCamera"),
        ]),
        Section(L(@"Playback", @"Просмотр"), nil, NO, @[
            Switch(L(@"Video Controls Below", @"Управление видео снизу"), nil, @"play.rectangle.fill", blue, @"videoControlsInFooter"),
            Switch(L(@"Swipe Up for Picture in Picture", @"Свайп вверх — картинка в картинке"), nil, @"pip.fill", teal, @"swipeForVideoPIP"),
            Switch(L(@"Built-in Microphone", @"Встроенный микрофон"), L(@"For voice messages, even with headphones", @"Для голосовых, даже в наушниках"), @"mic.circle.fill", red, @"forceBuiltInMic"),
        ]),
        Section(L(@"Speed", @"Скорость"), nil, NO, @[
            Switch(L(@"Faster Uploads", @"Быстрая отправка"), nil, @"arrow.up.circle.fill", green, @"uploadSpeedBoost"),
            Choice(L(@"Faster Downloads ↻", @"Быстрая загрузка ↻"), @"arrow.down.circle.fill", blue, @"downloadSpeedBoost"),
        ]),
    ]);

    LMCategory *language = Cat(L(@"Translation and Voice", @"Перевод и голос"), L(@"Translator, speech to text, voice changer", @"Переводчик, расшифровка, изменение голоса"), @"translation-voice", purple, @[
        Section(L(@"Translation", @"Перевод"), L(@"No Telegram Premium needed.", @"Telegram Premium не нужен."), NO, @[
            Choice(L(@"Translator", @"Переводчик"), @"globe", purple, @"translationBackend"),
            Switch(L(@"Quick Translate Button", @"Кнопка быстрого перевода"), nil, @"bolt.fill", yellow, @"quickTranslateButton"),
            Open(L(@"Language and Chat Translation", @"Язык и перевод чатов"), nil, @"textformat.abc", blue, @"language"),
        ]),
        Section(L(@"Voice Messages", @"Голосовые"), nil, NO, @[
            Choice(L(@"Speech to Text", @"Расшифровка"), @"waveform.and.mic", orange, @"transcriptionBackend"),
        ]),
        Section(L(@"Voice Changer", @"Изменение голоса"), L(@"Applies to the voice messages you record; lock the recording to hear it before sending. Each voice keeps its own strength.",
                                                            @"Применяется к записанным голосовым; зафиксируйте запись, чтобы послушать перед отправкой. Сила запоминается для каждого голоса отдельно."), NO, @[
            Choice(L(@"Voice", @"Голос"), @"waveform.badge.mic", purple, @"voiceEffect"),
            Requires(StepSlider(L(@"Strength", @"Сила эффекта"), @"dial.medium.fill", indigo, @"voiceEffectLevel",
                                @[L(@"Subtle", @"Слабо"), L(@"Light", @"Заметно"), L(@"Medium", @"Средне"), L(@"Strong", @"Сильно"), L(@"Maximum", @"Максимум")]),
                     @"voiceEffectEnabled", YES),
        ]),
    ]);

    LMCategory *profiles = Cat(L(@"Profiles", @"Профили"), L(@"ID, data center, dates, colors", @"ID, дата-центр, даты, цвета"), @"profiles", teal, @[
        Section(nil, nil, NO, @[
            Switch(L(@"Show ID", @"Показывать ID"), nil, @"number", blue, @"showProfileId"),
            Switch(L(@"Show Data Center", @"Показывать дата-центр"), nil, @"server.rack", gray, @"showDC"),
            Switch(L(@"Registration Date", @"Дата регистрации"), L(@"Approximate", @"Приблизительная"), @"calendar", orange, @"showRegDate"),
            Switch(L(@"Creation Date", @"Дата создания"), L(@"Of groups and channels", @"Групп и каналов"), @"calendar.badge.plus", green, @"showCreationDate"),
        ]),
        Section(nil, L(@"How bright name colors are in chats; 0 makes them all the same.", @"Насколько яркие цвета имён в чатах; 0 — все одинаковые."), NO, @[
            Slider(L(@"Name Color Saturation", @"Насыщенность цветов имён"), @"paintpalette.fill", pink, @"accountColorsSaturation"),
        ]),
    ]);

    LMCategory *calls = Cat(L(@"Calls and Notifications", @"Звонки и уведомления"), L(@"Call confirmation, pins, mentions", @"Подтверждение звонка, закрепы, упоминания"), @"calls-notifications", green, @[
        Section(L(@"Calls", @"Звонки"), nil, NO, @[
            Switch(L(@"Confirm Before Calling", @"Подтверждать звонок"), L(@"So you don't call by accident", @"Чтобы не позвонить случайно"), @"phone.fill", green, @"confirmCalls"),
            Switch(L(@"Calls over TCP", @"Звонки через TCP"), L(@"Only if calls don't connect", @"Только если звонки не соединяются"), @"network", gray, @"enableVoipTcp"),
        ]),
        Section(L(@"Notifications", @"Уведомления"), nil, NO, @[
            Choice(L(@"Pinned Messages", @"Закреплённые сообщения"), @"pin.fill", orange, @"pinnedMessageNotifications"),
            Choice(L(@"Mentions and Replies", @"Упоминания и ответы"), @"at", blue, @"mentionsAndRepliesNotifications"),
        ]),
    ]);

    LMCategory *appearance = Cat(L(@"Appearance", @"Оформление"), L(@"App icon, language, star balance", @"Иконка, язык, баланс звёзд"), @"appearance", pink, @[
        Section(nil, nil, NO, @[
            Open(L(@"App Icon", @"Иконка приложения"), nil, @"app.fill", blue, @"appIcons"),
            Choice(L(@"Solvgram Language", @"Язык Solvgram"), @"globe", teal, @"solvgramLanguage"),
        ]),
        Section(L(@"Stars", @"Звёзды"), L(@"The balance is only shown to you. Nothing changes on the server, and paying still uses your real balance.",
                                            @"Баланс видите только вы. На сервере ничего не меняется, оплата идёт с настоящего баланса."), NO, @[
            Toggle(L(@"Visual Star Balance", @"Свой баланс звёзд"), L(@"Shows the amount below instead", @"Показывать сумму ниже"), @"star.fill", yellow, @[@"LeadVisualStarsEnabled"]),
            Input(L(@"Star Balance", @"Баланс звёзд"), @"star.circle.fill", orange, @"LeadVisualStarsAmount"),
        ]),
    ]);

    LMCategory *location = Cat(L(@"Location", @"Геопозиция"), L(@"Spoofing, pick on map", @"Подмена, выбор на карте"), @"location", orange, @[
        Section(nil, L(@"Applies to “Send My Current Location” and to live location.", @"Работает для «Отправить моё местоположение» и трансляции геопозиции."), NO, @[
            Toggle(L(@"Spoof Location", @"Подменять геопозицию"), L(@"Shares a chosen point instead of your GPS", @"Отправляется выбранная точка вместо GPS"), @"location.fill", orange, @[@"LeadFakeLocation"]),
            Screen(L(@"Pick on Map", @"Выбрать на карте"), L(@"The point you'll share", @"Точка, которую увидят"), @"map.fill", blue, @"LMLocationPickerController"),
        ]),
    ]);

    LMCategory *accounts = Cat(L(@"Accounts", @"Аккаунты"), L(@"Session backup", @"Резервная копия сессий"), @"accounts", brown, @[
        Section(nil, L(@"Sessions are kept in the iOS Keychain, so you can log back in after reinstalling.", @"Сессии хранятся в связке ключей iOS: после переустановки можно войти без кода."), NO, @[
            Open(L(@"Session Backup", @"Резервная копия сессий"), nil, @"key.fill", mint, @"sessionBackup"),
        ]),
    ]);

    NSArray *groups = @[
        @[privacy, messages],
        @[chatList, chats, messageMenu, stories],
        @[media, language],
        @[profiles, calls, appearance, location, accounts],
    ];
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray<LMCategory *> *group in groups) {
        NSArray *nonEmpty = [group filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"sections.@count > 0"]];
        if (nonEmpty.count) [result addObject:nonEmpty];
    }
    return result;
}

#pragma mark - Values

static BOOL LMBridgeBool(NSString *name) {
    return [LMBridgeCall(@"boolValue:", name, nil) boolValue];
}

static BOOL LMIsOn(LMItem *item) {
    if (item.kind == LMKindBridgeToggle) return LMBridgeBool(item.name);
    for (NSString *k in item.keys) if (![NSUserDefaults.standardUserDefaults boolForKey:k]) return NO;
    return item.keys.count > 0;
}

static NSArray<NSArray<NSString *> *> *LMChoiceOptions(LMItem *item) {
    NSArray *options = LMBridgeCall(@"choiceOptions:", item.name, nil);
    return [options isKindOfClass:NSArray.class] ? options : @[];
}

static NSString *LMChoiceTitle(LMItem *item) {
    NSString *value = LMBridgeCall(@"choiceValue:", item.name, nil);
    for (NSArray<NSString *> *option in LMChoiceOptions(item)) {
        if (option.count == 2 && [option[0] isEqualToString:value]) return option[1];
    }
    return value;
}

#pragma mark - Icons

// Solvgram app icon (SolvgramIcon@2x/@3x.png in the app bundle), clipped like an iOS icon tile.
static UIImage *LMAppIcon(CGFloat side) {
    UIImage *src = [UIImage imageNamed:@"SolvgramIcon"];
    if (!src) return SolvgramMenuIcon(@"privacy", side);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.225] addClip];
        [src drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

// Some settings apply only after a restart. Changing one shows a checkmark at the top of every
// menu screen; tapping it closes Solvgram. iOS does not let an app relaunch itself, so it leaves a
// notification behind that opens Solvgram again with the settings applied.
static NSString *const LMRestartStateDidChange = @"LMRestartStateDidChange";
static BOOL LMNeedsRestart;

static void LMMarkRestartNeeded(void) {
    if (LMNeedsRestart) return;
    LMNeedsRestart = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:LMRestartStateDidChange object:nil];
}

static void LMRestartNow(void) {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = @"Solvgram";
    content.body = L(@"Settings applied. Tap to open Solvgram.", @"Настройки применены. Нажмите, чтобы открыть Solvgram.");
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"SolvgramRestart"
                                                                          content:content
                                                                          trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO]];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSUserDefaults.standardUserDefaults synchronize];
            exit(0);
        });
    }];
}

@interface UIViewController (LMRestart)
- (void)lm_restartPressed;
@end

static UIBarButtonItem *LMRestartItem(UIViewController *target) {
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"] style:UIBarButtonItemStyleDone target:target action:@selector(lm_restartPressed)];
    item.accessibilityLabel = L(@"Restart to Apply", @"Перезапустить и применить");
    return item;
}

@implementation UIViewController (LMRestart)
- (void)lm_restartPressed {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:L(@"Solvgram will close to apply the changes. Open it again from the notification.", @"Solvgram закроется, чтобы применить изменения. Откройте его снова из уведомления.")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"Restart Solvgram", @"Перезапустить Solvgram") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        LMRestartNow();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"Later", @"Позже") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

#pragma mark - Location picker

// Spoof Location's point: long-press (or tap) the map to move the pin, then Save.
// Stored as LeadSavedLatitude / LeadSavedLongitude, read by SolvgramSettings.fakeLocation.
@interface LMLocationPickerController : UIViewController
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@end

@implementation LMLocationPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = L(@"Pick on Map", @"Выбор на карте");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)];
    press.minimumPressDuration = 0.3;
    [self.mapView addGestureRecognizer:press];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)];
    [tap requireGestureRecognizerToFail:press];
    [self.mapView addGestureRecognizer:tap];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Save", @"Сохранить") style:UIBarButtonItemStyleDone target:self action:@selector(save)];

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:@"LeadSavedLatitude"]) {
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([d doubleForKey:@"LeadSavedLatitude"], [d doubleForKey:@"LeadSavedLongitude"]);
        [self placePinAt:c];
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 3000, 3000) animated:NO];
    }
}

- (void)placePinAt:(CLLocationCoordinate2D)coordinate {
    if (!self.pin) {
        self.pin = [MKPointAnnotation new];
        [self.mapView addAnnotation:self.pin];
    }
    self.pin.coordinate = coordinate;
    self.pin.title = [NSString stringWithFormat:@"%.5f, %.5f", coordinate.latitude, coordinate.longitude];
}

- (void)pressed:(UIGestureRecognizer *)gesture {
    if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] && gesture.state != UIGestureRecognizerStateBegan) return;
    CLLocationCoordinate2D c = [self.mapView convertPoint:[gesture locationInView:self.mapView] toCoordinateFromView:self.mapView];
    [self placePinAt:c];
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)save {
    if (!self.pin) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"No Point Picked", @"Точка не выбрана")
                                                                       message:L(@"Tap the map where you want to appear.", @"Нажмите на карту там, где хотите оказаться.")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:self.pin.coordinate.latitude forKey:@"LeadSavedLatitude"];
    [d setDouble:self.pin.coordinate.longitude forKey:@"LeadSavedLongitude"];
    [d setBool:YES forKey:@"LeadFakeLocation"];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Category screen

static BOOL LMIsGhostMaster(LMItem *item) {
    return item.kind == LMKindToggle && [item.keys containsObject:kGhostMaster];
}

static NSString *LMGhostStatus(BOOL enabled, BOOL compact) {
    if (compact) return enabled ? L(@"Active", @"Активен") : L(@"Off", @"Выключен");
    return enabled
        ? L(@"Active · Hiding the selected activity", @"Активен · Скрывает выбранные действия")
        : L(@"Off · Your activity is visible as usual", @"Выключен · Действия видны как обычно");
}

@interface LMCategoryController : UITableViewController
@property (nonatomic, strong) LMCategory *category;
@property (nonatomic) BOOL isSearchResults;                                  // no header, a "No Results" placeholder
@property (nonatomic, weak) UINavigationController *hostNavigationController;  // search results have none of their own
@end

@implementation LMCategoryController

- (instancetype)initWithCategory:(LMCategory *)category {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _category = category;
        self.title = category.title;
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.isSearchResults) {
        self.tableView.tableHeaderView = [self headerView];
    }
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    if (@available(iOS 17.0, *)) {
        [self registerForTraitChanges:@[UITraitPreferredContentSizeCategory.class] withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previousTraits) {
            [((LMCategoryController *)environment).tableView reloadData];
        }];
    } else {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contentSizeChanged) name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateRestartItem) name:LMRestartStateDidChange object:nil];
    [self updateRestartItem];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)contentSizeChanged {
    [self.tableView reloadData];
}

- (void)updateRestartItem {
    [self.navigationItem setRightBarButtonItem:(LMNeedsRestart ? LMRestartItem(self) : nil) animated:YES];
}

- (void)showSearchResults:(LMCategory *)results query:(NSString *)query {
    self.category = results;
    if (results.sections.count == 0 && query.length > 0) {
        UILabel *label = [UILabel new];
        label.text = L(@"No Results", @"Ничего не найдено");
        label.textColor = UIColor.secondaryLabelColor;
        label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        self.tableView.backgroundView = label;
    } else {
        self.tableView.backgroundView = nil;
    }
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UIView *)headerView {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 190)];
    UIImageView *icon = [[UIImageView alloc] initWithImage:SolvgramMenuIcon(self.category.iconName, 72)];
    UILabel *title = [UILabel new];
    title.text = self.category.title;
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.adjustsFontSizeToFitWidth = YES;
    UILabel *sub = [UILabel new];
    sub.text = self.category.subtitle;
    sub.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    sub.textColor = UIColor.secondaryLabelColor;
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 2;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, sub]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    [stack setCustomSpacing:14 afterView:icon];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:v.leadingAnchor constant:32],
        [icon.widthAnchor constraintEqualToConstant:72],
        [icon.heightAnchor constraintEqualToConstant:72],
    ]];
    return v;
}

- (BOOL)isDimmed:(LMSection *)section item:(LMItem *)item {
    if (section.needsGhostMode && ![NSUserDefaults.standardUserDefaults boolForKey:kGhostMaster]) return YES;
    if (item.dependsOn && LMBridgeBool(item.dependsOn) != item.dependsOnValue) return YES;
    return NO;
}

- (LMItem *)itemAt:(NSIndexPath *)ip {
    return self.category.sections[ip.section].items[ip.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.category.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.category.sections[s].items.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.category.sections[s].header; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return self.category.sections[s].footer; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    LMSection *section = self.category.sections[ip.section];
    LMItem *item = [self itemAt:ip];
    BOOL dimmed = [self isDimmed:section item:item];
    BOOL featured = LMIsGhostMaster(item) && !self.isSearchResults;
    BOOL checklist = section.needsGhostMode && item.kind == LMKindToggle;

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *c = item.kind == LMKindChoice || item.kind == LMKindInput
        ? [UIListContentConfiguration valueCellConfiguration]
        : [UIListContentConfiguration subtitleCellConfiguration];
    c.text = item.title;
    c.secondaryText = item.subtitle;
    c.textProperties.numberOfLines = 0;
    c.secondaryTextProperties.numberOfLines = 0;
    c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    // Quiet detail lists: icons identify destinations and the featured master control only.
    c.imageToTextPadding = 0;
    if (featured) {
        BOOL accessibleSize = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
        if (!accessibleSize) {
            c.image = SolvgramMenuIcon(@"ghost", 48);
            c.imageProperties.maximumSize = CGSizeMake(48, 48);
            c.imageToTextPadding = 16;
        }
        c.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        c.secondaryText = LMGhostStatus(LMIsOn(item), accessibleSize);
        c.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(20, 16, 20, 16);
    }
    if (dimmed) {
        c.textProperties.color = UIColor.tertiaryLabelColor;
        c.secondaryTextProperties.color = UIColor.tertiaryLabelColor;
    }
    cell.selectionStyle = dimmed ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.userInteractionEnabled = !dimmed;
    cell.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);

    switch (item.kind) {
        case LMKindToggle:
        case LMKindBridgeToggle: {
            if (checklist) {
                BOOL selected = LMIsOn(item);
                cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
                cell.tintColor = dimmed ? UIColor.tertiaryLabelColor : UIColor.systemIndigoColor;
                cell.accessibilityTraits |= UIAccessibilityTraitButton;
                if (selected) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
                if (dimmed) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
                cell.accessibilityValue = selected ? L(@"Selected", @"Выбрано") : L(@"Not selected", @"Не выбрано");
                cell.accessibilityHint = dimmed
                    ? L(@"Turn on Ghost Mode to change this option", @"Включите режим призрака, чтобы изменить этот параметр")
                    : L(@"Double-tap to change selection", @"Двойное касание меняет выбор");
                break;
            }
            UISwitch *sw = [UISwitch new];
            sw.on = LMIsOn(item);
            sw.enabled = !dimmed;
            sw.accessibilityLabel = item.title;
            sw.accessibilityHint = item.subtitle;
            if (featured) sw.onTintColor = UIColor.systemIndigoColor;
            sw.tag = ip.section * 1000 + ip.row;
            [sw addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case LMKindChoice:
            c.secondaryText = LMChoiceTitle(item);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case LMKindInput:
            c.secondaryText = [NSNumberFormatter localizedStringFromNumber:@([NSUserDefaults.standardUserDefaults integerForKey:item.name]) numberStyle:NSNumberFormatterDecimalStyle];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case LMKindSlider: {
            NSInteger value = [LMBridgeCall(@"sliderValue:", item.name, nil) integerValue];
            c.secondaryText = LMSliderText(item, value);
            cell.contentConfiguration = c;
            UISlider *slider = [UISlider new];
            slider.minimumValue = item.stepTitles.count ? 1 : 0;
            slider.maximumValue = item.stepTitles.count ? item.stepTitles.count : 100;
            slider.enabled = !dimmed;
            slider.value = value;
            slider.tag = ip.section * 1000 + ip.row;
            [slider addTarget:self action:@selector(slid:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(slideEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
            slider.frame = CGRectMake(0, 0, 130, 31);
            cell.accessoryView = slider;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case LMKindScreen:
        case LMKindOpen:
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
    }
    cell.contentConfiguration = c;
    return cell;
}

- (NSSet<NSIndexPath *> *)dimmedIndexPaths {
    NSMutableSet *result = [NSMutableSet set];
    [self.category.sections enumerateObjectsUsingBlock:^(LMSection *section, NSUInteger s, BOOL *stop) {
        [section.items enumerateObjectsUsingBlock:^(LMItem *item, NSUInteger r, BOOL *stop2) {
            if ([self isDimmed:section item:item]) [result addObject:[NSIndexPath indexPathForRow:r inSection:s]];
        }];
    }];
    return result;
}

- (void)toggled:(UISwitch *)sw {
    LMItem *item = self.category.sections[sw.tag / 1000].items[sw.tag % 1000];
    NSIndexPath *toggled = [NSIndexPath indexPathForRow:sw.tag % 1000 inSection:sw.tag / 1000];
    [self setToggleItem:item enabled:sw.on atIndexPath:toggled reloadSelection:NO];
}

- (void)setToggleItem:(LMItem *)item enabled:(BOOL)enabled atIndexPath:(NSIndexPath *)toggled reloadSelection:(BOOL)reloadSelection {
    NSSet *dimmedBefore = [self dimmedIndexPaths];
    BOOL needsRestart = NO;
    if (item.kind == LMKindBridgeToggle) {
        needsRestart = [LMBridgeCall(@"setBool:value:", item.name, @(enabled)) boolValue];
    } else {
        for (NSString *k in item.keys) [NSUserDefaults.standardUserDefaults setBool:enabled forKey:k];
    }
    [[UISelectionFeedbackGenerator new] selectionChanged];
    // Only the rows that depend on this switch (Ghost Mode, the tab bar, swipes, the camera) are
    // redrawn; the switch itself keeps its cell, so its animation plays out.
    NSMutableSet *changed = [dimmedBefore mutableCopy];
    NSSet *dimmedAfter = [self dimmedIndexPaths];
    [changed unionSet:dimmedAfter];
    NSMutableSet *both = [dimmedBefore mutableCopy];
    [both intersectSet:dimmedAfter];
    [changed minusSet:both];
    if (reloadSelection) [changed addObject:toggled];
    else [changed removeObject:toggled];
    if (LMIsGhostMaster(item) && !self.isSearchResults) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:toggled];
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        if ([content isKindOfClass:UIListContentConfiguration.class]) {
            content.secondaryText = LMGhostStatus(enabled, UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory));
            cell.contentConfiguration = content;
        }
    }
    if (changed.count) {
        [self.tableView reloadRowsAtIndexPaths:changed.allObjects withRowAnimation:UIAccessibilityIsReduceMotionEnabled() ? UITableViewRowAnimationNone : UITableViewRowAnimationFade];
    }
    if (needsRestart) LMMarkRestartNeeded();
}

- (void)slid:(UISlider *)slider {
    LMItem *item = self.category.sections[slider.tag / 1000].items[slider.tag % 1000];
    NSInteger value = (NSInteger)lroundf(slider.value);
    if (item.stepTitles.count) {
        // Snaps to its steps, with a tick on each new one.
        slider.value = value;
        if (value == [LMBridgeCall(@"sliderValue:", item.name, nil) integerValue]) return;
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }
    LMBridgeCall(@"setSlider:value:", item.name, @(value));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:slider.tag % 1000 inSection:slider.tag / 1000]];
    UIListContentConfiguration *c = (UIListContentConfiguration *)cell.contentConfiguration;
    if ([c isKindOfClass:UIListContentConfiguration.class]) {
        c.secondaryText = LMSliderText(item, value);
        cell.contentConfiguration = c;
    }
}

- (void)slideEnded:(UISlider *)slider {
    LMItem *item = self.category.sections[slider.tag / 1000].items[slider.tag % 1000];
    if (item.stepTitles.count) return; // ticked on every step already
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)choose:(LMItem *)item sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *current = LMBridgeCall(@"choiceValue:", item.name, nil);
    for (NSArray<NSString *> *option in LMChoiceOptions(item)) {
        if (option.count != 2) continue;
        NSString *title = [option[0] isEqualToString:current] ? [option[1] stringByAppendingString:@"  ✓"] : option[1];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            BOOL needsRestart = [LMBridgeCall(@"setChoice:value:", item.name, option[0]) boolValue];
            if ([item.name isEqualToString:@"solvgramLanguage"]) {
                LMUpdateLanguage();
                [NSNotificationCenter.defaultCenter postNotificationName:LMLanguageDidChange object:nil];
                return;
            }
            [self.tableView reloadData];
            if (needsRestart) LMMarkRestartNeeded();
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)editNumber:(LMItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%ld", (long)[NSUserDefaults.standardUserDefaults integerForKey:item.name]];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        long long value = [weakAlert.textFields.firstObject.text longLongValue];
        [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)MAX(0, value) forKey:item.name];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    LMItem *item = [self itemAt:ip];
    LMSection *section = self.category.sections[ip.section];
    if ([self isDimmed:section item:item]) return;
    if (section.needsGhostMode && item.kind == LMKindToggle) {
        [self setToggleItem:item enabled:!LMIsOn(item) atIndexPath:ip reloadSelection:YES];
        return;
    }
    switch (item.kind) {
        case LMKindChoice:
            [self choose:item sourceView:[tv cellForRowAtIndexPath:ip]];
            break;
        case LMKindInput:
            [self editNumber:item];
            break;
        case LMKindScreen: {
            Class cls = NSClassFromString(item.name);
            UINavigationController *navigationController = self.navigationController ?: self.hostNavigationController;
            if ([cls isSubclassOfClass:UIViewController.class]) [navigationController pushViewController:[cls new] animated:YES];
            break;
        }
        case LMKindOpen:
            LMBridgeOpen(item.name);
            break;
        default:
            break;
    }
}

@end

#pragma mark - Root screen

@interface LMRootController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSArray<LMCategory *> *> *groups;
@property (nonatomic, strong) LMCategoryController *searchResults;
@end

@implementation LMRootController

+ (void)setSolvgramBridge:(id)bridge {
    LMBridgeObject = bridge;
    LMUpdateLanguage();
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        LMUpdateLanguage();
        _groups = LMGroups();
        self.navigationItem.backButtonTitle = @"Solvgram";
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.tableHeaderView = [self headerView];

    // Search: every row of every category, shown and working in place.
    LMCategoryController *results = [[LMCategoryController alloc] initWithCategory:[LMCategory new]];
    results.isSearchResults = YES;
    results.hostNavigationController = self.navigationController;
    self.searchResults = results;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:results];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = L(@"Search Settings", @"Поиск настроек");
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateRestartItem) name:LMRestartStateDidChange object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(languageChanged) name:LMLanguageDidChange object:nil];
    [self updateRestartItem];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// Every text of the menu is built in the language of the moment: build it again and start over.
- (void)languageChanged {
    self.groups = LMGroups();
    self.navigationItem.searchController.searchBar.placeholder = L(@"Search Settings", @"Поиск настроек");
    self.navigationItem.searchController.active = NO;
    [self updateRestartItem];
    [self.tableView reloadData];
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)updateRestartItem {
    NSMutableArray *items = [NSMutableArray array];
    if (self.navigationController.viewControllers.firstObject == self) {
        [items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)]];
    }
    if (LMNeedsRestart) [items addObject:LMRestartItem(self)];
    [self.navigationItem setRightBarButtonItems:items animated:YES];
}

- (UIView *)headerView {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 150)];
    UIImageView *icon = [[UIImageView alloc] initWithImage:LMAppIcon(72)];
    UILabel *title = [UILabel new];
    title.text = @"Solvgram";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:72],
        [icon.heightAnchor constraintEqualToConstant:72],
    ]];
    return v;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

static BOOL LMMatches(NSString *text, NSString *query) {
    return text.length > 0 && [text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<LMSection *> *sections = [NSMutableArray array];
    if (query.length > 0) {
        for (NSArray<LMCategory *> *group in self.groups) {
            for (LMCategory *category in group) {
                BOOL categoryMatches = LMMatches(category.title, query);
                for (LMSection *section in category.sections) {
                    BOOL sectionMatches = categoryMatches || LMMatches(section.header, query);
                    NSMutableArray *items = [NSMutableArray array];
                    for (LMItem *item in section.items) {
                        if (sectionMatches || LMMatches(item.title, query) || LMMatches(item.subtitle, query)) [items addObject:item];
                    }
                    if (items.count == 0) continue;
                    LMSection *result = [LMSection new];
                    result.header = section.header.length ? [NSString stringWithFormat:@"%@ · %@", category.title, section.header] : category.title;
                    result.needsGhostMode = section.needsGhostMode;
                    result.items = items;
                    [sections addObject:result];
                }
            }
        }
    }
    LMCategory *results = [LMCategory new];
    results.sections = sections;
    self.searchResults.hostNavigationController = self.navigationController;
    [self.searchResults showSearchResults:results query:query];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.groups[s].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    LMCategory *cat = self.groups[ip.section][ip.row];
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    c.text = cat.title;
    c.secondaryText = cat.subtitle;
    c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    c.secondaryTextProperties.numberOfLines = 1;
    c.image = SolvgramMenuIcon(cat.iconName, 30);
    c.imageProperties.maximumSize = CGSizeMake(30, 30);
    c.imageToTextPadding = 14;
    cell.contentConfiguration = c;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self.navigationController pushViewController:[[LMCategoryController alloc] initWithCategory:self.groups[ip.section][ip.row]] animated:YES];
}

@end

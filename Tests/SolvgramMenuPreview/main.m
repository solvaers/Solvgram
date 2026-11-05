// Standalone UI verification. Uses the production menu and vector renderer, no Telegram account.
#import <UIKit/UIKit.h>
#import "../../Solvgram/SolvgramMenu/Sources/SolvgramMenu.m"

static NSMutableArray<NSString *> *failures;
static void Verify(BOOL condition, NSString *message) {
    if (!condition) { [failures addObject:message]; NSLog(@"FAIL: %@", message); }
}

@interface PreviewBridge : NSObject
@property NSMutableDictionary<NSString *, NSNumber *> *values;
@end
@implementation PreviewBridge
- (instancetype)init {
    if ((self = [super init])) _values = [@{@"chatSwipeOptions": @YES, @"galleryCamera": @YES, @"voiceEffectEnabled": @YES} mutableCopy];
    return self;
}
- (NSNumber *)isAvailable:(NSString *)name { return @YES; }
- (NSNumber *)boolValue:(NSString *)name { return self.values[name] ?: @NO; }
- (NSNumber *)setBool:(NSString *)name value:(NSNumber *)value { self.values[name] = value; return @NO; }
- (NSArray *)choiceOptions:(NSString *)name {
    if ([name isEqualToString:@"solvgramLanguage"]) return @[@[@"system", @"Как в системе"], @[@"ru", @"Русский"], @[@"en", @"English"]];
    return @[@[@"default", L(@"Default", @"По умолчанию")], @[@"other", L(@"Other", @"Другой")]];
}
- (NSString *)choiceValue:(NSString *)name { return @"default"; }
- (NSNumber *)setChoice:(NSString *)name value:(NSString *)value { return @NO; }
- (NSNumber *)sliderValue:(NSString *)name { return [name isEqualToString:@"voiceEffectLevel"] ? @3 : @70; }
- (NSNumber *)setSlider:(NSString *)name value:(NSNumber *)value { return @NO; }
- (void)open:(NSString *)name {}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property UINavigationController *navigation;
@property LMRootController *menu;
@property PreviewBridge *bridge;
@property NSString *output;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    failures = [NSMutableArray new];
    self.output = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"MenuPreview"];
    [NSFileManager.defaultManager createDirectoryAtPath:self.output withIntermediateDirectories:YES attributes:nil error:nil];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@"ru" forKey:@"SolvgramLanguage"];
    [defaults setBool:YES forKey:kGhostMaster];
    for (NSString *key in @[@"disableOnlineStatus", @"disableTypingStatus", @"disableMessageReadReceipt"]) [defaults setBool:YES forKey:key];
    for (NSString *key in @[@"disableRecordingVoiceStatus", @"disableRecordingRoundVideoStatus"]) [defaults setBool:NO forKey:key];
    self.bridge = [PreviewBridge new];
    [LMRootController setSolvgramBridge:self.bridge];
    self.menu = [LMRootController new];
    self.navigation = [[UINavigationController alloc] initWithRootViewController:self.menu];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.window.rootViewController = self.navigation;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self audit]; [self walkthrough]; });
    return YES;
}
- (LMCategoryController *)showCategory:(LMCategory *)category animated:(BOOL)animated {
    [self.navigation popToRootViewControllerAnimated:NO];
    LMCategoryController *controller = [[LMCategoryController alloc] initWithCategory:category];
    [self.navigation pushViewController:controller animated:animated];
    [controller.view layoutIfNeeded];
    return controller;
}
- (void)capture:(NSString *)name {
    [self.window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.window.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    [UIImagePNGRepresentation(image) writeToFile:[self.output stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}
- (void)audit {
    NSArray *names = @[@"privacy", @"messages", @"chat-list", @"chats", @"message-menu", @"stories", @"media", @"translation-voice", @"profiles", @"calls-notifications", @"appearance", @"location", @"accounts", @"ghost"];
    for (NSString *name in names) {
        UIImage *image = SolvgramMenuIcon(name, 32);
        Verify(image != nil && CGSizeEqualToSize(image.size, CGSizeMake(32,32)), [@"Vector icon: " stringByAppendingString:name]);
        Verify(image == SolvgramMenuIcon(name, 32), @"Vector images are cached");
    }
    NSInteger categoryCount = 0, detailCount = 0;
    for (NSArray<LMCategory *> *group in self.menu.groups) {
        for (LMCategory *category in group) {
            categoryCount++;
            LMCategoryController *controller = [[LMCategoryController alloc] initWithCategory:category];
            [controller loadViewIfNeeded];
            for (NSUInteger s=0; s<category.sections.count; s++) {
                for (NSUInteger r=0; r<category.sections[s].items.count; r++) {
                    LMItem *item = category.sections[s].items[r];
                    UITableViewCell *cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
                    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
                    Verify((content.image != nil) == LMIsGhostMaster(item), @"Only the featured control has a detail icon");
                    detailCount++;
                }
            }
        }
    }
    Verify(categoryCount == 13, @"All 13 categories are present");
    Verify(detailCount == 97, @"All existing settings are preserved");
    LMCategoryController *privacy = [self showCategory:self.menu.groups[0][0] animated:NO];
    [privacy.tableView reloadData];
    [privacy.tableView layoutIfNeeded];
    NSIndexPath *master = [NSIndexPath indexPathForRow:0 inSection:0];
    NSIndexPath *online = [NSIndexPath indexPathForRow:0 inSection:1];
    UITableViewCell *masterCell = [privacy tableView:privacy.tableView cellForRowAtIndexPath:master];
    UISwitch *toggle = (UISwitch *)masterCell.accessoryView;
    Verify([toggle isKindOfClass:UISwitch.class], @"Featured Ghost Mode control has a switch");
    [toggle setOn:NO animated:NO]; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    Verify(![NSUserDefaults.standardUserDefaults boolForKey:kGhostMaster], @"Master switch persists");
    BOOL old = [NSUserDefaults.standardUserDefaults boolForKey:@"disableOnlineStatus"];
    [privacy tableView:privacy.tableView didSelectRowAtIndexPath:online];
    Verify(old == [NSUserDefaults.standardUserDefaults boolForKey:@"disableOnlineStatus"], @"Disabled options do not change");
    [toggle setOn:YES animated:NO]; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    [privacy tableView:privacy.tableView didSelectRowAtIndexPath:online];
    Verify(old != [NSUserDefaults.standardUserDefaults boolForKey:@"disableOnlineStatus"], @"Checklist tap persists selection");
    UITableViewCell *onlineCell = [privacy tableView:privacy.tableView cellForRowAtIndexPath:online];
    Verify(onlineCell.accessoryView == nil, @"Checklist has no switch");
    Verify(onlineCell.accessoryType == UITableViewCellAccessoryNone, @"Unselected option loses its checkmark");
    [privacy tableView:privacy.tableView didSelectRowAtIndexPath:online];
    Verify(old == [NSUserDefaults.standardUserDefaults boolForKey:@"disableOnlineStatus"], @"Checklist can select again");
    NSIndexPath *recording = [NSIndexPath indexPathForRow:2 inSection:1];
    [privacy tableView:privacy.tableView didSelectRowAtIndexPath:recording];
    Verify([NSUserDefaults.standardUserDefaults boolForKey:@"disableRecordingVoiceStatus"] && [NSUserDefaults.standardUserDefaults boolForKey:@"disableRecordingRoundVideoStatus"], @"Grouped recording flags change together");
    // Existing switch dependencies still go through the bridge.
    LMCategoryController *list = [self showCategory:self.menu.groups[1][0] animated:NO];
    [list.tableView reloadData]; [list.tableView layoutIfNeeded];
    NSIndexPath *tabMaster = [NSIndexPath indexPathForRow:0 inSection:2];
    UITableViewCell *tabCell = [list tableView:list.tableView cellForRowAtIndexPath:tabMaster];
    UISwitch *tabToggle = (UISwitch *)tabCell.accessoryView;
    tabToggle.on = YES; [tabToggle sendActionsForControlEvents:UIControlEventValueChanged];
    Verify([self.bridge.values[@"hideTabBar"] boolValue], @"Ordinary switches call the bridge");
    Verify([list isDimmed:list.category.sections[2] item:list.category.sections[2].items[1]], @"Dependent settings are disabled");
    tabToggle.on = NO; [tabToggle sendActionsForControlEvents:UIControlEventValueChanged];
    Verify(![list isDimmed:list.category.sections[2] item:list.category.sections[2].items[1]], @"Dependent settings are enabled again");
    UISearchController *search = self.menu.navigationItem.searchController;
    search.searchBar.text = @"призрак";
    [self.menu updateSearchResultsForSearchController:search];
    Verify(self.menu.searchResults.category.sections.count > 0, @"Settings search still finds Ghost Mode");
    for (NSUInteger s=0; s<self.menu.searchResults.category.sections.count; s++) {
        for (NSUInteger r=0; r<self.menu.searchResults.category.sections[s].items.count; r++) {
            UITableViewCell *cell = [self.menu.searchResults tableView:self.menu.searchResults.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
            Verify(((UIListContentConfiguration *)cell.contentConfiguration).image == nil, @"Search results remain icon-free");
        }
    }
    search.searchBar.text = nil;
    [self.menu updateSearchResultsForSearchController:search];
    [self.navigation popToRootViewControllerAnimated:NO];
    NSLog(@"Menu audit: %ld categories, %ld rows, %lu failures", (long)categoryCount, (long)detailCount, (unsigned long)failures.count);
}
- (void)step:(NSInteger)index action:(dispatch_block_t)action capture:(NSString *)name {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(index * 3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        action();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self capture:name]; });
    });
}
- (void)walkthrough {
    [self step:0 action:^{ [self.navigation popToRootViewControllerAnimated:NO]; } capture:@"01-root-light"];
    [self step:1 action:^{ [self showCategory:self.menu.groups[0][0] animated:YES]; } capture:@"02-privacy-on"];
    [self step:2 action:^{
        LMCategoryController *c = (id)self.navigation.topViewController;
        UISwitch *sw = (id)[c.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].accessoryView;
        [sw setOn:NO animated:YES]; [sw sendActionsForControlEvents:UIControlEventValueChanged];
    } capture:@"03-privacy-off"];
    [self step:3 action:^{
        LMCategoryController *c = (id)self.navigation.topViewController;
        UISwitch *sw = (id)[c.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].accessoryView;
        [sw setOn:YES animated:YES]; [sw sendActionsForControlEvents:UIControlEventValueChanged];
        [c tableView:c.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    } capture:@"04-privacy-selection"];
    [self step:4 action:^{ [self showCategory:self.menu.groups[0][1] animated:YES]; } capture:@"05-messages"];
    [self step:5 action:^{
        [self.navigation popToRootViewControllerAnimated:NO];
        [self.menu.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:4 inSection:3] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    } capture:@"06-root-bottom"];
    [self step:6 action:^{
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [self.menu.tableView setContentOffset:CGPointMake(0,-self.menu.tableView.adjustedContentInset.top) animated:NO];
    } capture:@"07-root-dark"];
    [self step:7 action:^{ [self showCategory:self.menu.groups[0][0] animated:YES]; } capture:@"08-privacy-dark"];
    [self step:8 action:^{
        self.navigation.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    } capture:@"09-privacy-large-text"];
    [self step:9 action:^{
        self.navigation.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:@"SolvgramLanguage"];
        LMUpdateLanguage(); self.menu.groups = LMGroups();
        [self showCategory:self.menu.groups[0][0] animated:NO];
    } capture:@"10-privacy-english"];
    [self step:10 action:^{
        [NSUserDefaults.standardUserDefaults setObject:@"ru" forKey:@"SolvgramLanguage"];
        LMUpdateLanguage(); self.menu.groups = LMGroups();
        [self showCategory:self.menu.groups[0][0] animated:NO];
        CGRect frame = self.window.frame; frame.size.width = 375; self.window.frame = frame;
    } capture:@"11-privacy-narrow"];
    [self step:11 action:^{
        self.window.frame = CGRectMake(0,0,844,390);
        [self showCategory:self.menu.groups[0][1] animated:NO];
    } capture:@"12-messages-landscape-viewport"];
    [self step:12 action:^{
        self.window.frame = UIScreen.mainScreen.bounds;
        [self showCategory:self.menu.groups[0][0] animated:NO];
        NSDictionary *report = @{@"failures": failures, @"categories": @13, @"settings": @97, @"icons": @14, @"completed": @YES};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:[self.output stringByAppendingPathComponent:@"report.json"] atomically:YES];
        NSLog(@"MENU_PREVIEW_DONE %@", self.output);
    } capture:@"13-privacy-final"];
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); } }

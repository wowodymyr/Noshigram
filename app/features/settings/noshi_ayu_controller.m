#import "noshi_ayu_controller.h"

#import "noshi_alert.h"
#import "noshi_ayu.h"
#import "noshi_chat_settings.h"
#import "noshi_gift_screen.h"
#import "noshi_session_saved.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_weak_reference.h"

static NoshiSettingsRow *NoshiAyuSwitch(NSString *titleKey, NSString *infoKey, NoshiChatFlag flag, void (^changed)(void)) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil on:NoshiChatFlagGet(flag) toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on);
        if (changed) changed();
    }];
}

#pragma mark ghost mode

@implementation NoshiGhostController

- (id)init {
    self = [super init];
    if (!self) return nil;
    self.pageTitle = NSLocalizedString(@"ayu.ghost", nil);
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiGhostController alloc] init] autorelease];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiAyuSwitch(@"ayu.ghost.noread", @"ayu.ghost.noread.info", NoshiChatFlagGhostNoRead, nil)];
    [rows addObject:NoshiAyuSwitch(@"ayu.ghost.nostories", @"ayu.ghost.nostories.info", NoshiChatFlagGhostNoStories, nil)];
    [rows addObject:NoshiAyuSwitch(@"ayu.ghost.offline", @"ayu.ghost.offline.info", NoshiChatFlagGhostOffline, ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    })];
    self.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.ghost.info", nil) rows:rows]];
    [self reloadSettings];
}

@end

#pragma mark filters

@interface NoshiRegexFiltersController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiRegexFiltersController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"ayu.regex.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiRegexFiltersController alloc] init] autorelease];
}

- (void)store:(NSArray *)patterns {
    NoshiAyuSetRegexList(patterns);
    /* an open chat takes the new list the next time its messages are put in order */
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    [self rebuild];
}

- (void)addOrChange:(NSString *)old {
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(old ? @"ayu.regex.change" : @"ayu.regex.add", nil), NSLocalizedString(@"ayu.regex.hint", nil), old, NSLocalizedString(@"ayu.regex.placeholder", nil), ^(NSString *text) {
        NoshiRegexFiltersController *me = weak.target;
        if (!me) return;
        NSString *pattern = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *problem = NoshiAyuRegexProblem(pattern);
        if (problem) {
            NoshiGiftAlert(nil, problem);
            return;
        }
        NSMutableArray *list = [NSMutableArray arrayWithArray:NoshiAyuRegexList()];
        NSUInteger at = old ? [list indexOfObject:old] : NSNotFound;
        if (at != NSNotFound) [list replaceObjectAtIndex:at withObject:pattern];
        else [list addObject:pattern];
        [me store:list];
    });
}

- (void)choose:(NSString *)pattern {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsChoose(self, pattern, [NSArray arrayWithObjects:NSLocalizedString(@"ayu.regex.change", nil), NSLocalizedString(@"ayu.regex.remove", nil), nil], ^(NSUInteger index) {
        NoshiRegexFiltersController *me = weak.target;
        if (!me) return;
        if (index == 0) {
            [me addOrChange:pattern];
            return;
        }
        NSMutableArray *list = [NSMutableArray arrayWithArray:NoshiAyuRegexList()];
        [list removeObject:pattern];
        [me store:list];
    });
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *pattern in NoshiAyuRegexList()) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:pattern value:nil tap:^{ [(NoshiRegexFiltersController *)weak.target choose:pattern]; }]];
    }
    [rows addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle title:NSLocalizedString(@"ayu.regex.add", nil) destructive:NO tap:^{
        [(NoshiRegexFiltersController *)weak.target addOrChange:nil];
    }]];
    self.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.regex.info", nil) rows:rows]];
    [self reloadSettings];
}

@end

#pragma mark AyuMoments

@interface NoshiAyuController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NSInteger _savedCount;
}
@end

@implementation NoshiAyuController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _savedCount = -1;
    self.pageTitle = NSLocalizedString(@"ayu.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NoshiWeakReference *weak = _weak;
    [_session countSavedMessages:^(NSInteger count, NSString *errorName) {
        NoshiAyuController *me = weak.target;
        if (!me) return;
        if (errorName) NSLog(@"noshigram: the saved messages were not counted: %@", errorName);
        me->_savedCount = errorName ? -1 : count;
        [me rebuild];
    }];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiAyuController alloc] initWithSession:_session] autorelease];
}

/* the keeping of messages is read by the part that handles the updates, so it is told at once; the open chats are not touched */
- (void)savingChanged {
    [_session setSavingSettingsFromDefaults];
    [self rebuild];
}

- (void)disableAll {
    static const NoshiChatFlag flags[] = {NoshiChatFlagGhostNoRead, NoshiChatFlagGhostNoStories, NoshiChatFlagGhostOffline, NoshiChatFlagAyuRegex,
                                            NoshiChatFlagAyuSaveDeleted, NoshiChatFlagAyuSaveEdits, NoshiChatFlagAyuCopyProtected};
    for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); ++i) NoshiChatFlagSet(flags[i], NO);
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    [self savingChanged];
}

- (void)clearSaved {
    NoshiWeakReference *weak = _weak;
    [_session clearSavedMessages:^(NSString *errorName) {
        NoshiAyuController *me = weak.target;
        if (!me) return;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        me->_savedCount = 0;
        [me rebuild];
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    void (^saving)(void) = ^{ [(NoshiAyuController *)weak.target savingChanged]; };
    NSMutableArray *sections = [NSMutableArray array];

    NoshiSettingsRow *ghost = [NoshiSettingsRow rowWithSymbol:NoshiSymbolEyeSlash tone:NoshiSettingsTonePurple title:NSLocalizedString(@"ayu.ghost", nil) subtitle:nil value:nil tap:^{
        [[(NoshiAyuController *)weak.target navigationController] pushViewController:[[[NoshiGhostController alloc] init] autorelease] animated:YES];
    }];
    NSMutableArray *main = [NSMutableArray arrayWithObject:ghost];
    [main addObject:NoshiAyuSwitch(@"ayu.copyprotected", @"ayu.copyprotected.info", NoshiChatFlagAyuCopyProtected, nil)];
    [main addObject:NoshiAyuSwitch(@"ayu.regex.switch", nil, NoshiChatFlagAyuRegex, ^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil]; })];
    NSUInteger count = NoshiAyuRegexList().count;
    [main addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"ayu.regex.title", nil) value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil tap:^{
        [[(NoshiAyuController *)weak.target navigationController] pushViewController:[[[NoshiRegexFiltersController alloc] init] autorelease] animated:YES];
    }]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"ayu.info", nil) rows:main]];

    NSMutableArray *saving1 = [NSMutableArray array];
    [saving1 addObject:NoshiAyuSwitch(@"ayu.savedeleted", @"ayu.savedeleted.info", NoshiChatFlagAyuSaveDeleted, saving)];
    if (NoshiChatFlagGet(NoshiChatFlagAyuSaveDeleted)) {
        [saving1 addObject:NoshiAyuSwitch(@"ayu.deleted.private", nil, NoshiChatFlagAyuDeletedPrivate, saving)];
        [saving1 addObject:NoshiAyuSwitch(@"ayu.deleted.groups", nil, NoshiChatFlagAyuDeletedGroups, saving)];
        [saving1 addObject:NoshiAyuSwitch(@"ayu.deleted.channels", nil, NoshiChatFlagAyuDeletedChannels, saving)];
        [saving1 addObject:NoshiAyuSwitch(@"ayu.deleted.bots", nil, NoshiChatFlagAyuDeletedBots, saving)];
        [saving1 addObject:NoshiAyuSwitch(@"ayu.translucent", nil, NoshiChatFlagAyuTranslucent, ^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil]; })];
        [saving1 addObject:NoshiAyuSwitch(@"ayu.replyquote", @"ayu.replyquote.info", NoshiChatFlagAyuReplyQuote, nil)];
    }
    [saving1 addObject:NoshiAyuSwitch(@"ayu.saveedits", @"ayu.saveedits.info", NoshiChatFlagAyuSaveEdits, saving)];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"ayu.saving.header", nil) footer:nil rows:saving1]];

    NSMutableArray *danger = [NSMutableArray array];
    [danger addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolBlock title:NSLocalizedString(@"ayu.disableall", nil) destructive:YES tap:^{
        NoshiAyuController *me = weak.target;
        if (!me) return;
        NoshiConfirmAction(me, NSLocalizedString(@"ayu.disableall.confirm", nil), NSLocalizedString(@"ayu.disableall", nil), ^{ [(NoshiAyuController *)weak.target disableAll]; });
    }]];
    NSString *cleared = _savedCount >= 0 ? [NSString stringWithFormat:NSLocalizedString(@"ayu.clear.count", nil), (long)_savedCount] : nil;
    [danger addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolTrash tone:NoshiSettingsToneRed title:NSLocalizedString(@"ayu.clear", nil) subtitle:cleared value:nil tap:^{
        NoshiAyuController *me = weak.target;
        if (!me) return;
        NoshiConfirmAction(me, NSLocalizedString(@"ayu.clear.confirm", nil), NSLocalizedString(@"ayu.clear", nil), ^{ [(NoshiAyuController *)weak.target clearSaved]; });
    }]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:danger]];

    self.sections = sections;
    [self reloadSettings];
}

@end

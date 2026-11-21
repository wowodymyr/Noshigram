#import "noshi_developer_settings.h"
#import "noshi_logs_controller.h"

#import "noshi_alert.h"
#import "noshi_crash_prompt.h"
#import "noshi_developer_badges_controller.h"
#import "noshi_developers.h"
#import "noshi_inapp_banner.h"
#import "noshi_cleaning.h"
#import "noshi_popup_menu.h"
#import "noshi_release_check.h"
#import "noshi_senko_popup.h"
#import "noshi_shiro.h"
#import "noshi_shiro_failure_prompt.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_welcome_toast.h"
#import "noshi_platform.h"
#import "noshi_weak_reference.h"

NSString *const NoshiDeveloperModeDidChangeNotification = @"NoshiDeveloperModeDidChange";

static NSString *const NoshiDeveloperModeKey = @"noshigram.developer.mode";

BOOL NoshiDeveloperModeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoshiDeveloperModeKey];
}

void NoshiDeveloperModeSet(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:NoshiDeveloperModeKey];
}

@interface NoshiDeveloperSettingsController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NoshiSenkoPopup *_senko;
    NoshiWelcomeToast *_toast;
}
@end

@implementation NoshiDeveloperSettingsController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"developer.settings", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    _senko.dismissHandler = nil;
    [_senko dismiss];
    [_senko release];
    _toast.dismissHandler = nil;
    [_toast dismiss];
    [_toast release];
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
    return [[[NoshiDeveloperSettingsController alloc] initWithSession:_session] autorelease];
}

/* the windows come up over the whole app, which is the host the app itself uses for them */
static UIView *NoshiDeveloperHost(void) {
    return NoshiOverlayHost();
}

- (void)showSenko {
    if (_senko.isShown) return;
    [_senko release];
    _senko = [[NoshiSenkoPopup alloc] init];
    _senko.titleText = NSLocalizedString(@"welcome.senko.title", nil);
    _senko.messageText = NSLocalizedString(@"welcome.senko.message", nil);
    _senko.buttonTitle = NSLocalizedString(@"welcome.senko.ok", nil);
    NoshiWeakReference *weak = _weak;
    _senko.dismissHandler = ^{
        NoshiDeveloperSettingsController *me = weak.target;
        if (!me) return;
        [me->_senko release];
        me->_senko = nil;
    };
    [_senko showInView:NoshiDeveloperHost()];
}

- (void)showToast {
    if (_toast.isShown) return;
    [_toast release];
    _toast = [[NoshiWelcomeToast alloc] init];
    _toast.titleText = NSLocalizedString(@"developer.popup.toast", nil);
    _toast.messageText = NSLocalizedString(@"developer.popup.toast.text", nil);
    _toast.primaryTitle = NSLocalizedString(@"notice.ok", nil);
    _toast.secondaryTitle = NSLocalizedString(@"notice.cancel", nil);
    _toast.lifetime = 8;
    NoshiWeakReference *weak = _weak;
    _toast.dismissHandler = ^{
        NoshiDeveloperSettingsController *me = weak.target;
        if (!me) return;
        [me->_toast release];
        me->_toast = nil;
    };
    [_toast showInView:NoshiDeveloperHost() inset:NoshiStatusBarHeight()];
}

/* every chat of the main list and of the archive that holds unread messages or carries the manual unread mark is read on the server, one call after another so the
   server is not flooded; the person is told how many went through and how many failed */
- (void)markEverythingRead {
    NoshiDeveloperSettingsController *me = self;
    [_session loadDialogsInFolder:0 completion:^(NSArray *main, NSString *mainError) {
        if (mainError) {
            NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"developer.readall.failed", nil), mainError]);
            return;
        }
        [me->_session loadDialogsInFolder:1 completion:^(NSArray *archived, NSString *archiveError) {
            if (archiveError) NSLog(@"noshigram: the archive was not read by mark everything: %@", archiveError);
            NSMutableArray *queue = [NSMutableArray array];
            for (NoshiDialog *dialog in [main arrayByAddingObjectsFromArray:archived ? archived : [NSArray array]]) {
                if (dialog.unreadCount > 0 || dialog.unread) [queue addObject:dialog];
            }
            if (!queue.count) {
                NoshiShowNotice(nil, NSLocalizedString(@"developer.readall.none", nil));
                return;
            }
            [me markNextRead:queue done:0 failed:0];
        }];
    }];
}

- (void)markNextRead:(NSMutableArray *)queue done:(NSUInteger)done failed:(NSUInteger)failed {
    if (!queue.count) {
        NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"developer.readall.done", nil), (unsigned long)done, (unsigned long)failed]);
        return;
    }
    NoshiDialog *dialog = [[[queue objectAtIndex:0] retain] autorelease];
    [queue removeObjectAtIndex:0];
    NoshiChatCommand command = dialog.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark;
    [_session performAction:command onDialog:dialog completion:^(NSString *errorName) {
        if (errorName) NSLog(@"noshigram: %@ was not marked read: %@", dialog.title, errorName);
        [self markNextRead:queue done:done + (errorName ? 0 : 1) failed:failed + (errorName ? 1 : 0)];
    }];
}

- (void)showMarkNotices {
    static const struct { NSUInteger mark; NSString *key; } marks[] = {
        {NoshiMarkDeveloper, @"developer.mark.developer"}, {NoshiMarkLead, @"developer.mark.lead"}, {NoshiMarkSenko, @"developer.mark.senko"},
        {NoshiMarkTester, @"developer.mark.tester"}, {NoshiMarkOfficialTester, @"developer.mark.official"}, {NoshiMarkBugHunter, @"developer.mark.hunter"}, {NoshiMarkFlawSeer, @"developer.mark.flawseer"},
        {NoshiMarkManager, @"developer.mark.manager"}, {NoshiMarkVideoFix, @"developer.mark.videofix"}, {NoshiMarkPromotion, @"developer.mark.promotion"}
    };
    NSMutableArray *titles = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(marks) / sizeof(marks[0]); ++i) [titles addObject:NSLocalizedString(marks[i].key, nil)];
    NoshiChoose(NSLocalizedString(@"developer.popup.mark", nil), titles, -1, ^(NSInteger index) {
        if (index < 0 || (size_t)index >= sizeof(marks) / sizeof(marks[0])) return;
        NoshiShowMarkNotice(NSLocalizedString(@"developer.popup.someone", nil), marks[index].mark);
    });
}

- (void)showMenuAt:(CGPoint)point {
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"developer.menu.one", nil), NSLocalizedString(@"developer.menu.two", nil), NSLocalizedString(@"developer.menu.three", nil), nil];
    NoshiSymbol symbols[] = {NoshiSymbolPerson, NoshiSymbolStar, NoshiSymbolBookmark};
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) { (void)index; }] autorelease];
    [menu showInView:self.view anchor:point];
}

- (void)showCleaning {
    NSArray *steps = [NSArray arrayWithObjects:[NoshiCleaningStep stepNamed:NSLocalizedString(@"developer.popup.cleaning.one", nil) work:^{ [NSThread sleepForTimeInterval:0.8]; }],
                      [NoshiCleaningStep stepNamed:NSLocalizedString(@"developer.popup.cleaning.two", nil) work:^{ [NSThread sleepForTimeInterval:0.8]; }], nil];
    NoshiRunCleaning(steps, ^{});
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
#define ME ((NoshiDeveloperSettingsController *)weak.target)
#define POPUP(symbol, titleKey, subtitleKey, body) \
    [NoshiSettingsRow rowWithSymbol:symbol tone:NoshiSettingsToneBlack title:NSLocalizedString(titleKey, nil) subtitle:NSLocalizedString(subtitleKey, nil) value:nil tap:^{ body }]
    NSArray *popups = [NSArray arrayWithObjects:
        POPUP(NoshiSymbolReport, @"developer.popup.crash", @"developer.popup.crash.info", {
            if (!NoshiAskCrashReport(^(BOOL send) { (void)send; })) NoshiShowNotice(nil, NSLocalizedString(@"developer.popup.busy", nil));
        }),
        POPUP(NoshiSymbolGlobe, @"developer.popup.shiro", @"developer.popup.shiro.info", {
            NoshiShiro *shiro = NoshiShiroActive();
            if (shiro) NoshiShowShiroFailure(shiro);
            else NoshiShowNotice(nil, NSLocalizedString(@"developer.popup.noshiro", nil));
        }),
        POPUP(NoshiSymbolHeart, @"developer.popup.senko", @"developer.popup.senko.info", { [ME showSenko]; }),
        POPUP(NoshiSymbolExternalLink, @"developer.popup.release", @"developer.popup.release.info", { NoshiShowReleasePreview(NoshiDeveloperHost()); }),
        POPUP(NoshiSymbolMember, @"developer.popup.mark", @"developer.popup.mark.info", { [ME showMarkNotices]; }),
        POPUP(NoshiSymbolChats, @"developer.popup.toast", @"developer.popup.toast.info", { [ME showToast]; }),
        POPUP(NoshiSymbolBell, @"developer.popup.banner", @"developer.popup.banner.info", {
            [NoshiInAppBanner showTitle:NSLocalizedString(@"developer.popup.banner", nil) body:NSLocalizedString(@"developer.popup.banner.text", nil) dialog:nil avatars:nil tap:^{}];
        }),
        POPUP(NoshiSymbolStar, @"developer.popup.power", @"developer.popup.power.info", {
            [NoshiInAppBanner showPowerTitle:NSLocalizedString(@"developer.popup.power", nil) body:NSLocalizedString(@"developer.popup.power.text", nil)];
        }),
        POPUP(NoshiSymbolBroom, @"developer.popup.cleaning", @"developer.popup.cleaning.info", { [ME showCleaning]; }),
        nil];
    NSArray *system = [NSArray arrayWithObjects:
        POPUP(NoshiSymbolInfo, @"developer.popup.notice", @"developer.popup.notice.info", {
            NoshiShowNotice(NSLocalizedString(@"developer.popup.notice", nil), NSLocalizedString(@"developer.popup.notice.text", nil));
        }),
        POPUP(NoshiSymbolCheckMark(), @"developer.popup.confirm", @"developer.popup.confirm.info", {
            NoshiConfirm(NSLocalizedString(@"developer.popup.confirm", nil), NSLocalizedString(@"developer.popup.confirm.text", nil), NSLocalizedString(@"notice.ok", nil), ^{});
        }),
        POPUP(NoshiSymbolEllipsis, @"developer.popup.choose", @"developer.popup.choose.info", {
            NoshiChoose(NSLocalizedString(@"developer.popup.choose", nil), [NSArray arrayWithObjects:@"A", @"B", @"C", nil], -1, ^(NSInteger index) { (void)index; });
        }),
        POPUP(NoshiSymbolCompose, @"developer.popup.prompt", @"developer.popup.prompt.info", {
            NoshiPromptText(NSLocalizedString(@"developer.popup.prompt", nil), nil, @"", @"...", ^(NSString *text) { (void)text; });
        }),
        POPUP(NoshiSymbolEllipsisVertical, @"developer.popup.menu", @"developer.popup.menu.info", {
            NoshiDeveloperSettingsController *me = ME;
            [me showMenuAt:CGPointMake(me.view.bounds.size.width - 16, 120)];
        }),
        nil];
#undef POPUP
#undef ME
    /* the badges of the team on his own name, to see them where they are drawn */
    NoshiSettingsRow *badges = [NoshiSettingsRow rowWithSymbol:NoshiSymbolStar tone:NoshiSettingsToneBlack title:NSLocalizedString(@"developer.badges", nil)
                                                          subtitle:NSLocalizedString(@"developer.badges.row.info", nil) value:nil tap:^{
        NoshiDeveloperSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[NoshiDeveloperBadgesController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    NoshiSettingsRow *logs = [NoshiSettingsRow rowWithSymbol:NoshiSymbolDocument tone:NoshiSettingsToneBlack title:NSLocalizedString(@"logs.title", nil)
                                                        subtitle:NSLocalizedString(@"logs.row.info", nil) value:nil tap:^{
        NoshiDeveloperSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[NoshiLogsController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    NoshiSettingsRow *readAll = [NoshiSettingsRow rowWithSymbol:NoshiSymbolCheckMark() tone:NoshiSettingsToneBlack title:NSLocalizedString(@"developer.readall", nil)
                                                           subtitle:NSLocalizedString(@"developer.readall.info", nil) value:nil tap:^{
        NoshiDeveloperSettingsController *me = weak.target;
        if (!me) return;
        NoshiConfirm(NSLocalizedString(@"developer.readall", nil), NSLocalizedString(@"developer.readall.confirm", nil), NSLocalizedString(@"notice.ok", nil), ^{
            NoshiDeveloperSettingsController *again = weak.target;
            if (again) [again markEverythingRead];
        });
    }];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NoshiSettingsRow *classic = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.classic", nil) subtitle:NSLocalizedString(@"developer.classic.info", nil)
                                                                      on:[defaults boolForKey:NoshiClassicAnywhereKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:NoshiClassicAnywhereKey];
        /* the stored choice is dropped by the theme when the classic style is gone, and the screens are rebuilt */
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil];
    }];
    NoshiSettingsRow *pad = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.pad", nil) subtitle:NSLocalizedString(@"developer.pad.info", nil)
                                                                  on:[defaults boolForKey:NoshiPadInterfaceKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:NoshiPadInterfaceKey];
        /* the two switches name opposite interfaces, so one that goes on puts the other off */
        if (on) [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiPhoneInterfaceKey];
        [(NoshiDeveloperSettingsController *)weak.target rebuild];
    }];
    NoshiSettingsRow *phone = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"developer.phone", nil) subtitle:NSLocalizedString(@"developer.phone.info", nil)
                                                                    on:[defaults boolForKey:NoshiPhoneInterfaceKey] toggle:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:NoshiPhoneInterfaceKey];
        if (on) [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiPadInterfaceKey];
        [(NoshiDeveloperSettingsController *)weak.target rebuild];
    }];
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.interface.header", nil) footer:NSLocalizedString(@"developer.interface.footer", nil) rows:[NSArray arrayWithObjects:classic, pad, phone, nil]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"logs.header", nil) footer:nil rows:[NSArray arrayWithObject:logs]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.readall.header", nil) footer:nil rows:[NSArray arrayWithObject:readAll]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.badges.header", nil) footer:nil rows:[NSArray arrayWithObject:badges]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.popups", nil) footer:NSLocalizedString(@"developer.popups.info", nil) rows:popups],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.system", nil) footer:nil rows:system],
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
            [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCloseMark() title:NSLocalizedString(@"developer.hide", nil) destructive:YES tap:^{
                NoshiDeveloperModeSet(NO);
                /* the switches belong to the page, so hiding it puts the interface back */
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiClassicAnywhereKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiPadInterfaceKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiPhoneInterfaceKey];
                [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDeveloperModeDidChangeNotification object:nil];
                [((NoshiDeveloperSettingsController *)weak.target).navigationController popViewControllerAnimated:YES];
            }]]], nil];
}

@end

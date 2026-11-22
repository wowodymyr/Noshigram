#import "noshi_classic_chrome.h"
#import "noshi_classic_profile_controller.h"
#import "noshi_profile_qr_controller.h"
#import "noshi_folders_controller.h"
#import "noshi_settings_controller.h"
#import "noshi_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_avatar_view.h"
#import "noshi_avatar_viewer.h"
#import "noshi_chat_settings.h"
#import "noshi_chat_settings_controller.h"
#import "noshi_about_controller.h"
#import "noshi_update_controller.h"
#import "noshi_account_controller.h"
#import "noshi_accounts.h"
#import "noshi_data_settings_controller.h"
#import "noshi_stickers_settings_controller.h"
#import "noshi_passcode_settings_controller.h"
#import "noshi_people_avatars.h"
#import "noshi_passcode_store.h"
#import "noshi_privacy_controller.h"
#import "noshi_classic_devices_controller.h"
#import "noshi_dialog.h"
#import "noshi_emoji_label.h"
#import "noshi_language.h"
#import "noshi_language_controller.h"
#import "noshi_lite_mode.h"
#import "noshi_lite_mode_controller.h"
#import "noshi_notifications_settings_controller.h"
#import "noshi_person.h"
#import "noshi_popup_menu.h"
#import "noshi_profile_identity_view.h"
#import "noshi_platform.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_session_profile.h"
#import "noshi_settings_pages.h"
#import "noshi_sheet.h"
#import "noshi_theme.h"
#import "noshi_translator_controller.h"
#import "noshi_weak_reference.h"

/* the identity block starts 58 points under the top, like the one of the profile screen, and the table starts
   under the status bar so that it scrolls up behind the bar list does */
#define HEADER_HEIGHT (NOSHI_IDENTITY_BAR + NOSHI_IDENTITY_TOP + NOSHI_IDENTITY_HEIGHT + 24)
/* the classic style puts the table under the system navigation bar, so the block needs no room for a bar of ours; the grouped table
   adds a gap of its own above the first section, so the room under the @name is smaller than the 24 points of the modern one */
#define CLASSIC_HEADER_HEIGHT (NOSHI_IDENTITY_TOP + NOSHI_IDENTITY_HEIGHT + 8)
/* the title comes in once the header has gone up under the bar, over 420 ms */
#define TITLE_FADE_SECONDS 0.42
static NSString *const NoshiDevicesCountKey = @"noshigram.devices.count";

/* the table header: the shared identity block, below the room the bar takes */
@interface NoshiSettingsHeaderView : UIView {
    NoshiProfileIdentityView *_identity;
    CGFloat _identityTop;
}
@property (nonatomic, readonly) NoshiProfileIdentityView *identity;
- (id)initWithFrame:(CGRect)frame identityTop:(CGFloat)identityTop;
@end

@implementation NoshiSettingsHeaderView

@synthesize identity = _identity;

- (id)initWithFrame:(CGRect)frame identityTop:(CGFloat)identityTop {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _identityTop = identityTop;
    _identity = [[NoshiProfileIdentityView alloc] init];
    [self addSubview:_identity];
    return self;
}

- (void)dealloc {
    [_identity release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _identity.frame = CGRectMake(0, _identityTop, self.bounds.size.width, NOSHI_IDENTITY_HEIGHT + [_identity extraHeightForWidth:self.bounds.size.width]);
}

@end

@interface NoshiSettingsController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickerLibrary;
    NoshiWeakReference *_weak;
    NoshiSettingsHeaderView *_header;
    NoshiPerson *_person;
    NoshiPeopleAvatars *_faces;
    BOOL _uploading;
    BOOL _barFilled;
    CGFloat _headerExtra;
    /* the words the classic bar shows now: the title view is made again only when they change */
    NSString *_barHandle;
    BOOL _signingOut;
    UIButton *_more;
    UIButton *_qr;
    void (^_signOutHandler)(void (^)(NSString *));
}
@end

@implementation NoshiSettingsController

@synthesize signOutHandler = _signOutHandler;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.showsBack = NO;
    self.contentUnderBar = YES;
    self.pageTitle = NSLocalizedString(@"tab.settings", nil);
    self.barFill = 0;
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiChatSettingsDidChangeNotification object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickerLibrary release];
    [_header release];
    [_barHandle release];
    [_person release];
    [_faces invalidate];
    [_faces release];
    [_more release];
    [_qr release];
    [_signOutHandler release];
    [super dealloc];
}

#pragma mark header

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:NoshiChatSettingsDidChangeNotification object:nil];
    _header = [[NoshiSettingsHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, CLASSIC_HEADER_HEIGHT)
                                                   identityTop:NOSHI_IDENTITY_TOP];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    /* the grouped table of the light classic style keeps the system's own background, which the modern ring color is not */
    if (!NoshiThemeIsDark()) [_header.identity setBadgeRingColor:[UIColor clearColor]];
    [_header.identity.avatarHit addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header.identity.badge addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
    /* the name and the line under it open the full profile */
    for (UIView *words in [NSArray arrayWithObjects:_header.identity.name, _header.identity.line, nil]) {
        words.userInteractionEnabled = YES;
        [words addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfile)] autorelease]];
    }
    self.headerView = _header;
    /* the same one-row menu as the dots of the modern bar, on the system bar, and the magnifier of its search
           in the corner at the left; the bars of this style are dark, so the pictures are drawn white */
    UIBarButtonItem *dots = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolEllipsis, 22, [UIColor whiteColor])
                                                              style:UIBarButtonItemStyleBordered target:self action:@selector(showMenu)] autorelease];
    dots.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
    /* the username of the account stands in the middle of the bar; the code of the profile is one tap away in the modern look and in the profile */
    self.navigationItem.titleView = NoshiClassicTitleView(@"", nil);
    UIBarButtonItem *search = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, 22, [UIColor whiteColor])
                                                                style:UIBarButtonItemStyleBordered target:self action:@selector(focusSearch)] autorelease];
    search.accessibilityLabel = NSLocalizedString(@"settings.search", nil);
    /* the magnifier takes the corner on the left, and the dots stay alone on the right */
    self.navigationItem.leftBarButtonItem = search;
    self.navigationItem.rightBarButtonItem = dots;
    [self rebuildRows];
    [self loadPerson];
}

- (void)chatSettingsChanged {
    if (_person) [self showPerson];
}

/* the full profile of the account: its stories, gifts, music and channel, which the settings do not hold */
- (void)openProfile {
    NoshiClassicProfileController *profile = [[[NoshiClassicProfileController alloc] initWithSession:_session avatars:_avatars] autorelease];
    profile.media = _media;
    profile.stickerLibrary = _stickerLibrary;
    profile.signOutHandler = _signOutHandler;
    [self.navigationController pushViewController:profile animated:YES];
}

- (void)openQr {
    if (!_person) return;
    NoshiProfileQrController *code = [[[NoshiProfileQrController alloc] initWithSession:_session person:_person avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:code animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildRows];
    [self loadPerson];
}

- (void)loadPerson {
    /* the profile of the last time draws at once, and the answer corrects it */
    NoshiPerson *known = _person ? nil : [_session ownPerson];
    if (known) {
        _person = [known retain];
        [self showPerson];
    }
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiSettingsController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"noshigram: the profile of the settings did not load: %@", errorName);
            return;
        }
        [me->_person release];
        me->_person = [[items objectAtIndex:0] retain];
        [me->_avatars pinPhoto:me->_person.photo];
        NoshiAccountKeepPhotoOfPerson(me->_person, me->_avatars);
        NoshiLiteSetPremium(NoshiPremiumEffective(me->_person.premium));
        [me showPerson];
    }];
}

- (void)showPerson {
    NoshiProfileIdentityView *identity = _header.identity;
    identity.userId = _person.userId;
    [identity setName:_person.name];
    identity.line.text = _person.username.length ? [@"@" stringByAppendingString:_person.username] : NoshiOwnPhoneText(_person.phone);
    NSString *handle = _person.username.length ? [@"@" stringByAppendingString:_person.username] : _person.name;
    /* every return to this page asks the profile again, and a title view swapped while the page slides back jumps on the bar */
    if (![handle isEqualToString:_barHandle]) {
        [_barHandle release];
        _barHandle = [handle copy];
        self.navigationItem.titleView = NoshiClassicTitleView(handle, nil);
    }
    identity.avatar.initials = _person.initials;
    identity.avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [identity.avatar setPhoto:_person.photo cache:_avatars];
    /* a name with many badges runs to more lines, and the head of the page grows by them */
    CGFloat extra = [identity extraHeightForWidth:_header.bounds.size.width];
    if (extra != _headerExtra) {
        _headerExtra = extra;
        CGRect frame = _header.frame;
        frame.size.height = (CLASSIC_HEADER_HEIGHT) + extra;
        _header.frame = frame;
        self.headerView = _header;
        [_header setNeedsLayout];
    }
}

/* a tap on the photo: it jumps, as the photo of exteraGram does when it is pressed, and the sheet of the library comes up under it */
- (void)avatarTapped {
    if (_uploading || !_person) return;
    CALayer *layer = _header.identity.avatar.layer;
    CAKeyframeAnimation *jump = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    jump.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:1], [NSNumber numberWithDouble:0.86], [NSNumber numberWithDouble:1.1], [NSNumber numberWithDouble:0.97],
                   [NSNumber numberWithDouble:1], nil];
    jump.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0.25], [NSNumber numberWithDouble:0.6], [NSNumber numberWithDouble:0.85],
                     [NSNumber numberWithDouble:1], nil];
    jump.duration = 0.42;
    jump.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:jump forKey:@"noshigram.jump"];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showPhotoSheet) object:nil];
    [self performSelector:@selector(showPhotoSheet) withObject:nil afterDelay:NoshiReduceMotionEnabled() ? 0 : 0.3];
}

- (void)showPhotoSheet {
    if (_uploading) return;
    NoshiWeakReference *weak = _weak;
    [NoshiProfilePhotoPicker pickWithSheetIn:NoshiOverlayHost() picked:^(NSString *path, BOOL video) {
        NoshiSettingsController *me = weak.target;
        if (!me) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [me uploadPickedPath:path video:video];
    } failed:^{
        NoshiShowNotice(nil, NSLocalizedString(@"attach.failed", nil));
    }];
}

- (void)uploadPickedPath:(NSString *)path video:(BOOL)video {
    NoshiWeakReference *weak = _weak;
    _uploading = YES;
    [_header.identity setUploading:YES];
    void (^finished)(NSString *) = ^(NSString *errorName) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NoshiSettingsController *again = weak.target;
        if (!again) return;
        again->_uploading = NO;
        [again->_header.identity setUploading:NO];
        if (errorName) {
            NSLog(@"noshigram: the profile %@ was not set: %@", video ? @"video" : @"photo", errorName);
            NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
            return;
        }
        [again loadPerson];
    };
    if (video) [_session uploadProfileVideoAtPath:path completion:finished];
    else [_session uploadProfilePhotoAtPath:path completion:finished];
}

#pragma mark rows

- (void)push:(UIViewController *)page {
    [self.navigationController pushViewController:page animated:YES];
}

/* the sessions list has rows with a picture and three lines, which only the classic screen of its own draws in a grouped table */
- (void)openDevices {
    [self push:(UIViewController *)[[[NoshiClassicDevicesController alloc] initWithSession:_session media:_media] autorelease]];
}

/* the accounts of this phone other than the one in use, as a section above the settings of Noshigram; a phone with one account has none. an account that is not
   connected has no photo here, so its round picture is its initials on its color */
- (NoshiSettingsSection *)otherAccountsSection {
    NSString *active = NoshiAccountActive();
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in NoshiAccountNames()) {
        if ([name isEqualToString:active]) continue;
        NSDictionary *info = NoshiAccountInfo(name);
        NSString *title = [info objectForKey:@"title"];
        if (!title.length) title = NSLocalizedString(@"account.title", nil);
        NSString *username = [info objectForKey:@"username"];
        if (!_faces) {
            NoshiWeakReference *weak = _weak;
            _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiSettingsController *)weak.target rebuildRows]; }];
        }
        NSUInteger seed = (NSUInteger)([[info objectForKey:@"user"] longLongValue] % 1000003);
        [_faces useStoredPhoto:NoshiAccountPhoto(name) forKey:[@"account:" stringByAppendingString:name] seed:seed];
        UIImage *face = [_faces imageForKey:[@"account:" stringByAppendingString:name] initials:NoshiInitialsOfName(title)
                                       seed:(NSUInteger)([[info objectForKey:@"user"] longLongValue] % 1000003) deleted:NO photo:nil];
        [rows addObject:[NoshiSettingsRow rowWithTileImage:face title:title subtitle:username.length ? [@"@" stringByAppendingString:username] : nil tap:^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiAccountSwitchNotification object:nil userInfo:[NSDictionary dictionaryWithObject:name forKey:@"name"]];
        }]];
    }
    return rows.count ? [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"account.accounts", nil) footer:nil rows:rows] : nil;
}

- (void)rebuildRows {
    NoshiWeakReference *weak = _weak;
    UIImage *logo = NoshiSettingsMarkTile(29);
    NoshiSettingsRow *look = [NoshiSettingsRow rowWithTileImage:logo title:NSLocalizedString(@"settings.noshigram", nil)
                                                           subtitle:nil
                                                                tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiAboutController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session avatars:((NoshiSettingsController *)weak.target)->_avatars] autorelease]]; }];
    NoshiSettingsRow *profile = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPerson tone:NoshiSettingsToneRed title:NSLocalizedString(@"settings.myprofile", nil)
                                                           subtitle:nil value:nil tap:^{ [(NoshiSettingsController *)weak.target openProfile]; }];
    NoshiSettingsRow *account = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsAccount tone:NoshiSettingsToneBlue title:NSLocalizedString(@"account.title", nil)
                                                           subtitle:nil value:nil tap:^{
        NoshiSettingsController *me = weak.target;
        if (!me) return;
        NoshiAccountController *page = [[[NoshiAccountController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease];
        page.changedHandler = ^{ [(NoshiSettingsController *)weak.target loadPerson]; };
        page.logoutHandler = ^{ [(NoshiSettingsController *)weak.target confirmSignOut]; };
        [me push:page];
    }];
    NoshiSettingsRow *chats = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsChat tone:NoshiSettingsToneOrange title:NSLocalizedString(@"settings.chats", nil)
                                                         subtitle:nil value:nil
                                                              tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiChatSettingsController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session] autorelease]]; }];
    NoshiSettingsRow *stickers = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSticker tone:NoshiSettingsToneOrangeBright title:NSLocalizedString(@"chatset.stickers", nil)
                                                            subtitle:nil value:nil tap:^{
        NoshiSettingsController *me = weak.target;
        if (me) [me push:[[[NoshiStickersSettingsController alloc] initWithSession:me->_session media:me->_media] autorelease]];
    }];
    NoshiSettingsRow *folders = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsFolders tone:NoshiSettingsToneBlue title:NSLocalizedString(@"folders.title", nil) subtitle:nil value:nil tap:^{
        NoshiSettingsController *me = weak.target;
        if (me) [me push:[[[NoshiFoldersController alloc] initWithSession:me->_session] autorelease]];
    }];
    NoshiSettingsRow *notifications = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsSounds tone:NoshiSettingsToneRed
                                                                    title:NSLocalizedString(@"settings.notifications", nil) subtitle:nil
                                                                    value:nil tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiNotificationsSettingsController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session avatars:((NoshiSettingsController *)weak.target)->_avatars media:((NoshiSettingsController *)weak.target)->_media] autorelease]]; }];
    NoshiSettingsRow *privacy = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsPrivacy tone:NoshiSettingsToneGreen title:NSLocalizedString(@"privacy.title", nil)
                                                           subtitle:nil value:nil tap:^{
        NoshiSettingsController *me = weak.target;
        if (me) [me push:[[[NoshiPrivacyController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    }];
    NoshiSettingsRow *passcode = [NoshiSettingsRow rowWithSymbol:NoshiSymbolLock tone:NoshiSettingsToneGray title:NSLocalizedString(@"passcode.title", nil)
                                                            subtitle:nil value:NSLocalizedString(NoshiPasscodeEnabled() ? @"passcode.on" : @"passcode.off", nil) tap:^{
        NoshiSettingsController *me = weak.target;
        if (!me) return;
        [NoshiPasscodeSettingsController openFrom:me push:^(UIViewController *page) { [(NoshiSettingsController *)weak.target push:page]; }];
    }];
    NoshiSettingsRow *data = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsData tone:NoshiSettingsToneBlueDeep title:NSLocalizedString(@"settings.data", nil)
                                                        subtitle:nil value:nil tap:^{
        NoshiSettingsController *me = weak.target;
        [me push:[[[NoshiDataSettingsController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    }];
    /* the number of sessions the last visit to the devices screen saw stands at the right of the row the count it
       last knew */
    NSInteger known = [[NSUserDefaults standardUserDefaults] integerForKey:NoshiDevicesCountKey];
    NoshiSettingsRow *devices = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsDevices tone:NoshiSettingsToneCyan title:NSLocalizedString(@"settings.devices", nil)
                                                           subtitle:nil
                                                              value:known > 0 ? [NSString stringWithFormat:@"%ld", (long)known] : nil tap:^{
        [(NoshiSettingsController *)weak.target openDevices];
    }];
    NoshiSettingsRow *power = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsPower tone:NoshiSettingsToneOrangeDeep title:NSLocalizedString(@"settings.power", nil)
                                                         subtitle:nil value:nil
                                                              tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiLiteModeSettingsController alloc] init] autorelease]]; }];
    NoshiSettingsRow *language = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsLanguage tone:NoshiSettingsTonePurple title:NSLocalizedString(@"language.title", nil)
                                                            subtitle:nil value:NoshiNativeLanguageName(NoshiInterfaceLanguageVariant())
                                                                 tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiLanguageSettingsController alloc] init] autorelease]]; }];
    NoshiSettingsRow *update = [NoshiSettingsRow rowWithSymbol:NoshiSymbolDocument tone:NoshiSettingsToneBlue title:NSLocalizedString(@"update.page.title", nil)
                                                         subtitle:nil value:nil tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiUpdateController alloc] init] autorelease]]; }];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
#if defined(__arm64__)
    NSString *architecture = @"arm64";
#else
    NSString *architecture = @"armv7";
#endif
    NSString *version = [NSString stringWithFormat:NSLocalizedString(@"settings.version.line", nil), [info objectForKey:@"CFBundleShortVersionString"], architecture];
    /* the groups of telegram for ios 4: what belongs to the account, then how the app behaves, then the app itself, each row a title alone */
    NoshiSettingsSection *app = [NoshiSettingsSection sectionWithHeader:nil footer:version rows:[NSArray arrayWithObjects:look, update, nil]];
    app.centerFooter = YES;
    NSMutableArray *sections = [NSMutableArray array];
    NoshiSettingsSection *accounts = [self otherAccountsSection];
    if (accounts) [sections addObject:accounts];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:profile, account, stickers, folders, devices, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:notifications, privacy, passcode, data, chats, power, language, nil]]];
    [sections addObject:app];
    self.sections = sections;
}

#pragma mark scrolling

/* the title stands in the bar all the time */
- (void)updateBarFill {
}

- (CGFloat)statusInset {
    return NoshiLayoutInsets(self).top;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    (void)scrollView;
    [self updateBarFill];
}

#pragma mark menu

/* the dots in the bar open a card with one row do */
- (void)showMenu {
    NoshiWeakReference *weak = _weak;
    /* from the dots that were tapped: the sheet of an ipad is a popover, and without a place to point at it came up in the middle of the screen over the chat */
    NoshiChooseFromView(_more, nil, [NSArray arrayWithObject:NSLocalizedString(@"settings.signout", nil)], 0, ^(NSInteger index) {
        if (index < 0) return;
        [(NoshiSettingsController *)weak.target confirmSignOut];
    });
}

- (void)confirmSignOut {
    if (_signingOut) return;
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"settings.signout.confirm", nil), NSLocalizedString(@"settings.signout", nil),
                         ^{ [(NoshiSettingsController *)weak.target signOutNow]; });
}

- (void)signOutNow {
    if (!_signOutHandler || _signingOut) return;
    _signingOut = YES;
    NoshiWeakReference *weak = _weak;
    _signOutHandler(^(NSString *errorName) {
        NoshiSettingsController *me = weak.target;
        if (me) me->_signingOut = NO;
        if (!errorName) return;
        NSLog(@"noshigram: the sign out failed: %@", errorName);
        NoshiShowNotice(nil, [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
    });
}

#pragma mark search

/* a result row: the name of the setting, the way to it under that, and what a tap does */
- (NoshiSettingsRow *)resultWithTitle:(NSString *)title path:(NSArray *)path symbol:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone tap:(void (^)(void))tap {
    return [NoshiSettingsRow rowWithSymbol:symbol tone:tone title:title subtitle:path.count ? [path componentsJoinedByString:@" › "] : nil value:nil tap:tap];
}

- (NSArray *)searchEntries {
    NoshiWeakReference *weak = _weak;
    void (^openLook)(void) = ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiAppearanceSettingsController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session] autorelease]]; };
    void (^openNotifications)(void) = ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiNotificationsSettingsController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session avatars:((NoshiSettingsController *)weak.target)->_avatars media:((NoshiSettingsController *)weak.target)->_media] autorelease]]; };
    void (^openChats)(void) = ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiChatSettingsController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session] autorelease]]; };
    void (^openStickers)(void) = ^{
        NoshiSettingsController *me = weak.target;
        if (me) [me push:[[[NoshiStickersSettingsController alloc] initWithSession:me->_session media:me->_media] autorelease]];
    };
    void (^openData)(void) = ^{
        NoshiSettingsController *me = weak.target;
        [me push:[[[NoshiDataSettingsController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    };
    void (^openDevices)(void) = ^{ [(NoshiSettingsController *)weak.target openDevices]; };
    void (^openPower)(void) = ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiLiteModeSettingsController alloc] init] autorelease]]; };
    void (^openLanguage)(void) = ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiLanguageSettingsController alloc] init] autorelease]]; };
    void (^openTranslator)(void) = ^{
        NoshiSettingsController *me = weak.target;
        [me.navigationController pushViewController:[[[NoshiLanguageSettingsController alloc] init] autorelease] animated:NO];
        [me push:[[[NoshiTranslatorSettingsController alloc] init] autorelease]];
    };
    NSString *look = NSLocalizedString(@"settings.noshigram", nil), *notify = NSLocalizedString(@"settings.notifications", nil);
    NSString *data = NSLocalizedString(@"settings.data", nil), *language = NSLocalizedString(@"language.title", nil), *translator = NSLocalizedString(@"tr.title", nil);
    NSMutableArray *entries = [NSMutableArray array];
    NoshiSettingsTone blue = NoshiSettingsToneBlue;
#define ENTRY(t_, p_, s_, k_, a_) [entries addObject:[self resultWithTitle:t_ path:p_ symbol:s_ tone:k_ tap:a_]]
    ENTRY(look, nil, NoshiSymbolGear, blue, openLook);
    NSString *lookKeys[] = {@"look.layout.header", @"look.avatar.corners", @"look.stories", @"look.hidesearch", @"look.title", @"look.senderavatars", @"look.folders.header", @"look.cards.radius"};
    for (size_t i = 0; i < sizeof(lookKeys) / sizeof(lookKeys[0]); ++i) ENTRY(NSLocalizedString(lookKeys[i], nil), [NSArray arrayWithObject:look], NoshiSymbolGear, blue, openLook);
    NSString *chats = NSLocalizedString(@"settings.chats", nil);
    ENTRY(chats, nil, NoshiSymbolSettingsChat, NoshiSettingsToneOrange, openChats);
    NSString *chatKeys[] = {@"chatset.textsize.header", @"chatset.colortheme.header", @"chatset.corners.header", @"chatset.list.header", @"chatset.night", @"chatset.animations",
                            @"chatset.sendenter"};
    for (size_t i = 0; i < sizeof(chatKeys) / sizeof(chatKeys[0]); ++i) ENTRY(NSLocalizedString(chatKeys[i], nil), [NSArray arrayWithObject:chats], NoshiSymbolSettingsChat, NoshiSettingsToneOrange, openChats);
    NSString *stickers = NSLocalizedString(@"chatset.stickers", nil);
    ENTRY(stickers, nil, NoshiSymbolSticker, NoshiSettingsToneOrangeBright, openStickers);
    NSString *stickerKeys[] = {@"stickers.featured", @"stickers.archived", @"stickers.emoji", @"chatset.largeemoji", @"chatset.dynamicorder"};
    for (size_t i = 0; i < sizeof(stickerKeys) / sizeof(stickerKeys[0]); ++i) ENTRY(NSLocalizedString(stickerKeys[i], nil), [NSArray arrayWithObject:stickers], NoshiSymbolSticker, NoshiSettingsToneOrangeBright, openStickers);
    ENTRY(notify, nil, NoshiSymbolSettingsSounds, NoshiSettingsToneRed, openNotifications);
    NSString *notifyKeys[] = {@"notif.private", @"notif.groups", @"notif.channels", @"notif.stories", @"notif.reactions", @"notif.vibrate", @"notif.badge.header", @"notif.inapp.sounds",
                              @"notif.inapp.vibrate", @"notif.inapp.preview", @"notif.inchat", @"notif.contactjoined", @"notif.pinned", @"notif.repeat", @"notif.reset",
                              @"notif.exceptions.title"};
    for (size_t i = 0; i < sizeof(notifyKeys) / sizeof(notifyKeys[0]); ++i) {
        ENTRY(NSLocalizedString(notifyKeys[i], nil), [NSArray arrayWithObject:notify], NoshiSymbolSettingsSounds, NoshiSettingsToneRed, openNotifications);
    }
    ENTRY(data, nil, NoshiSymbolSettingsData, NoshiSettingsToneBlueDeep, openData);
    NSString *dataKeys[] = {@"memory.title", @"netusage.title", @"data.drafts", @"memory.keep"};
    for (size_t i = 0; i < sizeof(dataKeys) / sizeof(dataKeys[0]); ++i) ENTRY(NSLocalizedString(dataKeys[i], nil), [NSArray arrayWithObject:data], NoshiSymbolSettingsData, NoshiSettingsToneBlueDeep, openData);
    ENTRY(NSLocalizedString(@"settings.devices", nil), nil, NoshiSymbolSettingsDevices, NoshiSettingsToneCyan, openDevices);
    NSString *power = NSLocalizedString(@"lite.title", nil);
    ENTRY(NSLocalizedString(@"settings.power", nil), nil, NoshiSymbolSettingsPower, NoshiSettingsToneOrangeDeep, openPower);
    NSString *lite[] = {@"lite.battery.title", @"lite.options", @"lite.stickers", @"lite.emoji", @"lite.background", @"lite.calls", @"lite.smooth", @"lite.class"};
    for (size_t i = 0; i < sizeof(lite) / sizeof(lite[0]); ++i) ENTRY(NSLocalizedString(lite[i], nil), [NSArray arrayWithObject:power], NoshiSymbolSettingsPower, NoshiSettingsToneOrangeDeep, openPower);
    ENTRY(NSLocalizedString(@"update.page.title", nil), nil, NoshiSymbolDocument, blue, ^{ [(NoshiSettingsController *)weak.target push:[[[NoshiUpdateController alloc] init] autorelease]]; });
    ENTRY(language, nil, NoshiSymbolSettingsLanguage, NoshiSettingsTonePurple, openLanguage);
    ENTRY(translator, [NSArray arrayWithObject:language], NoshiSymbolTranslate, NoshiSettingsTonePurple, openTranslator);
    NSArray *translatorPath = [NSArray arrayWithObjects:language, translator, nil];
    NSString *keys[] = {@"tr.show", @"tr.provider", @"tr.original", @"tr.target", @"tr.skip", @"tr.preferred", @"tr.google.key", @"tr.deepl.key", @"tr.ai", @"tr.llm.preset",
                        @"tr.llm.model", @"tr.llm.key", @"tr.llm.url", @"tr.llm.system", @"tr.llm.user", @"tr.llm.context", @"tr.llm.temperature", @"tr.google.new", @"tr.keep"};
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) ENTRY(NSLocalizedString(keys[i], nil), translatorPath, NoshiSymbolTranslate, NoshiSettingsTonePurple, openTranslator);
    ENTRY(NSLocalizedString(@"settings.signout", nil), nil, NoshiSymbolLogout, NoshiSettingsToneRed, ^{ [(NoshiSettingsController *)weak.target confirmSignOut]; });
#undef ENTRY
    return entries;
}

/* every word of the name is tried tries them: the query has to open one of them */
- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *hits = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NoshiSettingsRow *row in [self searchEntries]) {
        NSString *key = [NSString stringWithFormat:@"%@/%@", row.title, row.subtitle];
        if ([seen containsObject:key]) continue;
        BOOL match = NO;
        for (NSString *word in [[row.title lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if ([word hasPrefix:wanted]) { match = YES; break; }
        }
        if (!match && [[row.title lowercaseString] hasPrefix:wanted]) match = YES;
        if (!match) continue;
        [seen addObject:key];
        [hits addObject:row];
    }
    return hits.count ? [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:hits]] : [NSArray array];
}

@end

#import "noshi_classic_chrome.h"
#import "noshi_classic_profile_controller.h"
#import "noshi_bookmarks_controller.h"
#import "noshi_chat_controller.h"
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
#import "noshi_info_rows.h"
#import "noshi_name_badge.h"
#import "noshi_platform.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_session_profile.h"
#import "noshi_settings_pages.h"
#import "noshi_sheet.h"
#import "noshi_theme.h"
#import "noshi_translator_controller.h"
#import "noshi_weak_reference.h"

/* the head of the settings of telegram for ios 4: a white row of 97 points with the photo of 66 at the left, the name beside it and the number and the username under
   the name; a tap on the photo changes it, a tap on the rest opens the profile */
#define HEAD_HEIGHT 97.0
#define HEAD_AVATAR 66.0
#define HEAD_TEXT_X 92.0
/* the grey above the head, the gap the grouped list keeps above its first group */
#define HEAD_TOP 18.0
static NSString *const NoshiDevicesCountKey = @"noshigram.devices.count";

@interface NoshiSettingsHeaderView : UIControl {
    UIView *_panel;
    NoshiAvatarView *_avatar;
    UIButton *_avatarHit;
    UIActivityIndicatorView *_spinner;
    NoshiEmojiLabel *_name;
    UILabel *_phone;
    UILabel *_username;
}
@property (nonatomic, readonly) NoshiAvatarView *avatar;
@property (nonatomic, readonly) UIButton *avatarHit;
@property (nonatomic, readonly) NoshiEmojiLabel *name;
- (void)setPhone:(NSString *)phone username:(NSString *)username;
- (void)setUploading:(BOOL)uploading;
@end

@implementation NoshiSettingsHeaderView

@synthesize avatar = _avatar;
@synthesize avatarHit = _avatarHit;
@synthesize name = _name;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _panel = NoshiNewInfoGroup();
    _panel.userInteractionEnabled = NO;
    [self addSubview:_panel];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.userInteractionEnabled = NO;
    [self addSubview:_avatar];
    _avatarHit = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _avatarHit.accessibilityLabel = NSLocalizedString(@"profile.choosephoto", nil);
    [self addSubview:_avatarHit];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontMedium(20);
    _name.textColor = NoshiColorTitle();
    _name.dropsUndrawable = YES;
    _name.userInteractionEnabled = NO;
    [self addSubview:_name];
    for (int i = 0; i < 2; ++i) {
        UILabel *line = [[UILabel alloc] init];
        line.backgroundColor = [UIColor clearColor];
        line.font = [UIFont systemFontOfSize:15];
        line.textColor = NoshiColorSecondary();
        line.userInteractionEnabled = NO;
        [self addSubview:line];
        if (i == 0) _phone = line;
        else _username = line;
    }
    return self;
}

- (void)dealloc {
    [_panel release];
    [_avatar release];
    [_avatarHit release];
    [_spinner release];
    [_name release];
    [_phone release];
    [_username release];
    [super dealloc];
}

- (void)setPhone:(NSString *)phone username:(NSString *)username {
    _phone.text = phone;
    _username.text = username;
    [self setNeedsLayout];
}

- (void)setUploading:(BOOL)uploading {
    if (uploading) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _panel.backgroundColor = highlighted ? (NoshiThemeIsDark() ? [UIColor colorWithWhite:0.25 alpha:1] : [UIColor colorWithWhite:0.85 alpha:1]) : NoshiColorCard();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _panel.frame = CGRectMake(0, HEAD_TOP, width, HEAD_HEIGHT);
    NoshiFitInfoGroupLines(_panel, YES);
    _avatar.frame = CGRectMake(15, HEAD_TOP + floor((HEAD_HEIGHT - HEAD_AVATAR) / 2), HEAD_AVATAR, HEAD_AVATAR);
    _avatarHit.frame = _avatar.frame;
    _spinner.center = _avatar.center;
    /* the name over the number over the username, as one block in the middle of the row; a line with nothing on it takes no room */
    CGFloat textWidth = MAX(0, width - HEAD_TEXT_X - 15);
    BOOL phone = _phone.text.length > 0, username = _username.text.length > 0;
    CGFloat block = 25 + (phone ? 20 : 0) + (username ? 20 : 0);
    CGFloat y = HEAD_TOP + floor((HEAD_HEIGHT - block) / 2);
    _name.frame = CGRectMake(HEAD_TEXT_X, y, textWidth, 25);
    y += 25;
    _phone.hidden = !phone;
    _phone.frame = CGRectMake(HEAD_TEXT_X, y, textWidth, 20);
    if (phone) y += 20;
    _username.hidden = !username;
    _username.frame = CGRectMake(HEAD_TEXT_X, y, textWidth, 20);
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
    /* the words the classic bar shows now: the title view is made again only when they change */
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
    _header = [[NoshiSettingsHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, HEAD_TOP + HEAD_HEIGHT)];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_header.avatarHit addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
    /* the rest of the row opens the full profile */
    [_header addTarget:self action:@selector(openProfile) forControlEvents:UIControlEventTouchUpInside];
    self.headerView = _header;
    /* the same one-row menu as the dots of the modern bar, on the system bar, and the magnifier of its search
           in the corner at the left; the bars of this style are dark, so the pictures are drawn white */
    UIBarButtonItem *dots = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolEllipsis, 22, [UIColor whiteColor])
                                                              style:UIBarButtonItemStyleBordered target:self action:@selector(showMenu)] autorelease];
    dots.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
    /* the bar says Settings, as in telegram for ios 4; the name is in the head */
    self.navigationItem.titleView = NoshiClassicTitleView(NSLocalizedString(@"tab.settings", nil), nil);
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

/* the chat with oneself, which telegram for ios 4 kept as a row of its settings */
- (void)openSavedMessages {
    NoshiDialog *saved = _person ? [NoshiDialog savedMessagesWithPerson:_person] : nil;
    if (!saved) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:saved avatars:_avatars media:_media stickers:_stickerLibrary] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)openBookmarks {
    [self.navigationController pushViewController:[[[NoshiBookmarksController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickerLibrary] autorelease] animated:YES];
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
        NoshiLiteSetPremium(me->_person.premium);
        [me showPerson];
    }];
}

- (void)showPerson {
    NSArray *entities = nil;
    /* the mark after the name is the one the lists and the chat show: the status the person chose, or the Premium star */
    long long badge = NoshiPersonBadgeDocument(_person);
    _header.name.text = NoshiNameWithBadge(_person.name, badge, &entities);
    _header.name.entities = entities;
    NoshiWeakReference *weak = _weak;
    NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:badge]], _session, _media, ^{
        NoshiSettingsController *me = weak.target;
        if (me) [me->_header.name setNeedsDisplay];
    });
    [_header setPhone:_person.phone.length ? NoshiOwnPhoneText(_person.phone) : nil username:_person.username.length ? [@"@" stringByAppendingString:_person.username] : nil];
    _header.avatar.initials = _person.initials;
    _header.avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [_header.avatar setPhoto:_person.photo cache:_avatars];
}

/* a tap on the photo: it jumps, as the photo of exteraGram does when it is pressed, and the sheet of the library comes up under it */
- (void)avatarTapped {
    if (_uploading || !_person) return;
    CALayer *layer = _header.avatar.layer;
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
    [_header setUploading:YES];
    void (^finished)(NSString *) = ^(NSString *errorName) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NoshiSettingsController *again = weak.target;
        if (!again) return;
        again->_uploading = NO;
        [again->_header setUploading:NO];
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
    NoshiSettingsRow *look = [NoshiSettingsRow rowWithIconImage:logo title:NSLocalizedString(@"settings.noshigram", nil)
                                                                tap:^{ [(NoshiSettingsController *)weak.target push:[[[NoshiAboutController alloc] initWithSession:((NoshiSettingsController *)weak.target)->_session avatars:((NoshiSettingsController *)weak.target)->_avatars] autorelease]]; }];
    NoshiSettingsRow *profile = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPerson tone:NoshiSettingsToneRed title:NSLocalizedString(@"settings.myprofile", nil)
                                                           subtitle:nil value:nil tap:^{ [(NoshiSettingsController *)weak.target openProfile]; }];
    NoshiSettingsRow *saved = [NoshiSettingsRow rowWithIconImage:[UIImage imageNamed:@"SettingsSavedMessagesIcon"] title:NSLocalizedString(@"menu.saved", nil)
                                                                 tap:^{ [(NoshiSettingsController *)weak.target openSavedMessages]; }];
    NoshiSettingsRow *bookmarks = [NoshiSettingsRow rowWithSymbol:NoshiSymbolStar tone:NoshiSettingsToneOrange title:NSLocalizedString(@"bookmarks.title", nil)
                                                             subtitle:nil value:nil tap:^{ [(NoshiSettingsController *)weak.target openBookmarks]; }];
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
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:saved, bookmarks, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:notifications, privacy, passcode, data, chats, power, language, nil]]];
    [sections addObject:app];
    self.sections = sections;
}

#pragma mark scrolling

/* the title stands in the bar all the time */
- (void)updateBarFill {
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
    NSString *lookKeys[] = {@"look.stories", @"look.hidesearch", @"look.title", @"look.senderavatars", @"look.folders.header"};
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

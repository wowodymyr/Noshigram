#import "noshi_privacy_controller.h"

#import "noshi_alert.h"
#import "noshi_channel_profile_controller.h"
#import "noshi_user_profile_controller.h"
#import "noshi_classic_devices_controller.h"
#import "noshi_contact_picker_controller.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_people_avatars.h"
#import "noshi_person.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_remote_file.h"
#import "noshi_session_profile.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"
#import "noshi_settings_extras.h"
#import "noshi_session_data.h"

/* the seconds of the default auto-delete the server offers: off, a day, a week, a month */
#define TTL_DAY 86400
#define TTL_WEEK 604800
#define TTL_MONTH 2678400

static const struct { noshi_privacy_key key; NoshiSymbol symbol; NoshiSettingsTone tone; NSString *title; NSString *who; } NoshiPrivacyKeys[] = {
    {NOSHI_PRIVACY_PHONE, NoshiSymbolPhone, NoshiSettingsToneBlue, @"privacy.phone", @"privacy.who.phone"},
    {NOSHI_PRIVACY_LAST_SEEN, NoshiSymbolClock, NoshiSettingsToneGreen, @"privacy.lastseen", @"privacy.who.lastseen"},
    {NOSHI_PRIVACY_PHOTO, NoshiSymbolGallery, NoshiSettingsToneOrange, @"privacy.photo", @"privacy.who.photo"},
    {NOSHI_PRIVACY_FORWARDS, NoshiSymbolForward, NoshiSettingsToneCyan, @"privacy.forwards", @"privacy.who.forwards"},
    {NOSHI_PRIVACY_CALLS, NoshiSymbolCallback, NoshiSettingsToneRed, @"privacy.calls", @"privacy.who.calls"},
    {NOSHI_PRIVACY_VOICE, NoshiSymbolMicrophone, NoshiSettingsTonePurple, @"privacy.voice", @"privacy.who.voice"},
    {NOSHI_PRIVACY_ABOUT, NoshiSymbolInfo, NoshiSettingsToneBlueDeep, @"privacy.about", @"privacy.who.about"},
    {NOSHI_PRIVACY_BIRTHDAY, NoshiSymbolCake, NoshiSettingsToneOrangeBright, @"privacy.birthday", @"privacy.who.birthday"},
    {NOSHI_PRIVACY_MUSIC, NoshiSymbolMusic, NoshiSettingsToneRed, @"privacy.music", @"privacy.who.music"},
    {NOSHI_PRIVACY_INVITES, NoshiSymbolGroupsMenu, NoshiSettingsToneGreen, @"privacy.invites", @"privacy.who.invites"},
};
#define PRIVACY_KEY_ROWS (sizeof(NoshiPrivacyKeys) / sizeof(NoshiPrivacyKeys[0]))

/* the base of a rule in words, and what the exceptions add to it, the way the settings of the original client write it: "Contacts (+2, -1)" */
NSString *NoshiPrivacyValue(NoshiPrivacyRules *rules) {
    NSString *base;
    switch (rules.base) {
    case NOSHI_PRIVACY_EVERYBODY: base = NSLocalizedString(@"privacy.everybody", nil); break;
    case NOSHI_PRIVACY_CONTACTS: base = NSLocalizedString(@"privacy.contacts", nil); break;
    default: base = NSLocalizedString(@"privacy.nobody", nil); break;
    }
    NSUInteger allowed = [rules countAllowed:YES], never = [rules countAllowed:NO];
    /* what contradicts the base has no meaning, so it is not counted: an exception that adds a person to everybody changes nothing */
    BOOL showAllowed = allowed && rules.base != NOSHI_PRIVACY_EVERYBODY;
    BOOL showNever = never && rules.base != NOSHI_PRIVACY_NOBODY;
    if (showAllowed && showNever) return [NSString stringWithFormat:@"%@ (+%lu, -%lu)", base, (unsigned long)allowed, (unsigned long)never];
    if (showAllowed) return [NSString stringWithFormat:@"%@ (+%lu)", base, (unsigned long)allowed];
    if (showNever) return [NSString stringWithFormat:@"%@ (-%lu)", base, (unsigned long)never];
    return base;
}

static NSString *NoshiHistoryTTLText(int32_t seconds) {
    if (seconds <= 0) return NSLocalizedString(@"privacy.ttl.off", nil);
    if (seconds == TTL_DAY) return NSLocalizedString(@"privacy.ttl.day", nil);
    if (seconds == TTL_WEEK) return NSLocalizedString(@"privacy.ttl.week", nil);
    if (seconds == TTL_MONTH) return NSLocalizedString(@"privacy.ttl.month", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"privacy.ttl.days", nil), (int)(seconds / TTL_DAY)];
}

static NSString *NoshiAccountTTLText(int32_t days) {
    if (days == 30) return NSLocalizedString(@"privacy.away.1", nil);
    if (days == 90) return NSLocalizedString(@"privacy.away.3", nil);
    if (days == 180) return NSLocalizedString(@"privacy.away.6", nil);
    if (days == 365) return NSLocalizedString(@"privacy.away.12", nil);
    if (days == 730) return NSLocalizedString(@"privacy.away.24", nil);
    /* the server keeps any period from 30 to 730 days, and other apps set ones such as 18 months */
    if (days >= 730) return [NSString stringWithFormat:NSLocalizedString(@"privacy.away.years", nil), 2];
    if (days >= 60) return [NSString stringWithFormat:NSLocalizedString(@"privacy.away.months", nil), (int)((days + 15) / 30)];
    return [NSString stringWithFormat:NSLocalizedString(@"privacy.ttl.days", nil), (int)days];
}

/* what to say of a failed call: a list too long for the screen has a line of its own, the rest the plain names of the server */
static void NoshiPrivacyFail(NSString *errorName) {
    NSString *text = [errorName isEqualToString:@"PRIVACY_TOO_MANY"] ? NSLocalizedString(@"privacy.error.toomany", nil)
        : [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"privacy.error.premium", nil)
        : [NSString stringWithFormat:NSLocalizedString(@"privacy.error", nil), errorName];
    NoshiGiftAlert(nil, text);
}

#pragma mark main screen

@interface NoshiPrivacyController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    BOOL _deleting;
    NoshiWeakReference *_weak;
    NoshiPrivacyRules *_rules[NOSHI_PRIVACY_KEY_COUNT];
    int32_t _blocked;
    BOOL _blockedKnown;
    int32_t _historyTTL;
    BOOL _historyKnown;
    int32_t _accountTTL;
    BOOL _accountKnown;
    BOOL _loaded;
}
@end

@implementation NoshiPrivacyController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"privacy.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    for (int i = 0; i < NOSHI_PRIVACY_KEY_COUNT; ++i) [_rules[i] release];
    [_session release];
    [_avatars release];
    [_media release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadAll];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiPrivacyController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
}

/* everything the rows show comes from the server, one call each, and the rows fill in as the answers come */
- (void)loadAll {
    NoshiWeakReference *weak = _weak;
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        noshi_privacy_key key = NoshiPrivacyKeys[i].key;
        [_session loadPrivacy:key completion:^(NoshiPrivacyRules *rules, NSString *error) {
            NoshiPrivacyController *me = weak.target;
            if (!me) return;
            if (!rules) {
                NSLog(@"noshigram: privacy rule %d did not load: %@", (int)key, error);
                return;
            }
            [me->_rules[key] release];
            me->_rules[key] = [rules retain];
            [me rebuild];
        }];
    }
    [_session loadBlockedFrom:0 completion:^(NSArray *peers, int32_t total, NSString *error) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        if (!peers) { NSLog(@"noshigram: the blocked list did not load: %@", error); return; }
        me->_blocked = total;
        me->_blockedKnown = YES;
        [me rebuild];
    }];
    [_session loadHistoryTTL:^(int32_t seconds, NSString *error) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        if (error) { NSLog(@"noshigram: the auto-delete time did not load: %@", error); return; }
        me->_historyTTL = seconds;
        me->_historyKnown = YES;
        [me rebuild];
    }];
    [_session loadAccountTTL:^(int32_t days, NSString *error) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        if (error) { NSLog(@"noshigram: the account time did not load: %@", error); return; }
        me->_accountTTL = days;
        me->_accountKnown = YES;
        [me rebuild];
    }];
}

- (void)open:(UIViewController *)page {
    [self.navigationController pushViewController:page animated:YES];
}

- (void)openRule:(noshi_privacy_key)key {
    NoshiPrivacyRules *rules = _rules[key];
    /* the rule is asked for again if it did not come the first time, and the page opens when it is here */
    if (!rules) {
        NoshiWeakReference *weak = _weak;
        [_session loadPrivacy:key completion:^(NoshiPrivacyRules *loaded, NSString *error) {
            NoshiPrivacyController *me = weak.target;
            if (!me) return;
            if (!loaded) { NoshiPrivacyFail(error); return; }
            [me->_rules[key] release];
            me->_rules[key] = [loaded retain];
            [me rebuild];
            [me openRule:key];
        }];
        return;
    }
    NoshiWeakReference *weak = _weak;
    NoshiPrivacyRuleController *page = [[[NoshiPrivacyRuleController alloc] initWithSession:_session rules:rules avatars:_avatars media:_media] autorelease];
    page.changedHandler = ^(NoshiPrivacyRules *fresh) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        [me->_rules[key] release];
        me->_rules[key] = [fresh retain];
        [me rebuild];
    };
    [self open:page];
}

- (void)openBlocked {
    NoshiWeakReference *weak = _weak;
    NoshiBlockedController *page = [[[NoshiBlockedController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    page.countHandler = ^(int32_t total) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        me->_blocked = total;
        me->_blockedKnown = YES;
        [me rebuild];
    };
    [self open:page];
}

- (void)openDevices {
    [self open:(UIViewController *)[[[NoshiClassicDevicesController alloc] initWithSession:_session media:_media] autorelease]];
}

- (void)chooseHistoryTTL {
    NoshiWeakReference *weak = _weak;
    static const int32_t values[] = {0, TTL_DAY, TTL_WEEK, TTL_MONTH};
    NSArray *options = [NSArray arrayWithObjects:NoshiHistoryTTLText(0), NoshiHistoryTTLText(TTL_DAY), NoshiHistoryTTLText(TTL_WEEK), NoshiHistoryTTLText(TTL_MONTH), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"privacy.autodelete", nil), options, ^(NSUInteger index) {
        NoshiPrivacyController *me = weak.target;
        if (!me || index >= 4) return;
        int32_t seconds = values[index];
        int32_t before = me->_historyTTL;
        /* the row shows the choice at once, and goes back to what it was when the server refuses */
        me->_historyTTL = seconds;
        [me rebuild];
        [me->_session setHistoryTTL:seconds completion:^(NSString *error) {
            NoshiPrivacyController *again = weak.target;
            if (!error) return;
            NoshiPrivacyFail(error);
            if (!again) return;
            again->_historyTTL = before;
            [again rebuild];
        }];
    });
}

- (void)chooseAccountTTL {
    NoshiWeakReference *weak = _weak;
    static const int32_t values[] = {30, 90, 180, 365, 730};
    NSArray *options = [NSArray arrayWithObjects:NoshiAccountTTLText(30), NoshiAccountTTLText(90), NoshiAccountTTLText(180), NoshiAccountTTLText(365), NoshiAccountTTLText(730), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"privacy.away", nil), options, ^(NSUInteger index) {
        NoshiPrivacyController *me = weak.target;
        if (!me || index >= sizeof(values) / sizeof(values[0])) return;
        int32_t days = values[index];
        int32_t before = me->_accountTTL;
        me->_accountTTL = days;
        [me rebuild];
        [me->_session setAccountTTL:days completion:^(NSString *error) {
            NoshiPrivacyController *again = weak.target;
            if (!error) return;
            NoshiPrivacyFail(error);
            if (!again) return;
            again->_accountTTL = before;
            [again rebuild];
        }];
    });
}

- (void)confirmResetContacts {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"privacy.contacts.confirm", nil), NSLocalizedString(@"privacy.contacts.delete", nil), ^{
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        [me->_session resetSavedContactsWithCompletion:^(NSString *error) {
            if (error) NoshiPrivacyFail(error);
            else NoshiGiftAlert(nil, NSLocalizedString(@"privacy.contacts.done", nil));
        }];
    });
}

- (void)choosePaymentsToClear {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"privacy.payments.cards", nil), NSLocalizedString(@"privacy.payments.shipping", nil),
                        NSLocalizedString(@"privacy.payments.all", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"privacy.payments", nil), options, ^(NSUInteger index) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        BOOL cards = index == 0 || index == 2, shipping = index == 1 || index == 2;
        [me->_session clearPaymentsCredentials:cards info:shipping completion:^(NSString *error) {
            if (error) NoshiPrivacyFail(error);
            else NoshiGiftAlert(nil, NSLocalizedString(@"privacy.payments.done", nil));
        }];
    });
}

#pragma mark deleting the account

/* two questions, the second asking for the word, since nothing brings the account back */
- (void)askDeleteAccount {
    if (_deleting) return;
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"more.delete.confirm", nil), NSLocalizedString(@"more.delete.action", nil), ^{
        NoshiPromptText(NSLocalizedString(@"more.delete.title", nil), [NSString stringWithFormat:NSLocalizedString(@"more.delete.type", nil), NSLocalizedString(@"more.delete.word", nil)], nil, nil, ^(NSString *text) {
            NoshiPrivacyController *me = weak.target;
            if (!me) return;
            NSString *typed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([typed caseInsensitiveCompare:NSLocalizedString(@"more.delete.word", nil)] != NSOrderedSame) {
                NoshiGiftAlert(nil, NSLocalizedString(@"more.delete.mismatch", nil));
                return;
            }
            [me deleteAccountNow];
        });
    });
}

static NSString *NoshiDeleteErrorText(NSString *errorName) {
    /* an account with a cloud password has to wait for the deletion; the wait starts with the first try */
    if ([errorName hasPrefix:@"2FA_CONFIRM_WAIT"]) return NSLocalizedString(@"more.delete.wait", nil);
    if ([errorName hasPrefix:@"2FA_RECENT_CONFIRM"]) return NSLocalizedString(@"more.delete.recent", nil);
    return NoshiGiftErrorText(errorName);
}

- (void)deleteAccountNow {
    _deleting = YES;
    NoshiWeakReference *weak = _weak;
    [_session deleteAccountWithReason:@"Deleted from Noshigram" completion:^(NSString *errorName) {
        NoshiPrivacyController *me = weak.target;
        if (!me) return;
        me->_deleting = NO;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiDeleteErrorText(errorName));
            return;
        }
        /* the server dropped the account, and the connection tells the app, which goes to the next account or to the welcome screen */
        NoshiGiftAlert(nil, NSLocalizedString(@"more.delete.done", nil));
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSString *blocked = _blockedKnown ? (_blocked > 0 ? [NSString stringWithFormat:@"%d", (int)_blocked] : NSLocalizedString(@"privacy.blocked.none", nil)) : nil;
    NoshiSettingsRow *blockedRow = [NoshiSettingsRow rowWithSymbol:NoshiSymbolBlock tone:NoshiSettingsToneRed title:NSLocalizedString(@"privacy.blocked", nil)
                                                              subtitle:nil value:blocked tap:^{ [(NoshiPrivacyController *)weak.target openBlocked]; }];
    NoshiSettingsRow *autoDelete = [NoshiSettingsRow rowWithSymbol:NoshiSymbolClearHistory tone:NoshiSettingsToneOrange title:NSLocalizedString(@"privacy.autodelete", nil)
                                                              subtitle:nil value:_historyKnown ? NoshiHistoryTTLText(_historyTTL) : nil
                                                                   tap:^{ [(NoshiPrivacyController *)weak.target chooseHistoryTTL]; }];
    NoshiSettingsRow *sessions = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsDevices tone:NoshiSettingsToneCyan title:NSLocalizedString(@"settings.devices", nil)
                                                            subtitle:nil value:nil tap:^{ [(NoshiPrivacyController *)weak.target openDevices]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.security", nil) footer:NSLocalizedString(@"privacy.autodelete.info", nil)
                                                             rows:[NSArray arrayWithObjects:blockedRow, autoDelete, sessions, nil]]];

    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        noshi_privacy_key key = NoshiPrivacyKeys[i].key;
        NoshiPrivacyRules *rules = _rules[key];
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiPrivacyKeys[i].symbol tone:NoshiPrivacyKeys[i].tone title:NSLocalizedString(NoshiPrivacyKeys[i].title, nil)
                                                 subtitle:nil value:rules ? NoshiPrivacyValue(rules) : nil tap:^{ [(NoshiPrivacyController *)weak.target openRule:key]; }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.header", nil) footer:nil rows:rows]];
    [sections addObject:NoshiProfileDisplaySection()];
    [sections addObject:NoshiConfirmSettingsSection(weak)];

    NoshiSettingsRow *away = [NoshiSettingsRow rowWithSymbol:NoshiSymbolTrash tone:NoshiSettingsToneRed title:NSLocalizedString(@"privacy.away", nil)
                                                        subtitle:nil value:_accountKnown ? NoshiAccountTTLText(_accountTTL) : nil
                                                             tap:^{ [(NoshiPrivacyController *)weak.target chooseAccountTTL]; }];
    NoshiSettingsRow *deleteNow = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"more.delete", nil) destructive:YES tap:^{
        [(NoshiPrivacyController *)weak.target askDeleteAccount];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.delete.header", nil) footer:NSLocalizedString(@"privacy.away.info", nil)
                                                             rows:[NSArray arrayWithObjects:away, deleteNow, nil]]];

    NoshiSettingsRow *contacts = [NoshiSettingsRow rowWithSymbol:NoshiSymbolMember tone:NoshiSettingsToneBlueDeep title:NSLocalizedString(@"privacy.contacts.delete", nil)
                                                            subtitle:nil value:nil tap:^{ [(NoshiPrivacyController *)weak.target confirmResetContacts]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.contacts.header", nil) footer:NSLocalizedString(@"privacy.contacts.info", nil)
                                                             rows:[NSArray arrayWithObject:contacts]]];

    NoshiSettingsRow *payments = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsBusiness tone:NoshiSettingsTonePurple title:NSLocalizedString(@"privacy.payments", nil)
                                                            subtitle:nil value:nil tap:^{ [(NoshiPrivacyController *)weak.target choosePaymentsToClear]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.payments.header", nil) footer:NSLocalizedString(@"privacy.payments.info", nil)
                                                             rows:[NSArray arrayWithObject:payments]]];
    self.sections = sections;
    [self reloadSettings];
}

@end

#pragma mark one rule

@interface NoshiPrivacyRuleController () {
    NoshiSession *_session;
    NoshiPrivacyRules *_rules;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    void (^_changedHandler)(NoshiPrivacyRules *rules);
    BOOL _saving;
    BOOL _uploadingPublic;
    BOOL _deletingPublic;
    /* the public photo the account has, asked for when the page of the profile photo opens, and the small round picture of it that sits by the row that deletes it */
    NoshiMedia *_publicPhoto;
    UIImage *_publicCircle;
    NSUInteger _publicGeneration;
}
@end

/* the list of the people who are the exception, which edits the rules of the page that opened it */
@interface NoshiPrivacyExceptionsController : NoshiSettingsPageController {
    NoshiSession *_session;
    NoshiPrivacyRules *_rules;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    BOOL _allowed;
    BOOL _saving;
    NoshiPeopleAvatars *_faces;
    void (^_changedHandler)(NoshiPrivacyRules *rules);
}
- (id)initWithSession:(NoshiSession *)session rules:(NoshiPrivacyRules *)rules allowed:(BOOL)allowed avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@property (nonatomic, copy) void (^changedHandler)(NoshiPrivacyRules *rules);
@end

@implementation NoshiPrivacyRuleController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(NoshiSession *)session rules:(NoshiPrivacyRules *)rules avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _rules = [rules retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        if (NoshiPrivacyKeys[i].key == rules.key) self.pageTitle = NSLocalizedString(NoshiPrivacyKeys[i].title, nil);
    }
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_rules release];
    [_avatars release];
    [_media release];
    [_changedHandler release];
    [_publicPhoto release];
    [_publicCircle release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    if (_rules.key == NOSHI_PRIVACY_PHOTO) [self loadPublicPhoto];
}

#define PUBLIC_CIRCLE 34.0

/* the picture cut to a circle, since a row draws its trailing picture in a rounded square */
static UIImage *NoshiPrivacyCircle(UIImage *image) {
    CGRect frame = CGRectMake(0, 0, PUBLIC_CIRCLE, PUBLIC_CIRCLE);
    UIGraphicsBeginImageContextWithOptions(frame.size, NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:frame] addClip];
    CGFloat side = MIN(image.size.width, image.size.height);
    if (side <= 0) {
        UIGraphicsEndImageContext();
        return nil;
    }
    CGFloat scale = PUBLIC_CIRCLE / side;
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    [image drawInRect:CGRectMake((PUBLIC_CIRCLE - drawn.width) / 2, (PUBLIC_CIRCLE - drawn.height) / 2, drawn.width, drawn.height)];
    UIImage *circle = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return circle;
}

/* the account's own full profile carries the public photo; a later answer for an older page is dropped */
- (void)loadPublicPhoto {
    NoshiWeakReference *weak = _weak;
    NSUInteger generation = ++_publicGeneration;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiPrivacyRuleController *me = weak.target;
        NoshiPerson *self_ = items.count ? [items objectAtIndex:0] : nil;
        if (!me || generation != me->_publicGeneration) return;
        if (!self_) {
            NSLog(@"noshigram: the public photo was not looked up, own profile failed: %@", errorName);
            return;
        }
        [me->_session loadFullUserOfDialog:[NoshiDialog savedMessagesWithPerson:self_] completion:^(NoshiFullUser *user, NSString *fullError) {
            NoshiPrivacyRuleController *again = weak.target;
            if (!again || generation != again->_publicGeneration) return;
            if (!user) {
                NSLog(@"noshigram: the public photo was not looked up: %@", fullError);
                return;
            }
            [again adoptPublicPhoto:user.publicPhoto];
        }];
    }];
}

- (void)adoptPublicPhoto:(NoshiMedia *)photo {
    [_publicPhoto release];
    _publicPhoto = [photo retain];
    [_publicCircle release];
    _publicCircle = nil;
    [self rebuild];
    if (!photo) return;
    noshi_media_ref ref = photo.ref;
    NoshiRemoteFile *file = [NoshiRemoteFile fileForMedia:&ref];
    if (!file) return;
    NoshiWeakReference *weak = _weak;
    NSUInteger generation = _publicGeneration;
    [_media loadImageForFile:file maxSide:PUBLIC_CIRCLE * 3 completion:^(UIImage *image) {
        NoshiPrivacyRuleController *me = weak.target;
        if (!me || generation != me->_publicGeneration || !image) return;
        UIImage *circle = NoshiPrivacyCircle(image);
        if (!circle) return;
        [me->_publicCircle release];
        me->_publicCircle = [circle retain];
        [me rebuild];
    }];
}

- (void)deletePublicPhoto {
    if (_deletingPublic || !_publicPhoto) return;
    NoshiWeakReference *weak = _weak;
    NoshiConfirm(nil, NSLocalizedString(@"privacy.photo.public.remove.confirm", nil), NSLocalizedString(@"privacy.photo.public.remove", nil), ^{
        NoshiPrivacyRuleController *me = weak.target;
        if (!me || !me->_publicPhoto) return;
        me->_deletingPublic = YES;
        [me->_session deleteProfilePhoto:me->_publicPhoto completion:^(NSString *errorName) {
            NoshiPrivacyRuleController *again = weak.target;
            if (!again) return;
            again->_deletingPublic = NO;
            if (errorName) {
                NoshiPrivacyFail(errorName);
                return;
            }
            ++again->_publicGeneration;
            [again adoptPublicPhoto:nil];
            NoshiShowNotice(nil, NSLocalizedString(@"privacy.photo.public.removed", nil));
        }];
    });
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

/* the page shows the rules as the server answered the last write, and a refused write brings back what the server holds */
- (void)adopt:(NoshiPrivacyRules *)fresh {
    if (!fresh) return;
    [_rules release];
    _rules = [fresh retain];
    if (_changedHandler) _changedHandler(fresh);
}

- (void)choose:(noshi_privacy_base)base {
    if (_saving || _rules.base == base) return;
    _saving = YES;
    _rules.base = base;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    noshi_privacy_key key = _rules.key;
    [_session savePrivacy:_rules completion:^(NoshiPrivacyRules *fresh, NSString *error) {
        NoshiPrivacyRuleController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        if (fresh) {
            [me adopt:fresh];
            [me rebuild];
            return;
        }
        NoshiPrivacyFail(error);
        /* what the server holds is the truth, so the page asks for it again */
        [me->_session loadPrivacy:key completion:^(NoshiPrivacyRules *held, NSString *loadError) {
            NoshiPrivacyRuleController *again = weak.target;
            if (!again) return;
            if (held) [again adopt:held];
            else NSLog(@"noshigram: the privacy rule did not load again: %@", loadError);
            [again rebuild];
        }];
    }];
}

/* the photo that those who may not see the main one get instead; the picker hands over a square jpeg that this page deletes */
- (void)choosePublicPhoto {
    if (_uploadingPublic) return;
    NoshiWeakReference *weak = _weak;
    [NoshiProfilePhotoPicker pickFrom:self picked:^(NSString *path) {
        NoshiPrivacyRuleController *me = weak.target;
        if (!me) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        me->_uploadingPublic = YES;
        [me->_session uploadPublicPhotoAtPath:path completion:^(NSString *errorName) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            NoshiPrivacyRuleController *again = weak.target;
            if (!again) return;
            again->_uploadingPublic = NO;
            if (errorName) {
                NoshiPrivacyFail(errorName);
                return;
            }
            NoshiShowNotice(nil, NSLocalizedString(@"privacy.photo.public.done", nil));
            /* the page shows the photo that was just set, and the one it replaced is gone */
            [again loadPublicPhoto];
        }];
    } unavailable:^{
        NoshiShowNotice(nil, NSLocalizedString(@"attach.failed", nil));
    }];
}

- (void)openExceptions:(BOOL)allowed {
    NoshiWeakReference *weak = _weak;
    NoshiPrivacyExceptionsController *page = [[[NoshiPrivacyExceptionsController alloc] initWithSession:_session rules:_rules allowed:allowed avatars:_avatars media:_media] autorelease];
    page.changedHandler = ^(NoshiPrivacyRules *fresh) {
        NoshiPrivacyRuleController *me = weak.target;
        if (!me) return;
        [me adopt:fresh];
        [me rebuild];
    };
    [self.navigationController pushViewController:page animated:YES];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSString *who = @"";
    for (size_t i = 0; i < PRIVACY_KEY_ROWS; ++i) {
        if (NoshiPrivacyKeys[i].key == _rules.key) who = NSLocalizedString(NoshiPrivacyKeys[i].who, nil);
    }
    noshi_privacy_base base = _rules.base;
    NoshiSettingsRow *everybody = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.everybody", nil) subtitle:nil checked:base == NOSHI_PRIVACY_EVERYBODY
                                                                     tap:^{ [(NoshiPrivacyRuleController *)weak.target choose:NOSHI_PRIVACY_EVERYBODY]; }];
    NoshiSettingsRow *contacts = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.contacts", nil) subtitle:nil checked:base == NOSHI_PRIVACY_CONTACTS
                                                                    tap:^{ [(NoshiPrivacyRuleController *)weak.target choose:NOSHI_PRIVACY_CONTACTS]; }];
    NoshiSettingsRow *nobody = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"privacy.nobody", nil) subtitle:nil checked:base == NOSHI_PRIVACY_NOBODY
                                                                  tap:^{ [(NoshiPrivacyRuleController *)weak.target choose:NOSHI_PRIVACY_NOBODY]; }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:who footer:nil rows:[NSArray arrayWithObjects:everybody, contacts, nobody, nil]]];

    /* a person added to everybody or removed from nobody would change nothing, so the lists that would be empty of meaning are not offered */
    NSMutableArray *exceptions = [NSMutableArray array];
    if (base != NOSHI_PRIVACY_EVERYBODY) {
        NSUInteger count = [_rules countAllowed:YES];
        [exceptions addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolPlusCircle tone:NoshiSettingsToneGreen title:NSLocalizedString(@"privacy.always", nil) subtitle:nil
                                                          value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : NSLocalizedString(@"privacy.add", nil)
                                                            tap:^{ [(NoshiPrivacyRuleController *)weak.target openExceptions:YES]; }]];
    }
    if (base != NOSHI_PRIVACY_NOBODY) {
        NSUInteger count = [_rules countAllowed:NO];
        [exceptions addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolBlock tone:NoshiSettingsToneRed title:NSLocalizedString(@"privacy.never", nil) subtitle:nil
                                                          value:count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : NSLocalizedString(@"privacy.add", nil)
                                                            tap:^{ [(NoshiPrivacyRuleController *)weak.target openExceptions:NO]; }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"privacy.exceptions", nil) footer:NSLocalizedString(@"privacy.exceptions.info", nil) rows:exceptions]];
    /* somebody is kept from the main photo only when the base is narrower than everybody or a person is on the never list */
    BOOL canSetPublic = _rules.key == NOSHI_PRIVACY_PHOTO && (base != NOSHI_PRIVACY_EVERYBODY || [_rules countAllowed:NO]);
    NSMutableArray *publicRows = [NSMutableArray array];
    if (canSetPublic) {
        [publicRows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolCameraPlus tone:NoshiSettingsToneBlue title:NSLocalizedString(@"privacy.photo.public", nil) subtitle:nil
                                                          value:nil tap:^{ [(NoshiPrivacyRuleController *)weak.target choosePublicPhoto]; }]];
    }
    /* a public photo can be taken away whatever the rule is now, since it stays on the account after the rule widens */
    if (_rules.key == NOSHI_PRIVACY_PHOTO && _publicPhoto) {
        NoshiSettingsRow *remove = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"privacy.photo.public.remove", nil) destructive:YES
                                                                         tap:^{ [(NoshiPrivacyRuleController *)weak.target deletePublicPhoto]; }];
        remove.trailingImage = _publicCircle;
        remove.trailingImageUnclipped = YES;
        [publicRows addObject:remove];
    }
    if (publicRows.count) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:canSetPublic ? NSLocalizedString(@"privacy.photo.public.info", nil) : nil rows:publicRows]];
    self.sections = sections;
    [self reloadSettings];
}

@end

@implementation NoshiPrivacyExceptionsController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(NoshiSession *)session rules:(NoshiPrivacyRules *)rules allowed:(BOOL)allowed avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _rules = [rules retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _allowed = allowed;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(allowed ? @"privacy.always" : @"privacy.never", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_rules release];
    [_avatars release];
    [_media release];
    [_faces invalidate];
    [_faces release];
    [_changedHandler release];
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
    return nil;
}

/* writes the list as edited, and shows what the server answers; a refusal puts back what the server holds */
- (void)save {
    if (_saving) return;
    _saving = YES;
    NoshiWeakReference *weak = _weak;
    noshi_privacy_key key = _rules.key;
    [_session savePrivacy:_rules completion:^(NoshiPrivacyRules *fresh, NSString *error) {
        NoshiPrivacyExceptionsController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        if (fresh) {
            [me->_rules release];
            me->_rules = [fresh retain];
            if (me->_changedHandler) me->_changedHandler(fresh);
            [me rebuild];
            return;
        }
        NoshiPrivacyFail(error);
        [me->_session loadPrivacy:key completion:^(NoshiPrivacyRules *held, NSString *loadError) {
            NoshiPrivacyExceptionsController *again = weak.target;
            if (!again) return;
            if (held) {
                [again->_rules release];
                again->_rules = [held retain];
                if (again->_changedHandler) again->_changedHandler(held);
            } else {
                NSLog(@"noshigram: the privacy rule did not load again: %@", loadError);
            }
            [again rebuild];
        }];
    }];
}

- (void)addPerson {
    if (_saving) return;
    NoshiWeakReference *weak = _weak;
    NoshiContactPickerController *picker = [[[NoshiContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"privacy.exceptions.add", nil);
    NoshiWeakReference *pickerRef = [NoshiWeakReference referenceTo:picker];
    picker.pickHandler = ^(NoshiDialog *dialog) {
        NoshiPrivacyExceptionsController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (!me) return;
        if (![me->_rules addUser:dialog.peerId hash:dialog.peerHash name:dialog.title photo:dialog.photo allowed:me->_allowed]) {
            NoshiGiftAlert(nil, NSLocalizedString(@"privacy.exceptions.cannot", nil));
            return;
        }
        [me rebuild];
        [me save];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)addGroup {
    if (_saving) return;
    NoshiWeakReference *weak = _weak;
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] init] autorelease];
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        return dialog.kind == NOSHI_DIALOG_GROUP && !dialog.folder && !dialog.left;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiPrivacyExceptionsController *me = weak.target;
        if (!me) return;
        for (NoshiDialog *dialog in dialogs) {
            if (![me->_rules addChat:dialog.peerId title:dialog.title photo:dialog.photo allowed:me->_allowed]) {
                NoshiGiftAlert(nil, NSLocalizedString(@"privacy.exceptions.cannot", nil));
                break;
            }
        }
        [me rebuild];
        [me save];
    };
    picker.limit = 20;
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)confirmRemove:(NoshiPrivacyEntry *)entry {
    NoshiWeakReference *weak = _weak;
    [NoshiSheet presentInView:self.view title:entry.name message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"privacy.exceptions.remove", nil)]
                    destructive:[NSIndexSet indexSetWithIndex:0] cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        NoshiPrivacyExceptionsController *me = weak.target;
        if (!me || me->_saving) return;
        [me->_rules removeEntry:entry allowed:me->_allowed];
        [me rebuild];
        [me save];
    }];
}

- (UIImage *)faceForKey:(NSString *)key name:(NSString *)name seed:(NSUInteger)seed photo:(NoshiPhoto *)photo {
    if (!_faces) {
        NoshiWeakReference *weak = _weak;
        _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiPrivacyExceptionsController *)weak.target rebuild]; }];
    }
    return [_faces imageForKey:key initials:NoshiInitialsOfName(name) seed:seed deleted:NO photo:photo];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *add = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle title:NSLocalizedString(@"privacy.exceptions.add", nil) destructive:NO
                                                                  tap:^{ [(NoshiPrivacyExceptionsController *)weak.target addPerson]; }];
    NoshiSettingsRow *addGroup = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle title:NSLocalizedString(@"privacy.exceptions.addgroup", nil) destructive:NO
                                                                      tap:^{ [(NoshiPrivacyExceptionsController *)weak.target addGroup]; }];
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiPrivacyEntry *entry in [_rules entriesAllowed:_allowed]) {
        NSString *name = entry.name.length ? entry.name : NSLocalizedString(@"privacy.exceptions.unknown", nil);
        UIImage *face = [self faceForKey:[NSString stringWithFormat:@"%d:%lld", entry.chat, entry.identifier] name:entry.name seed:(NSUInteger)(entry.identifier % 1000003) photo:entry.photo];
        [rows addObject:[NoshiSettingsRow rowWithTileImage:face title:name subtitle:entry.chat ? NSLocalizedString(@"privacy.exceptions.group", nil) : nil tap:^{
            [(NoshiPrivacyExceptionsController *)weak.target confirmRemove:entry];
        }]];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:add, addGroup, nil]]];
    if (rows.count) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"privacy.exceptions.hint", nil) rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end

#pragma mark blocked

@interface NoshiBlockedController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NSArray *_peers;
    int32_t _total;
    BOOL _loaded;
    BOOL _working;
    NoshiPeopleAvatars *_faces;
    void (^_countHandler)(int32_t total);
}
@end

@implementation NoshiBlockedController

@synthesize countHandler = _countHandler;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"privacy.blocked", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_peers release];
    [_faces invalidate];
    [_faces release];
    [_countHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self load];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)load {
    NoshiWeakReference *weak = _weak;
    [_session loadBlockedFrom:0 completion:^(NSArray *peers, int32_t total, NSString *error) {
        NoshiBlockedController *me = weak.target;
        if (!me) return;
        if (!peers) {
            NoshiPrivacyFail(error);
            return;
        }
        [me->_peers release];
        me->_peers = [peers retain];
        me->_total = total;
        me->_loaded = YES;
        if (me->_countHandler) me->_countHandler(total);
        [me rebuild];
    }];
}

- (void)blockPerson {
    if (_working) return;
    NoshiWeakReference *weak = _weak;
    NoshiContactPickerController *picker = [[[NoshiContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"privacy.blocked.block", nil);
    NoshiWeakReference *pickerRef = [NoshiWeakReference referenceTo:picker];
    picker.pickHandler = ^(NoshiDialog *dialog) {
        NoshiBlockedController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (!me) return;
        me->_working = YES;
        [me->_session setBlocked:YES kind:dialog.peerKind identifier:dialog.peerId hash:dialog.peerHash completion:^(NSString *error) {
            NoshiBlockedController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (error) NoshiPrivacyFail(error);
            else [again load];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

/* a blocked user opens as a profile, a blocked channel (a sender that wrote as one) as a channel; the access hash of the list is all the screen needs to ask for the rest */
- (void)openProfileOfPeer:(NoshiBlockedPeer *)peer {
    BOOL channel = peer.kind == 3;
    NoshiDialog *dialog = [NoshiDialog dialogWithPeerKind:peer.kind peerId:peer.identifier accessHash:peer.accessHash
                                                         kind:channel ? NOSHI_DIALOG_CHANNEL : NOSHI_DIALOG_USER title:peer.name];
    if (!dialog) return;
    UIViewController *screen = channel ? (UIViewController *)[[[NoshiChannelProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:nil] autorelease]
                                       : (UIViewController *)[[[NoshiUserProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:nil] autorelease];
    [self.navigationController pushViewController:screen animated:YES];
}

- (void)confirmUnblock:(NoshiBlockedPeer *)peer {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"privacy.blocked.profile", nil), NSLocalizedString(@"privacy.blocked.unblock", nil), nil];
    [NoshiSheet presentInView:self.view title:peer.name message:nil options:options
                    destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        NoshiBlockedController *me = weak.target;
        if (!me) return;
        if (index == 0) {
            [me openProfileOfPeer:peer];
            return;
        }
        if (me->_working) return;
        me->_working = YES;
        [me->_session setBlocked:NO kind:peer.kind identifier:peer.identifier hash:peer.accessHash completion:^(NSString *error) {
            NoshiBlockedController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (error) NoshiPrivacyFail(error);
            else [again load];
        }];
    }];
}

- (UIImage *)faceForKey:(NSString *)key name:(NSString *)name seed:(NSUInteger)seed photo:(NoshiPhoto *)photo {
    if (!_faces) {
        NoshiWeakReference *weak = _weak;
        _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiBlockedController *)weak.target rebuild]; }];
    }
    return [_faces imageForKey:key initials:NoshiInitialsOfName(name) seed:seed deleted:NO photo:photo];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    NoshiSettingsRow *add = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolBlock title:NSLocalizedString(@"privacy.blocked.block", nil) destructive:YES
                                                                  tap:^{ [(NoshiBlockedController *)weak.target blockPerson]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:add]]];
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiBlockedPeer *peer in _peers) {
        NSString *date = peer.date > 0 ? [NSString stringWithFormat:NSLocalizedString(@"privacy.blocked.since", nil), NoshiListTimeText(peer.date)] : nil;
        UIImage *face = [self faceForKey:[NSString stringWithFormat:@"%d:%lld", peer.kind, peer.identifier] name:peer.name seed:(NSUInteger)(peer.identifier % 1000003) photo:peer.photo];
        [rows addObject:[NoshiSettingsRow rowWithTileImage:face title:peer.name.length ? peer.name : NSLocalizedString(@"privacy.exceptions.unknown", nil) subtitle:date tap:^{
            [(NoshiBlockedController *)weak.target confirmUnblock:peer];
        }]];
    }
    NSString *footer = !_loaded ? nil : (rows.count ? NSLocalizedString(@"privacy.blocked.hint", nil) : NSLocalizedString(@"privacy.blocked.empty", nil));
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end

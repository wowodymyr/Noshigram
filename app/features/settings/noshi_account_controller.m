#import "noshi_account_controller.h"

#import "noshi_accounts.h"
#import "noshi_alert.h"
#import "noshi_date_sheet.h"
#import "noshi_people_avatars.h"
#import "noshi_text_filter.h"
#import "noshi_channel_picker_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_session_profile.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#import "noshi_name_color_controller.h"

/* the account page asks for the person and the full profile one after the other, and the privacy rule of the bio on its own */
@interface NoshiAccountController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NoshiPerson *_person;
    NoshiFullUser *_full;
    NoshiPeopleAvatars *_faces;
    BOOL _working;
    void (^_changedHandler)(void);
    void (^_logoutHandler)(void);
}
@end

@implementation NoshiAccountController

@synthesize changedHandler = _changedHandler;
@synthesize logoutHandler = _logoutHandler;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"account.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_person release];
    [_full release];
    [_faces invalidate];
    [_faces release];
    [_changedHandler release];
    [_logoutHandler release];
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

#pragma mark loading

- (void)load {
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiAccountController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"noshigram: the account page did not load the person: %@", errorName);
            return;
        }
        [me->_person release];
        me->_person = [[items objectAtIndex:0] retain];
        NoshiAccountSetInfo(NoshiAccountActive(), me->_person.name, me->_person.username, me->_person.userId);
        [me rebuild];
        [me loadFull];
    }];
}

- (void)loadFull {
    if (!_person) return;
    NoshiWeakReference *weak = _weak;
    [_session loadFullUserOfDialog:[NoshiDialog savedMessagesWithPerson:_person] completion:^(NoshiFullUser *user, NSString *errorName) {
        NoshiAccountController *me = weak.target;
        if (!me) return;
        if (!user) {
            NSLog(@"noshigram: the account page did not load the profile: %@", errorName);
            return;
        }
        [me->_full release];
        me->_full = [user retain];
        [me rebuild];
    }];
}

#pragma mark editing

- (NSString *)firstName {
    NSRange space = [_person.name rangeOfString:@" "];
    return space.location == NSNotFound ? _person.name : [_person.name substringToIndex:space.location];
}

- (NSString *)lastName {
    NSRange space = [_person.name rangeOfString:@" "];
    return space.location == NSNotFound ? @"" : [_person.name substringFromIndex:space.location + 1];
}

static NSString *NoshiAccountErrorText(NSString *errorName) {
    if ([errorName isEqualToString:@"FIRSTNAME_INVALID"]) return NSLocalizedString(@"profile.edit.noname", nil);
    if ([errorName isEqualToString:@"ABOUT_TOO_LONG"]) return NSLocalizedString(@"profile.edit.longabout", nil);
    return NoshiGiftErrorText(errorName);
}

/* a nil part stays as it is on the server */
- (void)saveFirst:(NSString *)first last:(NSString *)last about:(NSString *)about {
    if (_working) return;
    _working = YES;
    NoshiWeakReference *weak = _weak;
    [_session updateFirstName:first lastName:last about:about completion:^(NoshiPerson *person, NSString *errorName) {
        NoshiAccountController *me = weak.target;
        if (!me) return;
        me->_working = NO;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiAccountErrorText(errorName));
            return;
        }
        if (person) {
            [me->_person release];
            me->_person = [person retain];
        }
        if (me->_changedHandler) me->_changedHandler();
        [me loadFull];
        [me rebuild];
    }];
}

- (void)editFirst {
    if (!_person) return;
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"profile.edit.first", nil), nil, [self firstName], NSLocalizedString(@"profile.edit.first", nil), ^(NSString *text) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) {
            NoshiGiftAlert(nil, NSLocalizedString(@"profile.edit.noname", nil));
            return;
        }
        [(NoshiAccountController *)weak.target saveFirst:trimmed last:nil about:nil];
    });
}

- (void)editLast {
    if (!_person) return;
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"profile.edit.last", nil), nil, [self lastName], NSLocalizedString(@"profile.edit.last", nil), ^(NSString *text) {
        [(NoshiAccountController *)weak.target saveFirst:nil last:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] about:nil];
    });
}

- (void)editAbout {
    if (!_full) return;
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"profile.about", nil), NSLocalizedString(@"profile.edit.hint.about", nil), _full.about, NSLocalizedString(@"profile.about", nil), ^(NSString *text) {
        [(NoshiAccountController *)weak.target saveFirst:nil last:nil about:text];
    });
}

- (void)editUsername {
    if (!_person) return;
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"profile.username", nil), NSLocalizedString(@"profile.edit.hint", nil), _person.username, NSLocalizedString(@"profile.username", nil), ^(NSString *text) {
        NoshiAccountController *me = weak.target;
        if (!me || me->_working) return;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name hasPrefix:@"@"]) name = [name substringFromIndex:1];
        me->_working = YES;
        [me->_session updateUsername:name completion:^(NoshiPerson *person, NSString *errorName) {
            NoshiAccountController *again = weak.target;
            if (!again) return;
            again->_working = NO;
            if (errorName) {
                NSString *key = nil;
                if ([errorName isEqualToString:@"USERNAME_OCCUPIED"] || [errorName isEqualToString:@"USERNAME_PURCHASE_AVAILABLE"]) key = @"profile.edit.taken";
                else if ([errorName isEqualToString:@"USERNAME_INVALID"] || [errorName isEqualToString:@"USERNAME_NOT_MODIFIED"]) key = @"profile.edit.badusername";
                NoshiGiftAlert(nil, key ? NSLocalizedString(key, nil) : NoshiGiftErrorText(errorName));
                return;
            }
            if (person) {
                [again->_person release];
                again->_person = [person retain];
            }
            NoshiAccountSetInfo(NoshiAccountActive(), again->_person.name, again->_person.username, again->_person.userId);
            if (again->_changedHandler) again->_changedHandler();
            [again rebuild];
        }];
    });
}

- (void)chooseBirthday {
    if (!_full || _working) return;
    NoshiDateSheet *sheet = [[[NoshiDateSheet alloc] initWithDay:_full.birthdayDay month:_full.birthdayMonth year:_full.birthdayYear] autorelease];
    sheet.canRemove = _full.hasBirthday;
    NoshiWeakReference *weak = _weak;
    sheet.doneHandler = ^(int32_t day, int32_t month, int32_t year) {
        NoshiAccountController *me = weak.target;
        if (!me || me->_working) return;
        me->_working = YES;
        [me->_session setBirthdayDay:day month:month year:year completion:^(NSString *errorName) { [(NoshiAccountController *)weak.target birthdayDone:errorName]; }];
    };
    sheet.removeHandler = ^{
        NoshiAccountController *me = weak.target;
        if (!me || me->_working) return;
        me->_working = YES;
        [me->_session clearBirthday:^(NSString *errorName) { [(NoshiAccountController *)weak.target birthdayDone:errorName]; }];
    };
    [sheet showInView:self.view];
}

- (void)birthdayDone:(NSString *)errorName {
    _working = NO;
    if (errorName) {
        NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
        return;
    }
    [self loadFull];
}

- (NSString *)birthdayText {
    if (!_full) return nil;
    if (!_full.hasBirthday) return NSLocalizedString(@"account.empty", nil);
    NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
    parts.day = _full.birthdayDay;
    parts.month = _full.birthdayMonth;
    parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
    return date ? [formatter stringFromDate:date] : NSLocalizedString(@"account.empty", nil);
}

- (void)chooseChannel {
    if (!_full || _working) return;
    NoshiChannelPickerController *picker = [[[NoshiChannelPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"profile.channel", nil);
    picker.currentChannelId = _full.channel ? _full.channel.dialog.peerId : 0;
    NoshiWeakReference *weak = _weak;
    NoshiWeakReference *pickerRef = [NoshiWeakReference referenceTo:picker];
    picker.pickHandler = ^(NoshiDialog *channel) {
        NoshiAccountController *me = weak.target;
        UIViewController *host = pickerRef.target;
        if (host) [host.navigationController popViewControllerAnimated:YES];
        if (me) [me saveChannel:channel];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)saveChannel:(NoshiDialog *)channel {
    if (_working) return;
    _working = YES;
    NoshiWeakReference *weak = _weak;
    [_session setPersonalChannel:channel completion:^(NSString *errorName) {
        NoshiAccountController *me = weak.target;
        if (!me) return;
        me->_working = NO;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        if (me->_changedHandler) me->_changedHandler();
        [me loadFull];
    }];
}

#pragma mark rows

- (UIImage *)faceForAccount:(NSString *)name title:(NSString *)title active:(BOOL)active {
    if (!_faces) {
        NoshiWeakReference *weak = _weak;
        _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiAccountController *)weak.target rebuild]; }];
    }
    NSDictionary *info = NoshiAccountInfo(name);
    long long user = active ? _person.userId : [[info objectForKey:@"user"] longLongValue];
    if (!active) [_faces useStoredPhoto:NoshiAccountPhoto(name) forKey:[@"account:" stringByAppendingString:name] seed:(NSUInteger)(user % 1000003)];
    return [_faces imageForKey:[@"account:" stringByAppendingString:name] initials:NoshiInitialsOfName(title) seed:(NSUInteger)(user % 1000003) deleted:NO
                         photo:active ? _person.photo : nil];
}

- (NoshiSettingsRow *)rowOfAccount:(NSString *)name {
    BOOL active = [name isEqualToString:NoshiAccountActive()];
    NSDictionary *info = NoshiAccountInfo(name);
    NSString *title = active && _person ? _person.name : [info objectForKey:@"title"];
    NSString *username = active && _person ? _person.username : [info objectForKey:@"username"];
    if (!title.length) title = NSLocalizedString(@"account.title", nil);
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTileImage:[self faceForAccount:name title:title active:active] title:title
                                                          subtitle:username.length ? [@"@" stringByAppendingString:username] : nil tap:^{
        if (!active) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiAccountSwitchNotification object:nil userInfo:[NSDictionary dictionaryWithObject:name forKey:@"name"]];
    }];
    if (active) row.trailingImage = NoshiSymbolImage(NoshiSymbolCheckMark(), 22, NoshiColorAccent());
    return row;
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *first = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"profile.edit.first", nil) value:_person ? [self firstName] : nil
                                                             tap:^{ [(NoshiAccountController *)weak.target editFirst]; }];
    NoshiSettingsRow *last = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"profile.edit.last", nil)
                                                          value:_person ? ([[self lastName] length] ? [self lastName] : NSLocalizedString(@"account.empty", nil)) : nil
                                                            tap:^{ [(NoshiAccountController *)weak.target editLast]; }];
    NSString *about = _full ? (_full.about.length ? _full.about : NSLocalizedString(@"account.empty", nil)) : nil;
    NoshiSettingsRow *bio = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"profile.about", nil) value:about
                                                           tap:^{ [(NoshiAccountController *)weak.target editAbout]; }];
    NoshiSettingsRow *phone = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPhone tone:NoshiSettingsToneGreen title:NSLocalizedString(@"profile.phone", nil) subtitle:nil
                                                            value:_person ? NoshiOwnPhoneText(_person.phone) : nil
                                                              tap:^{ NoshiGiftAlert(nil, NSLocalizedString(@"account.phone.info", nil)); }];
    NoshiSettingsRow *username = [NoshiSettingsRow rowWithSymbol:NoshiSymbolAt tone:NoshiSettingsToneOrange title:NSLocalizedString(@"profile.username", nil) subtitle:nil
                                                               value:_person ? (_person.username.length ? [@"@" stringByAppendingString:_person.username] : NSLocalizedString(@"account.empty", nil)) : nil
                                                                 tap:^{ [(NoshiAccountController *)weak.target editUsername]; }];
    NoshiSettingsRow *birthday = [NoshiSettingsRow rowWithSymbol:NoshiSymbolCake tone:NoshiSettingsToneBlue title:NSLocalizedString(@"profile.birthday", nil) subtitle:nil
                                                               value:[self birthdayText] tap:^{ [(NoshiAccountController *)weak.target chooseBirthday]; }];
    NoshiSettingsRow *channel = [NoshiSettingsRow rowWithSymbol:NoshiSymbolMegaphone tone:NoshiSettingsToneOrange title:NSLocalizedString(@"profile.channel", nil)
                                                           subtitle:nil value:_full ? (_full.channel ? _full.channel.dialog.title : NSLocalizedString(@"profile.channel.add", nil)) : nil
                                                                tap:^{ [(NoshiAccountController *)weak.target chooseChannel]; }];
    /* the color of the name and of the replies, which needs the account loaded */
    NoshiSettingsRow *color = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPerson tone:NoshiSettingsTonePurple title:NSLocalizedString(@"chatset.namecolor", nil)
                                                         subtitle:nil value:_person.name tap:^{
        NoshiAccountController *me = weak.target;
        if (!me || !me->_person) return;
        NoshiNameColorController *colors = [[[NoshiNameColorController alloc] initWithSession:me->_session person:me->_person] autorelease];
        colors.changedHandler = ^(NSInteger colorId) { (void)colorId; [(NoshiAccountController *)weak.target load]; };
        [me.navigationController pushViewController:colors animated:YES];
    }];
    NoshiSettingsRow *add = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle title:NSLocalizedString(@"account.add", nil) destructive:NO
                                                                  tap:^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiAccountAddNotification object:nil]; }];
    NSMutableArray *accounts = [NSMutableArray arrayWithObject:add];
    for (NSString *name in NoshiAccountNames()) [accounts addObject:[self rowOfAccount:name]];
    NoshiSettingsRow *logout = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolLogout title:NSLocalizedString(@"profile.signout", nil) destructive:YES tap:^{
        NoshiAccountController *me = weak.target;
        if (me && me->_logoutHandler) me->_logoutHandler();
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"profile.edit.yourname", nil) footer:NSLocalizedString(@"account.about.info", nil)
                                                             rows:[NSArray arrayWithObjects:first, last, bio, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"profile.edit.info", nil) footer:NSLocalizedString(@"profile.edit.hint", nil)
                                                             rows:[NSArray arrayWithObjects:phone, username, birthday, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"account.channel.info", nil) rows:[NSArray arrayWithObject:channel]]];
    if (_person) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:color]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"account.accounts", nil) footer:NSLocalizedString(@"account.accounts.info", nil) rows:accounts]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:logout]]];
    self.sections = sections;
    [self reloadSettings];
}

@end

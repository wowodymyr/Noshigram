#import "noshi_channel_invite_edit_controller.h"

#import "noshi_channel_errors.h"
#import "noshi_channel_field_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define HOUR 3600
#define DAY (24 * HOUR)

/* the terms the form offers, in seconds from the moment of choosing; zero is a link that does not end */
static const int32_t kExpirePresets[] = {0, HOUR, DAY, 7 * DAY, 30 * DAY};
static const int32_t kLimitPresets[] = {0, 1, 5, 10, 25, 50, 100};
#define EXPIRE_PRESET_COUNT (sizeof(kExpirePresets) / sizeof(kExpirePresets[0]))
#define LIMIT_PRESET_COUNT (sizeof(kLimitPresets) / sizeof(kLimitPresets[0]))

@interface NoshiChannelInviteEditController () {
    NoshiSession *_session;
    NoshiFullChannel *_channel;
    NoshiInvite *_invite;
    void (^_saved)(NoshiInvite *saved);
    NoshiWeakReference *_weak;
    NSString *_name;
    /* the end of the link as a unix time, zero for none; a preset is turned into one when it is picked */
    int32_t _expire;
    int32_t _limit;
    BOOL _approval;
    BOOL _saving;
    UIButton *_done;
}
@end

@implementation NoshiChannelInviteEditController

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel invite:(NoshiInvite *)invite saved:(void (^)(NoshiInvite *))saved {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _invite = [invite retain];
    _saved = [saved copy];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _name = [(invite ? invite.title : @"") copy];
    _expire = invite.expireDate;
    _limit = invite.usageLimit;
    _approval = invite.requestNeeded;
    self.pageTitle = NSLocalizedString(invite ? @"invite.edit.title" : @"invite.new.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_invite release];
    [_saved release];
    [_name release];
    [_done release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self refreshSaveButton];
}

#pragma mark content

static NSString *NoshiExpireName(int32_t seconds) {
    switch (seconds) {
    case 0: return NSLocalizedString(@"invite.expire.never", nil);
    case HOUR: return NSLocalizedString(@"invite.expire.hour", nil);
    case DAY: return NSLocalizedString(@"invite.expire.day", nil);
    case 7 * DAY: return NSLocalizedString(@"invite.expire.week", nil);
    default: return NSLocalizedString(@"invite.expire.month", nil);
    }
}

static NSString *NoshiInviteEditDate(int32_t date) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

/* the choice the term of the form stands at: the index of a preset, or the date the link already had */
- (NSString *)expireValue {
    if (_expire == 0) return NoshiExpireName(0);
    return NoshiInviteEditDate(_expire);
}

- (NSString *)limitValue {
    return _limit > 0 ? [NSString stringWithFormat:@"%d", (int)_limit] : NSLocalizedString(@"invite.limit.none", nil);
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.title.hint", nil) rows:[NSArray arrayWithObject:
        [NoshiSettingsRow rowWithSymbol:NoshiSymbolCompose tone:NoshiSettingsToneBlue title:NSLocalizedString(@"invite.field.title", nil) subtitle:nil
                                    value:_name.length ? _name : NSLocalizedString(@"invite.title.none", nil) tap:^{
            [(NoshiChannelInviteEditController *)weak.target editName];
        }]]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.expire.hint", nil) rows:[NSArray arrayWithObject:
        [NoshiSettingsRow rowWithSymbol:NoshiSymbolClock tone:NoshiSettingsToneOrange title:NSLocalizedString(@"invite.expire", nil) subtitle:nil
                                    value:[self expireValue] tap:^{
            [(NoshiChannelInviteEditController *)weak.target chooseExpire];
        }]]]];
    NoshiSettingsRow *limit = [NoshiSettingsRow rowWithSymbol:NoshiSymbolMember tone:NoshiSettingsToneBlueDeep title:NSLocalizedString(@"invite.limit.title", nil)
                                                         subtitle:nil value:[self limitValue] tap:^{
        [(NoshiChannelInviteEditController *)weak.target chooseLimit];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.limit.hint", nil) rows:[NSArray arrayWithObject:limit]]];
    NoshiSettingsRow *approval = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolCheck tone:NoshiSettingsToneGreen title:NSLocalizedString(@"invite.approval.title", nil)
                                                                  subtitle:nil on:_approval toggle:^(BOOL on) {
        [(NoshiChannelInviteEditController *)weak.target setApproval:on];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"invite.approval.hint", nil) rows:[NSArray arrayWithObject:approval]]];
    self.sections = sections;
    [self reloadSettings];
}

#pragma mark editing

- (void)editName {
    NoshiWeakReference *weak = _weak;
    NoshiChannelFieldController *field = [[[NoshiChannelFieldController alloc] initWithSession:_session avatars:nil media:nil kind:NoshiChannelFieldInviteTitle text:_name
                                                                                            dialog:_channel.dialog save:^(NSString *text, void (^done)(NSString *)) {
        NoshiChannelInviteEditController *me = weak.target;
        if (me) {
            [me->_name release];
            me->_name = [text copy];
            [me rebuild];
        }
        done(nil);
    }] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

- (void)chooseExpire {
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < EXPIRE_PRESET_COUNT; ++i) [options addObject:NoshiExpireName(kExpirePresets[i])];
    NoshiWeakReference *weak = _weak;
    NoshiSettingsChoose(self, NSLocalizedString(@"invite.expire", nil), options, ^(NSUInteger index) {
        NoshiChannelInviteEditController *me = weak.target;
        if (!me || index >= EXPIRE_PRESET_COUNT) return;
        int32_t seconds = kExpirePresets[index];
        me->_expire = seconds ? (int32_t)time(NULL) + seconds : 0;
        [me rebuild];
    });
}

- (void)chooseLimit {
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < LIMIT_PRESET_COUNT; ++i) {
        [options addObject:kLimitPresets[i] ? [NSString stringWithFormat:@"%d", (int)kLimitPresets[i]] : NSLocalizedString(@"invite.limit.none", nil)];
    }
    NoshiWeakReference *weak = _weak;
    NoshiSettingsChoose(self, NSLocalizedString(@"invite.limit.title", nil), options, ^(NSUInteger index) {
        NoshiChannelInviteEditController *me = weak.target;
        if (!me || index >= LIMIT_PRESET_COUNT) return;
        me->_limit = kLimitPresets[index];
        /* a join that waits for an admin counts no use of the link, so the server takes either the limit or the approval, not both */
        if (me->_limit > 0) me->_approval = NO;
        [me rebuild];
    });
}

- (void)setApproval:(BOOL)on {
    _approval = on;
    if (on) _limit = 0;
    [self rebuild];
}

#pragma mark saving

- (void)refreshSaveButton {
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"channel.save", nil) style:UIBarButtonItemStyleBordered
                                                                              target:self action:@selector(save)] autorelease];
}

- (void)save {
    if (_saving) return;
    _saving = YES;
    _done.enabled = NO;
    NoshiWeakReference *weak = _weak;
    [self retain];
    void (^finish)(NoshiInvite *, NSString *) = ^(NoshiInvite *saved, NSString *errorName) {
        [self autorelease];
        NoshiChannelInviteEditController *me = weak.target;
        if (!me) return;
        me->_saving = NO;
        me->_done.enabled = YES;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiChannelErrorText(errorName));
            return;
        }
        if (me->_saved) me->_saved(saved);
        [me.navigationController popViewControllerAnimated:YES];
    };
    if (_invite) {
        [_session editInvite:_invite inDialog:_channel.dialog expireDate:_expire usageLimit:_limit requestNeeded:_approval title:_name completion:finish];
    } else {
        [_session createInviteInDialog:_channel.dialog expireDate:_expire usageLimit:_limit requestNeeded:_approval title:_name completion:finish];
    }
}

@end

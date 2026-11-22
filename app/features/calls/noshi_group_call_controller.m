#import "noshi_group_call_controller.h"
#import "noshi_alert_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_audio_session.h"
#import "noshi_call_route.h"
#import "noshi_avatar_view.h"
#import "noshi_emoji_label.h"
#import "noshi_name_badge.h"
#import "noshi_group_call_engine.h"
#import "noshi_person.h"
#import "noshi_platform.h"
#import "noshi_popup_menu.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define BUTTON_SIZE 52.0
#define MIC_SIZE 72.0
#define ROW_HEIGHT 60.0
#define AVATAR_SIDE 44.0
#define RING_WIDTH 2.5
#define ENDED_HOLD_SECONDS 1.4

static UIColor *GroupBackground(void) { return [UIColor colorWithRed:0.09f green:0.10f blue:0.15f alpha:1]; }
static UIColor *GroupGreen(void) { return [UIColor colorWithRed:0.18f green:0.72f blue:0.35f alpha:1]; }
static UIColor *GroupBlue(void) { return [UIColor colorWithRed:0.20f green:0.52f blue:0.92f alpha:1]; }

static UIButton *GroupButton(NoshiSymbol symbol, UIColor *fill, CGFloat size, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, size, size);
    button.backgroundColor = fill;
    button.layer.cornerRadius = size / 2;
    [button setImage:NoshiSymbolImage(symbol, size > 60 ? 30 : 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UILabel *GroupLabel(CGFloat size, BOOL bold, CGFloat alpha) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    label.textAlignment = NoshiTextAlignmentCenter;
    label.font = bold ? NoshiFontSemibold(size) : NoshiFontRegular(size);
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumFontSize = size * 0.7;
    return label;
}

@interface NoshiGroupMemberCell : UITableViewCell {
    NoshiAvatarView *_avatar;
    UIView *_ring;
    NoshiEmojiLabel *_name;
    UILabel *_status;
    UIImageView *_mic;
    long long _key;
}
- (void)showMember:(NoshiGroupMember *)member avatars:(NoshiAvatarCache *)avatars session:(NoshiSession *)session media:(NoshiMediaCache *)media;
@end

@implementation NoshiGroupMemberCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _ring = [[UIView alloc] init];
    _ring.layer.cornerRadius = (AVATAR_SIDE + 2 * (RING_WIDTH + 1)) / 2;
    _ring.layer.borderColor = GroupGreen().CGColor;
    _ring.layer.borderWidth = RING_WIDTH;
    _ring.hidden = YES;
    [self.contentView addSubview:_ring];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.circular = YES;
    [self.contentView addSubview:_avatar];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.textColor = [UIColor whiteColor];
    _name.font = NoshiFontSemibold(16);
    _name.userInteractionEnabled = NO;
    [self.contentView addSubview:_name];
    _status = GroupLabel(13, NO, 0.6f);
    _status.textAlignment = NoshiTextAlignmentLeft;
    [_status retain];
    [self.contentView addSubview:_status];
    _mic = [[UIImageView alloc] init];
    [self.contentView addSubview:_mic];
    return self;
}

- (void)dealloc {
    [_avatar release];
    [_ring release];
    [_name release];
    [_status release];
    [_mic release];
    [super dealloc];
}

- (void)showMember:(NoshiGroupMember *)member avatars:(NoshiAvatarCache *)avatars session:(NoshiSession *)session media:(NoshiMediaCache *)media {
    NSString *name = member.name.length ? member.name : @"";
    BOOL speaking = member.speaking;
    _avatar.seed = (NSUInteger)member.peerId;
    _avatar.initials = NoshiInitialsOfName(name);
    [_avatar setPhoto:member.photo cache:avatars];
    /* the member's marks and status come after the name, a user's only: a chat or a channel in the call wears none */
    NoshiShowNameWithBadges(_name, member.isSelf ? [NSString stringWithFormat:NSLocalizedString(@"group.you", nil), name] : name, member.peerKind == 1 ? member.peerId : 0,
                              member.peerKind == 1 ? session : nil, media);
    _ring.hidden = !speaking;
    if (speaking) {
        _status.text = NSLocalizedString(@"group.speaking", nil);
        _status.textColor = GroupGreen();
    } else if (member.muted) {
        _status.text = member.mutedByYou ? NSLocalizedString(@"group.muted.you", nil) : (member.canSelfUnmute ? NSLocalizedString(@"group.muted", nil) : NSLocalizedString(@"group.muted.admin", nil));
        _status.textColor = [UIColor colorWithWhite:1 alpha:0.5f];
    } else {
        _status.text = NSLocalizedString(@"group.listening", nil);
        _status.textColor = [UIColor colorWithWhite:1 alpha:0.6f];
    }
    _mic.image = NoshiSymbolImage(member.muted ? NoshiSymbolMicrophoneSlash : NoshiSymbolMicrophone, 20, member.muted ? [UIColor colorWithWhite:1 alpha:0.35f] : GroupGreen());
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, ringSide = AVATAR_SIDE + 2 * (RING_WIDTH + 1);
    _ring.frame = CGRectMake(12, (ROW_HEIGHT - ringSide) / 2, ringSide, ringSide);
    _avatar.frame = CGRectMake(12 + RING_WIDTH + 1, (ROW_HEIGHT - AVATAR_SIDE) / 2, AVATAR_SIDE, AVATAR_SIDE);
    _mic.frame = CGRectMake(width - 44, (ROW_HEIGHT - 28) / 2, 28, 28);
    _mic.contentMode = UIViewContentModeCenter;
    CGFloat textX = CGRectGetMaxX(_ring.frame) + 12, textWidth = MAX(0, width - textX - 52);
    _name.frame = CGRectMake(textX, 9, textWidth, 22);
    _status.frame = CGRectMake(textX, 32, textWidth, 18);
}

@end

@interface NoshiGroupCallController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NoshiGroupCall *_call;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    UILabel *_title, *_subtitle, *_micCaption, *_speakerCaption, *_endCaption;
    UIButton *_minimize, *_more, *_mic, *_speaker, *_end;
    UITableView *_table;
    UIView *_bottom;
    BOOL _speakerOn, _speakerSet, _closing;
    long long _callId;
    void (^_onMinimize)(void);
    void (^_onFinish)(void);
    NSTimer *_clock;
}
@end

@implementation NoshiGroupCallController

@synthesize avatars = _avatars;
@synthesize media = _media;
@synthesize callId = _callId;
@synthesize onMinimize = _onMinimize;
@synthesize onFinish = _onFinish;

- (BOOL)finishing { return _closing; }

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _speakerOn = YES;
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_clock invalidate];
    [_session release];
    [_call release];
    [_avatars release];
    [_media release];
    [_onMinimize release];
    [_onFinish release];
    [_title release]; [_subtitle release]; [_micCaption release]; [_speakerCaption release]; [_endCaption release];
    [_minimize release]; [_more release]; [_mic release]; [_speaker release]; [_end release];
    [_table release]; [_bottom release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.backgroundColor = GroupBackground();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _title = [GroupLabel(18, YES, 1) retain];
    _subtitle = [GroupLabel(13, NO, 0.65f) retain];
    _minimize = [GroupButton(NoshiSymbolArrowDown, [UIColor colorWithWhite:1 alpha:0.18f], 40, self, @selector(minimizeTapped)) retain];
    _minimize.accessibilityLabel = NSLocalizedString(@"call.minimize", nil);
    _more = [GroupButton(NoshiSymbolEllipsis, [UIColor colorWithWhite:1 alpha:0.18f], 40, self, @selector(moreTapped)) retain];
    _more.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = ROW_HEIGHT;
    _bottom = [[UIView alloc] init];
    _bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28f];
    _mic = [GroupButton(NoshiSymbolMicrophone, GroupBlue(), MIC_SIZE, self, @selector(micTapped)) retain];
    _speaker = [GroupButton(NoshiSymbolSpeaker, [UIColor colorWithWhite:1 alpha:0.2f], BUTTON_SIZE, self, @selector(speakerTapped)) retain];
    _end = [GroupButton(NoshiSymbolPhone, [UIColor colorWithRed:0.86f green:0.24f blue:0.24f alpha:1], BUTTON_SIZE, self, @selector(leaveTapped)) retain];
    _speaker.accessibilityLabel = NSLocalizedString(@"call.speaker", nil);
    _end.accessibilityLabel = NSLocalizedString(@"group.leave", nil);
    _micCaption = [GroupLabel(12, NO, 0.85f) retain];
    _speakerCaption = [GroupLabel(11, NO, 0.7f) retain];
    _speakerCaption.text = NSLocalizedString(@"call.speaker", nil);
    _endCaption = [GroupLabel(11, NO, 0.7f) retain];
    _endCaption.text = NSLocalizedString(@"group.leave", nil);
    for (UIView *view in [NSArray arrayWithObjects:_table, _bottom, _title, _subtitle, _minimize, _more, nil]) [root addSubview:view];
    for (UIView *view in [NSArray arrayWithObjects:_mic, _speaker, _end, _micCaption, _speakerCaption, _endCaption, nil]) [_bottom addSubview:view];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return NoshiOrientationMask(); }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat top = NoshiStatusBarHeight(), barHeight = 120;
    _minimize.frame = CGRectMake(12, top + 8, 40, 40);
    _more.frame = CGRectMake(size.width - 52, top + 8, 40, 40);
    _title.frame = CGRectMake(64, top + 8, MAX(0, size.width - 128), 24);
    _subtitle.frame = CGRectMake(64, top + 32, MAX(0, size.width - 128), 18);
    _bottom.frame = CGRectMake(0, size.height - barHeight, size.width, barHeight);
    _table.frame = CGRectMake(0, top + 60, size.width, MAX(0, size.height - barHeight - top - 60));
    CGFloat cx = size.width / 2, spread = MIN(110, size.width / 3);
    _mic.center = CGPointMake(cx, 48);
    _speaker.center = CGPointMake(cx - spread - 20, 48);
    _end.center = CGPointMake(cx + spread + 20, 48);
    _micCaption.frame = CGRectMake(cx - 100, 88, 200, 18);
    _speakerCaption.frame = CGRectMake(CGRectGetMidX(_speaker.frame) - 45, 88, 90, 16);
    _endCaption.frame = CGRectMake(CGRectGetMidX(_end.frame) - 45, 88, 90, 16);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _clock = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(render) userInfo:nil repeats:YES] retain];
    [self render];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_closing && _onFinish) {
        void (^finish)(void) = [_onFinish retain];
        [_onFinish release];
        _onFinish = nil;
        finish();
        [finish release];
    }
}

#pragma mark state

- (NSString *)clockText {
    NSInteger seconds = _call.startedAt > 0 ? MAX(0, (NSInteger)([NSDate timeIntervalSinceReferenceDate] - _call.startedAt)) : 0;
    return seconds >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60), (long)(seconds % 60)]
                           : [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)render {
    if (!_title) return;
    NSString *title = _call.title.length ? _call.title : (_call.chatTitle.length ? _call.chatTitle : NSLocalizedString(@"group.title", nil));
    _title.text = title;
    switch (_call.phase) {
    case NoshiGroupPhaseActive:
        _subtitle.text = [NSString stringWithFormat:@"%@ · %@", [NSString stringWithFormat:NSLocalizedString(@"group.members", nil), _call.participantsCount], [self clockText]];
        break;
    case NoshiGroupPhaseReconnecting: _subtitle.text = NSLocalizedString(@"call.reconnecting", nil); break;
    case NoshiGroupPhaseEnded: _subtitle.text = NSLocalizedString(@"group.ended", nil); break;
    default: _subtitle.text = NSLocalizedString(@"group.connecting", nil); break;
    }
    BOOL live = _call.phase == NoshiGroupPhaseActive || _call.phase == NoshiGroupPhaseReconnecting;
    UIColor *fill;
    NSString *caption;
    if (!live) {
        fill = [UIColor colorWithWhite:1 alpha:0.2f];
        caption = NSLocalizedString(@"group.connecting", nil);
    } else if (!_call.muted) {
        fill = GroupGreen();
        caption = NSLocalizedString(@"group.mic.on", nil);
    } else if (_call.canUnmute) {
        fill = GroupBlue();
        caption = NSLocalizedString(@"group.mic.off", nil);
    } else {
        fill = [UIColor colorWithWhite:1 alpha:0.2f];
        caption = NSLocalizedString(@"group.muted.admin", nil);
    }
    _mic.backgroundColor = fill;
    [_mic setImage:NoshiSymbolImage(live && _call.muted ? NoshiSymbolMicrophoneSlash : NoshiSymbolMicrophone, 30, [UIColor whiteColor]) forState:UIControlStateNormal];
    _mic.enabled = live && (!_call.muted || _call.canUnmute);
    _micCaption.text = caption;
    [_speaker setImage:NoshiSymbolImage(_speakerOn ? NoshiSymbolSpeaker : NoshiSymbolSpeakerSlash, 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    _speaker.backgroundColor = [UIColor colorWithWhite:1 alpha:_speakerOn ? 0.32f : 0.16f];
    [_table reloadData];
}

- (void)updateWithCall:(NoshiGroupCall *)call {
    NoshiGroupPhase previous = _call ? _call.phase : call.phase;
    [_call release];
    _call = [call retain];
    _callId = call.callId;
    if (call.phase == NoshiGroupPhaseActive && previous != NoshiGroupPhaseActive) {
        /* a voice chat starts on the loudspeaker, as the official clients do; the audio session exists from the moment the media is up */
        if (!_speakerSet) {
            _speakerSet = YES;
            /* the loudspeaker override beats whatever is plugged in, so a voice chat that began on it ignored the headphones; with a headset already carrying the sound it stays there */
            NoshiAudioRoute route = NoshiAudioSessionCurrentRoute();
            if (route == NoshiAudioRouteWired || route == NoshiAudioRouteBluetooth) _speakerOn = NO;
            NoshiAudioSessionSetSpeaker(_speakerOn);
        }
    }
    [self render];
    if (call.phase == NoshiGroupPhaseEnded && !_closing) {
        _closing = YES;
        /* a call the person left closes at once; one that ended on its own shows its end for a moment, and the owner words why */
        NSTimeInterval hold = call.end == NoshiGroupEndLeft ? 0 : ENDED_HOLD_SECONDS;
        [self performSelector:@selector(close) withObject:nil afterDelay:hold];
    }
}

- (void)close {
    [_clock invalidate];
    [_clock release];
    _clock = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark actions

- (void)minimizeTapped {
    if (_onMinimize) _onMinimize();
}

- (void)micTapped {
    [_session.groupCalls setMuted:!_call.muted];
}

- (void)speakerTapped {
    if (NoshiCallPresentRouteSheet(self, ^(NoshiAudioRoute route) {
        _speakerOn = route != NoshiAudioRouteEarpiece;
        _speakerSet = YES;
        [self render];
    })) return;
    _speakerOn = !_speakerOn;
    _speakerSet = YES;
    NoshiAudioSessionSetSpeaker(_speakerOn);
    [self render];
}

- (void)chooseAudioRoute {
    NoshiCallPresentRouteChoices(self, ^(NoshiAudioRoute route) {
        _speakerOn = route != NoshiAudioRouteEarpiece;
        _speakerSet = YES;
        [self render];
    });
}

- (void)leaveTapped {
    [_session.groupCalls leave];
}

- (void)moreTapped {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *kinds = [NSMutableArray array];
    NoshiSymbol symbols[3];
    [titles addObject:NSLocalizedString(@"group.invite", nil)];
    symbols[0] = NoshiSymbolShare;
    [kinds addObject:[NSNumber numberWithInt:0]];
    /* where the sound goes: the phone, the loudspeaker, headphones with a cable or a Bluetooth headset, whichever are there */
    [titles addObject:NSLocalizedString(@"call.route.title", nil)];
    symbols[1] = NoshiSymbolSpeaker;
    [kinds addObject:[NSNumber numberWithInt:2]];
    if (_call.canManage) {
        [titles addObject:NSLocalizedString(@"group.end.all", nil)];
        symbols[2] = NoshiSymbolClose;
        [kinds addObject:[NSNumber numberWithInt:1]];
    }
    NoshiWeakReference *weak = _weak;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        NoshiGroupCallController *controller = weak.target;
        if (!controller || index >= kinds.count) return;
        int kind = [[kinds objectAtIndex:index] intValue];
        if (kind == 0) [controller shareInvite];
        else if (kind == 2) [controller chooseAudioRoute];
        else [controller confirmEnd];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_more.frame), CGRectGetMaxY(_more.frame) + 4)];
}

- (void)notice:(NSString *)message {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)shareInvite {
    NoshiWeakReference *weak = _weak;
    [_session.groupCalls loadInviteLink:^(NSString *link, NSString *errorName) {
        NoshiGroupCallController *controller = weak.target;
        if (!controller) return;
        if (!link) {
            NSLog(@"noshigram: the invite link of the group call was not loaded: %@", errorName);
            [controller notice:NSLocalizedString(@"group.invite.failed", nil)];
            return;
        }
        Class activityClass = NSClassFromString(@"UIActivityViewController");
        if (activityClass) {
            id activity = [[activityClass alloc] initWithActivityItems:[NSArray arrayWithObject:link] applicationActivities:nil];
            if ([activity respondsToSelector:NSSelectorFromString(@"popoverPresentationController")]) {
                id popover = [activity performSelector:NSSelectorFromString(@"popoverPresentationController")];
                [popover setValue:controller->_more forKey:@"sourceView"];
                [popover setValue:[NSValue valueWithCGRect:controller->_more.bounds] forKey:@"sourceRect"];
            }
            [controller presentViewController:activity animated:YES completion:nil];
            [activity release];
        } else {
            [UIPasteboard generalPasteboard].string = link;
            [controller notice:NSLocalizedString(@"group.invite.copied", nil)];
        }
    }];
}

- (void)confirmEnd {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"group.end.confirm", nil) delegate:self
                               cancelButtonTitle:NSLocalizedString(@"notice.cancel", nil) otherButtonTitles:NSLocalizedString(@"group.end.all", nil), nil];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    (void)alertView;
    if (buttonIndex == 1) [_session.groupCalls endForEveryone];
}

#pragma mark members

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_call.members.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"member";
    NoshiGroupMemberCell *cell = (NoshiGroupMemberCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiGroupMemberCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell showMember:[_call.members objectAtIndex:(NSUInteger)indexPath.row] avatars:_avatars session:_session media:_media];
    return cell;
}

/* an admin mutes or unmutes another member from the row */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NoshiGroupMember *member = [_call.members objectAtIndex:(NSUInteger)indexPath.row];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_call.canManage || member.isSelf || member.peerKind != 1) return;
    [_session.groupCalls setMember:member muted:!member.muted];
}

@end

#import "noshi_notify_ui.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_plural.h"
#import "noshi_time.h"

noshi_notify_scope NoshiNotifyScopeOfKind(NoshiNotifyKind kind) {
    switch (kind) {
    case NoshiNotifyKindGroups: return NOSHI_SCOPE_CHATS;
    case NoshiNotifyKindChannels: return NOSHI_SCOPE_BROADCASTS;
    default: return NOSHI_SCOPE_USERS;
    }
}

int32_t NoshiNotifyNow(void) {
    return (int32_t)[[NSDate date] timeIntervalSince1970];
}

NSString *NoshiNotifyMuteText(int32_t muteUntil) {
    switch (noshi_notify_mute_state(muteUntil, NoshiNotifyNow())) {
    case 0: return NSLocalizedString(@"notif.on", nil);
    case 1: return NSLocalizedString(@"notif.off", nil);
    default: return [NSString stringWithFormat:NSLocalizedString(@"notif.offuntil", nil), NoshiListTimeText(muteUntil)];
    }
}

NSArray *NoshiNotifyTones(void) {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"sound_in.caf", NSLocalizedString(@"notif.tone.in", nil), nil],
        [NSArray arrayWithObjects:@"sound_out.caf", NSLocalizedString(@"notif.tone.out", nil), nil],
        [NSArray arrayWithObjects:@"voicechat_join.caf", NSLocalizedString(@"notif.tone.join", nil), nil],
        [NSArray arrayWithObjects:@"voicechat_leave.caf", NSLocalizedString(@"notif.tone.leave", nil), nil],
        [NSArray arrayWithObjects:@"voip_onallowtalk.caf", NSLocalizedString(@"notif.tone.allowtalk", nil), nil],
        [NSArray arrayWithObjects:@"voip_recordstart.caf", NSLocalizedString(@"notif.tone.record", nil), nil],
        [NSArray arrayWithObjects:@"voip_end.caf", NSLocalizedString(@"notif.tone.end", nil), nil],
        [NSArray arrayWithObjects:@"voip_busy.caf", NSLocalizedString(@"notif.tone.busy", nil), nil],
        [NSArray arrayWithObjects:@"voip_fail.caf", NSLocalizedString(@"notif.tone.failed", nil), nil], nil];
}

NSString *NoshiNotifySoundText(BOOL has, const noshi_notify_sound *sound) {
    if (!has) return NSLocalizedString(@"notif.sound.default", nil);
    switch (sound->kind) {
    case NOSHI_SOUND_NONE: return NSLocalizedString(@"notif.sound.none", nil);
    case NOSHI_SOUND_LOCAL:
        for (NSArray *tone in NoshiNotifyTones()) {
            if (!strcmp(sound->data, [[tone objectAtIndex:0] UTF8String])) return [tone objectAtIndex:1];
        }
        return sound->title[0] ? [NSString stringWithUTF8String:sound->title] : NSLocalizedString(@"notif.sound.custom", nil);
    case NOSHI_SOUND_RINGTONE:
        return sound->title[0] ? [NSString stringWithUTF8String:sound->title] : NSLocalizedString(@"notif.sound.custom", nil);
    default: return NSLocalizedString(@"notif.sound.default", nil);
    }
}

NSString *NoshiNotifyCountText(NSString *base, NSInteger count) {
    NSString *key = [NSString stringWithFormat:@"%@.%@", base, NoshiPluralForm(count)];
    return [NSString stringWithFormat:NSLocalizedString(key, nil), (int)count];
}

static BOOL NoshiHasMessageSettings(const noshi_peer_notify *n) {
    return n->has_mute || n->has_previews || n->has_silent || n->has_sound;
}

NSArray *NoshiNotifyExceptionsForKind(NSArray *all, NoshiNotifyKind kind) {
    NSMutableArray *list = [NSMutableArray array];
    for (NoshiNotifyException *exception in all) {
        noshi_peer_notify n = exception.settings;
        if (exception.forumTopic) continue;
        BOOL user = exception.peerKind == 1, channel = exception.peerKind == 3 && exception.broadcast;
        switch (kind) {
        case NoshiNotifyKindPrivate: if (user && NoshiHasMessageSettings(&n)) [list addObject:exception]; break;
        case NoshiNotifyKindGroups: if (!user && !channel && NoshiHasMessageSettings(&n)) [list addObject:exception]; break;
        case NoshiNotifyKindChannels: if (channel && NoshiHasMessageSettings(&n)) [list addObject:exception]; break;
        case NoshiNotifyKindStories: if (n.has_stories_muted) [list addObject:exception]; break;
        case NoshiNotifyKindAllExceptions: [list addObject:exception]; break;
        default: break;
        }
    }
    return list;
}

UIImage *NoshiNotifyInitialsTile(NSString *title, long long seed, CGFloat side) {
    NoshiAvatarView *avatar = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, side, side)] autorelease];
    avatar.circular = YES;
    avatar.seed = (NSUInteger)(seed < 0 ? -seed : seed) % 1000003;
    NSArray *words = [title componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *initials = [NSMutableString string];
    for (NSString *word in words) {
        if (!word.length || initials.length >= 2) continue;
        [initials appendString:[[word substringToIndex:[word rangeOfComposedCharacterSequenceAtIndex:0].length] uppercaseString]];
    }
    avatar.initials = initials;
    [avatar layoutIfNeeded];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [avatar.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *tile = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return tile;
}

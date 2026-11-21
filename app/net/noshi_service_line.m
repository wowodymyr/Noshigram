#import "noshi_service_line.h"

#import "noshi_gift_screen.h"

/* 3600 as "1 h", 172800 as "2 d": the largest unit that divides the period, hours and minutes below a day */
static NSString *NoshiPeriodText(int32_t seconds) {
    if (seconds % 604800 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.weeks", nil), (int)(seconds / 604800)];
    if (seconds % 86400 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.days", nil), (int)(seconds / 86400)];
    if (seconds % 3600 == 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.period.hours", nil), (int)(seconds / 3600)];
    return [NSString stringWithFormat:NSLocalizedString(@"chat.period.minutes", nil), (int)MAX(1, seconds / 60)];
}

static NSString *NoshiDurationText(int32_t seconds) {
    if (seconds >= 3600) return [NSString stringWithFormat:@"%d:%02d:%02d", (int)(seconds / 3600), (int)(seconds / 60 % 60), (int)(seconds % 60)];
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

/* the six lines of exteraGram for a chat added to a community or taken out of it, in the words of a group, a channel or a bot */
static NSString *NoshiCommunityLine(NSString *actor, NSString *community, int32_t value) {
    NSString *noun = (value & NoshiCommunityBot) ? @"bot" : ((value & NoshiCommunityChannel) ? @"channel" : @"group");
    NSString *action = (value & NoshiCommunityRemoved) ? @"removed" : @"added";
    NSString *who = (value & NoshiCommunityUnknownActor) ? @"unknown" : ((value & NoshiCommunityByMe) ? @"you" : @"someone");
    NSString *key = [NSString stringWithFormat:@"chat.service.community.%@.%@.%@", noun, action, who];
    NSString *title = community.length ? community : NSLocalizedString(@"channel.community.card", nil);
    BOOL removed = (value & NoshiCommunityRemoved) != 0;
    NSString *format = NSLocalizedString(key, nil);
    if ([who isEqualToString:@"someone"]) return removed ? [NSString stringWithFormat:format, actor] : [NSString stringWithFormat:format, actor, title];
    if (removed) return format;
    return [NSString stringWithFormat:format, title];
}

NSString *NoshiServiceLine(noshi_service_kind kind, NSString *who, NSString *whom, NSString *text, int32_t value, BOOL actorIsTarget) {
    NSString *actor = who.length ? who : NSLocalizedString(@"chat.someone", nil);
    NSString *target = whom.length ? whom : NSLocalizedString(@"chat.someone", nil);
    switch (kind) {
    case NOSHI_SERVICE_CHAT_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.created", nil), actor, text];
    case NOSHI_SERVICE_CHANNEL_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.channel", nil), text];
    case NOSHI_SERVICE_TITLE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.title", nil), actor, text];
    case NOSHI_SERVICE_PHOTO_CHANGED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photo", nil), actor];
    case NOSHI_SERVICE_PHOTO_DELETED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photo.removed", nil), actor];
    /* the server sends the same action when a member leaves or comes back by a link, with the actor and the target the same person */
    case NOSHI_SERVICE_USER_ADDED:
        if (actorIsTarget) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.joined", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.added", nil), actor, target];
    case NOSHI_SERVICE_USER_REMOVED:
        if (actorIsTarget) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.left", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.removed", nil), actor, target];
    case NOSHI_SERVICE_JOINED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.joined", nil), actor];
    case NOSHI_SERVICE_PIN: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.pinned", nil), actor];
    case NOSHI_SERVICE_CALL: return NSLocalizedString(@"chat.service.call", nil);
    case NOSHI_SERVICE_CONTACT_JOINED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.contact", nil), actor];
    case NOSHI_SERVICE_SCREENSHOT: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.screenshot", nil), actor];
    case NOSHI_SERVICE_HISTORY_CLEAR: return NSLocalizedString(@"chat.service.history", nil);
    case NOSHI_SERVICE_MIGRATED:
        return text.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.service.migrated.from", nil), text]
                           : NSLocalizedString(@"chat.service.migrated.to", nil);
    case NOSHI_SERVICE_CUSTOM: return text.length ? text : NSLocalizedString(@"chat.service.other", nil);
    case NOSHI_SERVICE_VIDEO_CHAT:
        if (value > 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.end", nil), NoshiDurationText(value)];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.start", nil), actor];
    case NOSHI_SERVICE_VIDEO_CHAT_INVITE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.videochat.invite", nil), actor, target];
    case NOSHI_SERVICE_TOPIC_CREATE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.create", nil), actor, text];
    case NOSHI_SERVICE_TOPIC_EDIT:
        if (value == 1) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.close", nil), actor];
        if (value == 2) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.reopen", nil), actor];
        if (text.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.rename", nil), actor, text];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.topic.edit", nil), actor];
    case NOSHI_SERVICE_TTL:
        if (value <= 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.ttl.off", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.ttl.on", nil), actor, NoshiPeriodText(value)];
    case NOSHI_SERVICE_BOOST: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.boost", nil), actor];
    case NOSHI_SERVICE_PAYMENT: return NSLocalizedString(@"chat.service.payment", nil);
    case NOSHI_SERVICE_BOT_ALLOWED: return NSLocalizedString(@"chat.service.botallowed", nil);
    case NOSHI_SERVICE_PREMIUM_GIFT:
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.premium", nil), actor, [NSString stringWithFormat:NSLocalizedString(@"chat.period.months", nil), (int)MAX(1, value)]];
    case NOSHI_SERVICE_STARS_GIFT:
        /* a gift whose amount cannot be read still says it was a gift of Stars */
        if (value <= 0) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.stars.unknown", nil), actor];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.stars", nil), actor, NoshiStarsText(value)];
    case NOSHI_SERVICE_THEME:
        if (text.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.service.theme", nil), actor, text];
        return [NSString stringWithFormat:NSLocalizedString(@"chat.service.theme.off", nil), actor];
    case NOSHI_SERVICE_WALLPAPER: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.wallpaper", nil), actor];
    case NOSHI_SERVICE_PHOTO_SUGGESTED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.photosuggest", nil), actor];
    case NOSHI_SERVICE_GAME_SCORE: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.score", nil), actor, (int)value];
    case NOSHI_SERVICE_GIVEAWAY: return NSLocalizedString(@"chat.service.giveaway", nil);
    case NOSHI_SERVICE_GIVEAWAY_RESULTS: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.giveaway.results", nil), (int)value];
    case NOSHI_SERVICE_PAYMENT_REFUNDED: return NSLocalizedString(@"chat.service.refunded", nil);
    case NOSHI_SERVICE_SHARING_REQUEST:
        if (value & 4) return NSLocalizedString(@"chat.service.sharing.expired", nil);
        return [NSString stringWithFormat:NSLocalizedString((value & 2) ? @"chat.service.sharing.request.disable" : @"chat.service.sharing.request.enable", nil), actor];
    case NOSHI_SERVICE_SHARING_TOGGLE:
        if (!!(value & 1) == !!(value & 2)) return NSLocalizedString((value & 2) ? @"chat.service.sharing.still.disabled" : @"chat.service.sharing.still.enabled", nil);
        return [NSString stringWithFormat:NSLocalizedString((value & 2) ? @"chat.service.sharing.disabled" : @"chat.service.sharing.enabled", nil), actor];
    case NOSHI_SERVICE_POLL_ANSWER_ADDED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.poll.added", nil), actor, text];
    case NOSHI_SERVICE_POLL_ANSWER_REMOVED: return [NSString stringWithFormat:NSLocalizedString(@"chat.service.poll.removed", nil), actor, text];
    case NOSHI_SERVICE_COMMUNITY: return NoshiCommunityLine(actor, text, value);
    case NOSHI_SERVICE_OTHER:
        /* no wording for it: the action's own name, as readable as it gets, beats a line that says nothing */
        if (text.length) return text;
        break;
    case NOSHI_SERVICE_GIFT:
        break;
    }
    return NSLocalizedString(@"chat.service.other", nil);
}

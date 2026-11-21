#import "noshi_notify_store.h"

#import "noshi_platform.h"

NSString *const NoshiNotifyStoreDidChangeNotification = @"NoshiNotifyStoreDidChange";

#define KEY_SCOPE @"noshigram.notify.scope."
#define KEY_REACTIONS @"noshigram.notify.reactions"
#define KEY_IN_APP_SOUNDS @"noshigram.notify.inapp.sounds"
#define KEY_IN_APP_VIBRATE @"noshigram.notify.inapp.vibrate"
#define KEY_IN_APP_PREVIEW @"noshigram.notify.inapp.preview"
#define KEY_IN_CHAT @"noshigram.notify.inchat"
#define KEY_CONTACT_JOINED @"noshigram.notify.contactjoined"
#define KEY_PINNED @"noshigram.notify.pinned"
#define KEY_BADGE @"noshigram.notify.badge.shown"
#define KEY_BADGE_MUTED @"noshigram.notify.badge.muted"
#define KEY_BADGE_MESSAGES @"noshigram.notify.badge.messages"
#define KEY_REPEAT @"noshigram.notify.repeat"
#define KEY_CALL_VIBRATE @"noshigram.notify.callvibrate"
#define REPEAT_DEFAULT_MINUTES 60

static NSDictionary *NoshiSoundDictionary(const noshi_notify_sound *sound) {
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:sound->kind], @"k", [NSNumber numberWithLongLong:sound->ringtone_id], @"i",
            [NSString stringWithUTF8String:sound->title], @"t", [NSString stringWithUTF8String:sound->data], @"d", nil];
}

static void NoshiSoundFromDictionary(NSDictionary *dictionary, noshi_notify_sound *sound, uint8_t *has) {
    memset(sound, 0, sizeof(*sound));
    *has = 0;
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    int kind = [[dictionary objectForKey:@"k"] intValue];
    if (kind < NOSHI_SOUND_DEFAULT || kind > NOSHI_SOUND_RINGTONE) return;
    sound->kind = kind;
    sound->ringtone_id = [[dictionary objectForKey:@"i"] longLongValue];
    NSString *title = [dictionary objectForKey:@"t"], *data = [dictionary objectForKey:@"d"];
    if ([title isKindOfClass:[NSString class]]) strlcpy(sound->title, title.UTF8String, sizeof(sound->title));
    if ([data isKindOfClass:[NSString class]]) strlcpy(sound->data, data.UTF8String, sizeof(sound->data));
    *has = 1;
}

static NSDictionary *NoshiPeerNotifyDictionary(const noshi_peer_notify *n) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (n->has_mute) [d setObject:[NSNumber numberWithInt:n->mute_until] forKey:@"mute"];
    if (n->has_previews) [d setObject:[NSNumber numberWithBool:n->previews] forKey:@"previews"];
    if (n->has_silent) [d setObject:[NSNumber numberWithBool:n->silent] forKey:@"silent"];
    if (n->has_sound) [d setObject:NoshiSoundDictionary(&n->sound) forKey:@"sound"];
    if (n->has_stories_muted) [d setObject:[NSNumber numberWithBool:n->stories_muted] forKey:@"storiesMuted"];
    if (n->has_stories_hide_sender) [d setObject:[NSNumber numberWithBool:n->stories_hide_sender] forKey:@"storiesHide"];
    if (n->has_stories_sound) [d setObject:NoshiSoundDictionary(&n->stories_sound) forKey:@"storiesSound"];
    return d;
}

static void NoshiPeerNotifyFromDictionary(NSDictionary *d, noshi_peer_notify *n) {
    memset(n, 0, sizeof(*n));
    if (![d isKindOfClass:[NSDictionary class]]) return;
    NSNumber *value;
    if ((value = [d objectForKey:@"mute"])) { n->has_mute = 1; n->mute_until = (int32_t)[value longLongValue]; }
    if ((value = [d objectForKey:@"previews"])) { n->has_previews = 1; n->previews = [value boolValue]; }
    if ((value = [d objectForKey:@"silent"])) { n->has_silent = 1; n->silent = [value boolValue]; }
    NoshiSoundFromDictionary([d objectForKey:@"sound"], &n->sound, &n->has_sound);
    if ((value = [d objectForKey:@"storiesMuted"])) { n->has_stories_muted = 1; n->stories_muted = [value boolValue]; }
    if ((value = [d objectForKey:@"storiesHide"])) { n->has_stories_hide_sender = 1; n->stories_hide_sender = [value boolValue]; }
    NoshiSoundFromDictionary([d objectForKey:@"storiesSound"], &n->stories_sound, &n->has_stories_sound);
}

static void NoshiNotifyChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiNotifyStoreDidChangeNotification object:nil];
    });
}

static void NoshiNotifySave(void) {
    NoshiDefaultsSaveSoon();
    NoshiNotifyChanged();
}

noshi_peer_notify NoshiNotifyScopeStored(noshi_notify_scope scope) {
    noshi_peer_notify n;
    memset(&n, 0, sizeof(n));
    if ((int)scope < 0 || scope >= NOSHI_SCOPE_COUNT) return n;
    NoshiPeerNotifyFromDictionary([[NSUserDefaults standardUserDefaults] objectForKey:[KEY_SCOPE stringByAppendingFormat:@"%d", (int)scope]], &n);
    return n;
}

void NoshiNotifyScopeStore(noshi_notify_scope scope, const noshi_peer_notify *value) {
    if ((int)scope < 0 || scope >= NOSHI_SCOPE_COUNT || !value) return;
    [[NSUserDefaults standardUserDefaults] setObject:NoshiPeerNotifyDictionary(value) forKey:[KEY_SCOPE stringByAppendingFormat:@"%d", (int)scope]];
    NoshiNotifySave();
}

noshi_reaction_notify NoshiNotifyReactionsStored(void) {
    noshi_reaction_notify r;
    memset(&r, 0, sizeof(r));
    r.messages_from = NOSHI_REACTION_FROM_EVERYONE;
    r.stories_from = NOSHI_REACTION_FROM_EVERYONE;
    r.previews = 1;
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_REACTIONS];
    if (![d isKindOfClass:[NSDictionary class]]) return r;
    r.messages_from = (int32_t)[[d objectForKey:@"messages"] intValue];
    r.stories_from = (int32_t)[[d objectForKey:@"stories"] intValue];
    r.previews = [[d objectForKey:@"previews"] boolValue];
    uint8_t has;
    NoshiSoundFromDictionary([d objectForKey:@"sound"], &r.sound, &has);
    return r;
}

void NoshiNotifyReactionsStore(const noshi_reaction_notify *value) {
    if (!value) return;
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:value->messages_from], @"messages",
                       [NSNumber numberWithInt:value->stories_from], @"stories", [NSNumber numberWithBool:value->previews], @"previews",
                       NoshiSoundDictionary(&value->sound), @"sound", nil];
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:KEY_REACTIONS];
    NoshiNotifySave();
}

static BOOL NoshiNotifyFlag(NSString *key, BOOL fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return stored ? [stored boolValue] : fallback;
}

static void NoshiNotifySetFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    NoshiNotifySave();
}

void NoshiNotifyRulesSnapshot(noshi_notify_rules *out) {
    noshi_notify_rules_init(out);
    for (int i = 0; i < NOSHI_SCOPE_COUNT; ++i) out->scope[i] = NoshiNotifyScopeStored((noshi_notify_scope)i);
    out->contact_joined = NoshiNotifyContactJoined();
    out->pinned_messages = NoshiNotifyPinnedMessages();
}

BOOL NoshiNotifyInAppSounds(void) { return NoshiNotifyFlag(KEY_IN_APP_SOUNDS, YES); }
void NoshiNotifySetInAppSounds(BOOL on) { NoshiNotifySetFlag(KEY_IN_APP_SOUNDS, on); }
#define KEY_CHAT_NO_VIBRATION @"noshigram.notify.chat.novibration"

BOOL NoshiNotifyChatVibrates(int32_t peerKind, long long peerId) {
    NSArray *off = [[NSUserDefaults standardUserDefaults] arrayForKey:KEY_CHAT_NO_VIBRATION];
    return ![off containsObject:[NSString stringWithFormat:@"%d:%lld", (int)peerKind, peerId]];
}

void NoshiNotifySetChatVibrates(int32_t peerKind, long long peerId, BOOL on) {
    NSMutableArray *off = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:KEY_CHAT_NO_VIBRATION]];
    NSString *key = [NSString stringWithFormat:@"%d:%lld", (int)peerKind, peerId];
    if (on) [off removeObject:key];
    else if (![off containsObject:key]) [off addObject:key];
    [[NSUserDefaults standardUserDefaults] setObject:off forKey:KEY_CHAT_NO_VIBRATION];
}

BOOL NoshiNotifyInAppVibrate(void) { return NoshiNotifyFlag(KEY_IN_APP_VIBRATE, YES); }
void NoshiNotifySetInAppVibrate(BOOL on) { NoshiNotifySetFlag(KEY_IN_APP_VIBRATE, on); }
BOOL NoshiNotifyInAppPreview(void) { return NoshiNotifyFlag(KEY_IN_APP_PREVIEW, YES); }
void NoshiNotifySetInAppPreview(BOOL on) { NoshiNotifySetFlag(KEY_IN_APP_PREVIEW, on); }
BOOL NoshiNotifyInChatSounds(void) { return NoshiNotifyFlag(KEY_IN_CHAT, NO); }
void NoshiNotifySetInChatSounds(BOOL on) { NoshiNotifySetFlag(KEY_IN_CHAT, on); }
BOOL NoshiNotifyContactJoined(void) { return NoshiNotifyFlag(KEY_CONTACT_JOINED, YES); }
void NoshiNotifySetContactJoined(BOOL on) { NoshiNotifySetFlag(KEY_CONTACT_JOINED, on); }
BOOL NoshiNotifyPinnedMessages(void) { return NoshiNotifyFlag(KEY_PINNED, YES); }
void NoshiNotifySetPinnedMessages(BOOL on) { NoshiNotifySetFlag(KEY_PINNED, on); }
BOOL NoshiNotifyBadgeShown(void) { return NoshiNotifyFlag(KEY_BADGE, YES); }
void NoshiNotifySetBadgeShown(BOOL on) { NoshiNotifySetFlag(KEY_BADGE, on); }
BOOL NoshiNotifyBadgeMuted(void) { return NoshiNotifyFlag(KEY_BADGE_MUTED, NO); }
void NoshiNotifySetBadgeMuted(BOOL on) { NoshiNotifySetFlag(KEY_BADGE_MUTED, on); }
BOOL NoshiNotifyBadgeMessages(void) { return NoshiNotifyFlag(KEY_BADGE_MESSAGES, YES); }
void NoshiNotifySetBadgeMessages(BOOL on) { NoshiNotifySetFlag(KEY_BADGE_MESSAGES, on); }

NSInteger NoshiNotifyRepeatMinutes(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_REPEAT];
    return stored ? MAX(0, [stored integerValue]) : REPEAT_DEFAULT_MINUTES;
}

void NoshiNotifySetRepeatMinutes(NSInteger minutes) {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(0, minutes) forKey:KEY_REPEAT];
    NoshiNotifySave();
}

NSInteger NoshiNotifyCallVibration(void) {
    NSInteger style = [[NSUserDefaults standardUserDefaults] integerForKey:KEY_CALL_VIBRATE];
    return style >= 0 && style <= 3 ? style : 0;
}

void NoshiNotifySetCallVibration(NSInteger style) {
    [[NSUserDefaults standardUserDefaults] setInteger:(style >= 0 && style <= 3 ? style : 0) forKey:KEY_CALL_VIBRATE];
    NoshiNotifySave();
}

void NoshiNotifyStoreReset(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (int i = 0; i < NOSHI_SCOPE_COUNT; ++i) [defaults removeObjectForKey:[KEY_SCOPE stringByAppendingFormat:@"%d", i]];
    NSArray *keys = [NSArray arrayWithObjects:KEY_REACTIONS, KEY_IN_APP_SOUNDS, KEY_IN_APP_VIBRATE, KEY_IN_APP_PREVIEW, KEY_IN_CHAT, KEY_CONTACT_JOINED, KEY_PINNED,
                     KEY_BADGE, KEY_BADGE_MUTED, KEY_BADGE_MESSAGES, KEY_REPEAT, KEY_CALL_VIBRATE, nil];
    for (NSString *key in keys) [defaults removeObjectForKey:key];
    NoshiNotifySave();
}

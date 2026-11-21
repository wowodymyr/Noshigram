#import "noshi_typing_board.h"

#include "noshi_typing.h"

NSString *const NoshiTypingDidChangeNotification = @"NoshiTypingDidChange";

/* the server repeats an action every few seconds while it goes on, and the clients let it run out after six */
#define TYPING_LIFETIME_SECONDS 6.0

@interface NoshiTypingEntry : NSObject {
@public
    int32_t kind;
    long long peer;
    long long user;
    int32_t top;
    int action;
    NSString *name;
    NSTimeInterval expires;
}
@end

@implementation NoshiTypingEntry
- (void)dealloc {
    [name release];
    [super dealloc];
}
@end

@implementation NoshiTypingBoard

- (id)init {
    self = [super init];
    if (!self) return nil;
    _entries = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_entries release];
    [super dealloc];
}

static NSTimeInterval NoshiTypingNow(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

static BOOL NoshiTypingSamePerson(NoshiTypingEntry *entry, int32_t kind, long long peer, long long user, int32_t top) {
    return entry->kind == kind && entry->peer == peer && entry->user == user && entry->top == top;
}

static NSString *const NoshiTypingKindKey = @"kind";
static NSString *const NoshiTypingPeerKey = @"peer";

BOOL NoshiTypingChangeConcerns(NSNotification *note, NoshiDialog *dialog) {
    NSNumber *kind = [note.userInfo objectForKey:NoshiTypingKindKey], *peer = [note.userInfo objectForKey:NoshiTypingPeerKey];
    if (![kind isKindOfClass:[NSNumber class]] || ![peer isKindOfClass:[NSNumber class]]) return YES;
    return kind.intValue == dialog.peerKind && peer.longLongValue == dialog.peerId;
}

- (void)changedKind:(int32_t)kind peer:(long long)peer {
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], NoshiTypingKindKey,
                          [NSNumber numberWithLongLong:peer], NoshiTypingPeerKey, nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiTypingDidChangeNotification object:self userInfo:info];
}

/* one pass that drops what has run out and sets the next one for the soonest of the rest */
- (void)expire {
    _timerSet = NO;
    NSTimeInterval now = NoshiTypingNow();
    NSMutableArray *gone = [NSMutableArray array];
    for (NSInteger i = (NSInteger)_entries.count - 1; i >= 0; --i) {
        NoshiTypingEntry *entry = [_entries objectAtIndex:(NSUInteger)i];
        if (entry->expires <= now) {
            [gone addObject:entry];
            [_entries removeObjectAtIndex:(NSUInteger)i];
        }
    }
    [self scheduleExpiry];
    /* one report for each chat that lost someone, however many people ran out in it */
    for (NSUInteger i = 0; i < gone.count; ++i) {
        NoshiTypingEntry *entry = [gone objectAtIndex:i];
        BOOL reported = NO;
        for (NSUInteger earlier = 0; earlier < i && !reported; ++earlier) {
            NoshiTypingEntry *other = [gone objectAtIndex:earlier];
            reported = other->kind == entry->kind && other->peer == entry->peer;
        }
        if (!reported) [self changedKind:entry->kind peer:entry->peer];
    }
}

- (void)scheduleExpiry {
    if (_timerSet || !_entries.count) return;
    NSTimeInterval soonest = 0, now = NoshiTypingNow();
    for (NoshiTypingEntry *entry in _entries) {
        if (!soonest || entry->expires < soonest) soonest = entry->expires;
    }
    _timerSet = YES;
    [self performSelector:@selector(expire) withObject:nil afterDelay:MAX(0.05, soonest - now)];
}

- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top {
    [self noteKind:kind peer:peer user:user action:action top:top name:nil];
}

- (NSArray *)namesInDialog:(NoshiDialog *)dialog {
    NSMutableArray *names = [NSMutableArray array];
    for (NoshiTypingEntry *entry in _entries) {
        if ([self entry:entry belongsToDialog:dialog] && entry->name.length) [names addObject:entry->name];
    }
    return names;
}

- (void)noteKind:(int32_t)kind peer:(long long)peer user:(long long)user action:(int)action top:(int32_t)top name:(NSString *)name {
    NoshiTypingEntry *found = nil;
    for (NoshiTypingEntry *entry in _entries) {
        if (NoshiTypingSamePerson(entry, kind, peer, user, top)) {
            found = entry;
            break;
        }
    }
    if (action == NOSHI_TYPING_CANCEL) {
        if (!found) return;
        [_entries removeObject:found];
        [self changedKind:kind peer:peer];
        return;
    }
    BOOL fresh = found == nil || found->action != action;
    if (!found) {
        found = [[[NoshiTypingEntry alloc] init] autorelease];
        found->kind = kind;
        found->peer = peer;
        found->user = user;
        found->top = top;
        [_entries addObject:found];
    }
    found->action = action;
    if (name.length && ![name isEqualToString:found->name]) {
        [found->name release];
        found->name = [name copy];
        fresh = YES;
    }
    found->expires = NoshiTypingNow() + TYPING_LIFETIME_SECONDS;
    [self scheduleExpiry];
    /* a repeat of the same action only moves its end, which no screen shows */
    if (fresh) [self changedKind:kind peer:peer];
}

- (BOOL)entry:(NoshiTypingEntry *)entry belongsToDialog:(NoshiDialog *)dialog {
    if (entry->kind != dialog.peerKind || entry->peer != dialog.peerId) return NO;
    /* a topic shows its own thread and a whole chat shows every thread of it */
    return dialog.topicId <= 0 || entry->top == dialog.topicId;
}

- (NSUInteger)countInDialog:(NoshiDialog *)dialog {
    NSUInteger count = 0;
    for (NoshiTypingEntry *entry in _entries) {
        if ([self entry:entry belongsToDialog:dialog]) ++count;
    }
    return count;
}

- (int)actionInDialog:(NoshiDialog *)dialog {
    int best = NOSHI_TYPING_CANCEL;
    for (NoshiTypingEntry *entry in _entries) {
        if (![self entry:entry belongsToDialog:dialog]) continue;
        if (entry->action == NOSHI_TYPING_TEXT) return NOSHI_TYPING_TEXT;
        if (best == NOSHI_TYPING_CANCEL) best = entry->action;
    }
    return best;
}

@end

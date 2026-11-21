#import "noshi_search_history.h"

#import "noshi_person.h"

/* the keys of the first version held strings, "kind:id", and are read once for the chats the list still has */
static NSString *const NoshiSearchHistoryLegacyKey = @"NoshiRecentChats";
static NSString *const NoshiSearchHistoryPrefix = @"noshigram.search.history.";

static NSString *NoshiSearchHistoryKey(NoshiSession *session) {
    return [NoshiSearchHistoryPrefix stringByAppendingFormat:@"%lld", session.ownPerson.userId];
}

static BOOL NoshiSearchHistoryIsPeer(NSDictionary *record, NoshiDialog *dialog) {
    return [[record objectForKey:@"kind"] intValue] == dialog.peerKind && [[record objectForKey:@"id"] longLongValue] == dialog.peerId;
}

NSArray *NoshiSearchHistoryDialogs(NoshiSession *session, NSArray *dialogs) {
    NSMutableArray *found = [NSMutableArray array];
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:NoshiSearchHistoryKey(session)];
    if (!stored) {
        for (id key in [[NSUserDefaults standardUserDefaults] arrayForKey:NoshiSearchHistoryLegacyKey]) {
            if (![key isKindOfClass:[NSString class]]) continue;
            for (NoshiDialog *dialog in dialogs) {
                if (!dialog.folder && [[NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId] isEqualToString:key]) {
                    [found addObject:dialog];
                    break;
                }
            }
        }
        return found;
    }
    for (id record in stored) {
        if (![record isKindOfClass:[NSDictionary class]]) continue;
        NoshiDialog *match = nil;
        for (NoshiDialog *dialog in dialogs) {
            if (!dialog.folder && NoshiSearchHistoryIsPeer(record, dialog)) {
                match = dialog;
                break;
            }
        }
        if (!match && ![[record objectForKey:@"saved"] boolValue]) {
            match = [NoshiDialog dialogWithPeerKind:[[record objectForKey:@"kind"] intValue] peerId:[[record objectForKey:@"id"] longLongValue]
                                           accessHash:[[record objectForKey:@"hash"] longLongValue] kind:(noshi_dialog_kind)[[record objectForKey:@"dialogKind"] intValue]
                                                title:[record objectForKey:@"title"]];
        }
        if (match) [found addObject:match];
    }
    return found;
}

void NoshiSearchHistoryRemember(NoshiSession *session, NoshiDialog *dialog, NSArray *dialogs) {
    if (!dialog || dialog.folder) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = NoshiSearchHistoryKey(session);
    NSMutableArray *records = [NSMutableArray array];
    /* the first start of this version takes over what the first version kept, so nothing the person opened is lost */
    if (![defaults arrayForKey:key]) {
        for (NoshiDialog *older in NoshiSearchHistoryDialogs(session, dialogs)) {
            [records addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:older.peerKind], @"kind", [NSNumber numberWithLongLong:older.peerId], @"id",
                                [NSNumber numberWithLongLong:older.peerHash], @"hash", [NSNumber numberWithInt:(int)older.kind], @"dialogKind", older.title ?: @"", @"title",
                                [NSNumber numberWithBool:older.saved], @"saved", nil]];
        }
    } else {
        for (id record in [defaults arrayForKey:key]) if ([record isKindOfClass:[NSDictionary class]]) [records addObject:record];
    }
    for (NSUInteger i = records.count; i > 0; --i) if (NoshiSearchHistoryIsPeer([records objectAtIndex:i - 1], dialog)) [records removeObjectAtIndex:i - 1];
    [records insertObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:dialog.peerKind], @"kind", [NSNumber numberWithLongLong:dialog.peerId], @"id",
                           [NSNumber numberWithLongLong:dialog.peerHash], @"hash", [NSNumber numberWithInt:(int)dialog.kind], @"dialogKind", dialog.title ?: @"", @"title",
                           [NSNumber numberWithBool:dialog.saved], @"saved", nil] atIndex:0];
    while (records.count > NOSHI_SEARCH_HISTORY_MAX) [records removeLastObject];
    [defaults setObject:records forKey:key];
}

void NoshiSearchHistoryClear(NoshiSession *session) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSArray array] forKey:NoshiSearchHistoryKey(session)];
    [defaults removeObjectForKey:NoshiSearchHistoryLegacyKey];
}

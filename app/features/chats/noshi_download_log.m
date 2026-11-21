#import "noshi_download_log.h"

#import "noshi_chat_item.h"
#import "noshi_session_profile.h"

static NSString *NoshiDownloadLogPath(NoshiSession *session) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"];
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"downloads-%lld.plist", session.ownPerson.userId]];
}

static NSMutableArray *NoshiDownloadLogRead(NoshiSession *session) {
    NSArray *stored = [NSArray arrayWithContentsOfFile:NoshiDownloadLogPath(session)];
    NSMutableArray *records = [NSMutableArray array];
    for (id record in stored) if ([record isKindOfClass:[NSDictionary class]]) [records addObject:record];
    return records;
}

void NoshiDownloadLogAdd(NoshiSession *session, NoshiDialog *dialog, NoshiMessage *message) {
    NoshiMedia *media = message.media;
    if (!dialog || !media || message.messageId <= 0 || !media.file) return;
    noshi_preview_kind kind = media.kind;
    if (kind != NOSHI_PREVIEW_FILE && kind != NOSHI_PREVIEW_AUDIO && kind != NOSHI_PREVIEW_VOICE && kind != NOSHI_PREVIEW_VIDEO && kind != NOSHI_PREVIEW_GIF) return;
    NSString *name = media.name.length ? media.name : (media.title.length ? media.title : NoshiPreviewWord(kind));
    NSMutableArray *records = NoshiDownloadLogRead(session);
    for (NSUInteger i = records.count; i > 0; --i) {
        NSDictionary *record = [records objectAtIndex:i - 1];
        if ([[record objectForKey:@"kind"] intValue] == dialog.peerKind && [[record objectForKey:@"id"] longLongValue] == dialog.peerId &&
            [[record objectForKey:@"message"] intValue] == message.messageId) [records removeObjectAtIndex:i - 1];
    }
    [records insertObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:dialog.peerKind], @"kind", [NSNumber numberWithLongLong:dialog.peerId], @"id",
                           [NSNumber numberWithLongLong:dialog.peerHash], @"hash", [NSNumber numberWithInt:(int)dialog.kind], @"dialogKind", dialog.title ?: @"", @"chat",
                           [NSNumber numberWithInt:message.messageId], @"message", name, @"name", [NSNumber numberWithLongLong:media.size], @"size",
                           [NSNumber numberWithInt:(int)[[NSDate date] timeIntervalSince1970]], @"date", nil] atIndex:0];
    while (records.count > NOSHI_DOWNLOAD_LOG_MAX) [records removeLastObject];
    NSString *path = NoshiDownloadLogPath(session);
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![records writeToFile:path atomically:YES]) NSLog(@"noshigram: the list of downloads was not saved");
}

NSArray *NoshiDownloadLogDialogs(NoshiSession *session, NSString *query) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *record in NoshiDownloadLogRead(session)) {
        NSString *name = [record objectForKey:@"name"], *chat = [record objectForKey:@"chat"];
        if (query.length) {
            NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
            if ([name rangeOfString:query options:options].location == NSNotFound && [chat rangeOfString:query options:options].location == NSNotFound) continue;
        }
        NSString *line = [NSString stringWithFormat:@"%@ · %@", chat, NoshiFileSizeText([[record objectForKey:@"size"] longLongValue])];
        NoshiDialog *row = [NoshiDialog dialogWithPeerKind:[[record objectForKey:@"kind"] intValue] peerId:[[record objectForKey:@"id"] longLongValue]
                                                    accessHash:[[record objectForKey:@"hash"] longLongValue] kind:(noshi_dialog_kind)[[record objectForKey:@"dialogKind"] intValue]
                                                         title:name text:line date:[[record objectForKey:@"date"] intValue] messageId:[[record objectForKey:@"message"] intValue]];
        if (row) [rows addObject:row];
    }
    return rows;
}

#import "noshi_bookmark_store.h"

#import "noshi_files.h"

NSString *const NoshiBookmarksDidChangeNotification = @"NoshiBookmarksDidChange";

static NSString *NoshiBookmarkText(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiBookmark

- (id)initWithRow:(const noshi_bookmark *)row {
    self = [super init];
    if (!self) return nil;
    _row = *row;
    return self;
}

- (int32_t)messageId { return _row.message_id; }
- (int32_t)date { return _row.date; }
- (int32_t)added { return _row.added; }
- (NSString *)title { return NoshiBookmarkText(_row.title); }
- (NSString *)text { return NoshiBookmarkText(_row.text); }

- (NoshiDialog *)dialog {
    noshi_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = _row.peer_kind;
    row.peer_id = _row.peer_id;
    row.peer_hash = _row.peer_hash;
    row.kind = (noshi_dialog_kind)_row.dialog_kind;
    snprintf(row.title, sizeof(row.title), "%s", _row.title);
    return [[[NoshiDialog alloc] initWithRow:&row] autorelease];
}

- (BOOL)isFor:(const noshi_bookmark *)other {
    return _row.peer_kind == other->peer_kind && _row.peer_id == other->peer_id && _row.message_id == other->message_id;
}

@end

@interface NoshiBookmarks () {
    NSString *_path;
    long long _account;
    noshi_bookmarks *_list;
    NSArray *_entries;
}
@end

@implementation NoshiBookmarks

+ (NoshiBookmarks *)bookmarksForSession:(NoshiSession *)session {
    static NSMutableDictionary *cache;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    NSString *directory = session.directory;
    long long account = [NoshiSession accountIdInDirectory:directory];
    NSString *key = [NSString stringWithFormat:@"%@#%lld", directory, account];
    NoshiBookmarks *bookmarks = [cache objectForKey:key];
    if (!bookmarks) {
        bookmarks = [[[NoshiBookmarks alloc] initWithDirectory:directory account:account] autorelease];
        [cache setObject:bookmarks forKey:key];
    }
    return bookmarks;
}

- (id)initWithDirectory:(NSString *)directory account:(long long)account {
    self = [super init];
    if (!self) return nil;
    _path = [[directory stringByAppendingPathComponent:@"bookmarks.bin"] copy];
    _account = account;
    _list = calloc(1, sizeof(*_list));
    if (!_list) {
        NSLog(@"noshigram: no room for the bookmarks");
        [self release];
        return nil;
    }
    [self load];
    return self;
}

- (void)dealloc {
    free(_list);
    [_path release];
    [_entries release];
    [super dealloc];
}

/* a file of another account, or none, is an empty list; a damaged one is logged, and the next save replaces it */
- (void)load {
    noshi_bookmarks_init(_list);
    if (_account <= 0) return;
    uint8_t *buffer = malloc(NOSHI_BOOKMARKS_FILE_MAX + 1);
    size_t length = 0;
    if (!buffer) return;
    noshi_status read = NoshiReadFile(_path, buffer, NOSHI_BOOKMARKS_FILE_MAX + 1, &length);
    if (read == NOSHI_OK) {
        noshi_status status = noshi_bookmarks_unpack(buffer, length, _account, _list);
        if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) NSLog(@"noshigram: the bookmarks file is damaged: %s", noshi_status_name(status));
    }
    free(buffer);
    [self rebuild];
}

- (void)rebuild {
    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:_list->count];
    for (size_t i = 0; i < _list->count; ++i) [entries addObject:[[[NoshiBookmark alloc] initWithRow:&_list->items[i]] autorelease]];
    [_entries release];
    _entries = [entries copy];
}

- (NSArray *)entries {
    return _entries;
}

- (BOOL)save {
    if (_account <= 0) return NO;
    uint8_t *buffer = malloc(NOSHI_BOOKMARKS_FILE_MAX);
    size_t length = 0;
    if (!buffer) return NO;
    noshi_status status = noshi_bookmarks_pack(_list, _account, buffer, NOSHI_BOOKMARKS_FILE_MAX, &length);
    if (status == NOSHI_OK) status = NoshiWriteFile(_path, buffer, length);
    free(buffer);
    if (status != NOSHI_OK) NSLog(@"noshigram: the bookmarks were not saved: %s", noshi_status_name(status));
    return status == NOSHI_OK;
}

/* the list as it was is kept when the file cannot be written, so what the screen shows is what is on the disk */
- (BOOL)commit:(const noshi_bookmarks *)changed {
    noshi_bookmarks *previous = malloc(sizeof(*previous));
    if (!previous) return NO;
    memcpy(previous, _list, sizeof(*previous));
    memcpy(_list, changed, sizeof(*_list));
    BOOL saved = [self save];
    if (!saved) memcpy(_list, previous, sizeof(*_list));
    free(previous);
    if (!saved) return NO;
    [self rebuild];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiBookmarksDidChangeNotification object:self];
    return YES;
}

- (BOOL)containsMessageId:(int32_t)messageId inDialog:(NoshiDialog *)dialog {
    return noshi_bookmarks_contains(_list, dialog.peerKind, dialog.peerId, messageId);
}

/* the start of a message as a bookmark's line: one line, cut at a character that fits the entry */
static void NoshiCopyBookmarkText(char *out, size_t cap, NSString *text) {
    NSString *line = [[text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    NSUInteger used = 0;
    out[0] = 0;
    if (![line getBytes:out maxLength:cap - 1 usedLength:&used encoding:NSUTF8StringEncoding options:0 range:NSMakeRange(0, line.length)
               remainingRange:NULL]) used = 0;
    out[used] = 0;
}

- (BOOL)addMessageId:(int32_t)messageId date:(int32_t)date text:(NSString *)text inDialog:(NoshiDialog *)dialog {
    noshi_bookmark entry;
    memset(&entry, 0, sizeof(entry));
    entry.peer_kind = dialog.peerKind;
    entry.peer_id = dialog.peerId;
    entry.peer_hash = dialog.peerHash;
    entry.dialog_kind = (int32_t)dialog.kind;
    entry.message_id = messageId;
    entry.date = date;
    entry.added = (int32_t)[[NSDate date] timeIntervalSince1970];
    NoshiCopyBookmarkText(entry.title, sizeof(entry.title), dialog.title);
    NoshiCopyBookmarkText(entry.text, sizeof(entry.text), text);
    noshi_bookmarks *changed = malloc(sizeof(*changed));
    if (!changed) return NO;
    memcpy(changed, _list, sizeof(*changed));
    noshi_status status = noshi_bookmarks_add(changed, &entry);
    BOOL done = NO;
    if (status != NOSHI_OK) NSLog(@"noshigram: message %d was not bookmarked: %s", (int)messageId, noshi_status_name(status));
    else done = [self commit:changed];
    free(changed);
    return done;
}

- (BOOL)removeMessageId:(int32_t)messageId inDialog:(NoshiDialog *)dialog {
    noshi_bookmarks *changed = malloc(sizeof(*changed));
    if (!changed) return NO;
    memcpy(changed, _list, sizeof(*changed));
    BOOL done = NO;
    if (noshi_bookmarks_remove(changed, dialog.peerKind, dialog.peerId, messageId) == NOSHI_OK) done = [self commit:changed];
    free(changed);
    return done;
}

- (BOOL)removeEntry:(NoshiBookmark *)entry {
    return [self removeMessageId:entry.messageId inDialog:[entry dialog]];
}

@end

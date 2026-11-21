#import "noshi_reaction_people_controller.h"

#import "noshi_people_avatars.h"
#import "noshi_session_actions.h"
#import "noshi_person.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"
#import "noshi_custom_emoji.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_emoji_store.h"

#define REACTORS_MAX 500

@interface NoshiReactionPeopleController () {
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiMediaCache *_media;
    NoshiAvatarCache *_avatars;
    NoshiPeopleAvatars *_faces;
    int32_t _messageId;
    NSMutableArray *_reactors;
    NSMutableDictionary *_people;
    NSMutableSet *_offsets;
    NSString *_next;
    NSString *_error;
    BOOL _started;
    BOOL _loading;
    BOOL _limited;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiReactionPeopleController

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog messageId:(int32_t)messageId avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _media = [media retain];
    _avatars = [avatars retain];
    _messageId = messageId;
    _reactors = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _offsets = [[NSMutableSet alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chat.reactors.title", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(customEmojiLoaded:) name:NoshiCustomEmojiDidLoadNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_faces invalidate];
    [_faces release];
    [_avatars release];
    [_media release];
    [_reactors release];
    [_people release];
    [_offsets release];
    [_next release];
    [_error release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadNext];
}

- (void)themeDidChange { [self rebuild]; }

- (void)customEmojiLoaded:(NSNotification *)notification {
    long long document = [[notification object] longLongValue];
    for (NSDictionary *entry in _reactors) {
        NoshiReaction *reaction = [entry objectForKey:@"reaction"];
        if (reaction.row.kind == NOSHI_REACTION_CUSTOM && reaction.row.document_id == document) {
            if (self.isViewLoaded) [self rebuild];
            return;
        }
    }
}

UIImage *NoshiReactionRowImage(NoshiReaction *reaction) {
    if (reaction.row.kind == NOSHI_REACTION_CUSTOM) return [NoshiCustomEmoji imageForDocument:reaction.row.document_id];
    NSString *text = reaction.displayText;
    unichar units[64];
    size_t entry = 0;
    if (!text.length || text.length > 64) return nil;
    [text getCharacters:units range:NSMakeRange(0, text.length)];
    return noshi_emoji_single(units, text.length, &entry) ? NoshiEmojiImageNow(entry) : nil;
}

void NoshiLoadReactionDocuments(NSArray *items, NoshiSession *session, NoshiMediaCache *media, void (^done)(void)) {
    NSMutableArray *documents = [NSMutableArray array];
    for (NSDictionary *entry in items) {
        NoshiReaction *reaction = [entry objectForKey:@"reaction"];
        if (reaction.row.kind == NOSHI_REACTION_CUSTOM && reaction.row.document_id)
            [documents addObject:[NSNumber numberWithLongLong:reaction.row.document_id]];
    }
    if (!documents.count) return;
    [NoshiCustomEmojiLoader loadDocuments:documents session:session media:media documents:^(NSArray *found) {
        NSMutableDictionary *texts = [NSMutableDictionary dictionary];
        for (NoshiCustomEmojiDocument *document in found) [texts setObject:document.alt forKey:[NSNumber numberWithLongLong:document.documentId]];
        [NoshiReaction rememberCustomTexts:texts];
        if (done) done();
    } picture:nil];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in _reactors) {
        NSNumber *key = [entry objectForKey:@"peer"];
        NoshiPerson *person = [_people objectForKey:key];
        NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", key];
        int32_t date = [[entry objectForKey:@"date"] intValue];
        NSString *time = date > 0 ? NoshiMediaTimeText(date) : NSLocalizedString(@"chat.reactors.time.unknown", nil);
        NoshiReaction *reaction = [entry objectForKey:@"reaction"];
        UIImage *image = NoshiReactionRowImage(reaction);
        if (!_faces) {
            NoshiWeakReference *again = _weak;
            _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiReactionPeopleController *)again.target rebuild]; }];
        }
        UIImage *face = [_faces imageForKey:[NSString stringWithFormat:@"%@", key] initials:person.initials seed:(NSUInteger)([key longLongValue] % 1000003) deleted:person.deleted photo:person.photo];
        /* a row with a picture draws the name through the emoji label, which leaves out the characters of a styled nick that the system label shows as boxes */
        NoshiSettingsRow *row = [NoshiSettingsRow rowWithTileImage:face title:name subtitle:time tap:nil];
        row.trailingImage = image;
        row.trailingImageUnclipped = YES;
        [rows addObject:row];
    }
    NoshiWeakReference *weak = _weak;
    if (_loading) [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.loading", nil) value:nil tap:nil]];
    else if (_error) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.retry", nil) subtitle:_error value:nil tap:^{
            [(NoshiReactionPeopleController *)weak.target loadNext];
        }]];
    } else if (_next && _reactors.count < REACTORS_MAX) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"group.tab.more", nil) value:nil tap:^{
            [(NoshiReactionPeopleController *)weak.target loadNext];
        }]];
    } else if (_started && !_reactors.count) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.empty", nil) value:nil tap:nil]];
    }
    NSString *footer = _limited ? NSLocalizedString(@"chat.reactors.limit", nil) : nil;
    self.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}

- (void)loadNext {
    if (_loading || (_started && !_next && !_error) || _reactors.count >= REACTORS_MAX) return;
    NSString *cursor = [[_next copy] autorelease];
    _loading = YES;
    [_error release]; _error = nil;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadReactorsOfMessageId:_messageId ofDialog:_dialog offset:cursor completion:^(NSArray *items, NSDictionary *people, NSString *next, NSString *errorName) {
        NoshiReactionPeopleController *page = weak.target;
        if (!page) return;
        page->_loading = NO;
        page->_started = YES;
        if (errorName) {
            page->_error = [[NSString stringWithFormat:NSLocalizedString(@"chat.reactors.error", nil), errorName] copy];
        } else if (next && ([page->_offsets containsObject:next] || (cursor && [next isEqualToString:cursor]))) {
            page->_error = [NSLocalizedString(@"chat.reactors.badpage", nil) copy];
        } else {
            if (cursor) [page->_offsets addObject:cursor];
            [page->_people addEntriesFromDictionary:people];
            NSUInteger room = REACTORS_MAX - page->_reactors.count;
            NSUInteger take = MIN(room, items.count);
            if (take) [page->_reactors addObjectsFromArray:[items subarrayWithRange:NSMakeRange(0, take)]];
            NoshiLoadReactionDocuments(items, page->_session, page->_media, ^{
                NoshiReactionPeopleController *owner = weak.target;
                if (owner) [owner rebuild];
            });
            page->_limited = take < items.count || (next && page->_reactors.count >= REACTORS_MAX);
            [page->_next release];
            page->_next = [next copy];
        }
        [page rebuild];
    }];
}
@end

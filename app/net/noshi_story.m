#import "noshi_story.h"
#import "noshi_person.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *NoshiUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiStoryAudience

@synthesize base = _base;
@synthesize allowed = _allowed;
@synthesize denied = _denied;

+ (NoshiStoryAudience *)audienceWithBase:(noshi_story_privacy)base {
    NoshiStoryAudience *audience = [[[NoshiStoryAudience alloc] init] autorelease];
    audience->_base = base;
    return audience;
}

- (void)dealloc {
    [_allowed release];
    [_denied release];
    [super dealloc];
}

static uint16_t NoshiFillStoryUsers(NSArray *people, noshi_story_user *users) {
    uint16_t count = 0;
    for (NoshiPerson *person in people) {
        if (count >= NOSHI_STORY_USERS_MAX) break;
        /* the server names a user by id and access hash, so a person it never gave a hash for cannot be named */
        if (person.userId <= 0 || !person.accessHash) continue;
        users[count].id = person.userId;
        users[count].access_hash = person.accessHash;
        ++count;
    }
    return count;
}

- (void)fillAudience:(noshi_story_audience *)out {
    memset(out, 0, sizeof(*out));
    out->base = _base;
    if (_base == NOSHI_STORY_SELECTED) out->allow_count = NoshiFillStoryUsers(_allowed, out->allow);
    else if (_base != NOSHI_STORY_CLOSE_FRIENDS) out->deny_count = NoshiFillStoryUsers(_denied, out->deny);
}

@end

@implementation NoshiStory

@synthesize caption = _caption;
@synthesize media = _media;
@synthesize reaction = _reaction;

+ (NoshiStory *)storyWithRow:(const noshi_story_row *)row {
    NoshiStory *story = [[[NoshiStory alloc] init] autorelease];
    story->_row = *row;
    story->_caption = [NoshiUtf8(row->caption) copy];
    story->_media = [[NoshiMedia mediaWithInfo:&row->media] retain];
    if (row->music.ref.source != NOSHI_MEDIA_SOURCE_NONE) story->_music = [[NoshiMedia mediaWithInfo:&row->music] retain];
    if (row->reacted) story->_reaction = [[NoshiReaction reactionWithRow:&row->reaction] retain];
    return story;
}

- (void)dealloc {
    [_caption release];
    [_media release];
    [_music release];
    [_reaction release];
    [super dealloc];
}

- (NSString *)musicLine {
    if (!_music) return nil;
    NSString *performer = _music.performer, *title = _music.title;
    NSString *line = performer.length && title.length ? [NSString stringWithFormat:@"%@ \u00B7 %@", performer, title] : (title.length ? title : performer);
    return [line uppercaseString];
}

- (int32_t)storyId { return _row.id; }
- (int32_t)date { return _row.date; }
- (int32_t)expireDate { return _row.expire_date; }
- (int32_t)views { return _row.views; }
- (int32_t)reactions { return _row.reactions; }
- (BOOL)outgoing { return _row.out; }
- (BOOL)pinned { return _row.pinned; }
- (BOOL)closeFriends { return _row.close_friends; }
- (BOOL)noForwards { return _row.noforwards != 0; }
- (noshi_story_privacy)privacy { return noshi_story_row_privacy(&_row); }
- (BOOL)selectedAudience { return _row.selected != 0; }

@end

@implementation NoshiStoryPeer

@synthesize owner = _owner;
@synthesize maxReadId = _maxReadId;
@synthesize count = _count;
@synthesize unread = _unread;
@synthesize newestDate = _newestDate;
@synthesize firstUnreadId = _firstUnreadId;
@synthesize closeFriends = _closeFriends;

+ (NoshiStoryPeer *)peerWithRow:(const noshi_story_peer *)row {
    NoshiStoryPeer *peer = [[[NoshiStoryPeer alloc] init] autorelease];
    peer->_owner = [[NoshiDialog alloc] initWithRow:&row->owner];
    peer->_maxReadId = row->max_read_id;
    peer->_count = row->count;
    peer->_unread = row->unread;
    peer->_newestDate = row->newest_date;
    peer->_firstUnreadId = row->first_unread_id;
    peer->_closeFriends = row->close_friends != 0;
    return peer;
}

+ (NoshiStoryPeer *)peerWithOwner:(NoshiDialog *)owner count:(int32_t)count {
    NoshiStoryPeer *peer = [[[NoshiStoryPeer alloc] init] autorelease];
    peer->_owner = [owner retain];
    peer->_count = count;
    return peer;
}

- (void)dealloc {
    [_owner release];
    [super dealloc];
}

@end

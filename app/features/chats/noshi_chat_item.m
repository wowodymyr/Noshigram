#import "noshi_chat_item.h"
#import "noshi_album_layout.h"
#import "noshi_platform.h"

#import "noshi_person.h"
#import "noshi_service_line.h"
#import "noshi_dialog.h"
#import "noshi_plural.h"
#import "noshi_reactions_view.h"
#import "noshi_string_drawing.h"
#import "noshi_gift_screen.h"
#import "noshi_chat_settings.h"
#import "noshi_peer_colors.h"
#import "noshi_theme.h"
#import "noshi_imported_theme.h"
#import "noshi_emoji_store.h"
#import "noshi_music_player.h"
#import "noshi_developers.h"
#import "noshi_name_badge.h"
#import "noshi_time.h"

#define SIDE_MARGIN 8.0
#define AVATAR_SIDE 34.0
/* the picture and the gap after it */
#define AVATAR_COLUMN 40.0
#define PAD_X 11.0
#define PAD_TOP 6.0
#define PAD_BOTTOM 6.0
/* a picture runs to the edge of the bubble, as in the other clients; the bubble shows only around the caption and the time */
#define PICTURE_INSET 0.0
#define TIME_GAP 7.0
/* the plate of a quote: where the text starts, the room right of it, and the room above and below */
#define QUOTE_LEFT 17.0
#define QUOTE_RIGHT 10.0
#define QUOTE_PAD_Y 6.0
/* the room between the words of a bubble and the chips of its reactions */
#define REACTIONS_GAP 5.0
#define CHECK_WIDTH 20.0
#define META_HEIGHT 14.0
/* the eye before a view count, the gap after the count, the row of comments under a post, the round share button beside it and the
   room that button takes from the width of the bubble */
#define VIEWS_EYE 13.0
#define VIEWS_GAP 8.0
#define AUTHOR_WIDTH_MAX 140.0
#define AUTHOR_GAP 4.0
#define COMMENTS_HEIGHT 38.0
#define SHARE_SIDE 32.0
#define SHARE_ROOM 44.0
#define COMMENTS_MIN_WIDTH 214.0
#define FILE_HEIGHT 44.0
#define CALL_ICON 26.0
#define STICKER_SIDE 150.0
#define ROUND_SIDE_MAX 220.0
#define PHOTO_WIDTH_MAX 232.0
#define PHOTO_HEIGHT_MAX 320.0
#define PHOTO_WIDTH_MAX_PAD 360.0
#define PHOTO_HEIGHT_MAX_PAD 480.0
#define PHOTO_WIDTH_MIN 120.0
/* a tall picture is shown at least this share of the widest a picture goes, cut to fit, so its bubble and the words under it are not a thin column */
#define PHOTO_WIDTH_MIN_SHARE 0.72
#define SPACING_FAR 8.0
#define SPACING_NEAR 2.0
#define PILL_HEIGHT 24.0
#define TIME_SIZE 11.0
#define NAME_SIZE 13.0
#define MAX_BUBBLE_FRACTION 0.88
/* the widest a bubble gets; the text of a tablet is two points larger and its column wider */
#define BUBBLE_CAP_PHONE 380.0
#define BUBBLE_CAP_PAD 480.0
#define MARKUP_ROW 36.0
#define MARKUP_GAP 4.0
#define MARKUP_MIN_WIDTH 220.0

@implementation NoshiChatItem

@synthesize kind = _kind;
@synthesize singleEmoji = _singleEmoji;
@synthesize content = _content;
@synthesize message = _message;
@synthesize pillText = _pillText;
@synthesize sharingExpired = _sharingExpired;
@synthesize giftCard = _giftCard;
@synthesize senderName = _senderName;
@synthesize transcript = _transcript;
@synthesize senderTag = _senderTag;
@synthesize senderTagLayout = _senderTagLayout;
@synthesize senderTagOrigin = _senderTagOrigin;
@synthesize senderColor = _senderColor;
@synthesize forwardText = _forwardText;
@synthesize viaText = _viaText;
@synthesize replyTitle = _replyTitle;
@synthesize replyText = _replyText;
@synthesize replyEntities = _replyEntities;

@synthesize replyColor = _replyColor;
@synthesize replyFrame = _replyFrame;
@synthesize replyTitleLayout = _replyTitleLayout;
@synthesize replyTextLayout = _replyTextLayout;
@synthesize timeText = _timeText;
@synthesize viewsText = _viewsText;
@synthesize viewsWidth = _viewsWidth;
@synthesize authorText = _authorText;
@synthesize authorWidth = _authorWidth;
@synthesize deletedWidth = _deletedWidth;
@synthesize commentsText = _commentsText;
@synthesize commenterPeople = _commenterPeople;
@synthesize showsShare = _showsShare;
@synthesize bare = _bare;
@synthesize albumMessages = _albumMessages;
@synthesize albumFrames = _albumFrames;
@synthesize pollQuestionLayout = _pollQuestionLayout;
@synthesize pollQuestionOrigin = _pollQuestionOrigin;
@synthesize pollKindLayout = _pollKindLayout;
@synthesize pollVoterPeople = _pollVoterPeople;
@synthesize pollFooterOwnRow = _pollFooterOwnRow;
@synthesize pollFooterY = _pollFooterY;
@synthesize pollKindOrigin = _pollKindOrigin;
@synthesize pollAnswerLayouts = _pollAnswerLayouts;
@synthesize pollAnswerFrames = _pollAnswerFrames;
@synthesize pollShowsResults = _pollShowsResults;
@synthesize pollButtonFrame = _pollButtonFrame;
@synthesize pollButtonTitle = _pollButtonTitle;
@synthesize pollFooterText = _pollFooterText;
@synthesize reactionsHidden = _reactionsHidden;
@synthesize commentsFrame = _commentsFrame;
@synthesize shareFrame = _shareFrame;
@synthesize fileTitle = _fileTitle;
@synthesize fileDetail = _fileDetail;
@synthesize joinsPrevious = _joinsPrevious;
@synthesize joinsNext = _joinsNext;
@synthesize read = _read;
@synthesize textLayout = _textLayout;
@synthesize captionAbove = _captionAbove;
@synthesize pillLayout = _pillLayout;
@synthesize pillShift = _pillShift;
@synthesize senderLayout = _senderLayout;
@synthesize forwardLayout = _forwardLayout;
@synthesize viaLayout = _viaLayout;
@synthesize fileTitleLayout = _fileTitleLayout;
@synthesize fileDetailLayout = _fileDetailLayout;
@synthesize timeSize = _timeSize;
@synthesize height = _height;
@synthesize bubbleFrame = _bubbleFrame;
@synthesize senderPerson = _senderPerson;
@synthesize senderDeveloper = _senderDeveloper;
@synthesize pictureFrame = _pictureFrame;
@synthesize reactionFrame = _reactionFrame;
@synthesize reactionsInside = _reactionsInside;
@synthesize markup = _markup;
@synthesize markupFrame = _markupFrame;
@synthesize markupButtons = _markupButtons;
@synthesize fileFrame = _fileFrame;
@synthesize call = _call;
@synthesize callIncoming = _callIncoming;
@synthesize callFailed = _callFailed;
@synthesize callVideo = _callVideo;
@synthesize senderOrigin = _senderOrigin;
@synthesize forwardOrigin = _forwardOrigin;
@synthesize viaOrigin = _viaOrigin;
@synthesize textOrigin = _textOrigin;
@synthesize timeOrigin = _timeOrigin;

+ (NoshiChatItem *)pillWithText:(NSString *)text {
    NoshiChatItem *item = [[[NoshiChatItem alloc] init] autorelease];
    item->_kind = NoshiChatItemPill;
    item->_pillText = [text copy];
    return item;
}

static NSString *NoshiDurationText(int32_t seconds) {
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

NSString *NoshiFileSizeText(long long bytes) {
    if (bytes <= 0) return @"0 B";
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
}

/* the names of the people in a group take the color each person chose, or the one their id gives them (the classic theme keeps to the app's purple
   family, so no name comes out green or orange there) */
static UIColor *NoshiSenderColor(NoshiPerson *person, long long userId) {
    if (!NoshiThemeIsClassic()) return NoshiNameColor(person.nameColor, userId, NoshiThemeIsDark());
    static const CGFloat purples[][3] = {{0.52, 0.30, 0.78}, {0.68, 0.32, 0.74}, {0.42, 0.38, 0.84}, {0.78, 0.36, 0.64},
                                         {0.58, 0.26, 0.62}, {0.38, 0.44, 0.78}, {0.64, 0.44, 0.84}};
    NSUInteger index = (NSUInteger)NoshiDefaultNameColorId(userId);
    CGFloat boost = NoshiThemeIsDark() ? 0.12 : 0;
    return [UIColor colorWithRed:MIN(1, purples[index][0] + boost) green:MIN(1, purples[index][1] + boost) blue:MIN(1, purples[index][2] + boost) alpha:1];
}

/* what a gift service message says: who gave what, and the note that came with it */
static NSString *NoshiGiftText(NoshiMessage *message, NSString *who) {
    NSString *what = message.giftNumber > 0 ? [NSString stringWithFormat:@"%@ #%d", message.giftTitle, (int)message.giftNumber]
                                           : (message.giftTitle.length ? message.giftTitle : NSLocalizedString(@"gifts.gift", nil));
    NSString *price = message.giftStars > 0 ? [NSString stringWithFormat:@" (%@)", NoshiStarsText(message.giftStars)] : @"";
    NSString *line = message.outgoing ? [NSString stringWithFormat:NSLocalizedString(@"chat.service.gift.out", nil), what, price]
                                      : [NSString stringWithFormat:NSLocalizedString(@"chat.service.gift.in", nil), who, what, price];
    return message.text.length ? [NSString stringWithFormat:@"%@\n\u201c%@\u201d", line, message.text] : line;
}

/* the two lines over the note of a gift card: who gave it, and what it is */
static void NoshiGiftCardLines(NoshiMessage *message, NSString *who, NSString **title, NSString **subtitle) {
    NoshiStarGift *gift = message.gift;
    *title = message.outgoing ? NSLocalizedString(@"gifts.card.out", nil) : [NSString stringWithFormat:NSLocalizedString(@"gifts.card.from", nil), who];
    if (gift.unique) {
        *subtitle = [NSString stringWithFormat:@"%@ #%d", gift.title, (int)gift.number];
        return;
    }
    NSString *name = gift.title.length ? gift.title : NSLocalizedString(@"gifts.gift", nil);
    *subtitle = gift.stars > 0 ? [NSString stringWithFormat:@"%@ \u00b7 %@", name, NoshiStarsText(gift.stars)] : name;
}

static NSString *NoshiServiceText(NoshiMessage *message, NSDictionary *people) {
    /* a service line sent in the name of a channel (a video chat started by an anonymous admin or by the group itself) has no user id, and its sender is kept under the negative id of the channel */
    NoshiPerson *actor = [people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    NoshiPerson *target = [people objectForKey:[NSNumber numberWithLongLong:message.targetId]];
    NSString *who = actor.name.length ? actor.name : NSLocalizedString(@"chat.someone", nil);
    if (message.service - 1 == NOSHI_SERVICE_GIFT) return NoshiGiftText(message, who);
    if (message.outgoing && message.service - 1 == NOSHI_SERVICE_SHARING_REQUEST && !(message.serviceValue & 4))
        return NSLocalizedString((message.serviceValue & 2) ? @"chat.sharing.request.out.disable" : @"chat.sharing.request.out.enable", nil);
    if (message.outgoing && message.service - 1 == NOSHI_SERVICE_SHARING_TOGGLE && !!(message.serviceValue & 1) != !!(message.serviceValue & 2))
        return NSLocalizedString((message.serviceValue & 2) ? @"chat.sharing.changed.out.disable" : @"chat.sharing.changed.out.enable", nil);
    return NoshiServiceLine((noshi_service_kind)(message.service - 1), actor.name, target.name, message.text, message.serviceValue,
                              message.fromId == message.targetId);
}

BOOL NoshiMessageIsViewOnce(NoshiMessage *message) {
    NoshiMedia *media = message.media;
    if (!media.viewOnce) return NO;
    return media.kind == NOSHI_PREVIEW_PHOTO || media.kind == NOSHI_PREVIEW_VIDEO || media.kind == NOSHI_PREVIEW_VOICE || media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE;
}

BOOL NoshiViewOnceExpired(NoshiMessage *message) {
    if (message.viewOnceOpened) return YES;
    return !message.media.file && !(message.outgoing && message.pendingSend);
}

/* the words of a card of a one-time file: what it is, and whether it can still be opened */
static void NoshiViewOnceCaptions(NoshiMessage *message, NSString **title, NSString **detail) {
    NSString *key = @"viewonce.photo";
    switch (message.media.kind) {
    case NOSHI_PREVIEW_VIDEO: key = @"viewonce.video"; break;
    case NOSHI_PREVIEW_VOICE: key = @"viewonce.voice"; break;
    case NOSHI_PREVIEW_VIDEO_MESSAGE: key = @"viewonce.round"; break;
    default: break;
    }
    *title = NSLocalizedString(key, nil);
    BOOL expired = NoshiViewOnceExpired(message);
    if (message.outgoing) *detail = NSLocalizedString(expired ? @"viewonce.opened" : @"viewonce.sent", nil);
    else *detail = NSLocalizedString(expired ? @"viewonce.expired" : @"viewonce.tap", nil);
}

- (void)setSharingExpired:(BOOL)expired {
    _sharingExpired = expired;
    if (expired && _message.service == NOSHI_SERVICE_SHARING_REQUEST + 1) {
        [_pillText release];
        _pillText = [NSLocalizedString(@"chat.service.sharing.expired", nil) copy];
    }
}

- (void)captureMessage:(NoshiMessage *)message {
    _message = [message retain];
    _builtMessageId = message.messageId;
    _builtRandomId = message.randomId;
    _builtState = message.state;
    _builtEdited = message.edited;
    _builtOnceExpired = NoshiMessageIsViewOnce(message) && NoshiViewOnceExpired(message);
    _builtMediaUnread = message.mediaUnread;
    _builtService = message.service;
    _builtServiceValue = message.serviceValue;
    _builtText = [message.text copy];
    _builtReactionKey = [message.reactionKey copy];
    _builtMarkupKey = [message.markupKey copy];
    _builtPollKey = [message.pollKey copy];
}

static BOOL NoshiSameString(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

- (NSString *)highlightQuery { return _highlightQuery; }

/* the words reach a text that is laid out already as well as one that is laid out later */
- (void)setHighlightQuery:(NSString *)query {
    if (query == _highlightQuery || [query isEqualToString:_highlightQuery]) return;
    [_highlightQuery release];
    _highlightQuery = [query copy];
    _textLayout.highlight = _highlightQuery;
}

- (void)wordCommunityLineForDialog:(NoshiDialog *)dialog people:(NSDictionary *)people {
    if (!_message || _message.service - 1 != NOSHI_SERVICE_COMMUNITY || _kind != NoshiChatItemPill) return;
    int32_t value = _message.serviceValue;
    if (dialog.kind == NOSHI_DIALOG_CHANNEL) value |= NoshiCommunityChannel | NoshiCommunityUnknownActor;
    if (dialog.kind == NOSHI_DIALOG_BOT) value |= NoshiCommunityBot | NoshiCommunityUnknownActor;
    if (_message.outgoing) value |= NoshiCommunityByMe;
    /* the title belongs to the community the chat is in now: a line of an earlier one names no community rather than the wrong one */
    NSString *title = _message.serviceCommunity && _message.serviceCommunity == dialog.linkedCommunityId ? dialog.linkedCommunityTitle : nil;
    NoshiPerson *actor = [people objectForKey:[NSNumber numberWithLongLong:_message.senderKey]];
    [_pillText release];
    _pillText = [NoshiServiceLine(NOSHI_SERVICE_COMMUNITY, actor.name, nil, title, value, NO) copy];
}

- (BOOL)reflectsMessage:(NoshiMessage *)message {
    return _message && _message.replyTo == message.replyTo && _message.replyStory == message.replyStory && _message.sendReplyTo == message.sendReplyTo &&
           _message.replyPeerKind == message.replyPeerKind && _message.replyPeerId == message.replyPeerId && NoshiSameString(_message.replyQuote, message.replyQuote) &&
           _message.senderKey == message.senderKey && NoshiSameString(_message.senderRank, message.senderRank) &&
           _builtMessageId == message.messageId && _builtRandomId == message.randomId &&
           _builtState == message.state && _builtEdited == message.edited && _builtService == message.service && _builtServiceValue == message.serviceValue &&
           _builtOnceExpired == (NoshiMessageIsViewOnce(message) && NoshiViewOnceExpired(message)) &&
           _builtMediaUnread == message.mediaUnread &&
           NoshiSameString(_builtText, message.text) && NoshiSameString(_builtReactionKey, message.reactionKey) &&
           NoshiSameString(_builtMarkupKey, message.markupKey) && NoshiSameString(_builtPollKey, message.pollKey);
}

static NSString *NoshiSenderTag(NoshiMessage *message, NoshiPerson *person, NSString *role) {
    NSString *tag = message.senderRank.length ? message.senderRank : role;
    if (person.bot) {
        NSString *bot = NSLocalizedString(@"chat.status.bot", nil);
        return tag.length ? [NSString stringWithFormat:@"%@ \u00b7 %@", tag, bot] : bot;
    }
    return tag;
}

/* the color of the tag after a name goes by the role in the group and nothing else: the owner is purple and an administrator green, and every other tag (a title
   the owners gave, a bot) keeps the quiet grey; a title on an administrator is still green, since the role is what it says */
static UIColor *NoshiSenderTagColor(NSString *role) {
    if ([role isEqualToString:NSLocalizedString(@"chat.role.owner", nil)]) return [UIColor colorWithRed:0.60f green:0.34f blue:0.88f alpha:1];
    if ([role isEqualToString:NSLocalizedString(@"chat.role.admin", nil)]) return [UIColor colorWithRed:0.16f green:0.68f blue:0.40f alpha:1];
    return NoshiColorSecondary();
}

/* "via @bot" for a message that is the result of an inline bot, nil while the bot is not among the people or has no username */
static NSString *NoshiViaLine(NoshiMessage *message, NSDictionary *people) {
    if (!message.viaBotId) return nil;
    NoshiPerson *bot = [people objectForKey:[NSNumber numberWithLongLong:message.viaBotId]];
    if (![bot isKindOfClass:[NoshiPerson class]] || !bot.username.length) return nil;
    return [NSString stringWithFormat:NSLocalizedString(@"chat.via", nil), bot.username];
}

- (BOOL)reflectsPeople:(NSDictionary *)people role:(NSString *)role {
    /* the bot of a message may come in after the message did, and the line is then missing from the row that was laid out without it */
    if (!NoshiSameString(_viaText, NoshiViaLine(_message, people))) return NO;
    if (!_avatarColumn) return YES;
    NoshiPerson *sender = [people objectForKey:[NSNumber numberWithLongLong:_message.senderKey]];
    return NoshiSameString(_senderTag, NoshiSenderTag(_message, sender, role)) &&
           NoshiSameString(_senderPerson.name, sender.name) && NoshiSameString(_senderPerson.initials, sender.initials) &&
           _senderBadge == NoshiBadgeDocument(NoshiChatFlagGet(NoshiChatFlagShowMessageEmojiStatus) ? sender.emojiStatus : 0, sender.premium) && _senderDeveloper == NoshiPersonIsDeveloper(sender) &&
           NoshiSameString(_senderPerson.photo.key, sender.photo.key);
}

- (BOOL)isSameRowAs:(NoshiChatItem *)other {
    if (!_message || !other->_message) return !_message && !other->_message && NoshiSameString(_pillText, other->_pillText);
    if (_builtRandomId || other->_builtRandomId) return _builtRandomId == other->_builtRandomId;
    return _builtMessageId == other->_builtMessageId;
}

- (BOOL)displaysSameAs:(NoshiChatItem *)other {
    if (self == other) {
        return _joinsPrevious == _shownJoinsPrevious && _joinsNext == _shownJoinsNext && _read == _shownRead;
    }
    return !_message && !other->_message && NoshiSameString(_pillText, other->_pillText);
}

- (BOOL)hasDifferentReactionsFrom:(NoshiChatItem *)other {
    return other && _message && other->_message && !NoshiSameString(_builtReactionKey, other->_builtReactionKey);
}

- (void)markDisplayed {
    _shownJoinsPrevious = _joinsPrevious;
    _shownJoinsNext = _joinsNext;
    _shownRead = _read;
}

/* 79 as "79", 1234 as "1.2K", 1500000 as "1.5M" */
static NSString *NoshiShortCount(int32_t count) {
    if (count < 1000 || NoshiChatFlagGet(NoshiChatFlagExactNumbers)) return [NSString stringWithFormat:@"%d", (int)count];
    if (count < 1000000) return count < 10000 ? [NSString stringWithFormat:@"%d.%dK", (int)(count / 1000), (int)(count % 1000 / 100)] : [NSString stringWithFormat:@"%dK", (int)(count / 1000)];
    return [NSString stringWithFormat:@"%d.%dM", (int)(count / 1000000), (int)(count % 1000000 / 100000)];
}

/* "10 comments" with the plural form the language wants */
static NSString *NoshiCommentsLine(int32_t count) {
    if (count <= 0) return NSLocalizedString(@"channel.comments.none", nil);
    return [NSString stringWithFormat:NSLocalizedString([@"channel.comments." stringByAppendingString:NoshiPluralForm(count)], nil), (int)count];
}

/* what only a channel post has: the view count, the comments row and the button that shares it */
- (void)captureChannelPost:(NoshiMessage *)message people:(NSDictionary *)people {
    if (!message.post || message.messageId <= 0) return;
    _showsShare = !NoshiChatFlagGet(NoshiChatFlagHideShare);
    if (message.postAuthor.length) {
        /* the signature is a name the administrators chose, so a long one is cut and never pushes the time out of the bubble */
        NSString *name = message.postAuthor;
        NSString *line = [name stringByAppendingString:@","];
        UIFont *font = NoshiTimeFont();
        while (name.length > 1 && ceil(NoshiStringSize(line, font).width) > AUTHOR_WIDTH_MAX) {
            name = [name substringToIndex:name.length - 1];
            line = [[name stringByAppendingString:@"\u2026"] stringByAppendingString:@","];
        }
        _authorText = [line copy];
        _authorWidth = ceil(NoshiStringSize(_authorText, font).width) + AUTHOR_GAP;
    }
    if (message.views > 0) {
        _viewsText = [NoshiShortCount(message.views) copy];
        _viewsWidth = ceil(NoshiStringSize(_viewsText, NoshiTimeFont()).width) + VIEWS_EYE + 3 + VIEWS_GAP;
    }
    if (message.hasComments) {
        _commentsText = [NoshiCommentsLine(message.comments) copy];
        NSMutableArray *commenters = [NSMutableArray array];
        for (NSNumber *id in message.commenters) {
            NoshiPerson *person = [people objectForKey:id];
            if (person) [commenters addObject:person];
        }
        _commenterPeople = [commenters copy];
    }
}

+ (NoshiChatItem *)itemForMessage:(NoshiMessage *)message group:(BOOL)group people:(NSDictionary *)people {
    return [self itemForMessage:message group:group people:people role:nil];
}

NSString *NoshiForwardName(NoshiMessage *message, NSDictionary *people) {
    if (message.forwardName.length) return message.forwardName;
    NoshiPerson *origin = message.forwardKey ? [people objectForKey:[NSNumber numberWithLongLong:message.forwardKey]] : nil;
    return origin.name.length ? origin.name : @"";
}

/* how a call is named: who made it, how it ended, and whether it had video */
static NSString *NoshiCallTitle(NoshiMessage *message, BOOL *incoming, BOOL *failed) {
    BOOL missed = message.callOutcome == NOSHI_OUTCOME_MISSED;
    BOOL busy = message.callOutcome == NOSHI_OUTCOME_BUSY;
    BOOL video = message.callVideo;
    *incoming = !message.outgoing;
    *failed = *incoming && (missed || busy);
    NSString *kind = message.outgoing ? (missed ? @"cancelled" : @"out") : (missed ? @"missed" : (busy ? @"declined" : @"in"));
    NSString *key = [NSString stringWithFormat:video ? @"chat.call.video.%@" : @"chat.call.%@", kind];
    return NSLocalizedString(key, nil);
}

/* 20 seconds as "20 sec.", 65 as "1 min. 5 sec.", 3700 as "1 h. 1 min." */
static NSString *NoshiCallLength(int32_t seconds) {
    if (seconds < 60) return [NSString stringWithFormat:NSLocalizedString(@"chat.call.sec", nil), (int)seconds];
    if (seconds < 3600) {
        NSString *minutes = [NSString stringWithFormat:NSLocalizedString(@"chat.call.min", nil), (int)(seconds / 60)];
        return seconds % 60 ? [NSString stringWithFormat:@"%@ %@", minutes, [NSString stringWithFormat:NSLocalizedString(@"chat.call.sec", nil), (int)(seconds % 60)]] : minutes;
    }
    NSString *hours = [NSString stringWithFormat:NSLocalizedString(@"chat.call.hour", nil), (int)(seconds / 3600)];
    return seconds % 3600 >= 60 ? [NSString stringWithFormat:@"%@ %@", hours, [NSString stringWithFormat:NSLocalizedString(@"chat.call.min", nil), (int)(seconds % 3600 / 60)]] : hours;
}

static NSString *NoshiAlbumKey(NSArray *messages) {
    NSMutableString *key = [NSMutableString string];
    for (NoshiMessage *message in messages) [key appendFormat:@"%d:%lld:%lu;", message.messageId, message.randomId, (unsigned long)message.text.hash];
    return key;
}

+ (NoshiChatItem *)itemForAlbum:(NSArray *)messages group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role {
    /* pictures with one file, as a post of a channel can carry: the file owns the bubble, so its row, its progress and its taps are the ones of any file, and the
       pictures are the collage above it. the words may be on a picture, and then the bubble borrows them */
    NSMutableArray *pictures = [NSMutableArray array];
    NoshiMessage *fileMessage = nil;
    for (NoshiMessage *message in messages) {
        noshi_preview_kind kind = message.media.kind;
        if (kind == NOSHI_PREVIEW_PHOTO || kind == NOSHI_PREVIEW_VIDEO) [pictures addObject:message];
        else if (kind == NOSHI_PREVIEW_FILE && !fileMessage) fileMessage = message;
    }
    if (fileMessage && pictures.count && pictures.count + 1 == messages.count) {
        NoshiChatItem *item = [self itemForMessage:fileMessage group:group people:people role:role];
        item->_albumMessages = [pictures copy];
        item->_builtAlbumKey = [NoshiAlbumKey(messages) copy];
        if (!fileMessage.text.length) for (NoshiMessage *picture in pictures) if (picture.text.length) { item->_captionMessage = [picture retain]; break; }
        return item;
    }
    NoshiMessage *primary = [messages objectAtIndex:0];
    for (NoshiMessage *message in messages) if (message.text.length) { primary = message; break; }
    NoshiChatItem *item = [self itemForMessage:primary group:group people:people role:role];
    if (messages.count < 2) return item;
    item->_albumMessages = [messages copy];
    item->_builtAlbumKey = [NoshiAlbumKey(messages) copy];
    item->_content = NoshiChatItemContentPicture;
    return item;
}

- (BOOL)reflectsAlbum:(NSArray *)messages {
    if (!_albumMessages) return messages.count < 2;
    return NoshiSameString(_builtAlbumKey, NoshiAlbumKey(messages));
}

- (NoshiMessage *)albumMessageAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _albumFrames.count; ++i) {
        if (CGRectContainsPoint([[_albumFrames objectAtIndex:i] CGRectValue], point)) return [_albumMessages objectAtIndex:i];
    }
    return nil;
}

+ (NoshiChatItem *)itemForMessage:(NoshiMessage *)message group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role {
    BOOL isCall = message.service - 1 == NOSHI_SERVICE_CALL;
    if (message.service && !isCall) {
        NoshiChatItem *pill = [NoshiChatItem pillWithText:NoshiServiceText(message, people)];
        [pill captureMessage:message];
        pill.sharingExpired = (message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 && (message.serviceValue & 4));
        if (message.service - 1 == NOSHI_SERVICE_GIFT && message.gift) {
            NoshiPerson *actor = [people objectForKey:[NSNumber numberWithLongLong:message.fromId]];
            NSString *who = actor.name.length ? actor.name : NSLocalizedString(@"chat.someone", nil);
            NoshiGiftCardLines(message, who, &pill->_giftTitle, &pill->_giftSubtitle);
            [pill->_giftTitle retain];
            [pill->_giftSubtitle retain];
        }
        return pill;
    }
    NoshiChatItem *item = [[[NoshiChatItem alloc] init] autorelease];
    [item captureMessage:message];
    /* a pencil takes less of the bubble than the word */
    NSString *editedMark = NoshiChatFlagGet(NoshiChatFlagEditedIcon) ? @"\u270E" : NSLocalizedString(@"chat.edited", nil);
    NSString *clock = message.edited ? [NSString stringWithFormat:@"%@ %@", editedMark, NoshiClockText(message.date)] : NoshiClockText(message.date);
    /* a message the other side deleted and the phone kept has a trash can before its time */
    item->_timeText = [clock copy];
    [item captureChannelPost:message people:people];
    NoshiMedia *media = message.media;
    BOOL sticker = media.kind == NOSHI_PREVIEW_STICKER && (media.file || media.previewFile);
    BOOL once = NoshiMessageIsViewOnce(message);
    BOOL round = media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE && !message.text.length && !once;
    item->_kind = sticker ? NoshiChatItemSticker : (round ? NoshiChatItemRound : NoshiChatItemBubble);
    if ((media.kind == NOSHI_PREVIEW_NONE || media.kind == NOSHI_PREVIEW_TEXT) &&
        !message.entities.count && !message.forwarded && !message.post && !message.markup && message.text.length <= 32 && NoshiChatLargeEmoji()) {
        uint16_t units[32];
        size_t entry = 0;
        [message.text getCharacters:units range:NSMakeRange(0, message.text.length)];
        if (noshi_emoji_single(units, message.text.length, &entry)) {
            item->_kind = NoshiChatItemEmoji;
            item->_singleEmoji = entry;
        }
    }
    /* a game emoji the server threw (a dice, darts, a ball, bowling, slots) has no text: it is drawn as a large emoji, animated when its set arrives, so the message shows from the
       moment it is sent. an emoji the picture pack does not draw falls to the line of the case below */
    if (media.kind == NOSHI_PREVIEW_DICE && media.alt.length && media.alt.length <= 16) {
        uint16_t units[16];
        size_t entry = 0;
        [media.alt getCharacters:units range:NSMakeRange(0, media.alt.length)];
        if (noshi_emoji_single(units, media.alt.length, &entry)) {
            item->_kind = NoshiChatItemEmoji;
            item->_singleEmoji = entry;
        }
    }
    /* anonymous admin messages use the group identity stored at key zero */
    if (group && !message.outgoing && !message.post) {
        NoshiPerson *person = [people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
        item->_avatarColumn = YES;
        item->_senderPerson = [person retain];
        if (person.name.length) {
            item->_senderName = [person.name copy];
            item->_senderBadge = NoshiBadgeDocument(NoshiChatFlagGet(NoshiChatFlagShowMessageEmojiStatus) ? person.emojiStatus : 0, person.premium);
            item->_senderDeveloper = NoshiPersonIsDeveloper(person);
            item->_senderTag = [NoshiSenderTag(message, person, role) copy];
            item->_senderTagColor = [NoshiSenderTagColor(role) retain];
            item->_senderColor = [NoshiSenderColor(person, llabs(message.senderKey)) retain];
        }
    }
    if (message.forwarded) {
        NSString *origin = NoshiForwardName(message, people);
        NSString *line = origin.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.forwarded.from", nil), origin] : NSLocalizedString(@"chat.forwarded", nil);
        if (message.forwardDate > 0 && NoshiChatFlagGet(NoshiChatFlagForwardDate)) line = [NSString stringWithFormat:@"%@ \u00b7 %@", line, NoshiDayText(message.forwardDate)];
        item->_forwardText = [line copy];
    }
    item->_viaText = [NoshiViaLine(message, people) copy];
    if (isCall) {
        BOOL incoming = NO, failed = NO;
        item->_call = YES;
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NoshiCallTitle(message, &incoming, &failed) copy];
        item->_callIncoming = incoming;
        item->_callFailed = failed;
        item->_callVideo = message.callVideo;
        item->_fileDetail = [(message.serviceValue > 0 ? [NSString stringWithFormat:@"%@, %@", NoshiClockText(message.date), NoshiCallLength(message.serviceValue)]
                                                       : NoshiClockText(message.date)) copy];
        return item;
    }
    /* what stands in the bubble above the text */
    BOOL picture = noshi_media_uses_picture(media.kind, media.file != nil, media.previewFile != nil,
                                            message.localPreview != nil);
    if (once) {
        NSString *title = nil, *detail = nil;
        NoshiViewOnceCaptions(message, &title, &detail);
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [title copy];
        item->_fileDetail = [detail copy];
    } else switch (media.kind) {
    case NOSHI_PREVIEW_PHOTO:
        if (picture) item->_content = NoshiChatItemContentPicture;
        else { item->_content = NoshiChatItemContentFile; item->_fileTitle = [NSLocalizedString(@"preview.photo", nil) copy]; }
        break;
    case NOSHI_PREVIEW_VIDEO:
    case NOSHI_PREVIEW_VIDEO_MESSAGE:
    case NOSHI_PREVIEW_GIF:
        if (picture) item->_content = NoshiChatItemContentPicture;
        else {
            item->_content = NoshiChatItemContentFile;
            item->_fileTitle = [(media.kind == NOSHI_PREVIEW_GIF ? NSLocalizedString(@"preview.gif", nil) : NSLocalizedString(@"preview.video", nil)) copy];
            item->_fileDetail = [(media.duration ? NoshiDurationText(media.duration) : @"") copy];
        }
        break;
    case NOSHI_PREVIEW_VOICE:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.voice", nil) copy];
        item->_fileDetail = [NoshiDurationText(media.duration) copy];
        break;
    case NOSHI_PREVIEW_AUDIO:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NoshiTrackTitle(media) copy];
        item->_fileDetail = [(NoshiTrackPerformer(media).length ? [NSString stringWithFormat:@"%@, %@", NoshiTrackPerformer(media), NoshiDurationText(media.duration)]
                                                                 : NoshiDurationText(media.duration)) copy];
        break;
    case NOSHI_PREVIEW_FILE:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [(media.name.length ? media.name : NSLocalizedString(@"preview.file", nil)) copy];
        item->_fileDetail = [NoshiFileSizeText(media.size) copy];
        break;
    case NOSHI_PREVIEW_LOCATION:
        item->_content = media.location.valid ? NoshiChatItemContentPicture : NoshiChatItemContentFile;
        if (!media.location.valid) item->_fileTitle = [NSLocalizedString(@"map.invalid", nil) copy];
        break;
    case NOSHI_PREVIEW_CONTACT:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.contact", nil) copy];
        break;
    case NOSHI_PREVIEW_POLL:
        /* a poll the reader could not use keeps the plain line */
        if (message.poll) {
            item->_content = NoshiChatItemContentPoll;
            NSMutableArray *voters = [NSMutableArray array];
            for (NSNumber *voter in message.poll.recentVoters) {
                NoshiPerson *person = [people objectForKey:voter];
                if (person) [voters addObject:person];
            }
            item->_pollVoterPeople = [voters copy];
        } else {
            item->_content = NoshiChatItemContentFile;
            item->_fileTitle = [NSLocalizedString(@"preview.poll", nil) copy];
        }
        break;
    case NOSHI_PREVIEW_DICE:
        if (item->_kind != NoshiChatItemEmoji) {
            item->_content = NoshiChatItemContentFile;
            item->_fileTitle = [(media.alt.length ? media.alt : NSLocalizedString(@"chat.unsupported", nil)) copy];
        }
        break;
    case NOSHI_PREVIEW_STICKER:
        if (!sticker) { item->_content = NoshiChatItemContentFile; item->_fileTitle = [NSLocalizedString(@"preview.sticker", nil) copy]; }
        break;
    case NOSHI_PREVIEW_PAID:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.paid", nil) copy];
        item->_fileDetail = [[NSString stringWithFormat:NSLocalizedString(@"chat.paid.unlock", nil), media.paidStars] copy];
        break;
    case NOSHI_PREVIEW_STORY:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"preview.story", nil) copy];
        break;
    case NOSHI_PREVIEW_OTHER:
        item->_content = NoshiChatItemContentFile;
        item->_fileTitle = [NSLocalizedString(@"chat.unsupported", nil) copy];
        break;
    case NOSHI_PREVIEW_NONE:
    case NOSHI_PREVIEW_TEXT:
        /* a message of a kind the client does not read arrives with no text and no media; an empty bubble with only a clock says nothing */
        if (!message.text.length && !message.markup && !message.poll && !message.gift && !message.service) {
            item->_content = NoshiChatItemContentFile;
            item->_fileTitle = [NSLocalizedString(@"chat.unsupported", nil) copy];
        }
        break;
    case NOSHI_PREVIEW_SERVICE:
        break;
    }
    return item;
}

- (void)showOpenChatRow {
    [_commentsText release];
    _commentsText = [NSLocalizedString(@"chat.replies.open", nil) copy];
}

- (void)dropForwardText {
    [_forwardText release];
    _forwardText = nil;
}

- (void)dealloc {
    [_message release];
    [_builtText release];
    [_builtReactionKey release];
    [_builtMarkupKey release];
    [_markup release];
    [_markupButtons release];
    [_pillText release];
    [_giftTitle release];
    [_giftSubtitle release];
    [_giftCard release];
    [_senderName release];
    [_transcript release];
    [_senderTag release];
    [_senderTagColor release];
    [_senderTagLayout release];
    [_senderPerson release];
    [_senderColor release];
    [_forwardText release];
    [_viaText release];
    [_replyTitle release];
    [_replyText release];
    [_replyEntities release];
    [_highlightQuery release];
    [_replyColor release];
    [_replyTitleLayout release];
    [_replyTextLayout release];
    [_timeText release];
    [_viewsText release];
    [_authorText release];
    [_commentsText release];
    [_commenterPeople release];
    [_pollQuestionLayout release];
    [_pollKindLayout release];
    [_pollVoterPeople release];
    [_pollAnswerLayouts release];
    [_pollAnswerFrames release];
    [_pollButtonTitle release];
    [_pollFooterText release];
    [_builtPollKey release];
    [_albumMessages release];
    [_captionMessage release];
    [_albumFrames release];
    [_builtAlbumKey release];
    [_fileTitle release];
    [_fileDetail release];
    [_textLayout release];
    [_pillLayout release];
    [_senderLayout release];
    [_forwardLayout release];
    [_viaLayout release];
    [_fileTitleLayout release];
    [_fileDetailLayout release];
    [super dealloc];
}

- (BOOL)hasAvatarColumn {
    return _avatarColumn;
}

/* the picture stands under the last message of a run by one person, the others of the run leave its place empty */
- (BOOL)showsAvatar {
    return _avatarColumn && !_joinsNext;
}

- (CGFloat)incomingLeft {
    return _avatarColumn ? SIDE_MARGIN + AVATAR_COLUMN : SIDE_MARGIN;
}

- (void)invalidateLayout {
    _layoutWidth = 0;
}

static UIFont *NoshiTimeFont(void) { return NoshiFontRegular(TIME_SIZE); }

/* the picture's size at the width the bubble allows, in the proportions the file reports */
/* how many pictures stand in each row of a collage of this many; one picture in a row is wider than tall, two or three are square */
static const int NoshiAlbumRows[11][4] = {{0}, {0}, {2}, {1, 2}, {2, 2}, {2, 3}, {3, 3}, {1, 3, 3}, {2, 3, 3}, {3, 3, 3}, {1, 3, 3, 3}};
#define ALBUM_GAP 2.0
#define ALBUM_WIDTH_MAX 260.0

static CGFloat NoshiAlbumFill(NSMutableArray *frames, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    [frames addObject:[NSValue valueWithCGRect:CGRectMake(x, y, width, height)]];
    return height;
}

/* a column or a row of pictures split by their proportions; each takes a share of the length that is in step with
   how much room its picture needs, so the pictures of a collage keep close to their own shape and are not all cut
   to squares. ratios are width over height */
static void NoshiAlbumStack(NSMutableArray *frames, NSArray *ratios, NSUInteger first, NSUInteger count, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    CGFloat total = 0;
    for (NSUInteger i = 0; i < count; ++i) total += 1 / [[ratios objectAtIndex:first + i] floatValue];
    CGFloat room = height - (CGFloat)(count - 1) * ALBUM_GAP, used = 0;
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat part = i + 1 == count ? room - used : round(room * (1 / [[ratios objectAtIndex:first + i] floatValue]) / total);
        NoshiAlbumFill(frames, x, y + used + (CGFloat)i * ALBUM_GAP, width, part);
        used += part;
    }
}

/* the rows of a collage in a width, as rects from the top left, and the height they take */
CGFloat NoshiAlbumLayout(NSArray *ratios, CGFloat width, NSMutableArray *frames) {
    NSUInteger count = ratios.count;
    if (count < 2 || count > 10) return 0;
    CGFloat limit = floor(width * 1.0);
    CGFloat r0 = [[ratios objectAtIndex:0] floatValue], r1 = [[ratios objectAtIndex:1] floatValue];
    BOOL wide0 = r0 > 1.2, tall0 = r0 < 0.8;
    if (count == 2) {
        CGFloat average = (r0 + r1) / 2;
        if (r0 > 1.2 && r1 > 1.2 && average > 1.4) {
            /* two wide pictures stand one over the other */
            CGFloat h0 = round(MIN(width / r0, (limit - ALBUM_GAP) / 2)), h1 = round(MIN(width / r1, (limit - ALBUM_GAP) / 2));
            NoshiAlbumFill(frames, 0, 0, width, h0);
            NoshiAlbumFill(frames, 0, h0 + ALBUM_GAP, width, h1);
            return h0 + ALBUM_GAP + h1;
        }
        CGFloat room = width - ALBUM_GAP;
        CGFloat second = MAX(round(0.4 * room), round(room / r0 / (1 / r0 + 1 / r1)));
        CGFloat firstWidth = room - second;
        CGFloat height = MIN(limit, round(MIN(firstWidth / r0, second / r1)));
        NoshiAlbumFill(frames, 0, 0, firstWidth, height);
        NoshiAlbumFill(frames, firstWidth + ALBUM_GAP, 0, second, height);
        return height;
    }
    if (count == 3) {
        CGFloat r2 = [[ratios objectAtIndex:2] floatValue];
        if (tall0) {
            /* a tall one on the left, the other two stacked on its right */
            CGFloat left = round(MIN(limit * r0, 0.6 * width));
            CGFloat height = MIN(limit, round(left / r0));
            NoshiAlbumFill(frames, 0, 0, left, height);
            NoshiAlbumStack(frames, ratios, 1, 2, left + ALBUM_GAP, 0, width - left - ALBUM_GAP, height);
            return height;
        }
        CGFloat top = round(MIN(width / r0, limit * 0.55));
        NoshiAlbumFill(frames, 0, 0, width, top);
        CGFloat half = floor((width - ALBUM_GAP) / 2);
        CGFloat row = MIN(round(MIN(half / r1, half / r2)), limit - top - ALBUM_GAP);
        NoshiAlbumFill(frames, 0, top + ALBUM_GAP, half, row);
        NoshiAlbumFill(frames, half + ALBUM_GAP, top + ALBUM_GAP, width - half - ALBUM_GAP, row);
        return top + ALBUM_GAP + row;
    }
    if (count == 4) {
        if (wide0) {
            /* a wide one on top, the other three in a row under it */
            CGFloat top = round(MIN(width / r0, limit * 0.5));
            NoshiAlbumFill(frames, 0, 0, width, top);
            CGFloat each = floor((width - 2 * ALBUM_GAP) / 3), row = 0;
            for (NSUInteger i = 1; i < 4; ++i) {
                CGFloat h = round(each / [[ratios objectAtIndex:i] floatValue]);
                row = row ? MIN(row, h) : h;
            }
            row = MIN(row, limit - top - ALBUM_GAP);
            for (NSUInteger i = 0; i < 3; ++i) {
                CGFloat w = i == 2 ? width - 2 * (each + ALBUM_GAP) : each;
                NoshiAlbumFill(frames, (CGFloat)i * (each + ALBUM_GAP), top + ALBUM_GAP, w, row);
            }
            return top + ALBUM_GAP + row;
        }
        CGFloat left = round(MIN(limit * r0, 0.55 * width));
        CGFloat height = MIN(limit, round(left / r0));
        NoshiAlbumFill(frames, 0, 0, left, height);
        NoshiAlbumStack(frames, ratios, 1, 3, left + ALBUM_GAP, 0, width - left - ALBUM_GAP, height);
        return height;
    }
    CGFloat y = 0;
    NSUInteger at = 0;
    for (int row = 0; row < 4 && NoshiAlbumRows[count][row]; ++row) {
        int columns = NoshiAlbumRows[count][row];
        CGFloat side = floor((width - (CGFloat)(columns - 1) * ALBUM_GAP) / (CGFloat)columns);
        CGFloat height = columns == 1 ? floor(width * 0.66) : side;
        for (int column = 0; column < columns; ++column, ++at) {
            [frames addObject:[NSValue valueWithCGRect:CGRectMake((side + ALBUM_GAP) * (CGFloat)column, y, columns == 1 ? width : side, height)]];
        }
        y += height + ALBUM_GAP;
    }
    return y - ALBUM_GAP;
}

static CGSize NoshiPictureSize(NoshiMedia *media, CGFloat widthMax) {
    CGFloat w = media.width > 0 ? media.width : 4, h = media.height > 0 ? media.height : 3;
    CGFloat limit = MIN(widthMax, NoshiIsPad() ? PHOTO_WIDTH_MAX_PAD : PHOTO_WIDTH_MAX);
    CGFloat heightMax = NoshiIsPad() ? PHOTO_HEIGHT_MAX_PAD : PHOTO_HEIGHT_MAX;
    CGFloat scale = MIN(limit / w, heightMax / h);
    CGFloat width = MAX(MIN(w * scale, limit), MIN(MAX(PHOTO_WIDTH_MIN, limit * PHOTO_WIDTH_MIN_SHARE), limit));
    CGFloat height = MIN(h * scale, heightMax);
    if (width > w * scale) height = MIN(height * width / (w * scale), heightMax);
    return CGSizeMake(ceil(width), ceil(height));
}

- (void)layoutGiftCardForWidth:(CGFloat)width {
    CGFloat cardWidth = floor(MIN(width - 2 * SIDE_MARGIN, MAX(200.0, MIN(260.0, width * 0.66))));
    [_giftCard release];
    _giftCard = [[NoshiGiftCardLayout layoutForGift:_message.gift title:_giftTitle subtitle:_giftSubtitle note:_message.text width:cardWidth] retain];
    _bubbleFrame = CGRectMake(floor((width - cardWidth) / 2), 6, cardWidth, _giftCard.size.height);
    _height = _giftCard.size.height + 12;
}

- (void)layoutPillForWidth:(CGFloat)width {
    if (_giftTitle && _message.gift) {
        [self layoutGiftCardForWidth:width];
        return;
    }
    [_pillLayout release];
    /* plain grey text lost against a chat wallpaper (a pinned or renamed line over a photo), so the classic line stands on a light capsule too, in white text */
    UIColor *pillColor = [UIColor whiteColor];
    _pillLayout = [[NoshiTextLayout layoutForText:_pillText entities:nil font:NoshiFontMedium(12) color:pillColor
                                          linkColor:pillColor width:width - 2 * SIDE_MARGIN - 24 maxLines:2 flush:0.5] retain];
    _pillShift = floor((width - 2 * SIDE_MARGIN - 24 - _pillLayout.size.width) / 2);
    CGFloat pillWidth = ceil(_pillLayout.size.width) + 22;
    CGFloat pillHeight = MAX(PILL_HEIGHT, ceil(_pillLayout.size.height) + 10);
    _bubbleFrame = CGRectMake(floor((width - pillWidth) / 2), 6, pillWidth, pillHeight);
    _height = pillHeight + 10;
    if (_message.service == NOSHI_SERVICE_SHARING_REQUEST + 1 && !_message.outgoing && !_sharingExpired && _message.messageId > 0)
        _height += 45;
}

- (NSArray *)shownReactions {
    return _reactionsHidden ? nil : _message.reactions;
}

- (void)layoutStickerForWidth:(CGFloat)width {
    NoshiMedia *media = _message.media;
    CGFloat w = _kind != NoshiChatItemEmoji && media.width > 0 ? media.width : 512;
    CGFloat h = _kind != NoshiChatItemEmoji && media.height > 0 ? media.height : 512;
    /* only a sticker follows the size setting; the large emoji keep theirs */
    CGFloat side = _kind == NoshiChatItemSticker ? STICKER_SIDE * NoshiChatStickerScale() / 100.0 : STICKER_SIDE;
    CGFloat scale = MIN(side, width - 2 * SIDE_MARGIN) / MAX(w, h);
    CGSize picture = CGSizeMake(MAX(60, floor(w * scale)), MAX(60, floor(h * scale)));
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - picture.width : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, picture.width, picture.height);
    _pictureFrame = CGRectMake(0, 0, picture.width, picture.height);
    CGFloat metaWidth = NoshiStringSize(_timeText, NoshiTimeFont()).width + _authorWidth + _viewsWidth + _deletedWidth + (_message.outgoing ? CHECK_WIDTH : 0);
    _timeSize = CGSizeMake(ceil(metaWidth) + 10, 18);
    _timeOrigin = CGPointMake(picture.width - _timeSize.width - 4, picture.height - _timeSize.height - 4);
    _height = top + picture.height + 1;
}

/* the time sits below the circle, clear of the playback ring */
- (void)layoutRoundForWidth:(CGFloat)width {
    CGFloat side = MIN(ROUND_SIDE_MAX, floor(width * 0.62));
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - side : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, side, side);
    _pictureFrame = CGRectMake(0, 0, side, side);
    CGFloat metaWidth = NoshiStringSize(_timeText, NoshiTimeFont()).width + _authorWidth + _viewsWidth + _deletedWidth + (_message.outgoing ? CHECK_WIDTH : 0);
    _timeSize = CGSizeMake(ceil(metaWidth) + 10, 18);
    _timeOrigin = CGPointMake(side - _timeSize.width, side + 2);
    _height = top + side + _timeSize.height + 3;
}

#pragma mark poll

#define POLL_MARK 20.0
#define POLL_PERCENT_WIDTH 38.0
#define POLL_BAR_HEIGHT 4.0
#define POLL_BUTTON_HEIGHT 36.0
#define POLL_ROW_PAD 8.0

CGFloat NoshiPollVotersWidth(NSUInteger count) {
    return count ? NOSHI_POLL_VOTER_SIDE + (CGFloat)(count - 1) * NOSHI_POLL_VOTER_STEP + 6 : 0;
}

/* "1 vote", "5 votes", or the line for a poll nobody has answered */
static NSString *NoshiPollVotesLine(NoshiPoll *poll) {
    if (poll.totalVoters <= 0) return NSLocalizedString(poll.quiz ? @"poll.answers.none" : @"poll.votes.none", nil);
    NSString *prefix = poll.quiz ? @"poll.answers." : @"poll.votes.";
    return [NSString stringWithFormat:NSLocalizedString([prefix stringByAppendingString:NoshiPluralForm(poll.totalVoters)], nil), (int)poll.totalVoters];
}

static NSString *NoshiPollKindLine(NoshiPoll *poll) {
    if (poll.closed) return NSLocalizedString(@"poll.final", nil);
    if (poll.quiz) return NSLocalizedString(poll.publicVoters ? @"poll.quiz" : @"poll.quiz.anonymous", nil);
    if (poll.multiple) return NSLocalizedString(poll.publicVoters ? @"poll.public.multiple" : @"poll.anonymous.multiple", nil);
    return NSLocalizedString(poll.publicVoters ? @"poll.public" : @"poll.anonymous", nil);
}

/* the poll from y down: the question, what kind it is, an answer per row and the button; returns the y under them;
   the rows are as wide as the bubble may be, since an answer reads better with room */
- (CGFloat)layoutPollAt:(CGFloat)y width:(CGFloat)width color:(UIColor *)textColor contentWidth:(CGFloat *)contentWidth metaWidth:(CGFloat)metaWidth {
    NoshiPoll *poll = _message.poll;
    CGFloat rowWidth = MAX(150, width);
    [_pollQuestionLayout release];
    _pollQuestionLayout = [[NoshiTextLayout layoutForText:poll.question entities:poll.questionEntities font:NoshiFontSemibold(16) color:textColor linkColor:textColor
                                                      width:rowWidth maxLines:0 flush:0] retain];
    _pollQuestionOrigin = CGPointMake(PAD_X, y);
    y += _pollQuestionLayout.size.height + 3;
    /* the line wraps, since "public poll, choose one or more" is wider than a narrow bubble */
    [_pollKindLayout release];
    _pollKindLayout = [[NoshiTextLayout layoutForText:NoshiPollKindLine(poll) entities:nil font:NoshiFontRegular(12) color:NoshiColorBubbleMeta(_message.outgoing)
                                              linkColor:NoshiColorBubbleMeta(_message.outgoing) width:rowWidth maxLines:0 flush:0] retain];
    _pollKindOrigin = CGPointMake(PAD_X, y);
    y += _pollKindLayout.size.height + 4;
    _pollShowsResults = [poll showsResultsEarly:NoshiChatFlagGet(NoshiChatFlagPollResultsFirst)];
    [_pollAnswerLayouts release];
    [_pollAnswerFrames release];
    _pollAnswerLayouts = [[NSMutableArray alloc] initWithCapacity:poll.answers.count];
    _pollAnswerFrames = [[NSMutableArray alloc] initWithCapacity:poll.answers.count];
    CGFloat textWidth = rowWidth - POLL_MARK - 8 - (_pollShowsResults ? POLL_PERCENT_WIDTH : 0);
    for (NoshiPollAnswer *answer in poll.answers) {
        NoshiTextLayout *layout = [NoshiTextLayout layoutForText:answer.text entities:answer.entities font:NoshiFontRegular(15) color:textColor linkColor:textColor
                                                               width:MAX(40, textWidth) maxLines:3 flush:0];
        CGFloat height = MAX(POLL_MARK, layout.size.height) + (_pollShowsResults ? POLL_BAR_HEIGHT + 4 + (poll.hasCounts ? NOSHI_POLL_VOTES_LINE : 0) : 0) + 2 * POLL_ROW_PAD;
        [_pollAnswerLayouts addObject:layout];
        [_pollAnswerFrames addObject:[NSValue valueWithCGRect:CGRectMake(PAD_X, y, rowWidth, height)]];
        y += height;
    }
    [_pollButtonTitle release];
    _pollButtonTitle = nil;
    _pollButtonFrame = CGRectZero;
    BOOL voted = poll.voted;
    if (!poll.closed && poll.multiple && !voted && poll.picked.count > 0) _pollButtonTitle = [NSLocalizedString(@"poll.vote", nil) copy];
    else if (!poll.closed && voted && !poll.quiz && !poll.revotingDisabled) _pollButtonTitle = [NSLocalizedString(@"poll.retract", nil) copy];
    if (_pollButtonTitle) {
        _pollButtonFrame = CGRectMake(PAD_X, y + 2, rowWidth, POLL_BUTTON_HEIGHT);
        y += POLL_BUTTON_HEIGHT + 4;
    }
    [_pollFooterText release];
    _pollFooterText = [NoshiPollVotesLine(poll) copy];
    CGFloat footerWidth = ceil(NoshiStringSize(_pollFooterText, NoshiFontRegular(12)).width);
    if (_pollVoterPeople.count) footerWidth += NoshiPollVotersWidth(_pollVoterPeople.count);
    /* the count shares the row of the time when both fit, and the bubble is as wide as the rows */
    *contentWidth = MAX(*contentWidth, MAX(rowWidth, footerWidth + TIME_GAP + metaWidth));
    return y + 2;
}

- (NSUInteger)pollAnswerAtPoint:(CGPoint)point {
    for (NSUInteger i = 0; i < _pollAnswerFrames.count; ++i) {
        if (CGRectContainsPoint([[_pollAnswerFrames objectAtIndex:i] CGRectValue], point)) return i;
    }
    return NSNotFound;
}

- (void)setReplyTitle:(NSString *)title text:(NSString *)text color:(UIColor *)color {
    [_replyTitle release];
    _replyTitle = [title copy];
    [_replyText release];
    _replyText = [text copy];
    [_replyColor release];
    _replyColor = [color retain];
    [self invalidateLayout];
}

- (void)layoutReplyAt:(CGPoint)origin width:(CGFloat)width {
    [_replyTitleLayout release];
    [_replyTextLayout release];
    _replyTitleLayout = nil;
    _replyTextLayout = nil;
    _replyFrame = CGRectZero;
    if (!_replyTitle.length) return;
    /* the quote is a plate: a rounded bar inset 6 points from its left edge, then the name and a line of the message, with 6 points above and below */
    CGFloat room = MAX(1, width - QUOTE_LEFT - QUOTE_RIGHT);
    _replyTitleLayout = [[NoshiTextLayout layoutForName:_replyTitle font:NoshiFontSemibold((CGFloat)NoshiChatTextSize() - 1) color:_replyColor width:room] retain];
    UIColor *ink = NoshiColorBubbleText(_message.outgoing);
    _replyTextLayout = [[NoshiTextLayout layoutForText:_replyText entities:_replyEntities font:NoshiFontRegular((CGFloat)NoshiChatTextSize() - 1) color:ink linkColor:ink width:room maxLines:1 flush:0] retain];
    /* the quote is not tappable, so a covered spoiler in it could never be opened and left a bare plate */
    _replyTextLayout.spoilersRevealed = YES;
    CGFloat height = 2 * QUOTE_PAD_Y + _replyTitleLayout.size.height + 2 + _replyTextLayout.size.height;
    CGFloat used = MAX(_replyTitleLayout.size.width, _replyTextLayout.size.width) + QUOTE_LEFT + QUOTE_RIGHT;
    _replyFrame = CGRectMake(origin.x, origin.y, MIN(width, MAX(64, used)), height);
}

/* width over height of each picture of the collage, as the files report them; a picture that does not say is taken as square */
- (NSArray *)albumRatios {
    NSMutableArray *ratios = [NSMutableArray arrayWithCapacity:_albumMessages.count];
    for (NoshiMessage *message in _albumMessages) {
        NoshiMedia *media = message.media;
        CGFloat ratio = media.width > 0 && media.height > 0 ? (CGFloat)media.width / (CGFloat)media.height : 1;
        [ratios addObject:[NSNumber numberWithFloat:(float)MAX(0.4, MIN(2.5, ratio))]];
    }
    return ratios;
}

/* how many custom emoji a message is made of when it holds nothing else: every character of the text is under a custom emoji, bar blanks, and no other
   entity (a link, bold) is there; zero otherwise */
static NSUInteger NoshiCustomEmojiOnlyCount(NoshiMessage *message) {
    NSString *text = message.text;
    if (!text.length || !message.entities.count || message.markup) return 0;
    NSMutableIndexSet *covered = [NSMutableIndexSet indexSet];
    NSUInteger count = 0;
    for (NoshiTextEntity *entity in message.entities) {
        if (entity.style != NoshiTextStyleCustomEmoji || !entity.documentId || entity.range.length == 0 || NSMaxRange(entity.range) > text.length) return 0;
        [covered addIndexesInRange:entity.range];
        ++count;
    }
    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < text.length; ++i) {
        if (![covered containsIndex:i] && ![blank characterIsMember:[text characterAtIndex:i]]) return 0;
    }
    return count;
}

/* the least width of the row of comments: the faces, the words and the arrow each with their room, so the words do not run into the arrow */
- (CGFloat)commentsRowWidth {
    NSUInteger shown = MIN(_commenterPeople.count, (NSUInteger)3);
    CGFloat faces = shown ? 24 + (CGFloat)(shown - 1) * 16 + 8 : 0;
    CGFloat words = ceil(NoshiStringSize(_commentsText, NoshiFontSemibold(14)).width);
    return MAX(COMMENTS_MIN_WIDTH, 2 * 11 + faces + words + 8 + 14);
}

- (void)layoutBubbleForWidth:(CGFloat)width {
    NoshiMedia *media = _message.media;
    BOOL outgoing = _message.outgoing;
    CGFloat room = width - (_avatarColumn && !outgoing ? AVATAR_COLUMN : 0) - (_showsShare ? SHARE_ROOM : 0);
    CGFloat maxBubble = floor(MIN(room * MAX_BUBBLE_FRACTION, NoshiIsPad() ? BUBBLE_CAP_PAD : BUBBLE_CAP_PHONE));
    /* a post of a channel takes the width of the screen, as the wide posts of exteraGram do: a broadcast reads like a feed, not like a chat */
    if (_message.post && !outgoing) maxBubble = floor(MIN(room - 2 * SIDE_MARGIN, NoshiIsPad() ? BUBBLE_CAP_PAD * 1.5 : room));
    CGFloat metaWidth = ceil(NoshiStringSize(_timeText, NoshiTimeFont()).width) + (outgoing ? CHECK_WIDTH : 0) + _authorWidth + _viewsWidth + _deletedWidth;
    /* a voice message has no words of its own, so what the server heard in it takes their place */
    NoshiMessage *textSource = _captionMessage ? _captionMessage : _message;
    BOOL ownText = textSource.text.length > 0;
    NSString *bodyText = ownText ? textSource.text : _transcript;
    BOOL hasText = bodyText.length > 0;
    BOOL picture = _content == NoshiChatItemContentPicture;
    BOOL file = _content == NoshiChatItemContentFile;
    BOOL poll = _content == NoshiChatItemContentPoll;
    /* the collage of pictures over a file: the content is the file's, and the pictures come above its row */
    BOOL albumed = file && _albumMessages.count > 0;
    CGSize pictureSize = CGSizeZero;
    if ((picture && _albumMessages.count > 1) || albumed) {
        CGFloat albumWidth = MIN(maxBubble - 2 * PICTURE_INSET, NoshiIsPad() ? PHOTO_WIDTH_MAX_PAD : ALBUM_WIDTH_MAX);
        pictureSize = CGSizeMake(albumWidth, NoshiAlbumLayout([self albumRatios], albumWidth, [NSMutableArray array]));
    } else if (picture) {
        pictureSize = NoshiPictureSize(media, maxBubble - 2 * PICTURE_INSET);
    }
    CGFloat textMax = (picture || albumed ? pictureSize.width + 2 * PICTURE_INSET : maxBubble) - 2 * PAD_X;
    CGFloat contentWidth = 0;
    CGFloat y = PAD_TOP;
    UIColor *textColor = NoshiColorBubbleText(outgoing);
    UIColor *linkColor = NoshiColorBubbleLinkText(outgoing);

    [_textLayout release];
    /* a message of custom emoji alone shows them large, the fewer the larger, by the sizes of the official client */
    CGFloat textSize = (CGFloat)NoshiChatTextSize();
    NSUInteger emojis = 0;
    _bare = NO;
    if (ownText && !picture && !file && !poll) {
        emojis = NoshiCustomEmojiOnlyCount(_message);
        static const CGFloat sizes[] = {0, 82, 82, 55, 41, 34, 26, 23, 23, 23};
        if (emojis >= 1 && emojis <= 9 && sizes[emojis] > textSize) textSize = sizes[emojis];
    }
    _textLayout = hasText ? [[NoshiTextLayout layoutForText:bodyText entities:ownText ? textSource.entities : nil font:NoshiFontRegular(textSize)
                                                        color:textColor linkColor:linkColor width:MAX(40, textMax) maxLines:0 flush:0
                                              dropsUndrawable:NO expandedQuotes:textSource.expandedQuotes] retain] : nil;
    _textLayout.spoilersRevealed = textSource.spoilersRevealed;
    _textLayout.highlight = _highlightQuery;

    /* a run of messages from one person names them once, on the first bubble, and the picture stands under the last */
    [_senderLayout release];
    _senderLayout = nil;
    [_senderTagLayout release];
    _senderTagLayout = nil;
    if (_senderName.length && !_joinsPrevious) {
        /* the name takes the whole line it needs, and the tag after it takes what is left, cut to fit or left out when there is hardly any: a long nick that was
           cut to make room for a tag lost its end to dots */
        NSArray *badge = nil;
        NSString *named = NoshiNameWithBadges(_senderName, _senderBadge, _senderDeveloper, &badge);
        _senderLayout = [[NoshiTextLayout layoutForName:named entities:badge font:NoshiFontSemibold(NAME_SIZE) color:_senderColor
                                                    width:MAX(1, textMax)] retain];
        CGFloat room = textMax - _senderLayout.size.width - 6;
        CGFloat tagWidth = 0;
        if (_senderTag.length && room >= 36) {
            UIColor *tagColor = _senderTagColor ? _senderTagColor : NoshiColorSecondary();
            _senderTagLayout = [[NoshiTextLayout layoutForText:_senderTag entities:nil font:NoshiFontSemibold(11)
                color:tagColor linkColor:tagColor width:MIN(room, textMax * 0.45) maxLines:1 flush:0] retain];
            tagWidth = _senderTagLayout.size.width;
        }
        _senderOrigin = CGPointMake(PAD_X, y);
        _senderTagOrigin = CGPointMake(PAD_X + _senderLayout.size.width + 6, y + 1);
        contentWidth = MAX(contentWidth, _senderLayout.size.width + (tagWidth > 0 ? tagWidth + 6 : 0));
        y += 17;
    }
    [_viaLayout release];
    _viaLayout = nil;
    if (_viaText.length) {
        UIColor *viaColor = NoshiColorBubbleLink(outgoing);
        _viaLayout = [[NoshiTextLayout layoutForText:_viaText entities:nil font:NoshiFontRegular(12) color:viaColor linkColor:viaColor width:textMax maxLines:1 flush:0] retain];
        _viaOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _viaLayout.size.width);
        y += 16;
    }
    if (_forwardText.length) {
        UIColor *forwardColor = NoshiColorBubbleLink(outgoing);
        [_forwardLayout release];
        /* the line may take a second row, so a long name does not push the date of the original off its end as three dots */
        _forwardLayout = [[NoshiTextLayout layoutForText:_forwardText entities:nil font:NoshiFontRegular(12) color:forwardColor
                                                 linkColor:forwardColor width:textMax maxLines:2 flush:0 dropsUndrawable:YES] retain];
        _forwardOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _forwardLayout.size.width);
        y += 16 + (_forwardLayout.lineCount > 1 ? ceil(_forwardLayout.size.height / _forwardLayout.lineCount) * (_forwardLayout.lineCount - 1) : 0);
    }
    [self layoutReplyAt:CGPointMake(PAD_X, y) width:textMax];
    if (!CGRectIsEmpty(_replyFrame)) {
        contentWidth = MAX(contentWidth, _replyFrame.size.width);
        y += _replyFrame.size.height + 5;
    }
    CGFloat pictureTop = 0;
    _captionAbove = picture && hasText && _message.invertMedia;
    if (_captionAbove) {
        _textOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _textLayout.size.width);
        y += _textLayout.size.height + 4;
    }
    BOOL textPlaced = NO;
    if (albumed) {
        pictureTop = y == PAD_TOP ? PICTURE_INSET : y;
        y = pictureTop + pictureSize.height + 5;
        contentWidth = MAX(contentWidth, pictureSize.width + 2 * PICTURE_INSET - 2 * PAD_X);
        if (hasText) {
            _textOrigin = CGPointMake(PAD_X, y);
            contentWidth = MAX(contentWidth, _textLayout.size.width);
            y += _textLayout.size.height + 4;
            textPlaced = YES;
        }
    }
    if (picture) {
        /* a picture runs edge to edge, so the lines above it need the text padding and it needs none */
        pictureTop = y == PAD_TOP ? PICTURE_INSET : y;
        y = pictureTop + pictureSize.height + (hasText && !_captionAbove ? 5 : PICTURE_INSET);
        contentWidth = MAX(contentWidth, pictureSize.width + 2 * PICTURE_INSET - 2 * PAD_X);
    } else if (file) {
        UIColor *fileTitleColor = NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.fileTitle" : "chat.message.incoming.fileTitle") ?: textColor;
        [_fileTitleLayout release];
        _fileTitleLayout = [[NoshiTextLayout layoutForText:_fileTitle entities:nil font:NoshiFontMedium(15) color:fileTitleColor
                                                   linkColor:fileTitleColor width:MAX(40, textMax - 54) maxLines:1 flush:0] retain];
        [_fileDetailLayout release];
        _fileDetailLayout = nil;
        if (_message.media.kind == NOSHI_PREVIEW_AUDIO) {
            UIColor *detailColor = NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.fileDescription" : "chat.message.incoming.fileDescription") ?: NoshiColorBubbleMeta(outgoing);
            _fileDetailLayout = [[NoshiTextLayout layoutForText:_fileDetail entities:nil font:NoshiFontRegular(13) color:detailColor
                linkColor:detailColor width:MAX(40, textMax - 54) maxLines:1 flush:0] retain];
        }
        CGFloat titleWidth = ceil(_fileTitleLayout.size.width);
        CGFloat detailWidth = _fileDetailLayout ? ceil(_fileDetailLayout.size.width) : ceil(NoshiStringSize(_fileDetail, NoshiFontRegular(13)).width);
        if (_message.media.kind == NOSHI_PREVIEW_FILE) {
            NSString *progress = [NSString stringWithFormat:@"%@ / %@", _fileDetail, _fileDetail];
            detailWidth = MAX(detailWidth, ceil(NoshiStringSize(progress, NoshiFontRegular(13)).width));
        }
        CGFloat rowWidth = 44 + 10 + MAX(titleWidth, detailWidth);
        /* a call has no button in front: the arrow stands before the second line and the phone at the end of the row */
        if (_call) rowWidth = MAX(titleWidth, 18 + detailWidth) + 14 + CALL_ICON;
        /* a voice note needs room for its bars, and the bars are the same hundred for a note of any length, so the bubble is the same width too: the width the
           longest notes had, which the shorter ones used to fall short of */
        if (_message.media.kind == NOSHI_PREVIEW_VOICE) rowWidth = 54 + 150;
        _fileFrame = CGRectMake(PAD_X, y + 1, MIN(textMax, MAX(rowWidth, 150)), FILE_HEIGHT);
        contentWidth = MAX(contentWidth, _fileFrame.size.width);
        y += FILE_HEIGHT + 4;
    }
    BOOL timeOverPicture = picture && (!hasText || _captionAbove);
    /* the chips of the reactions stand in the bubble, between the words and the time; a picture with the time over it has no such row, and keeps them under it */
    BOOL chipsInside = [self shownReactions].count && !timeOverPicture;
    _reactionsInside = chipsInside;
    _pollFooterOwnRow = NO;
    if (poll) {
        y = [self layoutPollAt:y width:textMax color:textColor contentWidth:&contentWidth metaWidth:metaWidth];
        /* the chips, or a text under the poll (a forwarded poll can carry one), take the row the count of votes shares with the time, so the count gets a row above them;
           without it the text was drawn over the count */
        if (chipsInside || hasText) {
            _pollFooterOwnRow = YES;
            _pollFooterY = y;
            y += META_HEIGHT;
        }
    }
    if (hasText && !_captionAbove && !textPlaced) {
        _textOrigin = CGPointMake(PAD_X, y);
        contentWidth = MAX(contentWidth, _textLayout.size.width);
        y += _textLayout.size.height;
        if (chipsInside) {
            /* the time is placed with the chips below */
        } else if (_textLayout.lastLineWidth + TIME_GAP + metaWidth <= MAX(textMax, contentWidth)) {
            /* the time fits beside the last line, so the bubble does not grow a row for it */
            contentWidth = MAX(contentWidth, _textLayout.lastLineWidth + TIME_GAP + metaWidth);
        } else {
            y += META_HEIGHT - 3;
            contentWidth = MAX(contentWidth, metaWidth);
        }
    } else if (!timeOverPicture && !_call && !chipsInside) {
        /* a bubble of a file alone keeps a row of its own for the time */
        y += META_HEIGHT - 2;
        contentWidth = MAX(contentWidth, metaWidth);
    }
    _reactionFrame = CGRectZero;
    if (chipsInside) {
        CGFloat used = 0, lastRow = 0;
        CGFloat chipsHeight = NoshiReactionsMetrics([self shownReactions], textMax, YES, &used, &lastRow);
        y += REACTIONS_GAP;
        _reactionFrame = CGRectMake(PAD_X, y, used, chipsHeight);
        y += chipsHeight;
        contentWidth = MAX(contentWidth, used);
        if (lastRow + TIME_GAP + metaWidth <= MAX(textMax, contentWidth)) {
            /* the time fits right of the last row of chips, so the bubble does not grow a row for it */
            contentWidth = MAX(contentWidth, lastRow + TIME_GAP + metaWidth);
        } else {
            y += META_HEIGHT - 3;
            contentWidth = MAX(contentWidth, metaWidth);
        }
    }
    CGFloat bubbleWidth = picture || albumed ? pictureSize.width + 2 * PICTURE_INSET : contentWidth + 2 * PAD_X;
    if ((picture || albumed) && contentWidth + 2 * PAD_X > bubbleWidth) bubbleWidth = contentWidth + 2 * PAD_X;
    bubbleWidth = MAX(bubbleWidth, 56);
    if (!CGRectIsEmpty(_replyFrame)) _replyFrame.size.width = bubbleWidth - 2 * PAD_X;
    if (_commentsText.length) bubbleWidth = MAX(bubbleWidth, MIN([self commentsRowWidth], maxBubble));
    CGFloat bubbleHeight = timeOverPicture ? y : y + PAD_BOTTOM;
    /* the comments row takes the foot of the bubble, under the line with the time */
    CGFloat commentsRoom = _commentsText.length ? COMMENTS_HEIGHT : 0;
    bubbleHeight += commentsRoom;
    CGFloat top = _joinsPrevious ? SPACING_NEAR : SPACING_FAR;
    CGFloat x = outgoing ? width - SIDE_MARGIN - bubbleWidth : [self incomingLeft];
    _bubbleFrame = CGRectMake(x, top, bubbleWidth, bubbleHeight);
    if (picture || albumed) _pictureFrame = CGRectMake(PICTURE_INSET, pictureTop, bubbleWidth - 2 * PICTURE_INSET, pictureSize.height);
    [_albumFrames release];
    _albumFrames = nil;
    if ((picture && _albumMessages.count > 1) || albumed) {
        NSMutableArray *frames = [NSMutableArray array];
        NoshiAlbumLayout([self albumRatios], _pictureFrame.size.width, frames);
        for (NSUInteger i = 0; i < frames.count; ++i) {
            CGRect frame = [[frames objectAtIndex:i] CGRectValue];
            [frames replaceObjectAtIndex:i withObject:[NSValue valueWithCGRect:CGRectOffset(frame, _pictureFrame.origin.x, _pictureFrame.origin.y)]];
        }
        _albumFrames = [frames retain];
    }
    _timeSize = CGSizeMake(metaWidth, META_HEIGHT);
    if (timeOverPicture) {
        _timeSize = CGSizeMake(metaWidth + 10, 18);
        _timeOrigin = CGPointMake(bubbleWidth - PICTURE_INSET - _timeSize.width - 5, bubbleHeight - commentsRoom - PICTURE_INSET - _timeSize.height - 5);
    } else {
        _timeOrigin = CGPointMake(bubbleWidth - PAD_X - metaWidth, bubbleHeight - commentsRoom - PAD_BOTTOM - META_HEIGHT + 1);
    }
    /* one custom emoji alone: no bubble, no sender line, reply, forward, chips or comments to carry */
    if (emojis == 1 && hasText && !_forwardText.length && !_replyTitle.length && !(_senderName.length && !_joinsPrevious) && !_commentsText.length && !chipsInside &&
        ![self shownReactions].count && !_message.markup && !_call) {
        _bare = YES;
        bubbleWidth = MAX(ceil(_textLayout.size.width), 40);
        bubbleHeight = ceil(_textLayout.size.height);
        _textOrigin = CGPointMake(0, 0);
        x = outgoing ? width - SIDE_MARGIN - bubbleWidth : [self incomingLeft];
        _bubbleFrame = CGRectMake(x, top, bubbleWidth, bubbleHeight);
        _timeSize = CGSizeMake(ceil(metaWidth) + 10, 18);
        _timeOrigin = CGPointMake(bubbleWidth - _timeSize.width, bubbleHeight - _timeSize.height);
        commentsRoom = 0;
    }
    _commentsFrame = _commentsText.length ? CGRectMake(0, bubbleHeight - COMMENTS_HEIGHT, bubbleWidth, COMMENTS_HEIGHT) : CGRectZero;
    _shareFrame = _showsShare ? CGRectMake(bubbleWidth + 6, bubbleHeight - SHARE_SIDE, SHARE_SIDE, SHARE_SIDE) : CGRectZero;
    _height = top + bubbleHeight;
}

/* the buttons of an inline keyboard stand under the bubble, as wide as the bubble or as a short one's minimum, on the bubble's side */
- (void)layoutMarkupForWidth:(CGFloat)width {
    [_markup release];
    _markup = nil;
    [_markupButtons release];
    _markupButtons = nil;
    _markupFrame = CGRectZero;
    NoshiMarkup *markup = _message.markup;
    if (!markup || markup.kind != NOSHI_MARKUP_INLINE || _kind == NoshiChatItemPill) return;
    CGFloat available = width - 2 * SIDE_MARGIN - (_avatarColumn && !_message.outgoing ? AVATAR_COLUMN : 0);
    CGFloat keyboardWidth = MIN(available, MAX(_bubbleFrame.size.width, MARKUP_MIN_WIDTH));
    CGFloat height = 0;
    NSData *frames = [markup framesForWidth:keyboardWidth rowHeight:MARKUP_ROW gap:MARKUP_GAP height:&height];
    if (!frames.length) return;
    CGFloat x = _message.outgoing ? width - SIDE_MARGIN - keyboardWidth : [self incomingLeft];
    _markup = [markup retain];
    _markupButtons = [frames retain];
    _markupFrame = CGRectMake(x, _height + MARKUP_GAP, keyboardWidth, height);
    _height += height + MARKUP_GAP;
}

- (void)layoutForWidth:(CGFloat)width {
    if (width == _layoutWidth) return;
    _layoutWidth = width;
    _reactionsInside = NO;
    _reactionFrame = CGRectZero;
    switch (_kind) {
    case NoshiChatItemPill: [self layoutPillForWidth:width]; break;
    case NoshiChatItemSticker: [self layoutStickerForWidth:width]; break;
    case NoshiChatItemEmoji: [self layoutStickerForWidth:width]; break;
    case NoshiChatItemRound: [self layoutRoundForWidth:width]; break;
    case NoshiChatItemBubble: [self layoutBubbleForWidth:width]; break;
    }
    if (_kind != NoshiChatItemBubble && _kind != NoshiChatItemPill) {
        [self layoutReplyAt:CGPointZero width:MAX(100, _bubbleFrame.size.width)];
        if (!CGRectIsEmpty(_replyFrame)) {
            CGFloat extra = _replyFrame.size.height + 5;
            _bubbleFrame.origin.y += extra;
            _replyFrame.origin.y = -extra;
            if (_message.outgoing) _replyFrame.origin.x = _bubbleFrame.size.width - _replyFrame.size.width;
            _height += extra;
        }
    }
    if (_reactionsInside) {
        _reactionFrame = CGRectOffset(_reactionFrame, _bubbleFrame.origin.x, _bubbleFrame.origin.y);
    } else if ([self shownReactions].count) {
        /* the chips hang from the bubble: they start at its left edge for a message of somebody else, which in a
           group is right of the picture column, and end at its right edge for ours */
        CGFloat edge = 8;
        CGFloat x, chipsWidth;
        if (_message.outgoing) {
            chipsWidth = MIN(CGRectGetMaxX(_bubbleFrame) - edge, 380);
            x = CGRectGetMaxX(_bubbleFrame) - chipsWidth;
        } else {
            x = _bubbleFrame.origin.x;
            chipsWidth = MIN(width - edge - x, 380);
        }
        if (_giftCard) {
            CGFloat used = 0;
            NoshiReactionsMetrics([self shownReactions], MIN(width - 2 * edge, 380), YES, &used, NULL);
            chipsWidth = used;
            x = floor((width - chipsWidth) / 2);
        }
        CGFloat chipsHeight = NoshiReactionsHeight([self shownReactions], chipsWidth, YES);
        _reactionFrame = CGRectMake(x, _height + 4, chipsWidth, chipsHeight);
        _height += chipsHeight + 4;
    }
    if (_kind != NoshiChatItemBubble && _kind != NoshiChatItemPill) {
        if (_commentsText.length) {
            CGFloat available = _message.outgoing ? CGRectGetMaxX(_bubbleFrame) - SIDE_MARGIN : width - SIDE_MARGIN - _bubbleFrame.origin.x;
            CGFloat rowWidth = MIN(available, MAX(_bubbleFrame.size.width, [self commentsRowWidth]));
            CGFloat rowX = _message.outgoing ? _bubbleFrame.size.width - rowWidth : 0;
            _commentsFrame = CGRectMake(rowX, _height + 4 - _bubbleFrame.origin.y, rowWidth, COMMENTS_HEIGHT);
            _height += COMMENTS_HEIGHT + 4;
        }
        if (_showsShare) _shareFrame = CGRectMake(_bubbleFrame.size.width + 6, _bubbleFrame.size.height - SHARE_SIDE, SHARE_SIDE, SHARE_SIDE);
    }
    [self layoutMarkupForWidth:width];
}

@end

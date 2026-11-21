#import "noshi_chat_peek.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_animation.h"
#import "noshi_avatar_view.h"
#import "noshi_emoji_label.h"
#import "noshi_name_badge.h"
#import "noshi_platform.h"
#import "noshi_chat_item.h"
#import "noshi_message_cell.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define PEEK_COUNT 12
/* each pull to the top of the list brings one page of older messages, up to a bounded total so a long chat cannot fill the memory of an old device */
#define PEEK_PAGE 30
#define PEEK_TOTAL_MAX 300
/* pages made only of hidden messages add no rows, so the pages asked for are counted too */
#define PEEK_PAGES_MAX 30
#define PEEK_ACTION_HEIGHT 42.0

@interface NoshiChatPeek : UIView <UITableViewDataSource, UITableViewDelegate> {
    NoshiDialog *_dialog;
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    UIView *_dim;
    UIView *_card;
    UIView *_header;
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_title;
    UILabel *_status;
    UITableView *_table;
    UIView *_menu;
    NSArray *_items;
    NSMutableDictionary *_people;
    int32_t _oldestId;
    BOOL _loadingOlder;
    NSUInteger _pages;
    BOOL _reachedStart;
    NSArray *_buttons;
    BOOL _networkFinished;
    CGFloat _layoutWidth;
    BOOL _closing;
    void (^_handler)(NoshiChatPeekAction);
}
- (id)initWithDialog:(NoshiDialog *)dialog session:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
           canSelect:(BOOL)canSelect handler:(void (^)(NoshiChatPeekAction))handler;
- (void)showInView:(UIView *)host source:(CGRect)source;
@end

@implementation NoshiChatPeek
- (id)initWithDialog:(NoshiDialog *)dialog session:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
           canSelect:(BOOL)canSelect handler:(void (^)(NoshiChatPeekAction))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _dialog = [dialog retain]; _session = [session retain]; _avatars = [avatars retain]; _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _handler = [handler copy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = NoshiColorScreen();
    _card.layer.cornerRadius = 18;
    _card.layer.masksToBounds = YES;
    [_card addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)] autorelease]];
    [self addSubview:_card];
    _header = [[UIView alloc] init];
    _header.backgroundColor = NoshiColorCard();
    [_card addSubview:_header];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.circular = YES; _avatar.initials = dialog.initials; _avatar.seed = dialog.avatarSeed;
    [_avatar setPhoto:dialog.photo cache:avatars];
    [_header addSubview:_avatar];
    /* the name is drawn as in the chat header: emoji as pictures, the marks and the status after it */
    _title = [[NoshiEmojiLabel alloc] init];
    _title.backgroundColor = [UIColor clearColor]; _title.textColor = NoshiColorTitle();
    _title.font = NoshiFontSemibold(16); _title.dropsUndrawable = YES;
    NSArray *titleBadges = nil;
    _title.text = NoshiNameWithBadge(dialog.title, NoshiDialogBadgeDocument(dialog), &titleBadges);
    _title.entities = titleBadges;
    [_header addSubview:_title];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor]; _status.textColor = NoshiColorSecondary();
    _status.textAlignment = NoshiTextAlignmentCenter; _status.numberOfLines = 0; _status.font = NoshiFontRegular(14);
    _status.text = NSLocalizedString(@"peek.loading", nil);
    [_card addSubview:_status];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    NoshiScrollViewOwnsInsets(_table);
    NoshiTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor]; _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self; _table.delegate = self;
    /* the table scrolls the loaded messages; a tap on it reaches the tap on the card behind it, which opens the chat, as the messages have no delegate here to act on their own */
    [_card addSubview:_table];
    _menu = [[UIView alloc] init];
    _menu.backgroundColor = NoshiColorCard(); _menu.layer.cornerRadius = 14; _menu.clipsToBounds = YES;
    [self addSubview:_menu];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(dialog.pinned ? @"chats.unpin" : @"chats.pin", nil),
        NSLocalizedString(dialog.muted ? @"chats.unmute" : @"chats.mute", nil),
        NSLocalizedString(dialog.folderId ? @"chats.unarchive.action" : @"chats.archive.action", nil), NSLocalizedString(@"peek.select", nil),
        NSLocalizedString(@"chats.swipe.read", nil), nil];
    NoshiSymbol symbols[] = {NoshiSymbolPin, dialog.muted ? NoshiSymbolBell : NoshiSymbolBellMuted, NoshiSymbolArchive, NoshiSymbolCheck, NoshiSymbolCheckDouble};
    /* the read button sits above archive and shows only for a chat that has something to mark; the tag of a button is its action */
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil];
    if (dialog.unread) [rows addObject:[NSNumber numberWithInt:4]];
    [rows addObject:[NSNumber numberWithInt:2]];
    if (canSelect) [rows addObject:[NSNumber numberWithInt:3]];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSNumber *row in rows) {
        NSUInteger i = (NSUInteger)row.intValue;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i == 4 ? NoshiChatPeekMarkRead : (NSInteger)i + 1;
        button.accessibilityLabel = [titles objectAtIndex:i];
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        UIImageView *icon = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(symbols[i], 20, NoshiColorAccent())] autorelease];
        icon.frame = CGRectMake(14, 11, 20, 20); icon.userInteractionEnabled = NO;
        [button addSubview:icon];
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(46, 0, 150, PEEK_ACTION_HEIGHT)] autorelease];
        label.backgroundColor = [UIColor clearColor]; label.textColor = NoshiColorTitle(); label.font = NoshiFontMedium(15);
        label.text = [titles objectAtIndex:i]; label.autoresizingMask = UIViewAutoresizingFlexibleWidth; label.userInteractionEnabled = NO;
        [button addSubview:label];
        [_menu addSubview:button]; [buttons addObject:button];
    }
    _buttons = [buttons copy];
    return self;
}
- (void)dealloc {
    [_weak clear]; [_weak release]; _table.delegate = nil; _table.dataSource = nil;
    [_dialog release]; [_session release]; [_avatars release]; [_media release]; [_handler release];
    [_dim release]; [_card release]; [_header release]; [_avatar release]; [_title release]; [_status release]; [_table release]; [_menu release];
    [_items release]; [_people release]; [_buttons release]; [super dealloc];
}
- (void)showInView:(UIView *)host source:(CGRect)source {
    self.frame = host.bounds;
    [host addSubview:self]; [self layoutIfNeeded];
    CGFloat scale = 0.35;
    CGPoint center = _card.center;
    CGAffineTransform start = CGAffineTransformMake(scale, 0, 0, scale, CGRectGetMidX(source) - center.x, CGRectGetMidY(source) - center.y);
    if (NoshiReduceMotionEnabled()) start = CGAffineTransformIdentity;
    _card.transform = start; _card.alpha = 0;
    _menu.transform = CGAffineTransformMakeTranslation(0, 12); _menu.alpha = 0;
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.2 animations:^{ _dim.alpha = 1; }];
    NoshiAnimateView(_card, CGAffineTransformIdentity, 1, NOSHI_MOTION_SPRING, nil);
    NoshiAnimateViewAfter(_menu, CGAffineTransformIdentity, 1, NOSHI_MOTION_ENTER, 0.06, nil);
    NoshiWeakReference *weak = _weak;
    if (_dialog.emojiStatus) {
        NoshiLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.emojiStatus]], _session, _media, ^{
            NoshiChatPeek *peek = weak.target;
            if (peek) [peek->_title setNeedsDisplay];
        });
    }
    [_session loadCachedHistoryOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        (void)error;
        NoshiChatPeek *peek = weak.target;
        if (peek && !peek->_networkFinished && messages.count) [peek showMessages:messages people:people];
    }];
    [_session loadHistoryOfDialog:_dialog beforeId:0 limit:PEEK_COUNT completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        NoshiChatPeek *peek = weak.target;
        if (!peek) return;
        peek->_networkFinished = messages != nil;
        if (messages) [peek showMessages:messages people:people];
        else {
            NSLog(@"noshigram: chat preview failed: %@", error);
            if (!peek->_items.count) peek->_status.text = NSLocalizedString(@"peek.error", nil);
        }
    }];
}
static NSArray *NoshiPeekOrdered(NSArray *messages) {
    return [messages sortedArrayUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
        return a.messageId < b.messageId ? NSOrderedAscending : (a.messageId > b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
}
- (NSArray *)itemsForMessages:(NSArray *)ordered people:(NSDictionary *)people {
    NSMutableArray *items = [NSMutableArray array];
    for (NoshiMessage *message in ordered) {
        NoshiChatItem *item = [NoshiChatItem itemForMessage:message group:_dialog.kind == NOSHI_DIALOG_GROUP people:people];
        if (item) [items addObject:item];
    }
    return items;
}
- (void)showMessages:(NSArray *)messages people:(NSDictionary *)people {
    NSArray *ordered = NoshiPeekOrdered(messages);
    NSUInteger start = ordered.count > PEEK_COUNT ? ordered.count - PEEK_COUNT : 0;
    NSArray *shown = [ordered subarrayWithRange:NSMakeRange(start, ordered.count - start)];
    [_people release]; _people = [people mutableCopy];
    _oldestId = shown.count ? [(NoshiMessage *)[shown objectAtIndex:0] messageId] : 0;
    _reachedStart = NO;
    _pages = 0;
    [_items release]; _items = [[self itemsForMessages:shown people:_people] copy];
    _status.text = _items.count ? @"" : NSLocalizedString(@"peek.empty", nil);
    [_table reloadData]; [_table layoutIfNeeded];
    CGFloat end = MAX(0, _table.contentSize.height - _table.bounds.size.height);
    [_table setContentOffset:CGPointMake(0, end) animated:NO];
}
/* the page that came before what is on the list goes above it, and the list keeps showing the same messages where they were */
- (void)loadOlder {
    if (_loadingOlder || _reachedStart || !_networkFinished || _oldestId <= 0 || _items.count >= PEEK_TOTAL_MAX || _pages >= PEEK_PAGES_MAX) return;
    _loadingOlder = YES;
    ++_pages;
    NoshiWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog beforeId:_oldestId limit:PEEK_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *error) {
        NoshiChatPeek *peek = weak.target;
        if (!peek) return;
        peek->_loadingOlder = NO;
        if (!messages) {
            NSLog(@"noshigram: older messages of the chat preview failed: %@", error);
            return;
        }
        [peek prependMessages:messages people:people];
    }];
}
- (void)prependMessages:(NSArray *)messages people:(NSDictionary *)people {
    NSMutableArray *older = [NSMutableArray array];
    for (NoshiMessage *message in NoshiPeekOrdered(messages)) if (message.messageId < _oldestId) [older addObject:message];
    if (!older.count) {
        _reachedStart = YES;
        return;
    }
    if (people) [_people addEntriesFromDictionary:people];
    _oldestId = [(NoshiMessage *)[older objectAtIndex:0] messageId];
    NSMutableArray *items = [NSMutableArray arrayWithArray:[self itemsForMessages:older people:_people]];
    [items addObjectsFromArray:_items];
    CGFloat height = _table.contentSize.height, offset = _table.contentOffset.y;
    [_items release]; _items = [items copy];
    [_table reloadData]; [_table layoutIfNeeded];
    [_table setContentOffset:CGPointMake(0, offset + _table.contentSize.height - height) animated:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    if (scroll == _table && scroll.contentOffset.y < 120) [self loadOlder];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _dim.frame = self.bounds;
    UIEdgeInsets insets = NoshiSafeInsets(self);
    CGFloat width = MAX(100, MIN(NoshiIsPad() ? 520 : 350, self.bounds.size.width - insets.left - insets.right - 32));
    CGFloat available = MAX(100, self.bounds.size.height - insets.top - insets.bottom - 32);
    CGFloat menuHeight = _buttons.count * PEEK_ACTION_HEIGHT;
    CGFloat cardHeight = MAX(100, MIN(NoshiIsPad() ? 620 : 440, available - menuHeight - 12));
    CGFloat top = insets.top + MAX(0, floor((available - cardHeight - menuHeight - 12) / 2)) + 16;
    NoshiPlaceView(_card, CGRectMake(floor((self.bounds.size.width - width) / 2), top, width, cardHeight));
    _header.frame = CGRectMake(0, 0, width, 56); _avatar.frame = CGRectMake(12, 9, 38, 38);
    _title.frame = CGRectMake(60, 0, width - 72, 56);
    _table.frame = CGRectMake(0, 56, width, MAX(0, cardHeight - 56));
    if (_items.count && _layoutWidth != width) {
        _layoutWidth = width;
        [_table reloadData];
        [_table layoutIfNeeded];
        [_table setContentOffset:CGPointMake(0, MAX(0, _table.contentSize.height - _table.bounds.size.height)) animated:NO];
    }
    _status.frame = CGRectMake(16, 56, width - 32, MAX(0, cardHeight - 56));
    /* the card is scaled while it opens and closes, so its frame is not where it rests; the place is worked out from the numbers above */
    CGRect cardFrame = CGRectMake(floor((self.bounds.size.width - width) / 2), top, width, cardHeight);
    NoshiPlaceView(_menu, CGRectMake(CGRectGetMaxX(cardFrame) - MIN(width, 230), CGRectGetMaxY(cardFrame) + 12, MIN(width, 230), menuHeight));
    for (NSUInteger i = 0; i < _buttons.count; ++i) ((UIView *)[_buttons objectAtIndex:i]).frame = CGRectMake(0, i * PEEK_ACTION_HEIGHT, _menu.bounds.size.width, PEEK_ACTION_HEIGHT);
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return (NSInteger)_items.count; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)path.row]; [item layoutForWidth:table.bounds.size.width]; return item.height;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NoshiMessageCell *cell = (NoshiMessageCell *)[table dequeueReusableCellWithIdentifier:@"peek"];
    if (!cell) cell = [[[NoshiMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"peek"] autorelease];
    NoshiChatItem *item = [_items objectAtIndex:(NSUInteger)path.row]; [item layoutForWidth:table.bounds.size.width];
    cell.activationDeferred = YES; [cell configureWithItem:item media:_media avatars:_avatars];
    return cell;
}
- (void)leaveWithAction:(NSInteger)action {
    if (_closing) return;
    _closing = YES; self.userInteractionEnabled = NO;
    void (^handler)(NoshiChatPeekAction) = [_handler copy];
    /* the card clips a table of message cells with rounded corners, which is drawn off screen on every frame of the way out; a bitmap of it fades and shrinks smoothly */
    NoshiCacheForMotion(_card);
    NoshiCacheForMotion(_menu);
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.2 animations:^{ _dim.alpha = 0; }];
    NoshiAnimateView(_menu, CGAffineTransformMakeTranslation(0, 10), 0, NOSHI_MOTION_DISMISS, nil);
    NoshiAnimateView(_card, CGAffineTransformMakeScale(0.94, 0.94), 0, NOSHI_MOTION_DISMISS, ^(BOOL finished) {
        (void)finished; [self removeFromSuperview]; if (handler && action >= 0) handler((NoshiChatPeekAction)action); [handler release];
    });
}
- (void)open { [self leaveWithAction:NoshiChatPeekOpen]; }
- (void)dismiss { [self leaveWithAction:-1]; }
- (void)picked:(UIButton *)button { [self leaveWithAction:button.tag]; }
@end

void NoshiShowChatPeek(UIView *host, CGRect source, NoshiDialog *dialog, NoshiSession *session,
                         NoshiAvatarCache *avatars, NoshiMediaCache *media, BOOL canSelect,
                         void (^handler)(NoshiChatPeekAction)) {
    if (!host || !dialog || !session) return;
    for (UIView *view in host.subviews) if ([view isKindOfClass:[NoshiChatPeek class]]) return;
    NoshiChatPeek *peek = [[[NoshiChatPeek alloc] initWithDialog:dialog session:session avatars:avatars media:media canSelect:canSelect handler:handler] autorelease];
    [peek showInView:host source:source];
}

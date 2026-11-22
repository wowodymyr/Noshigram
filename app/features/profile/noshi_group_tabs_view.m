#import "noshi_group_tabs_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_person_cell.h"
#import "noshi_pill_tabs_view.h"
#import "noshi_symbol.h"
#import "noshi_time.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#import "noshi_music_player.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_plural.h"
#import "noshi_forward.h"
#import "noshi_session_actions.h"
#import "noshi_session_profile.h"
#import "noshi_session_channels.h"

#define TABS_GAP 10.0
/* the icon of a row of the person cell: its left margin and its side */
#define ROW_SIDE 14.0
#define ROW_ICON 44.0
#define BAR_HEIGHT 48.0
#define PAGE 30
#define COLUMNS 3
#define CELL_GAP 2.0
#define MORE_HEIGHT 48.0
#define EMPTY_HEIGHT 80.0

typedef enum { NoshiGroupTabMembers, NoshiGroupTabMedia, NoshiGroupTabFiles, NoshiGroupTabLinks, NoshiGroupTabAudio, NoshiGroupTabVoice, NoshiGroupTabCommon, NoshiGroupTabCount } NoshiGroupTab;

@interface NoshiGroupTabsView () {
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NoshiPillTabsView *_tabs;
    UIView *_body;
    UIView *_bar;
    UIView *_barLine;
    UILabel *_empty;
    NSMutableArray *_items[NoshiGroupTabCount];
    BOOL _loaded[NoshiGroupTabCount];
    BOOL _loading[NoshiGroupTabCount];
    BOOL _finished[NoshiGroupTabCount];
    BOOL _failed[NoshiGroupTabCount];
    NSUInteger _tab;
    BOOL _forUser;
    BOOL _skipFirst;
    BOOL _hasCommonTab;
    /* the id the next page of the groups in common starts after */
    long long _commonLast;
    CGFloat _width;
    CGFloat _bodyHeight;
    NSMutableSet *_selected;
    NSMutableDictionary *_people;
    BOOL _forwarding;
    id<NoshiGroupTabsDelegate> _delegate;
}
@end

@implementation NoshiGroupTabsView

@synthesize delegate = _delegate;

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    return [self initWithSession:session dialog:dialog avatars:avatars media:media forUser:NO];
}

- (NSUInteger)selectedTab {
    return _tab;
}

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
              forUser:(BOOL)forUser {
    return [self initWithSession:session dialog:dialog avatars:avatars media:media forUser:forUser hidesMembers:NO];
}

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
              forUser:(BOOL)forUser hidesMembers:(BOOL)hidesMembers {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _forUser = forUser;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _selected = [[NSMutableSet alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    for (int i = 0; i < NoshiGroupTabCount; ++i) _items[i] = [[NSMutableArray alloc] init];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(forUser ? @"gifts.title" : @"group.tab.members", nil), NSLocalizedString(@"group.tab.media", nil),
                                                NSLocalizedString(@"group.tab.files", nil), NSLocalizedString(@"group.tab.links", nil), NSLocalizedString(@"group.tab.audio", nil), NSLocalizedString(@"group.tab.voice", nil), nil];
    _skipFirst = dialog.saved || hidesMembers;
    if (_skipFirst) {
        titles = [titles subarrayWithRange:NSMakeRange(1, titles.count - 1)];
        _tab = NoshiGroupTabMedia;
    }
    [self installTabsWithTitles:titles];
    _body = [[UIView alloc] init];
    _body.backgroundColor = NoshiColorCard();
    _body.clipsToBounds = YES;
    [self addSubview:_body];
    _empty = [[UILabel alloc] init];
    _empty.backgroundColor = [UIColor clearColor];
    _empty.textColor = NoshiColorSecondary();
    _empty.font = NoshiFontRegular(15);
    _empty.textAlignment = NoshiTextAlignmentCenter;
    [self load];
    return self;
}

/* the capsule of tab names; a chosen index is the tab's own number less the one the first tab that is left out takes */
- (void)installTabsWithTitles:(NSArray *)titles {
    NSUInteger chosen = _tabs ? _tabs.selectedIndex : 0;
    [_tabs removeFromSuperview];
    [_tabs release];
    _tabs = [[NoshiPillTabsView alloc] initWithTitles:titles];
    NoshiWeakReference *me = _weak;
    BOOL skipFirst = _skipFirst;
    _tabs.changeHandler = ^(NSUInteger index) { [(NoshiGroupTabsView *)me.target chooseTab:skipFirst ? index + 1 : index]; };
    if (chosen < titles.count) _tabs.selectedIndex = chosen;
    [self addSubview:_tabs];
    [self setNeedsLayout];
}

- (void)setCommonChatsCount:(NSInteger)count {
    if (!_forUser || count <= 0 || _hasCommonTab) return;
    _hasCommonTab = YES;
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"gifts.title", nil), NSLocalizedString(@"group.tab.media", nil), NSLocalizedString(@"group.tab.files", nil),
                                                NSLocalizedString(@"group.tab.links", nil), NSLocalizedString(@"group.tab.audio", nil), NSLocalizedString(@"group.tab.voice", nil),
                                                NSLocalizedString(@"group.tab.common", nil), nil];
    if (_skipFirst) titles = [titles subarrayWithRange:NSMakeRange(1, titles.count - 1)];
    [self installTabsWithTitles:titles];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_bar release];
    [_tabs release];
    [_body release];
    [_empty release];
    [_selected release];
    [_people release];
    for (int i = 0; i < NoshiGroupTabCount; ++i) [_items[i] release];
    [super dealloc];
}

#pragma mark loading

- (void)reloadMembers {
    /* a page in flight would add its rows to the fresh list, so the reload waits for it to land and the tab shows what it has until then */
    if (_loading[NoshiGroupTabMembers]) return;
    [_items[NoshiGroupTabMembers] removeAllObjects];
    _loaded[NoshiGroupTabMembers] = NO;
    _finished[NoshiGroupTabMembers] = NO;
    if (_tab == NoshiGroupTabMembers) [self load];
    [self rebuild];
}

- (void)chooseTab:(NSUInteger)index {
    if (index >= NoshiGroupTabCount || index == _tab || (index == NoshiGroupTabCommon && !_hasCommonTab)) return;
    [_selected removeAllObjects];
    _tab = index;
    [self load];
    [self rebuild];
    if ([_delegate respondsToSelector:@selector(groupTabsDidChooseTab:)]) [_delegate groupTabsDidChooseTab:self];
}

- (void)finishTab:(NSUInteger)tab added:(NSUInteger)added error:(NSString *)errorName {
    _loading[tab] = NO;
    if (errorName) {
        NSLog(@"noshigram: the group tab %lu of %lld did not load: %@", (unsigned long)tab, _dialog.peerId, errorName);
        _failed[tab] = YES;
        [self rebuild];
        return;
    }
    _failed[tab] = NO;
    _loaded[tab] = YES;
    if (added == 0) _finished[tab] = YES;
    [self rebuild];
}

/* the next page of the chosen tab; a page that brings nothing ends the list */
- (void)load {
    NSUInteger tab = _tab;
    if (_loading[tab] || _finished[tab]) return;
    /* the gifts of a user come from the screen's own feed */
    if (_forUser && tab == NoshiGroupTabMembers) {
        _loaded[tab] = _finished[tab] = YES;
        return;
    }
    _loading[tab] = YES;
    _failed[tab] = NO;
    NoshiWeakReference *me = _weak;
    [self retain];
    if (tab == NoshiGroupTabMembers) {
        [_session loadMembersOfDialog:_dialog list:NoshiChannelListSubscribers query:nil offset:(NSInteger)_items[tab].count
                           completion:^(NSArray *members, NSInteger total, NSString *errorName) {
            [self autorelease];
            NoshiGroupTabsView *view = me.target;
            if (!view) return;
            [view->_items[tab] addObjectsFromArray:members];
            if (total > 0 && (NSInteger)view->_items[tab].count >= total) view->_finished[tab] = YES;
            [view finishTab:tab added:members.count error:errorName];
        }];
        return;
    }
    if (tab == NoshiGroupTabCommon) {
        [_session loadCommonChatsOfDialog:_dialog beforeId:_commonLast completion:^(NSArray *chats, long long lastId, BOOL finished, NSString *errorName) {
            [self autorelease];
            NoshiGroupTabsView *view = me.target;
            if (!view) return;
            NSMutableArray *list = view->_items[tab];
            for (NoshiDialog *chat in chats) {
                BOOL known = NO;
                for (NoshiDialog *held in list) if (held.peerKind == chat.peerKind && held.peerId == chat.peerId) { known = YES; break; }
                if (!known) [list addObject:chat];
            }
            if (!errorName) {
                view->_commonLast = lastId;
                if (finished) view->_finished[tab] = YES;
            }
            [view finishTab:tab added:chats.count error:errorName];
        }];
        return;
    }
    noshi_shared_kind kind = tab == NoshiGroupTabMedia ? NOSHI_SHARED_MEDIA : (tab == NoshiGroupTabFiles ? NOSHI_SHARED_FILES : (tab == NoshiGroupTabAudio ? NOSHI_SHARED_AUDIO : (tab == NoshiGroupTabVoice ? NOSHI_SHARED_VOICE : NOSHI_SHARED_LINKS)));
    int32_t before = _items[tab].count ? [(NoshiMessage *)[_items[tab] lastObject] messageId] : 0;
    [_session loadSharedOfDialog:_dialog kind:kind beforeId:before limit:PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        [self autorelease];
        NoshiGroupTabsView *view = me.target;
        if (!view) return;
        [view->_people addEntriesFromDictionary:people];
        /* the server filters by what the message holds, so a page of the links tab can carry a message with no readable link; those are dropped here */
        NSUInteger added = messages.count;
        for (NoshiMessage *message in messages) {
            if (tab == NoshiGroupTabLinks && ![view linkOfMessage:message]) continue;
            [view->_items[tab] addObject:message];
        }
        [view finishTab:tab added:added error:errorName];
    }];
}

#pragma mark rows

- (NSURL *)linkOfMessage:(NoshiMessage *)message {
    NSString *text = message.text;
    if (!text.length) return nil;
    static NSDataDetector *detector;
    if (!detector) detector = [[NSDataDetector dataDetectorWithTypes:(NSTextCheckingTypes)NSTextCheckingTypeLink error:NULL] retain];
    NSTextCheckingResult *found = [detector firstMatchInString:text options:0 range:NSMakeRange(0, MIN(text.length, 4096))];
    return found.URL;
}

static NSString *NoshiGroupSizeText(long long bytes) {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
}

static NSString *NoshiGroupDateText(int32_t date) {
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    }
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

- (UIControl *)tapAreaAtIndex:(NSUInteger)index frame:(CGRect)frame {
    UIControl *area = [[[UIControl alloc] initWithFrame:frame] autorelease];
    area.tag = (NSInteger)index;
    [area addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    if (_tab != NoshiGroupTabMembers && _tab != NoshiGroupTabCommon) {
        [area addGestureRecognizer:[[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowHeld:)] autorelease]];
        NoshiMessage *message = [_items[_tab] objectAtIndex:index];
        if ([_selected containsObject:[NSNumber numberWithInt:message.messageId]]) {
            UIImageView *check = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolCheck, 16, [UIColor whiteColor])] autorelease];
            check.backgroundColor = NoshiColorAccent();
            check.layer.cornerRadius = 12;
            check.contentMode = UIViewContentModeCenter;
            /* on the icon of a file or link row, the corner of a photo tile */
            if (_tab == NoshiGroupTabMedia) {
                check.frame = CGRectMake(MAX(0, frame.size.width - 30), MAX(0, frame.size.height - 30), 24, 24);
            } else {
                check.frame = CGRectMake(ROW_SIDE + ROW_ICON - 20, (frame.size.height + ROW_ICON) / 2 - 20, 24, 24);
                check.layer.borderWidth = 2;
                check.layer.borderColor = NoshiColorCard().CGColor;
            }
            check.userInteractionEnabled = NO;
            [area addSubview:check];
        }
    }
    return area;
}

- (NoshiPersonCell *)personRowWithFrame:(CGRect)frame {
    NoshiPersonCell *cell = [[[NoshiPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    cell.frame = frame;
    cell.userInteractionEnabled = NO;
    [cell layoutIfNeeded];
    return cell;
}

- (void)rebuild {
    for (UIView *view in [[_body.subviews copy] autorelease]) [view removeFromSuperview];
    [_bar removeFromSuperview];
    [_bar release];
    _bar = nil;
    _barLine = nil;
    NSUInteger tab = _tab;
    NSArray *items = _items[tab];
    CGFloat width = _width;
    CGFloat y = _selected.count ? BAR_HEIGHT : 0;
    if (_forUser && tab == NoshiGroupTabMembers) {
        _body.hidden = YES;
        _bodyHeight = 0;
        [self setNeedsLayout];
        [_delegate groupTabsDidResize:self];
        return;
    }
    _body.hidden = NO;
    if (_selected.count) [self addSelectionBar:width];
    if (tab == NoshiGroupTabMedia) {
        CGFloat side = floor((width - CELL_GAP * (COLUMNS - 1)) / COLUMNS);
        for (NSUInteger i = 0; i < items.count; ++i) {
            NoshiMessage *message = [items objectAtIndex:i];
            CGRect frame = CGRectMake((i % COLUMNS) * (side + CELL_GAP), y + (i / COLUMNS) * (side + CELL_GAP), side, side);
            [self addMediaTile:message frame:frame index:i];
        }
        y += items.count ? ceil(items.count / (double)COLUMNS) * (side + CELL_GAP) - CELL_GAP : 0;
    } else {
        CGFloat row = [NoshiPersonCell rowHeight];
        for (NSUInteger i = 0; i < items.count; ++i) {
            CGRect frame = CGRectMake(0, y, width, row);
            [_body addSubview:[self rowForItem:[items objectAtIndex:i] tab:tab frame:frame]];
            [_body addSubview:[self tapAreaAtIndex:i frame:frame]];
            y += row;
        }
    }
    if (!items.count) {
        _empty.text = NSLocalizedString(_failed[tab] ? @"group.tab.failed" : (_loaded[tab] ? @"group.tab.empty" : @"group.tab.loading"), nil);
        _empty.frame = CGRectMake(0, 0, width, EMPTY_HEIGHT);
        [_body addSubview:_empty];
        y = EMPTY_HEIGHT;
    }
    if ((!items.count && _failed[tab]) || (items.count && !_finished[tab])) {
        UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
        more.frame = CGRectMake(0, y, width, MORE_HEIGHT);
        more.titleLabel.font = NoshiFontMedium(15);
        [more setTitle:NSLocalizedString(_failed[tab] ? @"article.retry" : @"group.tab.more", nil) forState:UIControlStateNormal];
        [more setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
        [more addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
        [_body addSubview:more];
        y += MORE_HEIGHT;
    }
    _bodyHeight = y;
    [self setNeedsLayout];
    [_delegate groupTabsDidResize:self];
}

/* a voice message is named by who sent it, as the file name of a recording says nothing; in saved messages the sender is the account itself, so the author of the forward is shown.
   NO when the history named nobody, and the row keeps the plain title */
/* the voice list holds voice notes and round videos, and the picture of a row says which: a microphone or a video camera */
static NoshiSymbol NoshiVoiceRowSymbol(NoshiMessage *message) {
    return message.media.kind == NOSHI_PREVIEW_VIDEO_MESSAGE ? NoshiSymbolVideoCamera : NoshiSymbolMicrophone;
}

- (BOOL)configureVoiceRow:(NoshiPersonCell *)cell message:(NoshiMessage *)message {
    long long key = _dialog.saved && message.forwardKey ? message.forwardKey : message.senderKey;
    /* a message of a private chat can come without a sender: it is the account's own when it is outgoing and the other person's otherwise; the round videos of a profile lost their name here */
    if (!key && !_dialog.saved) key = message.outgoing ? [_session ownPerson].userId : (_dialog.peerKind == 1 ? _dialog.peerId : 0);
    NoshiPerson *person = key ? [_people objectForKey:[NSNumber numberWithLongLong:key]] : nil;
    if (!person && key && key == [_session ownPerson].userId) person = [_session ownPerson];
    NSString *name = person.name;
    NSString *initials = person.initials;
    NSUInteger seed = (NSUInteger)(person ? person.userId % 1000003 : message.messageId);
    if (!name.length && key && key == _dialog.peerId && _dialog.peerKind == 1) {
        name = _dialog.title;
        initials = _dialog.initials;
        seed = _dialog.avatarSeed;
    }
    if (!name.length && _dialog.saved) name = message.forwardName;
    if (!name.length) return NO;
    NSString *detail = [NSString stringWithFormat:@"%@, %@", NoshiGroupSizeText(message.media.size), NoshiGroupDateText(message.date)];
    [cell configureWithName:name initials:initials.length ? initials : [[name substringToIndex:1] uppercaseString] seed:seed
                   subtitle:detail subtitleColor:nil trailing:nil symbol:NoshiSymbolChevronRight showsSymbol:NO nameColor:nil photo:nil avatars:nil];
    cell.avatarDeleted = NO;
    [cell showAvatarSymbol:NoshiVoiceRowSymbol(message)];
    return YES;
}

- (UIView *)rowForItem:(id)item tab:(NSUInteger)tab frame:(CGRect)frame {
    NoshiPersonCell *cell = [self personRowWithFrame:frame];
    if (tab == NoshiGroupTabMembers) {
        NoshiChannelMember *member = item;
        NoshiPerson *person = member.person;
        /* the role stands at the right, as in the member list group screen */
        NSString *trailing = nil;
        if (member.role == NoshiChannelRoleCreator) {
            trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.creator", nil);
            cell.trailingTint = NoshiMemberTagColor(YES);
        } else if (member.role == NoshiChannelRoleAdmin) {
            trailing = member.rank.length ? member.rank : NSLocalizedString(@"channel.role.admin", nil);
            cell.trailingTint = NoshiMemberTagColor(NO);
        } else if (member.rank.length) {
            trailing = member.rank;
            cell.trailingTint = NoshiColorAccent();
        }
        UIColor *color = nil;
        NSString *subtitle;
        if (person.bot) {
            subtitle = NSLocalizedString(@"seen.bot", nil);
        } else {
            if (person.presence == NOSHI_PRESENCE_ONLINE) color = NoshiColorAccent();
            subtitle = NoshiLastSeenText(person.presence, person.seen);
        }
        cell.premium = person.premium;
        [cell configureWithName:person.name initials:person.initials seed:(NSUInteger)(person.userId % 1000003) subtitle:subtitle subtitleColor:color
                       trailing:trailing symbol:NoshiSymbolChevronRight showsSymbol:NO nameColor:nil photo:person.photo avatars:_avatars];
        cell.avatarDeleted = person.deleted;
    } else if (tab == NoshiGroupTabCommon) {
        NoshiDialog *chat = item;
        NSString *subtitle = nil;
        if (chat.participantsCount > 0) {
            NSString *key = [NSString stringWithFormat:@"chat.members.%@", NoshiPluralForm(chat.participantsCount)];
            subtitle = [NSString stringWithFormat:NSLocalizedString(key, nil), (long)chat.participantsCount];
        }
        [cell configureWithName:chat.title initials:chat.initials seed:chat.avatarSeed subtitle:subtitle subtitleColor:nil trailing:nil symbol:NoshiSymbolChevronRight
                    showsSymbol:NO nameColor:nil photo:chat.photo avatars:_avatars];
    } else if (tab == NoshiGroupTabVoice && [self configureVoiceRow:cell message:item]) {
        return cell;
    } else if (tab == NoshiGroupTabFiles || tab == NoshiGroupTabAudio || tab == NoshiGroupTabVoice) {
        NoshiMessage *message = item;
        NSString *name = message.media.name.length ? message.media.name : (message.media.title.length ? message.media.title : NSLocalizedString(tab == NoshiGroupTabVoice ? @"group.tab.voice" : @"group.tab.file", nil));
        NSString *extension = [[name pathExtension] uppercaseString];
        NSString *detail = [NSString stringWithFormat:@"%@, %@", NoshiGroupSizeText(message.media.size), NoshiGroupDateText(message.date)];
        [cell configureWithName:name initials:extension.length ? [extension substringToIndex:MIN(extension.length, 3)] : @"?" seed:(NSUInteger)message.messageId
                       subtitle:detail subtitleColor:nil trailing:nil symbol:NoshiSymbolChevronRight showsSymbol:NO nameColor:nil photo:nil avatars:nil];
        if (tab == NoshiGroupTabVoice) [cell showAvatarSymbol:NoshiVoiceRowSymbol(message)];
    } else {
        NoshiMessage *message = item;
        NSURL *url = [self linkOfMessage:message];
        NSString *host = url.host.length ? url.host : url.absoluteString;
        [cell configureWithName:host initials:host.length ? [[host substringToIndex:1] uppercaseString] : @"?" seed:(NSUInteger)message.messageId
                       subtitle:url.absoluteString subtitleColor:nil trailing:nil symbol:NoshiSymbolLink showsSymbol:NO nameColor:nil photo:nil avatars:nil];
    }
    return cell;
}

- (void)addMediaTile:(NoshiMessage *)message frame:(CGRect)frame index:(NSUInteger)index {
    UIImageView *tile = [[[UIImageView alloc] initWithFrame:frame] autorelease];
    tile.contentMode = UIViewContentModeScaleAspectFill;
    tile.clipsToBounds = YES;
    tile.backgroundColor = NoshiColorField();
    [_body addSubview:tile];
    NoshiMedia *media = message.media;
    NoshiRemoteFile *file = media.kind == NOSHI_PREVIEW_PHOTO ? media.file : media.previewFile;
    if (file) {
        CGFloat side = frame.size.width * [UIScreen mainScreen].scale;
        UIImage *ready = [_media cachedImageForFile:file maxSide:side];
        if (ready) {
            tile.image = ready;
        } else {
            [_media loadImageForFile:file maxSide:side completion:^(UIImage *image) {
                if (image) tile.image = image;
            }];
        }
    }
    if (media.kind == NOSHI_PREVIEW_GIF) {
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(frame.origin.x + 6, frame.origin.y + 6, 36, 20)] autorelease];
        label.text = @"GIF";
        label.font = NoshiFontMedium(12);
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NoshiTextAlignmentCenter;
        label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        label.layer.cornerRadius = 10;
        label.clipsToBounds = YES;
        [_body addSubview:label];
    } else if (media.kind != NOSHI_PREVIEW_PHOTO) {
        UIImageView *mark = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPlay, 24, [UIColor whiteColor])] autorelease];
        mark.contentMode = UIViewContentModeCenter;
        mark.frame = frame;
        [_body addSubview:mark];
    }
    [_body addSubview:[self tapAreaAtIndex:index frame:frame]];
}

- (UIButton *)selectionButton:(NoshiSymbol)symbol label:(NSString *)label action:(SEL)action frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    [button setImage:NoshiSymbolImage(symbol, 22, NoshiColorTitle()) forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:button];
    return button;
}

- (void)addSelectionBar:(CGFloat)width {
    _bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, BAR_HEIGHT)];
    _bar.backgroundColor = NoshiColorCard();
    _barLine = [[[UIView alloc] initWithFrame:CGRectMake(0, BAR_HEIGHT - 1, width, 1)] autorelease];
    _barLine.backgroundColor = NoshiColorHairline();
    _barLine.hidden = YES;
    [_bar addSubview:_barLine];
    [self addSubview:_bar];
    [self selectionButton:NoshiSymbolClose label:NSLocalizedString(@"chat.msg.cancel", nil) action:@selector(cancelSelection) frame:CGRectMake(4, 0, 44, 48)];
    UILabel *count = [[[UILabel alloc] initWithFrame:CGRectMake(54, 0, 80, 48)] autorelease];
    count.backgroundColor = [UIColor clearColor];
    count.font = NoshiFontSemibold(17);
    count.textColor = NoshiColorTitle();
    count.text = [NSString stringWithFormat:@"%lu", (unsigned long)_selected.count];
    [_bar addSubview:count];
    UIButton *view = [self selectionButton:NoshiSymbolEye label:NSLocalizedString(@"chat.msg.details", nil) action:@selector(viewSelection) frame:CGRectMake(width - 96, 0, 44, 48)];
    view.enabled = _selected.count == 1;
    view.alpha = view.enabled ? 1 : 0.35;
    [self selectionButton:NoshiSymbolForward label:NSLocalizedString(@"chat.msg.forward", nil) action:@selector(forwardSelection) frame:CGRectMake(width - 48, 0, 44, 48)];
}

- (UIScrollView *)hostScroll {
    UIView *view = self.superview;
    while (view && ![view isKindOfClass:[UIScrollView class]]) view = view.superview;
    return (UIScrollView *)view;
}

/* the bar waits where the list begins, and once that scrolls under the top bar it stays below the bar, so the buttons are in reach without a scroll back up */
- (void)hostDidScroll {
    if (!_bar) return;
    CGFloat home = 40.0 + TABS_GAP;
    CGFloat last = MAX(home, self.bounds.size.height - BAR_HEIGHT);
    CGFloat y = home;
    UIScrollView *scroll = [self hostScroll];
    if (scroll) {
        CGFloat top = [self convertPoint:CGPointMake(0, scroll.contentOffset.y + scroll.contentInset.top) fromView:scroll].y;
        y = MAX(home, MIN(top, last));
    }
    CGRect frame = _bar.frame;
    frame.origin.y = y;
    _bar.frame = frame;
    BOOL pinned = y > home + 0.5;
    /* a line closes the bar over the rows once it floats */
    _barLine.hidden = !pinned;
}

- (void)cancelSelection {
    [_selected removeAllObjects];
    [self rebuild];
}

- (void)toggleSelection:(NoshiMessage *)message {
    if (message.messageId <= 0) return;
    NSNumber *key = [NSNumber numberWithInt:message.messageId];
    if ([_selected containsObject:key]) [_selected removeObject:key];
    else if (_selected.count < NOSHI_MESSAGES_MAX) [_selected addObject:key];
    else { NoshiGiftAlert(nil, NSLocalizedString(@"chat.select.limit", nil)); return; }
    [self rebuild];
}

- (void)rowHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || _tab == NoshiGroupTabMembers || _tab == NoshiGroupTabCommon) return;
    NSUInteger index = (NSUInteger)gesture.view.tag;
    if (index < _items[_tab].count) [self toggleSelection:[_items[_tab] objectAtIndex:index]];
}

- (void)viewSelection {
    if (_selected.count != 1) return;
    NSNumber *key = [_selected anyObject];
    for (NoshiMessage *message in _items[_tab]) {
        if (message.messageId != key.intValue) continue;
        [self cancelSelection];
        [_delegate groupTabs:self didOpenMessage:message];
        return;
    }
}

- (void)forwardSelection {
    if (!_selected.count || _forwarding) return;
    UIResponder *responder = self;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) responder = [responder nextResponder];
    UIViewController *host = (UIViewController *)responder;
    if (!host.navigationController) { NSLog(@"noshigram: no navigation controller for forwarding shared messages"); return; }
    /* the rows of the tabs that hold messages, in the order the server numbers them */
    NSMutableArray *messages = [NSMutableArray arrayWithCapacity:_selected.count];
    for (int tab = 0; tab < NoshiGroupTabCount; ++tab) {
        if (tab == NoshiGroupTabMembers || tab == NoshiGroupTabCommon) continue;
        for (NoshiMessage *message in _items[tab]) {
            if ([_selected containsObject:[NSNumber numberWithInt:message.messageId]]) [messages addObject:message];
        }
    }
    if (!messages.count) return;
    [messages sortUsingComparator:^NSComparisonResult(NoshiMessage *a, NoshiMessage *b) {
        return a.messageId < b.messageId ? NSOrderedAscending : (a.messageId > b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"chat.msg.forward.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(NoshiDialog *dialog) { return !dialog.folder && !dialog.community && (dialog.kind != NOSHI_DIALOG_CHANNEL || dialog.canPost); };
    NoshiWeakReference *weak = _weak;
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiGroupTabsView *view = weak.target;
        NoshiDialog *target = [dialogs lastObject];
        if (!view || !target || view->_forwarding) return;
        view->_forwarding = YES;
        NoshiForwardMessages(view->_session, view->_media, view->_dialog, view->_dialog.noForwards, messages, target, NO, ^(NSString *errorText) {
            NoshiGroupTabsView *owner = weak.target;
            if (owner) owner->_forwarding = NO;
            if (errorText) {
                NSLog(@"noshigram: forwarding shared messages failed: %@", errorText);
                NoshiGiftAlert(nil, errorText);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
            if (owner) [owner cancelSelection];
            NoshiGiftAlert(nil, NSLocalizedString(@"chat.msg.forwarded", nil));
        });
    };
    [host.navigationController pushViewController:picker animated:YES];
}

- (void)rowTapped:(UIControl *)area {
    NSArray *items = _items[_tab];
    if ((NSUInteger)area.tag >= items.count) return;
    id item = [items objectAtIndex:(NSUInteger)area.tag];
    if (_tab == NoshiGroupTabCommon) {
        if ([_delegate respondsToSelector:@selector(groupTabs:didOpenDialog:)]) [_delegate groupTabs:self didOpenDialog:item];
        return;
    }
    if (_selected.count && _tab != NoshiGroupTabMembers) {
        [self toggleSelection:item];
        return;
    }
    if (_tab == NoshiGroupTabAudio) {
        NSMutableArray *queue = [NSMutableArray array];
        for (NoshiMessage *message in items) if (message.media.file) [queue addObject:message.media];
        NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
        if ([player isCurrentTrack:((NoshiMessage *)item).media]) [player togglePause];
        else [player playTrack:((NoshiMessage *)item).media queue:queue media:_media];
        return;
    }
    if (_tab == NoshiGroupTabMembers) {
        [_delegate groupTabs:self didOpenPerson:[(NoshiChannelMember *)item person]];
        return;
    }
    if (_tab == NoshiGroupTabMedia) {
        /* the pictures and videos that can be shown are the pages of the viewer */
        NSMutableArray *pages = [NSMutableArray array];
        for (NoshiMessage *message in items) {
            noshi_preview_kind kind = message.media.kind;
            if (message.media.file && noshi_media_opens_viewer(kind)) [pages addObject:message];
        }
        if ([pages containsObject:item]) {
            [_delegate groupTabs:self didOpenMedia:item among:pages];
            return;
        }
    }
    [_delegate groupTabs:self didOpenMessage:item];
}

#pragma mark layout

- (CGFloat)heightForWidth:(CGFloat)width {
    if (fabs(width - _width) > 0.5) {
        _width = width;
        [self rebuild];
    }
    return 40.0 + (_body.hidden ? 0 : TABS_GAP + _bodyHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _tabs.frame = CGRectMake(0, 0, width, 40.0);
    _body.frame = CGRectMake(0, 40.0 + TABS_GAP, width, _bodyHeight);
    if (_bar) _bar.frame = CGRectMake(0, _bar.frame.origin.y, width, BAR_HEIGHT);
    [self hostDidScroll];
}

@end

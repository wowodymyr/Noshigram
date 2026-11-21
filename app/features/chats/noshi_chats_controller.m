#import "noshi_draft.h"
#import "noshi_alert_view.h"
#import "noshi_dust_effect.h"
#import "noshi_lite_mode.h"
#import "noshi_status_label.h"
#import "noshi_chats_controller.h"
#import "noshi_developers.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_dialog.h"
#import "noshi_session_channels.h"
#import "noshi_folder_tabs.h"
#import "noshi_perf_probe.h"
#import "noshi_table_update.h"
#import "noshi_bookmarks_controller.h"
#import "noshi_chat_controller.h"
#import "noshi_chats_menu.h"
#import "noshi_chat_peek.h"
#import "noshi_force_touch.h"
#import "noshi_quick_actions.h"
#import "noshi_search_controller.h"
#import "noshi_split_controller.h"
#import "noshi_search_field.h"
#import "noshi_dialog_cell.h"
#import "noshi_login_prompt.h"
#import "noshi_developers.h"
#import "noshi_mini_player.h"
#import "noshi_name_badge.h"
#import "noshi_animation.h"
#import "noshi_platform.h"
#import "noshi_popup_menu.h"
#import "noshi_shiro_button.h"
#import "noshi_story_strip.h"
#import "noshi_symbol.h"
#import "noshi_chat_settings.h"
#import "noshi_more_settings_controller.h"
#import "noshi_proxy_settings.h"
#import "noshi_person.h"
#import "noshi_falling_view.h"
#import "noshi_sheet.h"
#import "noshi_theme.h"
#import "noshi_imported_theme.h"
#import "noshi_community_screen.h"
#import "noshi_topics_screen.h"
#import "noshi_weak_reference.h"
#import "noshi_string_drawing.h"
#include "noshi_clock.h"
#include "noshi_list_state.h"

#define SEARCH_HEIGHT 38.0
#define HEADER_HEIGHT (SEARCH_HEIGHT + 12)
/* a scan of a custom folder younger than this is not repeated; the kept chats are the folder */
#define FOLDER_KEPT_FRESH_SECONDS 90.0
/* the room above the folders when the field of search is hidden */
#define HEADER_HEIGHT_NO_SEARCH 6.0

static CGFloat NoshiChatsHeaderTop(void) {
    return NoshiChatFlagGet(NoshiChatFlagHideSearchBar) ? HEADER_HEIGHT_NO_SEARCH : HEADER_HEIGHT;
}

@interface NoshiChatsController () <NoshiDialogCellDelegate, UIAlertViewDelegate> {
    NoshiWeakReference *_badgeWeak;
    int32_t _folderId;
    /* the picture of the old rows that is leaving while a change of folder slides the new ones in */
    UIView *_leavingRows;
    BOOL _archiveHidden;
    /* the channels the feed of unread channels has shown since the person opened one from this list */
    NSMutableSet *_feedSeen;
    BOOL _vpnHidden;
    NoshiChatsMenu *_chatsMenu;
    NoshiDialogCell *_openCell;
    NoshiChatListStyle _listStyle;
    NoshiChatSwipe _swipe;
    NSArray *_dialogs;
    NSArray *_mainDialogs;
    /* the chats of the main list beyond the first request, kept across reloads so a refresh that returns the first hundred does not cut the list back */
    NSArray *_moreDialogs;
    BOOL _moreLoading;
    NSMutableDictionary *_folderSnapshots;
    NSMutableDictionary *_folderSnapshotDates;
    BOOL _usingFolderSnapshot;
    NSArray *_shown;
    /* the rows the table shows now, named by NoshiDialogRowKey, so a refresh can move them instead of redrawing the list */
    NSArray *_displayedKeys;
    UIView *_header;
    NoshiFolderTabs *_folders;
    NoshiMiniPlayer *_miniPlayer;
    id<NoshiFolderDialogRequest> _folderLoad;
    NSUInteger _folderProgressToken;
    uint64_t _lastLiveRefreshMs;
    UITextField *_search;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickerLibrary;
    NoshiStoryStrip *_stories;
    NoshiFallingView *_snow;
    NoshiFallingView *_foxes;
    NoshiLoginPrompt *_prompt;
    BOOL _liveRefreshScheduled;
}
@end

@implementation NoshiChatsController

@synthesize chatsDelegate = _chatsDelegate;
@synthesize folderId = _folderId;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(NoshiSession *)session {
    self = [super initWithSession:session];
    if (!self) return nil;
    self.contentUnderBar = YES;
    _badgeWeak = [[NoshiWeakReference referenceTo:self] retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogListChanged:) name:NoshiDialogsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localMarksChanged) name:NoshiLocalMarksDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogRead:) name:NoshiDialogReadNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outboxRead:) name:NoshiReadOutboxDidChangeNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liveDialogsChanged:) name:NoshiSessionDialogsUpdatedNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newMessageArrived:) name:NoshiNewMessageDidArriveNotification object:session];
    self.heading = [self titleForMode:NoshiChatListTitleStored() person:nil];
    _dialogs = [[NSArray alloc] init];
    _folderSnapshots = [[NSMutableDictionary alloc] init];
    _folderSnapshotDates = [[NSMutableDictionary alloc] init];
    _shown = [[NSArray alloc] init];
    _listStyle = NoshiChatListStyleStored();
    _swipe = NoshiChatSwipeStored();
    _archiveHidden = NoshiArchiveHidden();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(archiveSummaryChanged:)
        name:NoshiArchiveSummaryDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forumSummariesChanged:)
        name:NoshiForumSummariesDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:)
        name:NoshiTypingDidChangeNotification object:self.session.typing];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:)
        name:NoshiDraftDidChangeNotification object:self.session.drafts];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged)
        name:NoshiChatSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(folderRulesChanged:)
        name:NoshiChatFoldersDidChangeNotification object:session];
    return self;
}

- (void)liveDialogsChanged:(NSNotification *)note {
    (void)note;
    if (!self.isViewLoaded) return;
    /* a list under a chat or another tab drops the event, and its next appearance reloads only after 60 seconds: a chat read on another client kept its unread badge */
    if (!self.view.window) {
        [_folderSnapshotDates removeAllObjects];
        [self dialogsChanged];
        return;
    }
    if (_liveRefreshScheduled) return;
    _liveRefreshScheduled = YES;
    uint64_t now = noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
    uint64_t delay = noshi_list_refresh_delay(now, _lastLiveRefreshMs, 750, 100);
    [self performSelector:@selector(refreshLiveDialogs) withObject:nil afterDelay:(NSTimeInterval)delay / 1000.0];
}

/* the list that the server sends takes a round trip after the pause between reloads, and the banner of the message is up before that: the row shows the message and moves up
   at once, and the list that follows says the same */
- (void)newMessageArrived:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    NSArray *updated = NoshiDialogsApplyingNewMessage(_dialogs, note.userInfo);
    if (!updated) return;
    [_dialogs release];
    _dialogs = [updated retain];
    if (!_folderId && !_folders.selectedFolder.folderId) {
        [_mainDialogs release];
        _mainDialogs = [updated retain];
    }
    [self refreshCounts];
    [self applyFilters];
    [self reloadTable];
}

- (void)refreshLiveDialogs {
    _liveRefreshScheduled = NO;
    if (self.view.window) {
        _lastLiveRefreshMs = noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
        [_folderSnapshotDates removeAllObjects];
        [self reloadAfterCurrent];
    } else {
        [_folderSnapshotDates removeAllObjects];
        [self dialogsChanged];
    }
}

- (void)dialogListChanged:(NSNotification *)note {
    (void)note;
    if (self.isViewLoaded) [self reloadDiscardingRunning];
}

- (void)folderRulesChanged:(NSNotification *)notification {
    [_folderSnapshots removeAllObjects];
    [_folderSnapshotDates removeAllObjects];
}

/* the title of the main list is the word Chats, or what the person chose to read there; the name and the username come once the account answers */
- (NSString *)titleForMode:(NoshiChatListTitle)mode person:(NoshiPerson *)person {
    if (_folderId || self.showsBack) return NSLocalizedString(@"chats.title", nil);
    return NoshiChatListTitleText(mode, person);
}

- (void)loadOwnTitle {
    NoshiChatListTitle mode = NoshiChatListTitleStored();
    if (mode != NoshiChatListTitleUsername && mode != NoshiChatListTitleName) return;
    [self retain];
    [self.session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items.count) {
            NSLog(@"noshigram: the name for the title of the list did not load: %@", errorName);
            return;
        }
        self.heading = [self titleForMode:mode person:[items objectAtIndex:0]];
    }];
}

/* the stories switch of the settings takes the strip away, or brings it back, without leaving the screen */
- (void)syncStoriesWithSettings {
    if (NoshiChatFlagGet(NoshiChatFlagHideStories) && _stories) {
        [_stories.view removeFromSuperview];
        [_stories release];
        _stories = nil;
        [self.view setNeedsLayout];
    } else if (!NoshiChatFlagGet(NoshiChatFlagHideStories) && !_stories) {
        [self ensureStories];
        [_stories refresh];
        [self.view setNeedsLayout];
    }
}

/* the rows are laid out when they are built, so a new row style (one line of the preview or two) needs them built
   again */
- (void)chatSettingsChanged {
    /* the title was set when the screen was made, so a new choice (the word, the name, the username, a text of the person's own) waited for the next start; the person of the
       account is the one the session already holds, and the answer of the server follows */
    NSString *heading = [self titleForMode:NoshiChatListTitleStored() person:[self.session ownPerson]];
    if (![heading isEqualToString:self.heading]) self.heading = heading;
    [self loadOwnTitle];
    [self syncStoriesWithSettings];
    if (!_folderId && !self.showsBack && _vpnHidden != NoshiChatFlagGet(NoshiChatFlagHideVpnButton)) [self syncVpnButtonWithSettings];
    BOOL archiveChanged = _archiveHidden != NoshiArchiveHidden();
    _archiveHidden = NoshiArchiveHidden();
    if (archiveChanged) {
        [self applyFilters];
        [self reloadTable];
    }
    NoshiChatListStyle style = NoshiChatListStyleStored();
    NoshiChatSwipe swipe = NoshiChatSwipeStored();
    if (style == _listStyle && swipe == _swipe) return;
    _listStyle = style;
    _swipe = swipe;
    [self reloadTable];
}

- (void)archiveSummaryChanged:(NSNotification *)note {
    if (_folderId != 0) return;
    NSArray *updated = [NoshiDialogsReplacingArchive(_dialogs, [note.userInfo objectForKey:@"dialog"]) retain];
    [_dialogs release];
    _dialogs = updated;
    [self applyFilters];
    [self reloadTable];
}

/* the topics of a forum were read: its row names the topic of the last message and counts what is unread in them */
- (void)forumSummariesChanged:(NSNotification *)note {
    if (!self.isViewLoaded || !_dialogs.count) return;
    [self.session applyForumSummariesToDialogs:_dialogs];
    [self.session applyForumSummariesToDialogs:_mainDialogs];
    /* a folder tab that is shown from its snapshot holds rows of its own, which the two lists above do not reach */
    for (NSArray *snapshot in [_folderSnapshots allValues]) [self.session applyForumSummariesToDialogs:snapshot];
    [self loadBadgePictures];
    [self refreshCounts];
    [self applyFilters];
    [self reloadTable];
}

/* only the rows of the chat that changed are built again; a typing change in a chat that is not on screen touches nothing */
- (void)typingChanged:(NSNotification *)note {
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && NoshiTypingChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count == 0) return;
    [self.table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* a draft the person typed here or the account sent moves its chat to where its date puts it, and the row shows the new words; only that chat is touched */
- (void)draftChanged:(NSNotification *)note {
    if (!self.isViewLoaded || !_dialogs.count) return;
    NSDictionary *info = note.userInfo;
    NSArray *moved = NoshiDialogsMovedForDraft(_dialogs, self.session.drafts, [[info objectForKey:@"kind"] intValue], [[info objectForKey:@"peer"] longLongValue],
                                                 [[info objectForKey:@"top"] intValue]);
    if (moved != _dialogs) {
        [_dialogs release];
        _dialogs = [moved retain];
        [self applyFilters];
        [self reloadTable];
        return;
    }
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && NoshiDraftChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [self.table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* the rows on screen as a picture, over the table and under the bar of folders, for the old list to leave in while the new one comes; nil when there is no
   room for rows or the person asked for no motion */
- (UIView *)snapshotOfRowsForSlide {
    UITableView *table = self.table;
    /* a change of folder while the last one still slides: its picture goes at once and the rows that were moving stand still, or the two lists lay over each other and
       the picture taken of the rows held half of the old slide */
    [_leavingRows.layer removeAllAnimations];
    [_leavingRows removeFromSuperview];
    [_leavingRows release];
    _leavingRows = nil;
    for (UITableViewCell *cell in [table visibleCells]) {
        [cell.layer removeAllAnimations];
        cell.transform = CGAffineTransformIdentity;
    }
    if (NoshiReduceMotionEnabled() || !self.isViewLoaded || !table.window || !_folders.slideDirection) return nil;
    CGFloat top = MAX(table.contentInset.top, CGRectGetMaxY(_header.frame) - table.contentOffset.y);
    CGSize size = CGSizeMake(table.bounds.size.width, table.bounds.size.height - top);
    if (size.width <= 0 || size.height <= 0) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(), -table.bounds.origin.x, -(table.bounds.origin.y + top));
    [table.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!picture) return nil;
    UIImageView *view = [[[UIImageView alloc] initWithImage:picture] autorelease];
    view.frame = CGRectMake(table.frame.origin.x, table.frame.origin.y + top, size.width, size.height);
    view.userInteractionEnabled = NO;
    return view;
}

/* the new rows come in from the side the swipe moves toward as the old picture leaves to the other, so a change of
   folder reads as a page turning */
- (void)slideRowsInDirection:(NSInteger)direction replacing:(UIView *)leaving {
    if (!leaving) return;
    CGFloat width = leaving.bounds.size.width;
    CGFloat boundary = leaving.frame.origin.y - self.table.frame.origin.y;
    [_leavingRows release];
    _leavingRows = [leaving retain];
    [self.view insertSubview:leaving aboveSubview:self.table];
    /* reloadData makes its cells at the next layout, so with none yet the new rows had nothing to slide and stood still while the old picture left */
    [self.table layoutIfNeeded];
    for (UITableViewCell *cell in [self.table visibleCells]) {
        if (CGRectGetMaxY(cell.frame) - self.table.contentOffset.y <= boundary) continue;
        NoshiAnimateEnter(cell, CGAffineTransformMakeTranslation((CGFloat)direction * width, 0), 1, NOSHI_MOTION_ENTER);
    }
    NoshiAnimateView(leaving, CGAffineTransformMakeTranslation((CGFloat)-direction * width, 0), 1, NOSHI_MOTION_ENTER, ^(BOOL finished) {
        (void)finished;
        [leaving removeFromSuperview];
        if (_leavingRows == leaving) {
            [_leavingRows release];
            _leavingRows = nil;
        }
    });
}

/* a chat was read here: its count goes from the row now, without asking the server for the list, which can still answer with the old count or make the list wait */
- (void)dialogRead:(NSNotification *)note {
    /* the rows of the main list and of the folder tabs that are not on screen are other objects of the same chat, and would bring the old count back when their tab is opened */
    BOOL others = NoshiDialogsApplyingRead(_mainDialogs, note.userInfo);
    for (NSArray *snapshot in [_folderSnapshots allValues]) if (NoshiDialogsApplyingRead(snapshot, note.userInfo)) others = YES;
    if (!NoshiDialogsApplyingRead(_dialogs, note.userInfo) && !others) return;
    [self refreshCounts];
    if (self.isViewLoaded) [self reloadTable];
}

/* the other side read our last message here: the double check comes to its row now, as the list under a chat did not draw it until its next reload */
/* what the other side has read is told once, by an update, and the session keeps the number; a list made later from rows that are older than the update (the rows kept on
   the disk, a tab shown from its snapshot, the rows of a scan) would keep the single check until the server sent the list again */
- (BOOL)applyKnownOutboxReadsTo:(NSArray *)dialogs {
    BOOL changed = NO;
    for (NoshiDialog *dialog in dialogs) {
        if (dialog.folder || dialog.community || dialog.topicId) continue;
        int32_t known = [self.session readOutboxOfKind:dialog.peerKind peer:dialog.peerId topic:0];
        if (known > 0 && [dialog applyReadOutboxUpTo:known]) changed = YES;
    }
    return changed;
}

- (void)outboxRead:(NSNotification *)note {
    /* the rows of the main list and of the tabs that are not on screen are other objects of the same chat, which would bring the single check back when their tab is opened */
    BOOL others = NoshiDialogsApplyingReadOutbox(_mainDialogs, note.userInfo);
    for (NSArray *snapshot in [_folderSnapshots allValues]) if (NoshiDialogsApplyingReadOutbox(snapshot, note.userInfo)) others = YES;
    if (!NoshiDialogsApplyingReadOutbox(_dialogs, note.userInfo) && !others) return;
    if (self.isViewLoaded) [self reloadTable];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiDialogReadNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiReadOutboxDidChangeNotification object:self.session];
    [_feedSeen release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLiveDialogs) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiSessionDialogsUpdatedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiNewMessageDidArriveNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiDialogsChangedNotification object:nil];
    [_badgeWeak clear];
    [_badgeWeak release];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiArchiveSummaryDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiForumSummariesDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiTypingDidChangeNotification object:self.session.typing];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiDraftDidChangeNotification object:self.session.drafts];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiChatSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiChatFoldersDidChangeNotification object:self.session];
    _search.delegate = nil;
    [_openCell release];
    [_dialogs release];
    [_mainDialogs release];
    [_moreDialogs release];
    [_folderSnapshots release];
    [_folderSnapshotDates release];
    [_leavingRows removeFromSuperview];
    [_leavingRows release];
    [_shown release];
    [_displayedKeys release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_folders release];
    [_header release];
    _miniPlayer.changeHandler = nil;
    [_chatsMenu release];
    [_miniPlayer release];
    [_search release];
    [_media release];
    [_stickerLibrary release];
    [_snow stop];
    [_snow release];
    [_foxes stop];
    [_foxes release];
    [_stories release];
    [_prompt release];
    [super dealloc];
}

/* the menu of the main list, with the VPN button left of it unless the settings hide it; the list gives the pair the width of both */
- (void)syncVpnButtonWithSettings {
    _vpnHidden = NoshiChatFlagGet(NoshiChatFlagHideVpnButton);
    UIButton *dots = [UIButton buttonWithType:UIButtonTypeCustom];
    [dots setImage:NoshiSymbolImage(NoshiSymbolEllipsis, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    [dots addTarget:self action:@selector(showMenu:) forControlEvents:UIControlEventTouchUpInside];
    dots.accessibilityLabel = NSLocalizedString(@"chats.menu", nil);
    UIView *pair;
    if (_vpnHidden) {
        pair = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 44)] autorelease];
        dots.frame = CGRectMake(0, 0, 52, 44);
    } else {
        NoshiShiroButton *vpn = [[[NoshiShiroButton alloc] initWithShiro:self.session.shiro host:self] autorelease];
        CGSize pill = [vpn preferredSize];
        pair = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, pill.width + 4 + 52, 44)] autorelease];
        vpn.frame = CGRectMake(0, (44 - pill.height) / 2, pill.width, pill.height);
        vpn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        dots.frame = CGRectMake(pill.width + 4, 0, 52, 44);
        [pair addSubview:vpn];
    }
    dots.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [pair addSubview:dots];
    self.barAccessory = pair;
}

- (void)loadView {
    [super loadView];
    if (!_folderId && !self.showsBack) {
        /* the main list carries the menu; the title steps to the left edge of the field under it */
        self.titleOnLeft = YES;
        self.showsConnection = YES;
        [self syncVpnButtonWithSettings];
    }
    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, HEADER_HEIGHT)];
    _header.backgroundColor = [UIColor clearColor];

    _search = [[NoshiSearchField alloc] init];
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _search.backgroundColor = NoshiImportedThemeColor("root.searchBar.inputFill") ?: NoshiColorField();
    _search.layer.cornerRadius = SEARCH_HEIGHT / 2;
    _search.delegate = self;
    _search.placeholder = NSLocalizedString(@"chats.search", nil);
    _search.font = NoshiFontRegular(16);
    _search.textColor = NoshiImportedThemeColor("root.searchBar.inputText") ?: NoshiColorTitle();
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, 16, NoshiImportedThemeColor("root.searchBar.inputIcon") ?: NoshiColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, 38, SEARCH_HEIGHT);
    _search.leftView = glass;
    _search.leftViewMode = UITextFieldViewModeAlways;
    [_header addSubview:_search];
    /* the song that plays has its strip over the folders, with the buttons to change it */
    NoshiWeakReference *playerWeak = [NoshiWeakReference referenceTo:self];
    _miniPlayer = [[NoshiMiniPlayer alloc] init];
    _miniPlayer.changeHandler = ^{
        UIView *view = [(NoshiChatsController *)playerWeak.target view];
        [view setNeedsLayout];
        [view layoutIfNeeded];
    };
    [_header addSubview:_miniPlayer];

    if (!_folderId && !self.showsBack) {
        /* the card lives as long as this screen, so its callback must not keep the screen alive */
        NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
        _prompt = [[NoshiLoginPrompt alloc] initWithSession:self.session changed:^{ [[(NoshiChatsController *)me.target view] setNeedsLayout]; }];
        [_header addSubview:_prompt.view];
    }
    if (!_folderId && !self.showsBack) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        _folders = [[NoshiFolderTabs alloc] initWithSession:self.session media:_media changed:^{
            NoshiChatsController *me = weak.target;
            if (!me || !me->_folders) return;
            [me closeOpenCell];
            UIView *leaving = [me snapshotOfRowsForSlide];
            [me.view setNeedsLayout];
            NSNumber *key = [NSNumber numberWithInt:me->_folders.selectedFolder.folderId];
            NSArray *known = [me->_folderSnapshots objectForKey:key];
            /* a folder not seen yet starts empty: the main list under its tab was other chats, which the first rows of the scan then replaced on the screen */
            if (!known) known = key.intValue ? [NSArray array] : me->_mainDialogs;
            if (!known) known = [NSArray array];
            [me applyKnownOutboxReadsTo:known];
            if (known != me->_dialogs) {
                [known retain];
                [me->_dialogs release];
                me->_dialogs = known;
            }
            [me applyFilters];
            [me reloadTable];
            [me reloadDiscardingRunning];
            [me slideRowsInDirection:me->_folders.slideDirection replacing:leaving];
        }];
        [_header addSubview:_folders];
        [_folders installPagingInView:self.view];
        [_folders refresh];
    }
    self.table.tableHeaderView = _header;
    UILongPressGestureRecognizer *peek = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(peekChat:)] autorelease];
    [self.table addGestureRecognizer:peek];
    [self.table addGestureRecognizer:[[[NoshiForceTouchRecognizer alloc] initWithTarget:self action:@selector(peekChat:)] autorelease]];
    [self loadOwnTitle];
}

/* the archive row has no card to peek into; a press on it offers to read everything in it */
- (void)askToReadFolder:(NoshiDialog *)folder {
    UIView *host = self.view.window ? NoshiOverlayHost() : nil;
    if (!host) return;
    [self closeOpenCell];
    NoshiWeakReference *weak = _badgeWeak;
    int32_t folderId = folder.folderId;
    [NoshiSheet presentInView:host title:nil message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"chats.archive.readall", nil)] destructive:nil
                    cancelTitle:NSLocalizedString(@"notice.cancel", nil) handler:^(NSUInteger index) {
        NoshiChatsController *controller = weak.target;
        if (!controller || index != 0) return;
        [controller.session markAllReadInFolder:folderId completion:^(NSString *errorName) {
            NoshiChatsController *again = weak.target;
            if (!again) return;
            if (errorName) {
                NSLog(@"noshigram: reading the archive failed: %@", errorName);
                [again showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                              : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
            }
            [again reloadDiscardingRunning];
        }];
    }];
}

- (void)peekChat:(UIGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *path = [self.table indexPathForRowAtPoint:[gesture locationInView:self.table]];
    if (!path || (NSUInteger)path.row >= _shown.count) return;
    NoshiDialog *dialog = [_shown objectAtIndex:(NSUInteger)path.row];
    if (dialog.folder) {
        [self askToReadFolder:dialog];
        return;
    }
    if (dialog.community) return;
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
    /* the screen on top, not the window: before ios 8 a view put in the window keeps the turn of the device, and on an ipad held sideways the card and its menu lay on their side */
    UIView *host = self.view.window ? NoshiOverlayHost() : nil;
    if (!cell || !host) return;
    [self closeOpenCell];
    CGRect source = [self.table convertRect:cell.frame toView:host];
    NoshiWeakReference *weak = _badgeWeak;
    NoshiShowChatPeek(host, source, dialog, self.session, self.avatars, _media, NO, ^(NoshiChatPeekAction action) {
        NoshiChatsController *controller = weak.target;
        if (!controller) return;
        NSUInteger index = NSNotFound;
        for (NSUInteger i = 0; i < controller->_shown.count; ++i) {
            NoshiDialog *current = [controller->_shown objectAtIndex:i];
            if (current.peerKind == dialog.peerKind && current.peerId == dialog.peerId && current.topicId == dialog.topicId) { index = i; break; }
        }
        if (index == NSNotFound) return;
        NSIndexPath *currentPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        NoshiDialog *current = [controller->_shown objectAtIndex:index];
        if (action == NoshiChatPeekOpen) [controller tableView:controller.table didSelectRowAtIndexPath:currentPath];
        else if (action == NoshiChatPeekPin || action == NoshiChatPeekMute) {
            NoshiChatCommand command = action == NoshiChatPeekPin ? (current.pinned ? NoshiChatCommandUnpin : NoshiChatCommandPin)
                                                                        : (current.muted ? NoshiChatCommandUnmute : NoshiChatCommandMute);
            [controller runCommand:command onDialog:current cell:(NoshiDialogCell *)[controller.table cellForRowAtIndexPath:currentPath]];
        } else if (action == NoshiChatPeekMarkRead) {
            /* a chat that is only marked unread has nothing to read, and the mark is taken off instead */
            [controller runCommand:current.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark onDialog:current
                              cell:(NoshiDialogCell *)[controller.table cellForRowAtIndexPath:currentPath]];
        } else if (action == NoshiChatPeekArchive) {
            [controller.session moveDialog:current toFolder:current.folderId ? 0 : 1 completion:^(NSString *error) {
                NoshiChatsController *again = weak.target;
                if (!again) return;
                if (error) [again showFailureText:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), error]];
                else [again reload];
            }];
        }
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.table.bounds.size.width;
    CGRect frame = _header.frame;
    CGFloat promptHeight = [_prompt heightForWidth:width];
    CGFloat top = NoshiChatsHeaderTop();
    CGFloat player = _miniPlayer.showing ? [NoshiMiniPlayer height] : 0;
    CGFloat height = top + player + _folders.height + _stories.height + (promptHeight > 0 ? promptHeight + 8 : 0);
    if (frame.size.width != width || frame.size.height != height) {
        frame.size.width = width;
        frame.size.height = height;
        _header.frame = frame;
        self.table.tableHeaderView = _header;
    }
    _search.frame = CGRectMake(14, 4, width - 28, SEARCH_HEIGHT);
    _search.hidden = NoshiChatFlagGet(NoshiChatFlagHideSearchBar);
    _miniPlayer.frame = CGRectMake(0, top, width, player);
    _folders.frame = CGRectMake(0, top + player, width, _folders.height);
    [_stories layoutInWidth:width];
    CGRect strip = _stories.view.frame;
    strip.origin = CGPointMake(0, top + player + _folders.height);
    _stories.view.frame = strip;
    if (promptHeight > 0) [_prompt layoutInWidth:width atY:top + player + _folders.height + _stories.height];
}

/* only the main list has stories; the archive and a pushed list do not */
- (void)ensureStories {
    if (_stories || _folderId || self.showsBack || !_media || !self.isViewLoaded || NoshiChatFlagGet(NoshiChatFlagHideStories)) return;
    /* the strip lives as long as this screen, so its callback must not keep the screen alive */
    NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
    _stories = [[NoshiStoryStrip alloc] initWithSession:self.session avatars:self.avatars media:_media host:self changed:^{
        [[(NoshiChatsController *)me.target view] setNeedsLayout];
    }];
    _stories.peersChanged = ^{
        NoshiChatsController *controller = (NoshiChatsController *)me.target;
        if (!controller) return;
        for (NSIndexPath *path in controller->_table.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row >= controller->_shown.count) continue;
            NoshiDialogCell *cell = (NoshiDialogCell *)[controller->_table cellForRowAtIndexPath:path];
            [cell setStoryPeer:[controller->_stories peerForDialog:[controller->_shown objectAtIndex:(NSUInteger)path.row]]];
        }
    };
    [_header addSubview:_stories.view];
}

#pragma mark data

- (void)loadItemsWithCompletion:(NoshiListCompletion)completion {
    NSUInteger token = ++_folderProgressToken;
    [_folderLoad cancel];
    [_folderLoad release];
    _folderLoad = nil;
    _usingFolderSnapshot = NO;
    if (!_folderId && _folders.selectedFolder.folderId) {
        NSNumber *key = [NSNumber numberWithInt:_folders.selectedFolder.folderId];
        NSArray *snapshot = [_folderSnapshots objectForKey:key];
        NSDate *date = [_folderSnapshotDates objectForKey:key];
        if (snapshot && date && -[date timeIntervalSinceNow] < 60) {
            _usingFolderSnapshot = YES;
            completion(snapshot, nil);
            return;
        }
        NoshiChatFolder *folder = [[_folders.selectedFolder copy] autorelease];
        NoshiWeakReference *weak = _badgeWeak;
        void (^show)(NSArray *) = ^(NSArray *items) {
            NoshiChatsController *controller = weak.target;
            if (!controller || token != controller->_folderProgressToken) return;
            /* the rows of a scan are new objects, which know nothing of the topics read meanwhile; a forum without its topic line is a shorter row than in the main list */
            [controller.session applyForumSummariesToDialogs:items];
            [controller applyKnownOutboxReadsTo:items];
            [controller->_folderSnapshots setObject:items forKey:key];
            [items retain];
            [controller->_dialogs release];
            controller->_dialogs = items;
            [controller applyFilters];
            [controller reloadTable];
        };
        void (^scan)(void) = ^{
            NoshiChatsController *controller = weak.target;
            /* the screen waits for an answer to every request it made, a replaced one included */
            if (!controller || token != controller->_folderProgressToken) { completion(nil, @"CANCELLED"); return; }
            controller->_folderLoad = [[controller.session loadDialogsForChatFolder:folder progress:show completion:completion] retain];
        };
        /* a scan of a long list takes many pages of the chat list and ends in a flood wait when it is repeated, so a folder scanned a minute ago is shown from the disk, and an
           older one is shown from the disk while the scan runs */
        NoshiListCompletion keptCompletion = [[completion copy] autorelease];
        NSTimeInterval age = [self.session keptAgeOfChatFolder:folder];
        BOOL fresh = age >= 0 && age < FOLDER_KEPT_FRESH_SECONDS;
        [self.session loadKeptDialogsForChatFolder:folder completion:^(NSArray *kept, NSString *keptError) {
            (void)keptError;
            NoshiChatsController *controller = weak.target;
            if (!controller || token != controller->_folderProgressToken) { keptCompletion(nil, @"CANCELLED"); return; }
            if (kept && fresh) {
                controller->_usingFolderSnapshot = YES;
                keptCompletion(kept, nil);
                return;
            }
            /* the first rows of the scan replace these, and a scan that fails leaves them on the screen */
            if (kept && ![controller->_folderSnapshots objectForKey:key]) show(kept);
            scan();
        }];
    } else if (_folderId) {
        [self.session loadDialogsInFolder:_folderId completion:completion];
    } else {
        NoshiWeakReference *weak = _badgeWeak;
        NoshiListCompletion keptCompletion = [[completion copy] autorelease];
        [self.session loadDialogsInFolder:0 completion:^(NSArray *items, NSString *errorName) {
            NoshiChatsController *controller = weak.target;
            if (!items || !controller) { keptCompletion(items, errorName); return; }
            keptCompletion([controller dialogsAppendingMoreTo:items], nil);
            [controller loadMoreDialogsAfter:items];
        }];
    }
}

static NSString *NoshiDialogListKey(NoshiDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

/* a request returns the newest hundred chats, so the older ones that an earlier walk found are put back behind them */
- (NSArray *)dialogsAppendingMoreTo:(NSArray *)items {
    if (![_moreDialogs count]) return items;
    NSMutableSet *keys = [NSMutableSet set];
    for (NoshiDialog *dialog in items) [keys addObject:NoshiDialogListKey(dialog)];
    NSMutableArray *all = [NSMutableArray arrayWithArray:items];
    for (NoshiDialog *dialog in _moreDialogs) if (![keys containsObject:NoshiDialogListKey(dialog)]) [all addObject:dialog];
    return all;
}

/* the main list stopped at the first hundred chats; the pages after it are walked once, and a failed page leaves the chats that came */
- (void)loadMoreDialogsAfter:(NSArray *)first {
    if (_moreLoading || _moreDialogs || ![self.session mainListHasMore]) return;
    _moreLoading = YES;
    NoshiWeakReference *weak = _badgeWeak;
    [self.session loadRemainingDialogsAfter:first completion:^(NSArray *all) {
        NoshiChatsController *controller = weak.target;
        if (!controller) return;
        controller->_moreLoading = NO;
        NSMutableSet *keys = [NSMutableSet set];
        for (NoshiDialog *dialog in first) [keys addObject:NoshiDialogListKey(dialog)];
        NSMutableArray *more = [NSMutableArray array];
        for (NoshiDialog *dialog in all) if (![keys containsObject:NoshiDialogListKey(dialog)]) [more addObject:dialog];
        /* a walk that found nothing is asked again by the next reload */
        if (!more.count) return;
        controller->_moreDialogs = [more retain];
        if (!controller.isViewLoaded) return;
        /* the main list is whatever the updates made of the first page meanwhile; the new chats go behind it */
        NSArray *merged = [[controller dialogsAppendingMoreTo:controller->_mainDialogs ? controller->_mainDialogs : first] retain];
        [controller->_mainDialogs release];
        controller->_mainDialogs = merged;
        NoshiSetMainDialogsSnapshot(merged);
        /* a chat folder tab shows its own scan, which the main list does not replace */
        if (controller->_folders.selectedFolder.folderId) return;
        [controller->_dialogs release];
        controller->_dialogs = [merged retain];
        [controller refreshCounts];
        [controller applyFilters];
        [controller reloadTable];
    }];
}

- (void)loadKeptItemsWithCompletion:(NoshiListCompletion)completion {
    if (!_folderId && _folders.selectedFolder.folderId) {
        [self.session loadKeptDialogsForChatFolder:_folders.selectedFolder completion:completion];
        return;
    }
    [self.session loadCachedDialogsInFolder:_folderId completion:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    [_openCell release];
    _openCell = nil;
    [_dialogs release];
    _dialogs = [items retain];
    [self applyKnownOutboxReadsTo:items];
    if (!_folderId && _folders.selectedFolder.folderId) {
        [self.session applyForumSummariesToDialogs:items];
        if (!_usingFolderSnapshot) {
            NSNumber *key = [NSNumber numberWithInt:_folders.selectedFolder.folderId];
            [_folderSnapshots setObject:items forKey:key];
            [_folderSnapshotDates setObject:[NSDate date] forKey:key];
        }
    } else if (!_folderId) {
        [_mainDialogs release];
        _mainDialogs = [items retain];
        NoshiSetMainDialogsSnapshot(items);
        NoshiQuickActionsUpdate(items);
    }
    [self loadBadgePictures];
    [self refreshCounts];
    [self applyFilters];
    [self ensureStories];
    [_stories refresh];
    [_prompt refresh];
}

/* the custom emoji statuses that follow the names in the list are fetched once, and the rows on screen are drawn again as they land */
- (void)loadBadgePictures {
    NSMutableArray *documents = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) {
        if (dialog.emojiStatus && !dialog.saved) [documents addObject:[NSNumber numberWithLongLong:dialog.emojiStatus]];
        if (dialog.forumTopicEmoji) [documents addObject:[NSNumber numberWithLongLong:dialog.forumTopicEmoji]];
        for (NoshiTextEntity *entity in dialog.previewEntities) [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
    }
    NoshiWeakReference *weak = _badgeWeak;
    NoshiLoadBadgePictures(documents, self.session, _media, ^{
        NoshiChatsController *controller = weak.target;
        if (controller) NoshiRedrawVisibleRows(controller->_table);
    });
}

NSString *const NoshiUnreadTotalDidChangeNotification = @"NoshiUnreadTotalDidChange";
static NSArray *sMainDialogsSnapshot;
NSArray *NoshiMainDialogsSnapshot(void) { return sMainDialogsSnapshot; }
void NoshiSetMainDialogsSnapshot(NSArray *dialogs) {
    [sMainDialogsSnapshot release];
    sMainDialogsSnapshot = [dialogs retain];
}
static NSInteger sUnreadTotal;
NSInteger NoshiUnreadTotal(void) { return sUnreadTotal; }

- (void)refreshCounts {
    /* the tabs count the main list, which this screen holds only while the tab of all chats is the one shown */
    if (!_folderId) {
        if (!_folders.selectedFolder.folderId && _dialogs.count) NoshiSetMainDialogsSnapshot(_dialogs);
        [_folders updateCountsFromDialogs:NoshiMainDialogsSnapshot()];
    }
    if (_folders.selectedFolder.folderId) return;
    NSInteger total = 0;
    for (NoshiDialog *dialog in _dialogs) {
        if (dialog.unread && !dialog.folder && !dialog.muted && !(dialog.peerKind == 3 && dialog.left)) total += dialog.unreadCount;
    }
    if (!_folderId && !self.showsBack && total != sUnreadTotal) {
        sUnreadTotal = total;
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiUnreadTotalDidChangeNotification object:nil];
    }
    [_chatsDelegate chatsController:self didChangeUnreadTotal:total];
}

/* the archive entry is a shortcut that the person may hide on this device; the archive itself is the account's */
- (void)applyFilters {
    NSMutableArray *shown = [NSMutableArray array];
    BOOL archiveShown = !NoshiArchiveHidden();
    for (NoshiDialog *dialog in _dialogs) {
        if (!dialog.folder && dialog.peerKind == 3 && dialog.left) continue;
        if (_folders.selectedFolder.folderId && ![_folders.selectedFolder containsDialog:dialog]) continue;
        if (dialog.folder && !archiveShown) continue;
        [shown addObject:dialog];
    }
    /* a community shown as one chat holds the chats added to it, which the archive does not fold */
    NSArray *list = _folderId ? shown : NoshiDialogsFoldingCommunities(shown);
    shown = list == shown ? shown : [NSMutableArray arrayWithArray:list];
    [_shown release];
    _shown = [shown retain];
}

- (NSInteger)itemCount {
    return (NSInteger)[_shown count];
}

- (NSString *)emptyText {
    if (_folderId > 0 && ![_dialogs count]) return NSLocalizedString(@"chats.archive.empty", nil);
    return [_dialogs count] ? NSLocalizedString(@"chats.nothing", nil) : NSLocalizedString(@"chats.empty", nil);
}

/* the field on the list is a button: a tap opens the search screen, which has the keyboard, the kinds of results and the
   recent chats, and the list itself stays as it was */
- (BOOL)textFieldShouldBeginEditing:(UITextField *)field {
    (void)field;
    [self openSearch];
    return NO;
}

#pragma mark menu

- (void)showMenu:(UIView *)button {
    if (!_chatsMenu) {
        NoshiWeakReference *weak = _badgeWeak;
        _chatsMenu = [[NoshiChatsMenu alloc] initWithSession:self.session host:self avatars:self.avatars media:_media stickers:_stickerLibrary refresh:^{
            [(NoshiChatsController *)weak.target reloadDiscardingRunning];
        }];
    }
    CGPoint anchor = [button.superview convertPoint:CGPointMake(CGRectGetMaxX(button.frame) - 6, CGRectGetMaxY(button.frame) - 8) toView:self.view];
    [_chatsMenu showInView:self.view anchor:anchor];
}

/* the badges a developer gave himself on this phone: the names in the rows are drawn again */
- (void)localMarksChanged {
    if (self.isViewLoaded) [self reloadTable];
}

- (void)scrollToTopAnimated {
    if (!self.isViewLoaded) return;
    [self closeOpenCell];
    [self.table setContentOffset:CGPointMake(0, -self.table.contentInset.top) animated:YES];
}

- (void)openSearch {
    NoshiSearchController *search = [[[NoshiSearchController alloc] initWithSession:self.session dialogs:_dialogs avatars:self.avatars
                                                                                  media:_media stickers:_stickerLibrary] autorelease];
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.2;
    [self.navigationController.view.layer addAnimation:fade forKey:@"search"];
    [self.navigationController pushViewController:search animated:NO];
}

#pragma mark table

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ((NSUInteger)indexPath.row >= _shown.count) return [NoshiDialogCell rowHeight];
    return [NoshiDialogCell rowHeightForDialog:[_shown objectAtIndex:(NSUInteger)indexPath.row]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"dialog";
    NoshiDialogCell *cell = (NoshiDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    NoshiDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    double began = NoshiPerfNow();
    [self configureCell:cell dialog:dialog];
    NoshiPerfRecord("modern configure", NoshiPerfNow() - began);
    began = NoshiPerfNow();
    [cell layoutIfNeeded];
    NoshiPerfRecord("modern layout", NoshiPerfNow() - began);
    return cell;
}

- (void)configureCell:(NoshiDialogCell *)cell dialog:(NoshiDialog *)dialog {
    cell.swipeDelegate = self;
    [cell yieldSwipeToRecognizers:_folders.pagingRecognizers];
    cell.media = _media;
    [cell configureWithDialog:dialog avatars:self.avatars action:[self swipeActionForDialog:dialog]];
    [cell showDraft:NoshiVisibleDraft(self.session.drafts, dialog)];
    [cell showTypingText:NoshiTypingTextForDialog(self.session.typing, dialog)];
    [cell setStoryPeer:[_stories peerForDialog:dialog]];
    if (dialog.linkedCommunityId) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        cell.communityHandler = ^{ [(NoshiChatsController *)weak.target openCommunityOfDialog:dialog]; };
    }
}

/* the arrow on the avatar of a chat that was added to a community opens that community: the chats the account is in, and the ones it may look at */
- (void)openCommunityOfDialog:(NoshiDialog *)dialog {
    NoshiDialog *community = [dialog linkedCommunity];
    if (!community) return;
    [self closeOpenCell];
    [self.navigationController pushViewController:NoshiCommunityScreen(self.session, community, _dialogs, self.avatars, _media, _stickerLibrary,
                                                                         ^{ [self reload]; }) animated:YES];
}

/* a chat keeps its name through a refresh, a topic has its forum's peer and its own id, and the archive entry is told apart by its folder */
static NSString *NoshiDialogRowKey(NoshiDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld:%d:%d", dialog.peerKind, dialog.peerId, dialog.topicId, dialog.folder ? dialog.folderId + 1 : 0];
}

- (NSArray *)shownKeys {
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:_shown.count];
    for (NoshiDialog *dialog in _shown) [keys addObject:NoshiDialogRowKey(dialog)];
    return keys;
}

/* a new order of the same chats is the common refresh: the ones that moved travel and the rest keep their place */
- (BOOL)updateTableAnimated {
    NSArray *keys = [self shownKeys];
    NSArray *before = [_displayedKeys autorelease];
    _displayedKeys = [keys retain];
    if (!before) return NO;
    return NoshiTableUpdateRows(self.table, before, keys, ^(UITableViewCell *cell, NSUInteger index) {
        [self configureCell:(NoshiDialogCell *)cell dialog:[_shown objectAtIndex:index]];
        [cell layoutIfNeeded];
    });
}

/* the archive entry has its own swipe, and the archive itself always offers to take a chat out of it; in the main list the swipe is the one the chat
   settings chose, which is the archive until the person chooses another */
- (NoshiDialogAction)swipeActionForDialog:(NoshiDialog *)dialog {
    if (dialog.folder) return NoshiDialogActionHide;
    return NoshiDialogSwipeAction(dialog, _folderId);
}

- (void)showFailureText:(NSString *)text {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

#pragma mark swipe

- (void)dialogCellDidBeginSwipe:(NoshiDialogCell *)cell {
    if (_openCell != cell) [_openCell closeSwipeAnimated:YES];
    [cell retain];
    [_openCell release];
    _openCell = cell;
}

- (void)closeOpenCell {
    [_openCell closeSwipeAnimated:YES];
    [_openCell release];
    _openCell = nil;
}

/* the row has left the screen on the client side; the table animates it away without a reload, which
   would also snap every other row */
- (void)removeShownRowAtIndexPath:(NSIndexPath *)indexPath animation:(UITableViewRowAnimation)animation {
    NSUInteger before = [_shown count];
    [self applyFilters];
    if ([_shown count] + 1 != before || [_shown count] == 0) {
        [self reloadTable];
        return;
    }
    [self.table beginUpdates];
    [self.table deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:animation];
    [self.table endUpdates];
    [_displayedKeys release];
    _displayedKeys = [[self shownKeys] retain];
}

/* the swipe moves the chat on the server; the row leaves at once and comes back if the server refuses */
- (void)moveDialog:(NoshiDialog *)dialog atIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    NSArray *before = [[_dialogs retain] autorelease];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self refreshCounts];
    [self removeShownRowAtIndexPath:indexPath animation:UITableViewRowAnimationLeft];
    [self retain];
    [self.session moveDialog:dialog toFolder:_folderId > 0 ? 0 : 1 completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            /* the other list changed too, and the archive entry with its count; a refresh already on its way carries the old
               list, so it is dropped for a new one */
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"noshigram: moving chat %lld to folder failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self refreshCounts];
        [self applyFilters];
        [self reloadTable];
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

/* the swipes that change one flag of the chat on the server: the row slides back, and the list is asked for again, which carries the new state and the
   new order of the pinned chats */
- (void)runCommand:(NoshiChatCommand)command onDialog:(NoshiDialog *)dialog cell:(NoshiDialogCell *)cell {
    [cell closeSwipeAnimated:YES];
    if (_folders.selectedFolder.folderId && (command == NoshiChatCommandPin || command == NoshiChatCommandUnpin)) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        [self.session setDialogs:[NSArray arrayWithObject:dialog] pinned:command == NoshiChatCommandPin inChatFolder:_folders.selectedFolder completion:^(NSString *errorName) {
            NoshiChatsController *me = weak.target;
            if (errorName) [me showFailureText:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
        }];
        return;
    }
    [self retain];
    [self.session performAction:command onDialog:dialog completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"noshigram: command %d on chat %lld failed: %@", (int)command, dialog.peerId, errorName);
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

/* deleting asks first: a channel or a supergroup is left, a chat with a person or a basic group loses its history for this account only */
- (void)confirmDeleteOfDialog:(NoshiDialog *)dialog cell:(NoshiDialogCell *)cell {
    [cell closeSwipeAnimated:YES];
    BOOL leaves = dialog.kind == NOSHI_DIALOG_CHANNEL || dialog.kind == NOSHI_DIALOG_GROUP;
    NSString *format = NSLocalizedString(leaves ? @"chats.swipe.leave.confirm" : @"chats.swipe.delete.confirm", nil);
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    NoshiConfirmAction(self, [NSString stringWithFormat:format, dialog.title], NSLocalizedString(leaves ? @"chats.swipe.leave" : @"chats.swipe.delete", nil), ^{
        [(NoshiChatsController *)weak.target deleteDialog:dialog];
    });
}

/* the row leaves at once and comes back if the server refuses, as for the archive */
- (void)deleteDialog:(NoshiDialog *)dialog {
    NSUInteger shownIndex = [_shown indexOfObjectIdenticalTo:dialog];
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    NSArray *before = [[_dialogs retain] autorelease];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self refreshCounts];
    /* the chat breaks into dust where it stood when the effect is on, as a deleted message does */
    NSIndexPath *shownPath = shownIndex == NSNotFound ? nil : [NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0];
    UITableViewCell *shownCell = shownPath ? [self.table cellForRowAtIndexPath:shownPath] : nil;
    UIImage *dustPicture = shownCell && NoshiLiteEnabled(NOSHI_LITE_CHAT_THANOS) && NoshiLiteSmoothTransitions() ? NoshiDustSnapshot(shownCell) : nil;
    CGRect dustFrame = shownCell.frame;
    if (shownPath) [self removeShownRowAtIndexPath:shownPath animation:dustPicture ? UITableViewRowAnimationNone : UITableViewRowAnimationLeft];
    else [self reloadTable];
    if (dustPicture) NoshiDustDisperse(dustPicture, dustFrame, self.table);
    [self retain];
    [self.session performAction:NoshiChatCommandDelete onDialog:dialog completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"noshigram: deleting chat %lld failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self refreshCounts];
        [self applyFilters];
        [self reloadTable];
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

- (void)dialogCell:(NoshiDialogCell *)cell didTriggerAction:(NoshiDialogAction)action {
    NSIndexPath *indexPath = [self.table indexPathForCell:cell];
    if (_openCell == cell) {
        [_openCell release];
        _openCell = nil;
    }
    if (!indexPath || (NSUInteger)indexPath.row >= [_shown count]) return;
    NoshiDialog *dialog = [[[_shown objectAtIndex:(NSUInteger)indexPath.row] retain] autorelease];
    switch (action) {
    case NoshiDialogActionHide:
        NoshiArchiveSetHidden(YES);
        [self removeShownRowAtIndexPath:indexPath animation:UITableViewRowAnimationTop];
        break;
    case NoshiDialogActionPin:
        NoshiArchiveSetHidden(NO);
        [cell setSwipeAction:NoshiDialogActionHide];
        [cell closeSwipeAnimated:YES];
        break;
    case NoshiDialogActionArchive:
    case NoshiDialogActionUnarchive:
        [self moveDialog:dialog atIndexPath:indexPath];
        break;
    case NoshiDialogActionPinChat:
        [self runCommand:NoshiChatCommandPin onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionUnpinChat:
        [self runCommand:NoshiChatCommandUnpin onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionMute:
        [self runCommand:NoshiChatCommandMute onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionUnmute:
        [self runCommand:NoshiChatCommandUnmute onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionMarkRead:
        /* a chat that is only marked unread has nothing to read, and the mark is taken off instead */
        [self runCommand:dialog.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionMarkUnread:
        [self runCommand:NoshiChatCommandMarkUnread onDialog:dialog cell:cell];
        break;
    case NoshiDialogActionDeleteChat:
        [self confirmDeleteOfDialog:dialog cell:cell];
        break;
    case NoshiDialogActionNone:
        break;
    }
}

/* a chat opens into its messages; the archive entry opens the archive */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_openCell) {
        [self closeOpenCell];
        return;
    }
    NoshiDialog *selected = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    if (selected.folder) {
        [self openArchive:selected];
        return;
    }
    if (selected.community) {
        [self.navigationController pushViewController:NoshiCommunityScreen(self.session, selected, _dialogs, self.avatars, _media, _stickerLibrary,
                                                                             ^{ [self reload]; }) animated:YES];
        return;
    }
    if (selected.forum) {
        NoshiDialog *archive = nil;
        for (NoshiDialog *entry in _shown) if (entry.folder) { archive = entry; break; }
        /* a hidden archive stays out of the column of a phone too */
        void (^archiveHandler)(void) = archive && !_archiveHidden ? ^{ [self openArchive:archive]; } : nil;
        [self.navigationController pushViewController:NoshiTopicsScreenWithChats(self.session, selected, _shown, self.avatars, _media, _stickerLibrary,
                                                                                   archiveHandler, ^{ [self reload]; }) animated:YES];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:self.session dialog:selected avatars:self.avatars
                                                                           media:_media stickers:_stickerLibrary] autorelease];
    /* reading changed the counts of the list, so it asks again once the person is back */
    chat.closeHandler = ^{ [self reload]; };
    /* a feed starts from the channel that was opened: the ones it has gone through are forgotten */
    [_feedSeen removeAllObjects];
    chat.nextChatProvider = ^NoshiDialog *(NoshiDialog *current) { return [self nextUnreadChannelAfter:current]; };
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)openArchive:(NoshiDialog *)entry {
    NoshiChatsController *archive = [[[NoshiChatsController alloc] initWithSession:self.session] autorelease];
    archive.folderId = entry.folderId > 0 ? entry.folderId : 1;
    archive.heading = NSLocalizedString(@"chats.archive", nil);
    archive.avatars = self.avatars;
    archive.media = _media;
    archive.stickerLibrary = _stickerLibrary;
    archive.showsBack = YES;
    [self.navigationController pushViewController:archive animated:YES];
}

/* the first broadcast channel of the list with unread posts that the feed has not shown yet, in the order of the list as exteraGram takes it. the list is read again only when
   the person is back on it, so a channel that was just read still counts as unread there: asking for "not the one read now" took the feed from A to B and from B to A, and
   it never got past two channels */
- (NoshiDialog *)nextUnreadChannelAfter:(NoshiDialog *)current {
    if (!_feedSeen) _feedSeen = [[NSMutableSet alloc] init];
    [_feedSeen addObject:[NSString stringWithFormat:@"%d/%lld", (int)current.peerKind, current.peerId]];
    for (NoshiDialog *dialog in _dialogs) {
        if (dialog.kind != NOSHI_DIALOG_CHANNEL || !dialog.unread || dialog.forum || dialog.community) continue;
        if ([_feedSeen containsObject:[NSString stringWithFormat:@"%d/%lld", (int)dialog.peerKind, dialog.peerId]]) continue;
        return dialog;
    }
    return nil;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [super scrollViewWillBeginDragging:scrollView];
    [self closeOpenCell];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* no screen over the whole display is up, so a bar one of them left hidden comes back */
    NoshiStatusBarSettle();
    if (_folderId || self.showsBack) return;
    if (NoshiChatFlagGet(NoshiChatFlagSnow)) {
        if (!_snow) {
            _snow = [[NoshiFallingView alloc] initWithFrame:self.view.bounds];
            _snow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view addSubview:_snow];
        }
        [_snow start];
    }
    if (NoshiChatFlagGet(NoshiChatFlagFoxes)) {
        if (!_foxes) {
            _foxes = [[NoshiFallingView alloc] initWithFrame:self.view.bounds spriteNamed:@"senko-fall"];
            _foxes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view insertSubview:_foxes belowSubview:self.table];
        }
        [_foxes start];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_snow stop];
    [_foxes stop];
    [self closeOpenCell];
}

@end

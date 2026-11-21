#import "noshi_status_label.h"
#import "noshi_classic_chats_controller.h"
#import "noshi_chats_controller.h"
#import "noshi_chats_menu.h"
#import "noshi_main_controller.h"
#import "noshi_split_controller.h"

#import "noshi_alert.h"
#import "noshi_folder_tabs.h"
#import "noshi_chat_settings.h"
#import "noshi_chat_controller.h"
#import "noshi_chat_peek.h"
#import "noshi_force_touch.h"
#import "noshi_quick_actions.h"
#import "noshi_dialog_cell.h"
#import "noshi_developers.h"
#import "noshi_classic_chrome.h"
#import "noshi_draft.h"
#import "noshi_dust_effect.h"
#import "noshi_lite_mode.h"
#import "noshi_connecting_label.h"
#import "noshi_classic_dialog_cell.h"
#import "noshi_classic_search_controller.h"
#import "noshi_login_prompt.h"
#import "noshi_developers.h"
#import "noshi_name_badge.h"
#import "noshi_perf_probe.h"
#import "noshi_table_update.h"
#import "noshi_platform.h"
#import "noshi_session_channels.h"
#import "noshi_shiro_button.h"
#import "noshi_splash_view.h"
#import "noshi_story_strip.h"
#import "noshi_theme.h"
#import "noshi_community_screen.h"
#import "noshi_topics_screen.h"
#import "noshi_weak_reference.h"
#import "noshi_falling_view.h"
#import "noshi_mini_player.h"
#include "noshi_list_state.h"
#include "noshi_clock.h"
#import "noshi_time.h"

/* a list older than this is fetched again when its screen comes back */
#define STALE_SECONDS 60.0
#define CLASSIC_READ_FOLDER_SHEET 7101


@interface NoshiClassicChatsController () <UIActionSheetDelegate> {
    NoshiWeakReference *_badgeWeak;
    NoshiFallingView *_snow;
    NoshiFallingView *_foxes;
    NoshiFallingView *_boys;
    NoshiSession *_session;
    NoshiChatListStyle _listStyle;
    NoshiChatSwipe _swipe;
    int32_t _folderId;
    int32_t _readingFolderId;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    UIView *_search;
    UIButton *_searchButton;
    UIView *_header;
    NoshiMiniPlayer *_miniPlayer;
    NoshiFolderTabs *_folders;
    id<NoshiFolderDialogRequest> _folderLoad;
    NoshiStoryStrip *_stories;
    NoshiLoginPrompt *_prompt;
    UIView *_status;
    UILabel *_statusLabel;
    UIButton *_retry;
    NSArray *_dialogs;
    NSArray *_shown;
    /* the rows the table shows now, named by NoshiClassicKey, so a refresh can move them instead of redrawing the list */
    NSArray *_displayedKeys;
    NSDate *_loadedAt;
    BOOL _loading;
    BOOL _liveRefreshScheduled;
    BOOL _liveRefreshPending;
    uint64_t _lastLiveRefreshMs;
    BOOL _failed;
    BOOL _floodRetried;
    BOOL _archiveHidden;
    NSUInteger _generation;
    /* keys of the chats picked after a long press; nil outside selection */
    NSMutableSet *_selection;
    /* the selection was begun by the button of the bar and waits for the first pick, where one begun by a long press on a row has a pick already and ends when the last is taken back */
    BOOL _selectionPersistent;
    UIBarButtonItem *_savedLeft;
    NSArray *_savedRight;
    NoshiChatsMenu *_chatsMenu;
    void (^_unreadHandler)(NSInteger);
}
@end

@implementation NoshiClassicChatsController

@synthesize unreadHandler = _unreadHandler;

- (id)initWithSession:(NoshiSession *)session folderId:(int32_t)folderId avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _badgeWeak = [[NoshiWeakReference referenceTo:self] retain];
    _session = [session retain];
    _listStyle = NoshiChatListStyleStored();
    _swipe = NoshiChatSwipeStored();
    _folderId = folderId;
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _dialogs = [[NSArray alloc] init];
    _shown = [[NSArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timesChanged) name:NoshiTimeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localMarksChanged) name:NoshiLocalMarksDidChangeNotification object:nil];
    self.navigationItem.title = folderId > 0 ? NSLocalizedString(@"chats.archive", nil) : NSLocalizedString(@"chats.title", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(archiveSummaryChanged:)
        name:NoshiArchiveSummaryDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forumSummariesChanged:)
        name:NoshiForumSummariesDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:)
        name:NoshiTypingDidChangeNotification object:_session.typing];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:)
        name:NoshiDraftDidChangeNotification object:_session.drafts];
    return self;
}

- (void)timesChanged {
    if (self.isViewLoaded) [self reloadList:NO];
}

- (void)archiveSummaryChanged:(NSNotification *)note {
    if (_folderId != 0) return;
    NSArray *updated = [NoshiDialogsReplacingArchive(_dialogs, [note.userInfo objectForKey:@"dialog"]) retain];
    [_dialogs release];
    _dialogs = updated;
    [self applyFilters];
    [self reloadList:NO];
}

/* the topics of a forum were read, so its row counts what is unread in them */
- (void)forumSummariesChanged:(NSNotification *)note {
    if (![self isViewLoaded] || !_dialogs.count) return;
    [_session applyForumSummariesToDialogs:_dialogs];
    [self applyFilters];
    [self reloadList:NO];
}

/* only the rows of the chat that changed are built again; a typing change in a chat that is not on screen touches nothing */
- (void)typingChanged:(NSNotification *)note {
    if (![self isViewLoaded]) return;
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.tableView indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && NoshiTypingChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count == 0) return;
    [self.tableView reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* a draft the person typed here or the account sent moves its chat to where its date puts it, and the row shows the new words; only that chat is touched */
- (void)draftChanged:(NSNotification *)note {
    if (![self isViewLoaded] || !_dialogs.count) return;
    NSDictionary *info = note.userInfo;
    NSArray *moved = NoshiDialogsMovedForDraft(_dialogs, _session.drafts, [[info objectForKey:@"kind"] intValue], [[info objectForKey:@"peer"] longLongValue],
                                                 [[info objectForKey:@"top"] intValue]);
    if (moved != _dialogs) {
        [_dialogs release];
        _dialogs = [moved retain];
        [self applyFilters];
        [self reloadList:YES];
        return;
    }
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.tableView indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && NoshiDraftChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [self.tableView reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dealloc {
    [_snow stop];
    [_foxes stop];
    [_boys stop];
    [_snow release];
    [_foxes release];
    [_boys release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLiveDialogs) object:nil];
    [_badgeWeak clear];
    [_badgeWeak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(retryFloodWait) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_unreadHandler release];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_search release];
    [_searchButton release];
    [_stories release];
    [_prompt release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_folders release];
    _miniPlayer.changeHandler = nil;
    [_miniPlayer release];
    [_header release];
    [_status release];
    [_statusLabel release];
    [_retry release];
    [_dialogs release];
    [_shown release];
    [_displayedKeys release];
    [_loadedAt release];
    [_selection release];
    [_savedLeft release];
    [_savedRight release];
    [_chatsMenu release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _archiveHidden = NoshiArchiveHidden();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:NoshiChatSettingsDidChangeNotification object:nil];
    UITableView *table = self.tableView;
    NoshiClassicStyleTable(table);
    table.rowHeight = [NoshiClassicDialogCell rowHeight];
    if (_folderId == 0) {
        /* the plainest place for the choice of chats is the button that says Change: it opens the selection, as it does in the lists of the official clients */
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"chats.edit", nil) style:UIBarButtonItemStyleBordered
                                                                                  target:self action:@selector(editTapped)] autorelease];
        [self syncChromeWithSettings];
    }
    self.navigationItem.backBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"chats.title", nil)
                                                                              style:UIBarButtonItemStyleBordered target:nil action:nil] autorelease];

    CGFloat width = table.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)] autorelease];
    _header = [header retain];
    /* the song that plays has its strip under the search bar, with the buttons to change it, as the chat list of the other style has: the controls of the music were only inside a chat */
    NoshiWeakReference *playerWeak = [NoshiWeakReference referenceTo:self];
    _miniPlayer = [[NoshiMiniPlayer alloc] init];
    _miniPlayer.changeHandler = ^{ [(NoshiClassicChatsController *)playerWeak.target layoutHeader]; };
    [header addSubview:_miniPlayer];
    NSString *searchPlaceholder = NSLocalizedString(@"chats.search", nil);
    _search = [NoshiClassicSearchFacade(CGRectMake(0, 0, width, 44), searchPlaceholder) retain];
    _search.userInteractionEnabled = NO;
    [header addSubview:_search];
    /* the list opens a search screen, so this tap must not start a text field focus change */
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    searchButton.frame = _search.frame;
    searchButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    searchButton.accessibilityLabel = searchPlaceholder;
    [searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:searchButton];
    _searchButton = [searchButton retain];
    [self syncChromeWithSettings];
    if (!_folderId) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        _folders = [[NoshiFolderTabs alloc] initWithSession:_session media:_media changed:^{
            NoshiClassicChatsController *me = weak.target;
            if (!me || !me->_folders) return;
            [me layoutHeader];
            [me applyFilters];
            [me reloadList:NO];
            ++me->_generation;
            me->_loading = NO;
            [me reload];
        }];
        [header addSubview:_folders];
        [_folders installPagingInView:self.view];
        [_folders refresh];
    }

    table.tableHeaderView = header;
    if (_folderId == 0) {
        /* the strip lives as long as this screen, so its callback must not keep the screen alive */
        NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
        if (!NoshiChatFlagGet(NoshiChatFlagHideStories)) {
            _stories = [[NoshiStoryStrip alloc] initWithSession:_session avatars:_avatars media:_media host:self changed:^{
                [(NoshiClassicChatsController *)me.target layoutHeader];
            }];
            [self hookStories];
            [header addSubview:_stories.view];
        }
        _prompt = [[NoshiLoginPrompt alloc] initWithSession:_session changed:^{ [(NoshiClassicChatsController *)me.target layoutHeader]; }];
        [header addSubview:_prompt.view];
    }

    _status = [[UIView alloc] initWithFrame:table.bounds];
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.textColor = NoshiThemeIsDark() ? NoshiColorSecondary() : [UIColor grayColor];
    _statusLabel.textAlignment = NoshiTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.font = [UIFont systemFontOfSize:16];
    [_status addSubview:_statusLabel];
    _retry = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [_status addSubview:_retry];
    _status.frame = table.backgroundView.bounds;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:_status];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshConnectionTitle)
                                                 name:NoshiSessionConnectionDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogsChanged) name:NoshiDialogsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogRead:) name:NoshiDialogReadNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outboxRead:) name:NoshiReadOutboxDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liveDialogsChanged:) name:NoshiSessionDialogsUpdatedNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newMessageArrived:) name:NoshiNewMessageDidArriveNotification object:_session];
    [self refreshConnectionTitle];
    UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowPressed:)] autorelease];
    [table addGestureRecognizer:press];
    [table addGestureRecognizer:[[[NoshiForceTouchRecognizer alloc] initWithTarget:self action:@selector(rowPressed:)] autorelease]];
    [self reload];
}

/* joining or leaving a chat from another screen makes the list old, so it loads again when it is on screen next */
- (void)dialogsChanged {
    [_loadedAt release];
    _loadedAt = [[NSDate distantPast] retain];
}

/* the other side read our last message here: the double check comes to its row now */
- (void)outboxRead:(NSNotification *)note {
    if (NoshiDialogsApplyingReadOutbox(_dialogs, note.userInfo) && self.isViewLoaded) [self reloadList:NO];
}

/* a chat was read here: the count of its row goes at once, where the list under the chat waited up to a minute for its own reload before it drew the count the server has now */
- (void)dialogRead:(NSNotification *)note {
    if (!NoshiDialogsApplyingRead(_dialogs, note.userInfo)) return;
    [self reportUnread];
    if (self.isViewLoaded) [self reloadList:NO];
}

- (void)liveDialogsChanged:(NSNotification *)note {
    (void)note;
    if (!self.isViewLoaded) return;
    /* a list under a chat drops the event, and its next appearance reloads only after 60 seconds: a chat read on another client kept its unread badge */
    if (!self.view.window) {
        [self dialogsChanged];
        return;
    }
    if (_liveRefreshScheduled) return;
    _liveRefreshScheduled = YES;
    uint64_t now = noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
    uint64_t delay = noshi_list_refresh_delay(now, _lastLiveRefreshMs, 750, 100);
    [self performSelector:@selector(refreshLiveDialogs) withObject:nil afterDelay:(NSTimeInterval)delay / 1000.0];
}

/* the row shows a message that arrived live and moves up at once; the list the server sends a moment later says the same */
- (void)newMessageArrived:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    NSArray *updated = NoshiDialogsApplyingNewMessage(_dialogs, note.userInfo);
    if (!updated) return;
    [_dialogs release];
    _dialogs = [updated retain];
    [self applyFilters];
    [self reportUnread];
    [self reloadList:NO];
    [self refreshStatus];
}

- (void)refreshLiveDialogs {
    _liveRefreshScheduled = NO;
    if (!self.view.window) { [self dialogsChanged]; return; }
    _lastLiveRefreshMs = noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
    if (_loading) _liveRefreshPending = YES;
    else [self reload];
}

/* the system bar shows "Connecting..." in place of the title while the link is down; picked chats put their count there */
- (void)refreshConnectionTitle {
    BOOL linked = _session.connected;
    BOOL updating = linked && _loading && !_loadedAt;
    if (_folderId != 0 || _selection || (linked && !updating)) {
        self.navigationItem.titleView = nil;
        return;
    }
    NoshiConnectingLabel *label = [[[NoshiConnectingLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:20];
    label.textAlignment = NoshiTextAlignmentLeft;
    /* the engraved shadow is part of the look of the old bars; the flat ones have none */
    if (!NoshiClassicIsFlatSystem()) {
        label.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        label.shadowOffset = CGSizeMake(0, -1);
    }
    label.updating = updating;
    label.connecting = YES;
    CGSize fit = [label sizeThatFits:CGSizeMake(320, 44)];
    label.frame = CGRectMake(0, 0, fit.width, 44);
    self.navigationItem.titleView = label;
}

/* the stories sit under the search bar and push the rows down by their own height */
- (void)layoutHeader {
    CGFloat width = self.tableView.bounds.size.width;
    CGFloat promptHeight = [_prompt heightForWidth:width];
    CGFloat search = _search.hidden ? 0 : 44;
    CGFloat player = _miniPlayer.showing ? [NoshiMiniPlayer height] : 0;
    CGFloat height = search + player + _folders.height + _stories.height + (promptHeight > 0 ? promptHeight + 16 : 0);
    _miniPlayer.frame = CGRectMake(0, search, width, player);
    _folders.frame = CGRectMake(0, search + player, width, _folders.height);
    [_stories layoutInWidth:width];
    CGRect strip = _stories.view.frame;
    strip.origin = CGPointMake(0, search + player + _folders.height);
    _stories.view.frame = strip;
    if (promptHeight > 0) [_prompt layoutInWidth:width atY:search + player + _folders.height + _stories.height + 8];
    if (_header.frame.size.height == height && _header.frame.size.width == width) return;
    CGRect frame = _header.frame;
    frame.size = CGSizeMake(width, height);
    _header.frame = frame;
    self.tableView.tableHeaderView = _header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeader];
    CGSize size = self.tableView.bounds.size;
    CGFloat top = 100;
    _status.frame = self.tableView.backgroundView.bounds;
    _statusLabel.frame = CGRectMake(32, top + 30, size.width - 64, 60);
    _retry.frame = CGRectMake((size.width - 140) / 2, top + 100, 140, 40);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

#pragma mark data

- (void)retryFloodWait {
    if (self.isViewLoaded && self.view.window && _failed && !_loading) [self reload];
}

- (NSString *)listFailureText:(NSString *)name {
    uint32_t seconds = 0;
    if (noshi_list_flood_wait(name.UTF8String, &seconds))
        return [NSString stringWithFormat:NSLocalizedString(@"list.flood.wait", nil), (unsigned)seconds];
    if ([name isEqualToString:@"FLOOD_WAIT"] || [name isEqualToString:@"FLOOD_PREMIUM_WAIT"])
        return NSLocalizedString(@"list.flood.unknown", nil);
    if ([name isEqualToString:@"TIMEOUT"] || [name isEqualToString:@"OFFLINE"]) return NSLocalizedString(@"error.offline", nil);
    if ([name isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"list.load.error", nil), name ? name : @"?"];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    _failed = NO;
    NSUInteger generation = ++_generation;
    [self refreshConnectionTitle];
    [self refreshStatus];
    [self retain];
    if (!_loadedAt && !_folders.selectedFolder.folderId) {
        /* the kept list stands in until the network answers, and stays if it never does */
        [_session loadCachedDialogsInFolder:_folderId completion:^(NSArray *kept, NSString *keptError) {
            (void)keptError;
            if (generation != _generation || _loadedAt || !kept) return;
            _loadedAt = [[NSDate distantPast] retain];
            [self refreshConnectionTitle];
            [_dialogs release];
            _dialogs = [kept retain];
            [self applyFilters];
            [self reportUnread];
            [self reloadList:NO];
            [self refreshStatus];
        }];
    }
    NoshiListCompletion loaded = ^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) return;
        _loading = NO;
        [self refreshConnectionTitle];
        if (!items) {
            _failed = YES;
            NSLog(@"noshigram: refresh of the chat list failed: %@", errorName);
            _statusLabel.text = [self listFailureText:errorName];
            uint32_t seconds = 0;
            if (_folderId > 0 && !_floodRetried && noshi_list_flood_wait(errorName.UTF8String, &seconds) && seconds <= 60) {
                _floodRetried = YES;
                [self performSelector:@selector(retryFloodWait) withObject:nil afterDelay:(NSTimeInterval)seconds];
            }
            [self refreshStatus];
            if (_liveRefreshPending) { _liveRefreshPending = NO; [self reload]; }
            return;
        }
        _floodRetried = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(retryFloodWait) object:nil];
        [_loadedAt release];
        _loadedAt = [[NSDate date] retain];
        [_dialogs release];
        _dialogs = [items retain];
        if (!_folderId && !_folders.selectedFolder.folderId) NoshiQuickActionsUpdate(items);
        [self loadBadgePictures];
        [_stories refresh];
        [_prompt refresh];
        [self applyFilters];
        [self reportUnread];
        [self reloadList:YES];
        [self restoreSelection];
        [self refreshStatus];
        if (_liveRefreshPending) { _liveRefreshPending = NO; [self reload]; }
    };
    [_folderLoad cancel];
    [_folderLoad release];
    _folderLoad = nil;
    if (!_folderId && _folders.selectedFolder.folderId) {
        NoshiWeakReference *weak = _badgeWeak;
        _folderLoad = [[_session loadDialogsForChatFolder:_folders.selectedFolder progress:^(NSArray *items) {
            NoshiClassicChatsController *controller = weak.target;
            if (!controller || generation != controller->_generation) return;
            [items retain];
            [controller->_dialogs release];
            controller->_dialogs = items;
            [controller applyFilters];
            [controller reloadList:NO];
            [controller refreshStatus];
        } completion:loaded] retain];
    }
    else [_session loadDialogsInFolder:_folderId completion:loaded];
}

/* the custom emoji statuses that follow the names in the list are fetched once, and the rows on screen are drawn again as they land */
- (void)loadBadgePictures {
    NSMutableArray *documents = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) {
        if (dialog.emojiStatus && !dialog.saved) [documents addObject:[NSNumber numberWithLongLong:dialog.emojiStatus]];
        for (NoshiTextEntity *entity in dialog.previewEntities) [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
    }
    NoshiWeakReference *weak = _badgeWeak;
    NoshiLoadBadgePictures(documents, _session, _media, ^{
        NoshiClassicChatsController *controller = weak.target;
        if (controller) NoshiRedrawVisibleRows(controller.tableView);
    });
}

- (void)reportUnread {
    if (_folders.selectedFolder.folderId) return;
    if (!_folderId) NoshiSetMainDialogsSnapshot(_dialogs);
    NSInteger total = 0;
    for (NoshiDialog *dialog in _dialogs) if (dialog.unread && !dialog.folder && !dialog.muted && !(dialog.peerKind == 3 && dialog.left)) total += dialog.unreadCount;
    if (_unreadHandler) _unreadHandler(total);
}

/* a row follows the stories of the user it is with; the strip fills in after the list, so it calls back to dress the rows on screen */
- (void)showStoriesOfCell:(NoshiClassicDialogCell *)cell dialog:(NoshiDialog *)dialog {
    [cell setStoryPeer:[_stories peerForDialog:dialog]];
}

- (void)hookStories {
    NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
    _stories.peersChanged = ^{
        NoshiClassicChatsController *controller = me.target;
        if (!controller) return;
        for (NSIndexPath *path in controller.tableView.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row >= controller->_shown.count) continue;
            NoshiClassicDialogCell *cell = (NoshiClassicDialogCell *)[controller.tableView cellForRowAtIndexPath:path];
            [controller showStoriesOfCell:cell dialog:[controller->_shown objectAtIndex:(NSUInteger)path.row]];
        }
    };
}

/* the arrow on the avatar of a chat that was added to a community opens that community: the chats the account is in, and the ones it may look at */
- (void)linkCommunityOfCell:(NoshiClassicDialogCell *)cell dialog:(NoshiDialog *)dialog {
    if (!dialog.linkedCommunityId) return;
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    cell.communityHandler = ^{
        NoshiClassicChatsController *me = weak.target;
        NoshiDialog *community = [dialog linkedCommunity];
        if (!me || !community) return;
        [me.navigationController pushViewController:NoshiCommunityScreen(me->_session, community, me->_dialogs, me->_avatars, me->_media, me->_stickers,
                                                                           ^{ me->_loading = NO; [me reload]; }) animated:YES];
    };
}

/* a refresh that brings the same chats in a new order moves the rows that jumped and leaves the rest, where reloadData would redraw the whole list */
- (void)reloadList:(BOOL)animated {
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:_shown.count];
    for (NoshiDialog *dialog in _shown) [keys addObject:[NSString stringWithFormat:@"%d:%lld:%d", (int)dialog.peerKind, dialog.peerId, dialog.folder ? dialog.folderId + 1 : 0]];
    NSArray *before = [_displayedKeys autorelease];
    _displayedKeys = [keys retain];
    BOOL moved = animated && before && NoshiTableUpdateRows(self.tableView, before, keys, ^(UITableViewCell *cell, NSUInteger index) {
        NoshiClassicDialogCell *row = (NoshiClassicDialogCell *)cell;
        NoshiDialog *dialog = [_shown objectAtIndex:index];
        row.media = _media;
        [row configureWithDialog:dialog avatars:_avatars];
        [row showDraft:NoshiVisibleDraft(_session.drafts, dialog)];
        [row showTypingText:NoshiTypingTextForDialog(_session.typing, dialog)];
        [self linkCommunityOfCell:row dialog:dialog];
        [self showStoriesOfCell:row dialog:dialog];
        [row layoutIfNeeded];
    });
    if (!moved) [self.tableView reloadData];
}

/* the stories switch of the settings takes the strip away, or brings it back, without leaving the screen */
- (void)syncStoriesWithSettings {
    if (_folderId != 0 || !self.isViewLoaded) return;
    BOOL hide = NoshiChatFlagGet(NoshiChatFlagHideStories);
    if (hide && _stories) {
        [_stories.view removeFromSuperview];
        [_stories release];
        _stories = nil;
        [self layoutHeader];
    } else if (!hide && !_stories) {
        NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
        _stories = [[NoshiStoryStrip alloc] initWithSession:_session avatars:_avatars media:_media host:self changed:^{
            [(NoshiClassicChatsController *)me.target layoutHeader];
        }];
        [self hookStories];
        [_header addSubview:_stories.view];
        [_stories refresh];
        [self layoutHeader];
    }
}

/* the menu hangs from the right end of the bar, under the dots */
- (void)showChatsMenu {
    if (!_chatsMenu) {
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        _chatsMenu = [[NoshiChatsMenu alloc] initWithSession:_session host:self avatars:_avatars media:_media stickers:_stickers refresh:^{
            NoshiClassicChatsController *list = weak.target;
            if (!list) return;
            list->_loading = NO;
            [list reload];
        }];
    }
    UIView *host = self.navigationController.view;
    CGRect bar = [host convertRect:self.navigationController.navigationBar.bounds fromView:self.navigationController.navigationBar];
    [_chatsMenu showInView:host anchor:CGPointMake(CGRectGetMaxX(bar) - 10, CGRectGetMaxY(bar) - 4)];
}

/* the main list takes three choices of the appearance page: the VPN button, the field of search, and the words of the title; the archive list keeps its own */
- (void)syncChromeWithSettings {
    if (_folderId != 0 || _selection) return;
    BOOL hideVpn = NoshiChatFlagGet(NoshiChatFlagHideVpnButton);
    /* the three dots stand at the right edge and the VPN button left of them, where the modern list has them; the first item of the array is the one at the edge */
    NSArray *items = self.navigationItem.rightBarButtonItems;
    BOOL hasVpn = items.count > 1;
    if (!items.count || hasVpn == hideVpn) {
        UIBarButtonItem *dots = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolEllipsis, 22, [UIColor whiteColor]) style:UIBarButtonItemStyleBordered
                                                                 target:self action:@selector(showChatsMenu)] autorelease];
        dots.accessibilityLabel = NSLocalizedString(@"chats.menu", nil);
        if (hideVpn) self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:dots];
        else self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:dots, [[[NoshiShiroBarItem alloc] initWithShiro:_session.shiro host:self] autorelease], nil];
    }
    BOOL hideSearch = NoshiChatFlagGet(NoshiChatFlagHideSearchBar);
    _search.hidden = hideSearch;
    _searchButton.hidden = hideSearch;
    if (_header) [self layoutHeader];
    NoshiChatListTitle mode = NoshiChatListTitleStored();
    self.navigationItem.title = NoshiChatListTitleText(mode, nil);
    if (mode != NoshiChatListTitleUsername && mode != NoshiChatListTitleName) return;
    NoshiWeakReference *weak = _badgeWeak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiClassicChatsController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"noshigram: the name for the title of the list did not load: %@", errorName);
            return;
        }
        if (NoshiChatListTitleStored() == mode) me.navigationItem.title = NoshiChatListTitleText(mode, [items objectAtIndex:0]);
    }];
}

/* the classic rows are opaque, so snow and foxes fall over them: a layer on the table that does not take touches and is moved with the offset, so it stays on the screen */
- (NoshiFallingView *)fallingViewNamed:(NSString *)sprite {
    NoshiFallingView *view = sprite ? [[NoshiFallingView alloc] initWithFrame:self.tableView.bounds spriteNamed:sprite] : [[NoshiFallingView alloc] initWithFrame:self.tableView.bounds];
    view.userInteractionEnabled = NO;
    [self.tableView addSubview:view];
    return view;
}

- (void)syncFallingEffects {
    if (_folderId != 0 || ![self isViewLoaded] || !self.view.window) return;
    BOOL snow = NoshiChatFlagGet(NoshiChatFlagSnow), foxes = NoshiChatFlagGet(NoshiChatFlagFoxes), boys = NoshiChatFlagGet(NoshiChatFlagBoykisser);
    if (boys && !_boys) _boys = [self fallingViewNamed:@"boykisser"];
    if (!boys && _boys) {
        [_boys stop];
        [_boys removeFromSuperview];
        [_boys release];
        _boys = nil;
    }
    if (snow && !_snow) _snow = [self fallingViewNamed:nil];
    if (foxes && !_foxes) _foxes = [self fallingViewNamed:@"senko-fall"];
    if (!snow && _snow) {
        [_snow stop];
        [_snow removeFromSuperview];
        [_snow release];
        _snow = nil;
    }
    if (!foxes && _foxes) {
        [_foxes stop];
        [_foxes removeFromSuperview];
        [_foxes release];
        _foxes = nil;
    }
    [self pinFallingEffects];
    [_snow start];
    [_foxes start];
    [_boys start];
}

- (void)pinFallingEffects {
    CGRect bounds = self.tableView.bounds;
    if (_snow && !CGRectEqualToRect(_snow.frame, bounds)) _snow.frame = bounds;
    if (_foxes && !CGRectEqualToRect(_foxes.frame, bounds)) _foxes.frame = bounds;
    if (_boys && !CGRectEqualToRect(_boys.frame, bounds)) _boys.frame = bounds;
    if (_boys) [self.tableView bringSubviewToFront:_boys];
    if (_snow) [self.tableView bringSubviewToFront:_snow];
    if (_foxes) [self.tableView bringSubviewToFront:_foxes];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    (void)scrollView;
    if (_snow || _foxes || _boys) [self pinFallingEffects];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self syncFallingEffects];
}

- (void)chatSettingsChanged {
    [self syncFallingEffects];
    [self syncChromeWithSettings];
    [self syncStoriesWithSettings];
    BOOL hidden = NoshiArchiveHidden();
    if (hidden == _archiveHidden) return;
    _archiveHidden = hidden;
    [self applyFilters];
    [self.tableView reloadData];
}

- (void)applyFilters {
    NSMutableArray *shown = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) {
        if (!dialog.folder && dialog.peerKind == 3 && dialog.left) continue;
        if (dialog.folder && NoshiArchiveHidden()) continue;
        if (!_folders.selectedFolder.folderId || [_folders.selectedFolder containsDialog:dialog]) [shown addObject:dialog];
    }
    /* a community shown as one chat holds the chats added to it, which the archive does not fold */
    if (!_folderId) shown = [NSMutableArray arrayWithArray:NoshiDialogsFoldingCommunities(shown)];
    [_shown release];
    _shown = [shown retain];
}

- (void)refreshStatus {
    noshi_list_presentation presentation = noshi_list_present(_shown.count, _loading, _failed, self.tableView.tableHeaderView != nil);
    if (presentation.state != NOSHI_LIST_LOADING) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiFirstScreenReadyNotification object:self];
    _retry.hidden = presentation.state != NOSHI_LIST_FAILED;
    _statusLabel.hidden = presentation.state != NOSHI_LIST_FAILED && presentation.state != NOSHI_LIST_EMPTY;
    if (presentation.state == NOSHI_LIST_EMPTY) _statusLabel.text = _dialogs.count ? NSLocalizedString(@"chats.nothing", nil) : (_folderId > 0 ? NSLocalizedString(@"chats.archive.empty", nil) : NSLocalizedString(@"chats.empty", nil));
    self.tableView.separatorStyle = NoshiClassicListSeparatorStyle(_shown.count > 0);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* no screen over the whole display is up, so a bar one of them left hidden comes back */
    NoshiStatusBarSettle();
    [_folders refresh];
    /* the chat settings are a page over this list: a new style of the rows or a new swipe is applied when the person comes back */
    NoshiChatListStyle style = NoshiChatListStyleStored();
    NoshiChatSwipe swipe = NoshiChatSwipeStored();
    if (style != _listStyle || swipe != _swipe) {
        _listStyle = style;
        _swipe = swipe;
        [self reloadList:NO];
    }
    if (_loadedAt && -[_loadedAt timeIntervalSinceNow] > STALE_SECONDS) [self reload];
}

/* the edit button of the list shows the plate of the official client with "read all" while the rows are open for editing */
/* the badges a developer gave himself on this phone: the names in the rows are drawn again */
- (void)localMarksChanged {
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    if (_folderId) return;
    UINavigationController *navigation = self.navigationController;
    if (editing) {
        UIBarButtonItem *space = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
        UIBarButtonItem *all = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"chats.readall", nil) style:UIBarButtonItemStyleBordered target:self
                                                                action:@selector(readAllChats)] autorelease];
        self.toolbarItems = [NSArray arrayWithObjects:space, all, space, nil];
        if (navigation) NoshiClassicStyleToolbar(navigation.toolbar);
    }
    [navigation setToolbarHidden:!editing animated:animated];
}

- (void)editTapped {
    if (_selection) [self endSelection];
    else [self beginSelectionPersistent];
}

- (void)readAllChats {
    NSMutableArray *unread = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) if (!dialog.folder && !dialog.community && dialog.unread) [unread addObject:dialog];
    [self setEditing:NO animated:YES];
    [self endSelection];
    if (!unread.count) return;
    [self applyToDialogs:unread perform:^(NoshiDialog *dialog, void (^finished)(NSString *)) {
        [_session performAction:dialog.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark onDialog:dialog completion:finished];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_snow stop];
    [_foxes stop];
    [_boys stop];
    if (self.editing) [self setEditing:NO animated:animated];
    /* a selection begun by the button of the bar is left with the screen, so the toolbar does not stay over the next one */
    if (_selectionPersistent) [self endSelection];
}

#pragma mark search

- (void)openSearch {
    if (self.navigationController.topViewController != self) return;
    NoshiClassicSearchController *search = [[[NoshiClassicSearchController alloc] initWithSession:_session dialogs:_dialogs avatars:_avatars
                                                                                              media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:search animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_shown.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= _shown.count) return tableView.rowHeight;
    return [NoshiClassicDialogCell rowHeightForDialog:[_shown objectAtIndex:(NSUInteger)indexPath.row]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"dialog";
    NoshiClassicDialogCell *cell = (NoshiClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    double began = NoshiPerfNow();
    cell.media = _media;
    NoshiDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:dialog avatars:_avatars];
    [cell showDraft:NoshiVisibleDraft(_session.drafts, dialog)];
    [cell showTypingText:NoshiTypingTextForDialog(_session.typing, dialog)];
    [self linkCommunityOfCell:cell dialog:dialog];
    [self showStoriesOfCell:cell dialog:dialog];
    NoshiPerfRecord("classic configure", NoshiPerfNow() - began);
    began = NoshiPerfNow();
    [cell layoutIfNeeded];
    NoshiPerfRecord("classic layout", NoshiPerfNow() - began);
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NoshiDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    return !dialog.folder && NoshiDialogSwipeAction(dialog, _folderId) != NoshiDialogActionNone;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    /* the system shows one button for a swipe, which carries the word of the action the chat settings chose */
    return NoshiDialogActionText(NoshiDialogSwipeAction([_shown objectAtIndex:(NSUInteger)indexPath.row], _folderId));
}

- (void)showFailure:(NSString *)errorName {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                             : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                        delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

/* the swipes that change one flag of the chat on the server: the row slides back, and the list is asked for again,
   which carries the new state and the new order of the pinned chats */
- (void)performSwipeAction:(NoshiDialogAction)action onDialog:(NoshiDialog *)dialog atIndexPath:(NSIndexPath *)indexPath {
    NoshiChatCommand command;
    switch (action) {
    case NoshiDialogActionPinChat: command = NoshiChatCommandPin; break;
    case NoshiDialogActionUnpinChat: command = NoshiChatCommandUnpin; break;
    case NoshiDialogActionMute: command = NoshiChatCommandMute; break;
    case NoshiDialogActionUnmute: command = NoshiChatCommandUnmute; break;
    case NoshiDialogActionMarkRead: command = dialog.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark; break;
    case NoshiDialogActionMarkUnread: command = NoshiChatCommandMarkUnread; break;
    case NoshiDialogActionDeleteChat: command = NoshiChatCommandDelete; break;
    default: return;
    }
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    void (^run)(void) = ^{
        NoshiClassicChatsController *me = weak.target;
        if (!me) return;
        if (me->_folders.selectedFolder.folderId && (command == NoshiChatCommandPin || command == NoshiChatCommandUnpin)) {
            [me->_session setDialogs:[NSArray arrayWithObject:dialog] pinned:command == NoshiChatCommandPin inChatFolder:me->_folders.selectedFolder completion:^(NSString *errorName) {
                if (errorName) [(NoshiClassicChatsController *)weak.target showFailure:errorName];
            }];
            return;
        }
        NSArray *before = nil;
        if (command == NoshiChatCommandDelete) {
            /* the chat leaves at once, in dust when the effect is on, and comes back if the server refuses */
            NSUInteger shownIndex = [me->_shown indexOfObjectIdenticalTo:dialog];
            UITableViewCell *cell = shownIndex == NSNotFound ? nil : [me.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0]];
            BOOL dust = cell && NoshiLiteEnabled(NOSHI_LITE_CHAT_THANOS) && NoshiLiteSmoothTransitions();
            UIImage *picture = dust ? NoshiDustSnapshot(cell) : nil;
            CGRect frame = cell.frame;
            before = [[me->_dialogs retain] autorelease];
            NSMutableArray *remaining = [NSMutableArray arrayWithArray:me->_dialogs];
            [remaining removeObject:dialog];
            [me->_dialogs release];
            me->_dialogs = [remaining retain];
            [me applyFilters];
            [me reportUnread];
            if (shownIndex != NSNotFound && [me->_shown count]) {
                [me.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0]]
                                    withRowAnimation:picture ? UITableViewRowAnimationNone : UITableViewRowAnimationLeft];
            } else {
                [me.tableView reloadData];
            }
            [me refreshStatus];
            if (picture) NoshiDustDisperse(picture, frame, me.tableView);
        }
        [me retain];
        [me->_session performAction:command onDialog:dialog completion:^(NSString *errorName) {
            [me autorelease];
            if (errorName && before) {
                [me->_dialogs release];
                me->_dialogs = [before retain];
                [me applyFilters];
                [me reportUnread];
                [me.tableView reloadData];
                [me refreshStatus];
            }
            if (!errorName) {
                me->_loading = NO;
                [me reload];
                return;
            }
            NSLog(@"noshigram: command %d on chat %lld failed: %@", (int)command, dialog.peerId, errorName);
            [me showFailure:errorName];
            [me reloadList:NO];
        }];
    };
    if (action != NoshiDialogActionDeleteChat) {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        run();
        return;
    }
    BOOL leaves = dialog.kind == NOSHI_DIALOG_CHANNEL || dialog.kind == NOSHI_DIALOG_GROUP;
    NSString *format = NSLocalizedString(leaves ? @"chats.swipe.leave.confirm" : @"chats.swipe.delete.confirm", nil);
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    NoshiConfirm(nil, [NSString stringWithFormat:format, dialog.title], NSLocalizedString(leaves ? @"chats.swipe.leave" : @"chats.swipe.delete", nil), run);
}

/* the swipe or the red minus moves the chat on the server; the row leaves at once and comes back if the server refuses */
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    NoshiDialog *dialog = [[[_shown objectAtIndex:(NSUInteger)indexPath.row] retain] autorelease];
    NoshiDialogAction action = NoshiDialogSwipeAction(dialog, _folderId);
    if (action != NoshiDialogActionArchive && action != NoshiDialogActionUnarchive) {
        [self performSwipeAction:action onDialog:dialog atIndexPath:indexPath];
        return;
    }
    NSArray *before = [[_dialogs retain] autorelease];
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self applyFilters];
    [self reportUnread];
    [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationLeft];
    [self refreshStatus];
    [self retain];
    [_session moveDialog:dialog toFolder:_folderId > 0 ? 0 : 1 completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            /* the other list changed too, and the archive entry with its count */
            _loading = NO;
            [self reload];
            return;
        }
        NSLog(@"noshigram: moving chat %lld to folder failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self applyFilters];
        [self reportUnread];
        [self reloadList:NO];
        [self refreshStatus];
        [self showFailure:errorName];
    }];
}

#pragma mark selection

static NSString *NoshiClassicKey(NoshiDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (NSArray *)selectedDialogs {
    NSMutableArray *picked = [NSMutableArray array];
    for (NoshiDialog *dialog in _dialogs) if ([_selection containsObject:NoshiClassicKey(dialog)]) [picked addObject:dialog];
    return picked;
}

- (UIBarButtonItem *)selectionButtonWithSymbol:(NoshiSymbol)symbol action:(SEL)action {
    UIBarButtonItem *item = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(symbol, 22, [UIColor whiteColor])
                                                              style:UIBarButtonItemStyleBordered target:self action:action] autorelease];
    return item;
}

/* the bar shows what the whole pick can do: pin only when some chat is not pinned, mute only when some is not muted */
- (void)updateSelectionBar {
    NSArray *picked = [self selectedDialogs];
    if (!picked.count && !_selectionPersistent) {
        [self endSelection];
        return;
    }
    if (_selectionPersistent) [self showReadAllToolbar];
    if (!picked.count) {
        /* nothing is picked yet: the bar says what to do, and has no actions to offer */
        self.navigationItem.title = NSLocalizedString(@"chats.select.hint", nil);
        self.navigationItem.rightBarButtonItems = nil;
        return;
    }
    self.navigationItem.title = [NSString stringWithFormat:@"%lu", (unsigned long)picked.count];
    BOOL allPinned = YES, allMuted = YES;
    for (NoshiDialog *dialog in picked) {
        if (!dialog.pinned) allPinned = NO;
        if (!dialog.muted) allMuted = NO;
    }
    UIBarButtonItem *pin = [self selectionButtonWithSymbol:NoshiSymbolPin action:@selector(pinSelected)];
    UIBarButtonItem *mute = [self selectionButtonWithSymbol:NoshiSymbolBellSlash action:@selector(muteSelected)];
    UIBarButtonItem *archive = [self selectionButtonWithSymbol:NoshiSymbolArchive action:@selector(archiveSelected)];
    UIBarButtonItem *trash = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteSelected)] autorelease];
    pin.title = allPinned ? NSLocalizedString(@"chats.unpin", nil) : NSLocalizedString(@"chats.pin", nil);
    mute.title = allMuted ? NSLocalizedString(@"chats.unmute", nil) : NSLocalizedString(@"chats.mute", nil);
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:trash, archive, mute, pin, nil];
}

/* the toolbar keeps what the button Change used to offer: all the chats read at once */
- (void)showReadAllToolbar {
    UINavigationController *navigation = self.navigationController;
    UIBarButtonItem *space = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
    UIBarButtonItem *all = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"chats.readall", nil) style:UIBarButtonItemStyleBordered target:self action:@selector(readAllChats)] autorelease];
    self.toolbarItems = [NSArray arrayWithObjects:space, all, space, nil];
    if (navigation) NoshiClassicStyleToolbar(navigation.toolbar);
    [navigation setToolbarHidden:NO animated:YES];
}

- (void)beginSelectionPersistent {
    if (_selection || _folderId != 0) return;
    _selection = [[NSMutableSet alloc] init];
    _selectionPersistent = YES;
    [self refreshConnectionTitle];
    _savedLeft = [self.navigationItem.leftBarButtonItem retain];
    _savedRight = [self.navigationItem.rightBarButtonItems retain];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endSelection)] autorelease];
    self.tableView.allowsMultipleSelection = YES;
    [self updateSelectionBar];
}

- (void)beginSelectionAt:(NSIndexPath *)path {
    _selectionPersistent = NO;
    _selection = [[NSMutableSet alloc] init];
    [self refreshConnectionTitle];
    _savedLeft = [self.navigationItem.leftBarButtonItem retain];
    _savedRight = [self.navigationItem.rightBarButtonItems retain];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endSelection)] autorelease];
    self.tableView.allowsMultipleSelection = YES;
    [_selection addObject:NoshiClassicKey([_shown objectAtIndex:(NSUInteger)path.row])];
    [self.tableView selectRowAtIndexPath:path animated:YES scrollPosition:UITableViewScrollPositionNone];
    [self updateSelectionBar];
}

- (void)endSelection {
    if (!_selection) return;
    [_selection release];
    _selection = nil;
    if (_selectionPersistent) [self.navigationController setToolbarHidden:YES animated:YES];
    _selectionPersistent = NO;
    self.tableView.allowsMultipleSelection = NO;
    NSArray *rows = [[self.tableView indexPathsForSelectedRows] retain];
    for (NSIndexPath *path in rows) [self.tableView deselectRowAtIndexPath:path animated:YES];
    [rows release];
    self.navigationItem.leftBarButtonItem = _savedLeft;
    self.navigationItem.rightBarButtonItems = _savedRight;
    [_savedLeft release];
    _savedLeft = nil;
    [_savedRight release];
    _savedRight = nil;
    if (_folderId > 0) self.navigationItem.title = NSLocalizedString(@"chats.archive", nil);
    else [self syncChromeWithSettings];
    [self refreshConnectionTitle];
}

- (void)scrollToTopAnimated {
    if (!self.isViewLoaded) return;
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.contentInset.top) animated:YES];
}

/* a reload or a filter rebuilds the rows, which drops the table's own selection */
- (void)restoreSelection {
    if (!_selection) return;
    for (NSUInteger i = 0; i < _shown.count; ++i) {
        if ([_selection containsObject:NoshiClassicKey([_shown objectAtIndex:i])]) {
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

/* the archive row has no card to peek into; a press on it offers to read everything in it */
- (void)askToReadFolder:(NoshiDialog *)folder {
    _readingFolderId = folder.folderId;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"notice.cancel", nil)
                                          destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"chats.archive.readall", nil), nil];
    sheet.tag = CLASSIC_READ_FOLDER_SHEET;
    [sheet showFromTabBar:self.tabBarController.tabBar];
    [sheet release];
}

- (void)rowPressed:(UIGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || _selection || self.editing) return;
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    if (!path || (NSUInteger)path.row >= _shown.count) return;
    NoshiDialog *dialog = [_shown objectAtIndex:(NSUInteger)path.row];
    if (dialog.folder) {
        [self askToReadFolder:dialog];
        return;
    }
    if (dialog.community) return;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    /* the screen on top, not the window: before ios 8 a view put in the window keeps the turn of the device, and on an ipad held sideways the card and its menu lay on their side */
    UIView *host = self.view.window ? NoshiOverlayHost() : nil;
    if (!cell || !host) return;
    CGRect source = [self.tableView convertRect:cell.frame toView:host];
    NoshiWeakReference *weak = _badgeWeak;
    NoshiShowChatPeek(host, source, dialog, _session, _avatars, _media, YES, ^(NoshiChatPeekAction action) {
        NoshiClassicChatsController *controller = weak.target;
        if (!controller) return;
        NSUInteger index = NSNotFound;
        for (NSUInteger i = 0; i < controller->_shown.count; ++i) {
            NoshiDialog *current = [controller->_shown objectAtIndex:i];
            if (current.peerKind == dialog.peerKind && current.peerId == dialog.peerId && current.topicId == dialog.topicId) { index = i; break; }
        }
        if (index == NSNotFound) return;
        NSIndexPath *currentPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        NoshiDialog *current = [controller->_shown objectAtIndex:index];
        if (action == NoshiChatPeekOpen) [controller tableView:controller.tableView didSelectRowAtIndexPath:currentPath];
        else if (action == NoshiChatPeekSelect) [controller beginSelectionAt:currentPath];
        else if (action == NoshiChatPeekPin || action == NoshiChatPeekMute) {
            NoshiChatCommand command = action == NoshiChatPeekPin ? (current.pinned ? NoshiChatCommandUnpin : NoshiChatCommandPin)
                                                                        : (current.muted ? NoshiChatCommandUnmute : NoshiChatCommandMute);
            [controller applyAction:command toDialogs:[NSArray arrayWithObject:current]];
        } else if (action == NoshiChatPeekMarkRead) {
            [controller applyAction:current.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark toDialogs:[NSArray arrayWithObject:current]];
        } else if (action == NoshiChatPeekArchive) {
            [controller applyToDialogs:[NSArray arrayWithObject:current] perform:^(NoshiDialog *item, void (^finished)(NSString *)) {
                [controller->_session moveDialog:item toFolder:item.folderId ? 0 : 1 completion:finished];
            }];
        }
    });
}

/* runs the action on every picked chat, then asks for the list again; the first refusal is shown once */
- (void)applyToDialogs:(NSArray *)dialogs perform:(void (^)(NoshiDialog *dialog, void (^finished)(NSString *errorName)))perform {
    [self endSelection];
    __block NSUInteger waiting = dialogs.count;
    __block NSString *firstError = nil;
    [self retain];
    for (NoshiDialog *dialog in dialogs) {
        void (^finished)(NSString *) = ^(NSString *errorName) {
            if (errorName && !firstError) firstError = [errorName retain];
            if (--waiting) return;
            [self autorelease];
            _loading = NO;
            [self reload];
            if (firstError) {
                NSLog(@"noshigram: chat action failed: %@", firstError);
                [self showFailure:firstError];
                [firstError release];
            }
        };
        perform(dialog, finished);
    }
}

- (void)applyAction:(NoshiChatCommand)action toDialogs:(NSArray *)dialogs {
    if (_folders.selectedFolder.folderId && (action == NoshiChatCommandPin || action == NoshiChatCommandUnpin)) {
        [self endSelection];
        NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
        [_session setDialogs:dialogs pinned:action == NoshiChatCommandPin inChatFolder:_folders.selectedFolder completion:^(NSString *errorName) {
            if (errorName) [(NoshiClassicChatsController *)weak.target showFailure:errorName];
        }];
        return;
    }
    [self applyToDialogs:dialogs perform:^(NoshiDialog *dialog, void (^finished)(NSString *)) {
        [_session performAction:action onDialog:dialog completion:finished];
    }];
}

- (void)pinSelected {
    NSArray *picked = [self selectedDialogs];
    BOOL allPinned = YES;
    for (NoshiDialog *dialog in picked) if (!dialog.pinned) allPinned = NO;
    [self applyAction:allPinned ? NoshiChatCommandUnpin : NoshiChatCommandPin toDialogs:picked];
}

- (void)muteSelected {
    NSArray *picked = [self selectedDialogs];
    BOOL allMuted = YES;
    for (NoshiDialog *dialog in picked) if (!dialog.muted) allMuted = NO;
    [self applyAction:allMuted ? NoshiChatCommandUnmute : NoshiChatCommandMute toDialogs:picked];
}

- (void)archiveSelected {
    int32_t target = _folderId > 0 ? 0 : 1;
    [self applyToDialogs:[self selectedDialogs] perform:^(NoshiDialog *dialog, void (^finished)(NSString *)) {
        [_session moveDialog:dialog toFolder:target completion:finished];
    }];
}

- (void)deleteSelected {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"notice.cancel", nil)
                                          destructiveButtonTitle:NSLocalizedString(@"chats.delete.action", nil) otherButtonTitles:nil];
    [sheet showFromTabBar:self.tabBarController.tabBar];
    [sheet release];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (sheet.tag == CLASSIC_READ_FOLDER_SHEET) {
        if (index != sheet.firstOtherButtonIndex) return;
        NoshiWeakReference *weak = _badgeWeak;
        [_session markAllReadInFolder:_readingFolderId completion:^(NSString *errorName) {
            NoshiClassicChatsController *controller = weak.target;
            if (!controller) return;
            if (errorName) NSLog(@"noshigram: reading the archive failed: %@", errorName);
            [controller reload];
        }];
        return;
    }
    if (index != sheet.destructiveButtonIndex) return;
    [self applyAction:NoshiChatCommandDelete toDialogs:[self selectedDialogs]];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!_selection) return;
    [_selection removeObject:NoshiClassicKey([_shown objectAtIndex:(NSUInteger)indexPath.row])];
    [self updateSelectionBar];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_selection) {
        NoshiDialog *picked = [_shown objectAtIndex:(NSUInteger)indexPath.row];
        if (picked.folder) {
            [tableView deselectRowAtIndexPath:indexPath animated:NO];
            return;
        }
        [_selection addObject:NoshiClassicKey(picked)];
        [self updateSelectionBar];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NoshiDialog *selected = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    if (selected.folder) {
        NoshiClassicChatsController *archive = [[[NoshiClassicChatsController alloc] initWithSession:_session folderId:selected.folderId > 0 ? selected.folderId : 1
                                                                                                avatars:_avatars media:_media stickers:_stickers] autorelease];
        [self.navigationController pushViewController:archive animated:YES];
        return;
    }
    if (selected.community) {
        [self.navigationController pushViewController:NoshiCommunityScreen(_session, selected, _dialogs, _avatars, _media, _stickers,
                                                                             ^{ _loading = NO; [self reload]; }) animated:YES];
        return;
    }
    if (selected.forum) {
        [self.navigationController pushViewController:NoshiTopicsScreen(_session, selected, _avatars, _media, _stickers,
                                                                          ^{ _loading = NO; [self reload]; }) animated:YES];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:selected avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    /* reading changed the counts of the list, so it asks again once the person is back */
    chat.closeHandler = ^{ _loading = NO; [self reload]; };
    [self.navigationController pushViewController:chat animated:YES];
}

@end

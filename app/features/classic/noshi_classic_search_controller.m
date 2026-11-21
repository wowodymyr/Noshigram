#import "noshi_download_log.h"
#import "noshi_search_history.h"
#import "noshi_classic_search_controller.h"
#import "noshi_lite_mode.h"
#import "noshi_animation.h"

#import "noshi_chat_controller.h"
#import "noshi_community_screen.h"
#import "noshi_topics_screen.h"
#import "noshi_classic_chrome.h"
#import "noshi_classic_dialog_cell.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define STRIP_HEIGHT 40.0
#define TAB_WIDTH 94.0
#define SERVER_DELAY 0.4

/* the order of the kinds on the strip */
typedef enum {
    NoshiClassicTabChats,
    NoshiClassicTabChannels,
    NoshiClassicTabApps,
    NoshiClassicTabPosts,
    NoshiClassicTabMedia,
    NoshiClassicTabDownloads,
    NoshiClassicTabLinks,
    NoshiClassicTabFiles,
    NoshiClassicTabMusic,
    NoshiClassicTabVoice,
    NoshiClassicTabCount
} NoshiClassicTab;

typedef enum { NoshiClassicStateStart, NoshiClassicStateResults, NoshiClassicStateLoading, NoshiClassicStateFailed, NoshiClassicStateEmpty, NoshiClassicStateHint } NoshiClassicState;

/* the lists that are kept on the phone answer at once, with no pause for the server */
static BOOL NoshiClassicTabIsInstant(NSInteger tab) {
    return tab == NoshiClassicTabChats || tab == NoshiClassicTabChannels || tab == NoshiClassicTabApps || tab == NoshiClassicTabDownloads;
}

static BOOL NoshiClassicTabIsLocal(NSInteger tab) {
    return tab == NoshiClassicTabChats || tab == NoshiClassicTabChannels || tab == NoshiClassicTabApps;
}

static noshi_search_kind NoshiClassicServerKind(NSInteger tab) {
    switch (tab) {
    case NoshiClassicTabPosts: return NOSHI_SEARCH_POSTS;
    case NoshiClassicTabMedia: return NOSHI_SEARCH_MEDIA;
    case NoshiClassicTabLinks: return NOSHI_SEARCH_LINKS;
    case NoshiClassicTabFiles: return NOSHI_SEARCH_FILES;
    case NoshiClassicTabMusic: return NOSHI_SEARCH_MUSIC;
    default: return NOSHI_SEARCH_VOICE;
    }
}

@interface NoshiClassicSearchController () <UITableViewDataSource, UITableViewDelegate> {
    NoshiSession *_session;
    NSArray *_dialogs;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;
    NoshiClassicSearchInput *_bar;
    UIToolbar *_stripBack;
    UIScrollView *_strip;
    UISegmentedControl *_tabs;
    UITableView *_table;
    UIView *_emptyView;
    NoshiLottieView *_duck;
    UILabel *_emptyTitle;
    UILabel *_emptyText;
    UIActivityIndicatorView *_spinner;
    NSString *_query;
    NSArray *_rows;
    /* the public chats the server found for the text, shown under the local results on the chat kinds */
    NSArray *_global;
    /* the messages the server found in the chats, under the chats on the first kind, as the other clients list them */
    NSArray *_messages;
    BOOL _globalDone, _messagesDone, _globalFailed;
    NSArray *_recent;
    NoshiClassicState _state;
    NSUInteger _generation;
    CGFloat _keyboardOverlap;
    BOOL _focused;
}
@end

@implementation NoshiClassicSearchController

- (id)initWithSession:(NoshiSession *)session dialogs:(NSArray *)dialogs avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialogs = [dialogs retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _query = [@"" copy];
    _rows = [[NSArray alloc] init];
    _recent = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _bar.changeHandler = nil;
    _table.delegate = nil;
    _table.dataSource = nil;
    [_session release];
    [_dialogs release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_bar release];
    [_stripBack release];
    [_strip release];
    [_tabs release];
    [_table release];
    [_emptyView release];
    [_duck release];
    [_emptyTitle release];
    [_emptyText release];
    [_spinner release];
    [_query release];
    [_rows release];
    [_global release];
    [_messages release];
    [_recent release];
    [super dealloc];
}

#pragma mark recent

static NSString *NoshiClassicKeyOf(NoshiDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (void)loadRecent {
    [_recent release];
    _recent = [NoshiSearchHistoryDialogs(_session, _dialogs) retain];
}

- (void)remember:(NoshiDialog *)dialog {
    NoshiSearchHistoryRemember(_session, dialog, _dialogs);
}

- (void)clearRecent {
    NoshiSearchHistoryClear(_session);
    [self loadRecent];
    [self refreshState];
}

#pragma mark views

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _bar = [[NoshiClassicSearchInput alloc] initWithFrame:CGRectMake(0, 0, 240, 44) placeholder:NSLocalizedString(@"chats.search", nil)];
    NoshiWeakReference *searchWeak = _weak;
    _bar.changeHandler = ^(NSString *text) { [(NoshiClassicSearchController *)searchWeak.target searchTextChanged:text]; };
    self.navigationItem.titleView = _bar;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"picker.cancel", nil)
                                                                              style:UIBarButtonItemStyleBordered target:self action:@selector(close)] autorelease];

    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"search.tab.chats", nil), NSLocalizedString(@"search.tab.channels", nil),
                       NSLocalizedString(@"search.tab.apps", nil), NSLocalizedString(@"search.tab.posts", nil), NSLocalizedString(@"search.tab.media", nil),
                       NSLocalizedString(@"search.tab.downloads", nil), NSLocalizedString(@"search.tab.links", nil), NSLocalizedString(@"search.tab.files", nil),
                       NSLocalizedString(@"search.tab.music", nil), NSLocalizedString(@"search.tab.voice", nil), nil];
    _stripBack = [[UIToolbar alloc] init];
    NoshiClassicStyleToolbar(_stripBack);
    [root addSubview:_stripBack];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.backgroundColor = [UIColor clearColor];
    [root addSubview:_strip];
    _tabs = [[UISegmentedControl alloc] initWithItems:titles];
    NoshiClassicStyleSegmented(_tabs);
    for (NSUInteger i = 0; i < titles.count; ++i) [_tabs setWidth:TAB_WIDTH forSegmentAtIndex:i];
    _tabs.selectedSegmentIndex = 0;
    _tabs.frame = CGRectMake(8, 5, TAB_WIDTH * titles.count, 30);
    [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [_strip addSubview:_tabs];
    _strip.contentSize = CGSizeMake(_tabs.frame.size.width + 16, STRIP_HEIGHT);

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = [NoshiClassicDialogCell rowHeight];
    NoshiClassicStyleTable(_table);
    [root addSubview:_table];

    _emptyView = [[UIView alloc] init];
    _emptyView.hidden = YES;
    [root addSubview:_emptyView];
    _duck = [[NoshiLottieView alloc] initWithAnimationNamed:@"search_empty"];
    [_emptyView addSubview:_duck];
    _emptyTitle = [[UILabel alloc] init];
    _emptyTitle.backgroundColor = [UIColor clearColor];
    _emptyTitle.textColor = NoshiColorTitle();
    _emptyTitle.font = [UIFont boldSystemFontOfSize:19];
    _emptyTitle.textAlignment = NoshiTextAlignmentCenter;
    [_emptyView addSubview:_emptyTitle];
    _emptyText = [[UILabel alloc] init];
    _emptyText.backgroundColor = [UIColor clearColor];
    _emptyText.textColor = NoshiColorSecondary();
    _emptyText.font = [UIFont systemFontOfSize:15];
    _emptyText.textAlignment = NoshiTextAlignmentCenter;
    _emptyText.numberOfLines = 0;
    [_emptyView addSubview:_emptyText];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:NoshiThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRecent];
    [self refreshState];
    [self loadEveryChat];
}

/* the list the screen was given holds one request of chats, and a chat further down would be found only by the server's own search, which keeps few of them */
- (void)loadEveryChat {
    NoshiWeakReference *weak = _weak;
    [_session loadRemainingDialogsAfter:_dialogs completion:^(NSArray *all) {
        NoshiClassicSearchController *search = weak.target;
        if (!search || all.count <= search->_dialogs.count) return;
        [search->_dialogs release];
        search->_dialogs = [all retain];
        [search loadRecent];
        if (search->_query.length && NoshiClassicTabIsLocal(search->_tabs.selectedSegmentIndex)) {
            ++search->_generation;
            [search runSearch];
        }
    }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (void)layoutSearch {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    _stripBack.frame = CGRectMake(0, insets.top, size.width, STRIP_HEIGHT);
    _strip.frame = _stripBack.frame;
    CGFloat bodyY = insets.top + STRIP_HEIGHT;
    CGFloat bodyHeight = MAX(0, size.height - _keyboardOverlap - bodyY);
    _table.frame = CGRectMake(0, bodyY, size.width, bodyHeight);
    _emptyView.frame = _table.frame;
    CGFloat block = 130 + 12 + 24 + 6 + 62;
    CGFloat y = MAX(8, (bodyHeight - block) / 2 - 20);
    _duck.frame = CGRectMake((size.width - 130) / 2, y, 130, 130);
    _emptyTitle.frame = CGRectMake(24, y + 142, size.width - 48, 24);
    _emptyText.frame = CGRectMake(32, y + 172, size.width - 64, 62);
    CGPoint middle = CGPointMake(size.width / 2, bodyY + bodyHeight / 2 - 20);
    _spinner.center = middle;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSearch];
}

#pragma mark keyboard

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    /* coming back from a chat shows the chats opened lately, with the one just opened first */
    /* the screen opens without a push, so it fades in and grows from a little larger, the way the search brings
       its results in */
    if (!_focused) {
        CGFloat scale = NoshiLiteEnabled(NOSHI_LITE_CHAT_SCALE) ? 1.04f : 1;
        NoshiAnimateEnter(self.view, CGAffineTransformMakeScale(scale, scale), 0, NOSHI_MOTION_ENTER);
    }
    [self loadRecent];
    /* a file that came while a chat was open is in the list when it is left */
    if (_tabs.selectedSegmentIndex == NoshiClassicTabDownloads) [self runSearch];
    else [_table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* the keyboard comes up when the screen opens, not again when a chat opened from here is left */
    if (!_focused) {
        _focused = YES;
        [_bar becomeFirstResponder];
    }
    [self updateDuck];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_duck setPlaying:NO];
}

- (void)keyboardShown:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIWindow *window = self.view.window;
    if (!window) return;
    CGRect inView = [self.view convertRect:[window convertRect:end fromWindow:nil] fromView:window];
    _keyboardOverlap = MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    [self layoutSearch];
}

- (void)keyboardHidden:(NSNotification *)note {
    (void)note;
    _keyboardOverlap = 0;
    [self layoutSearch];
}

- (void)close {
    [_bar resignFirstResponder];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark query

- (void)searchTextChanged:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:_query]) return;
    [_query release];
    _query = [trimmed copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    ++_generation;
    if (NoshiClassicTabIsInstant(_tabs.selectedSegmentIndex) || !_query.length) {
        [self runSearch];
        return;
    }
    /* the server is asked once the typing pauses, and what is on the screen waits meanwhile */
    _state = NoshiClassicStateLoading;
    [self refreshState];
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)tabChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    ++_generation;
    [self runSearch];
}

- (BOOL)dialog:(NoshiDialog *)dialog fitsTab:(NSInteger)tab {
    switch (tab) {
    case NoshiClassicTabChats: return dialog.kind == NOSHI_DIALOG_USER || dialog.kind == NOSHI_DIALOG_GROUP;
    case NoshiClassicTabChannels: return dialog.kind == NOSHI_DIALOG_CHANNEL;
    default: return dialog.kind == NOSHI_DIALOG_BOT;
    }
}

/* looks for the query among the kinds of results the strip has selected */
- (void)runSearch {
    NSInteger tab = _tabs.selectedSegmentIndex;
    NSUInteger generation = _generation;
    [_rows release];
    _rows = [[NSArray alloc] init];
    [_global release];
    _global = nil;
    [_messages release];
    _messages = nil;
    _globalDone = _messagesDone = _globalFailed = NO;
    if (tab == NoshiClassicTabDownloads) {
        [_rows release];
        _rows = [NoshiDownloadLogDialogs(_session, _query) retain];
        _state = _rows.count ? NoshiClassicStateResults : (_query.length ? NoshiClassicStateEmpty : NoshiClassicStateHint);
    } else if (NoshiClassicTabIsLocal(tab)) {
        NSMutableArray *found = [NSMutableArray array];
        for (NoshiDialog *dialog in _dialogs) {
            if (dialog.folder || ![self dialog:dialog fitsTab:tab]) continue;
            if (_query.length && [dialog.title rangeOfString:_query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
            [found addObject:dialog];
        }
        [_rows release];
        _rows = [found retain];
        /* with nothing local the screen waits for the server's public chats before it says there is nothing */
        _state = !_query.length ? NoshiClassicStateStart : (found.count ? NoshiClassicStateResults : NoshiClassicStateLoading);
        [self scheduleGlobal];
    } else if (!_query.length) {
        _state = NoshiClassicStateHint;
    } else {
        _state = NoshiClassicStateLoading;
        [self refreshState];
        NoshiWeakReference *weak = _weak;
        [_session searchGlobal:_query kind:NoshiClassicServerKind(tab) offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            NoshiClassicSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didSearch:dialogs error:errorName];
        }];
        return;
    }
    [self refreshState];
}

/* the server is asked for public chats once the typing pauses */
- (void)scheduleGlobal {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    if (_query.length) [self performSelector:@selector(runGlobal) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)runGlobal {
    NSUInteger generation = _generation;
    NSInteger tab = _tabs.selectedSegmentIndex;
    NoshiWeakReference *weak = _weak;
    _messagesDone = tab != NoshiClassicTabChats;
    [_session searchPeers:_query completion:^(NSArray *dialogs, NSString *errorName) {
        NoshiClassicSearchController *search = weak.target;
        if (!search || generation != search->_generation) return;
        [search didFindGlobal:dialogs forTab:tab error:errorName];
    }];
    /* the first kind also reads the messages of the chats, which is what the other clients list under the chats */
    if (tab == NoshiClassicTabChats) {
        [_session searchGlobal:_query kind:NOSHI_SEARCH_ALL offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            NoshiClassicSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didFindMessages:dialogs error:errorName];
        }];
    }
}

/* what the screen says once the local rows and the answers of the server so far are in: the rows, a wait for the rest, or nothing found */
- (void)updateLocalState {
    BOOL any = _rows.count || _global.count || _messages.count;
    if (any) _state = NoshiClassicStateResults;
    else if (!_globalDone || !_messagesDone) _state = NoshiClassicStateLoading;
    else _state = _globalFailed ? NoshiClassicStateFailed : NoshiClassicStateEmpty;
    [self refreshState];
}

- (void)didFindGlobal:(NSArray *)dialogs forTab:(NSInteger)tab error:(NSString *)errorName {
    if (!dialogs) NSLog(@"noshigram: global search failed: %@", errorName);
    NSMutableSet *known = [NSMutableSet set];
    for (NoshiDialog *dialog in _rows) [known addObject:NoshiClassicKeyOf(dialog)];
    NSMutableArray *fresh = [NSMutableArray array];
    for (NoshiDialog *dialog in dialogs) {
        if (![self dialog:dialog fitsTab:tab] || [known containsObject:NoshiClassicKeyOf(dialog)]) continue;
        [fresh addObject:dialog];
    }
    [_global release];
    _global = fresh.count ? [fresh retain] : nil;
    _globalDone = YES;
    /* a failed server search with nothing local to show is a failure, not an empty answer */
    _globalFailed = !dialogs;
    [self updateLocalState];
}

- (void)didFindMessages:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) NSLog(@"noshigram: message search failed: %@", errorName);
    [_messages release];
    _messages = dialogs.count ? [dialogs retain] : nil;
    _messagesDone = YES;
    [self updateLocalState];
}

- (void)didSearch:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) {
        NSLog(@"noshigram: search failed: %@", errorName);
        _state = NoshiClassicStateFailed;
    } else {
        [_rows release];
        _rows = [dialogs retain];
        _state = dialogs.count ? NoshiClassicStateResults : NoshiClassicStateEmpty;
    }
    [self refreshState];
}

#pragma mark state

- (void)updateDuck {
    [_duck setPlaying:!_emptyView.hidden && !_duck.hidden && self.view.window != nil];
}

- (void)refreshState {
    BOOL showsEmpty = _state == NoshiClassicStateEmpty || _state == NoshiClassicStateHint || _state == NoshiClassicStateFailed;
    _emptyView.hidden = !showsEmpty;
    _duck.hidden = _state != NoshiClassicStateEmpty;
    if (_state == NoshiClassicStateEmpty) {
        _emptyTitle.text = NSLocalizedString(@"search.empty.title", nil);
        _emptyText.text = [NSString stringWithFormat:NSLocalizedString(@"search.empty.text", nil), _query];
    } else if (_state == NoshiClassicStateFailed) {
        _emptyTitle.text = @"";
        _emptyText.text = NSLocalizedString(@"search.failed", nil);
    } else if (_state == NoshiClassicStateHint) {
        BOOL downloads = _tabs.selectedSegmentIndex == NoshiClassicTabDownloads;
        _emptyTitle.text = downloads ? NSLocalizedString(@"search.downloads.title", nil) : @"";
        _emptyText.text = downloads ? NSLocalizedString(@"search.downloads.text", nil) : NSLocalizedString(@"search.hint", nil);
    }
    if (_state == NoshiClassicStateLoading) [_spinner startAnimating];
    else [_spinner stopAnimating];
    _table.hidden = !(_state == NoshiClassicStateResults || _state == NoshiClassicStateStart);
    [_table reloadData];
    [self updateDuck];
    [self layoutSearch];
}

#pragma mark table

/* the recent chats show on the chat kinds they fit; the rest of the screen shows what the last search found */
- (NSArray *)visibleRows {
    if (_state != NoshiClassicStateStart) return _rows;
    NSMutableArray *fitting = [NSMutableArray array];
    for (NoshiDialog *dialog in _recent) if ([self dialog:dialog fitsTab:_tabs.selectedSegmentIndex]) [fitting addObject:dialog];
    return fitting;
}

/* the groups of the list from the top: the rows, then the public chats and the messages when the server found some; 0, 1 and 2 */
- (NSArray *)sectionKinds {
    NSMutableArray *kinds = [NSMutableArray arrayWithObject:[NSNumber numberWithInt:0]];
    if (_state != NoshiClassicStateResults) return kinds;
    if (_global.count) [kinds addObject:[NSNumber numberWithInt:1]];
    if (_messages.count && _tabs.selectedSegmentIndex == NoshiClassicTabChats) [kinds addObject:[NSNumber numberWithInt:2]];
    return kinds;
}

- (NSInteger)kindOfSection:(NSInteger)section {
    NSArray *kinds = [self sectionKinds];
    return (NSUInteger)section < kinds.count ? [[kinds objectAtIndex:(NSUInteger)section] integerValue] : 0;
}

- (NSArray *)itemsOfKind:(NSInteger)kind {
    return kind == 1 ? _global : (kind == 2 ? _messages : [self visibleRows]);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)[[self sectionKinds] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[self itemsOfKind:[self kindOfSection:section]] count];
}

- (NoshiDialog *)dialogAtIndexPath:(NSIndexPath *)indexPath {
    return [[self itemsOfKind:[self kindOfSection:indexPath.section]] objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)headerTextOfSection:(NSInteger)section {
    NSInteger kind = [self kindOfSection:section];
    if (kind == 1) return NSLocalizedString(@"search.global", nil);
    if (kind == 2) return NSLocalizedString(@"search.messages", nil);
    return _state == NoshiClassicStateStart && [[self visibleRows] count] ? NSLocalizedString(@"search.recent", nil) : nil;
}

#define SECTION_HEADER_HEIGHT 28.0

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self headerTextOfSection:section] ? SECTION_HEADER_HEIGHT : 0;
}

/* the title is in the accent on the plain ground of the strips that stand over the wallpaper, as the system's own grey band with white words took no part in the theme */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self headerTextOfSection:section];
    if (!text) return nil;
    CGFloat width = tableView.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, SECTION_HEADER_HEIGHT)] autorelease];
    header.backgroundColor = NoshiClassicStripGround();
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(14, 0, MAX(0, width - 28), SECTION_HEADER_HEIGHT)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:15];
    label.textColor = NoshiColorAccent();
    label.text = text;
    [header addSubview:label];
    return header;
}

/* a chat of a forum or a community wears a row of its topics, and the fixed row height of the table cut it off */
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *shown = [self itemsOfKind:[self kindOfSection:indexPath.section]];
    if ((NSUInteger)indexPath.row >= shown.count) return tableView.rowHeight;
    return [NoshiClassicDialogCell rowHeightForDialog:[shown objectAtIndex:(NSUInteger)indexPath.row]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"result";
    NoshiClassicDialogCell *cell = (NoshiClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithDialog:[self dialogAtIndexPath:indexPath] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_bar resignFirstResponder];
    NoshiDialog *dialog = [self dialogAtIndexPath:indexPath];
    /* a message found in a chat opens the chat at the message; the chat that was looked for is kept in the history */
    BOOL message = [self kindOfSection:indexPath.section] == 2 || (!NoshiClassicTabIsLocal(_tabs.selectedSegmentIndex) && _state == NoshiClassicStateResults);
    if (!message) [self remember:dialog];
    if (!message && dialog.community) {
        [self.navigationController pushViewController:NoshiCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    if (!message && dialog.forum) {
        [self.navigationController pushViewController:NoshiTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    if (message) chat.startMessageId = dialog.topMessage;
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == _table) [_bar resignFirstResponder];
}

@end

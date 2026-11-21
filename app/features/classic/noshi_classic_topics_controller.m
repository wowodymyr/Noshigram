#import "noshi_classic_topics_controller.h"

#import "noshi_chat_controller.h"
#import "noshi_next_chat_hint.h"
#import "noshi_classic_chrome.h"
#import "noshi_classic_dialog_cell.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiClassicTopicsController () {
    NoshiSession *_session;
    NoshiDialog *_forum;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;
    NSArray *_topics;
    NSMutableSet *_topicsSeen;
    UILabel *_status;
    BOOL _loading;
    BOOL _loaded;
    void (^_closeHandler)(void);
}
@end

@implementation NoshiClassicTopicsController

@synthesize closeHandler = _closeHandler;

- (id)initWithSession:(NoshiSession *)session forum:(NoshiDialog *)forum avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media stickers:(NoshiStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _session = [session retain];
    _forum = [forum retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogRead:) name:NoshiDialogReadNotification object:session];
    _topics = [[NSArray alloc] init];
    NSString *heading = forum.saved ? NSLocalizedString(@"chat.saved.dialogs", nil) : forum.title;
    self.title = heading;
    /* the bar title is a user's own text, so the emoji in it come from the app's pictures */
    self.navigationItem.titleView = NoshiClassicTitleView(heading, nil);
    /* the arrow of the chats above it, instead of the system plate that names the list: after a swipe back from a topic that plate stayed in the bar under the arrow of the next
       chat, and the two lay over each other. with the same arrow on both screens, whatever the bar leaves behind is the same picture */
    self.navigationItem.hidesBackButton = YES;
    UIBarButtonItem *back = [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(NoshiSymbolBack, 22, [UIColor whiteColor])
                                                              style:UIBarButtonItemStyleBordered target:self action:@selector(goBack)] autorelease];
    back.accessibilityLabel = NSLocalizedString(@"phone.back", nil);
    self.navigationItem.leftBarButtonItem = back;
    return self;
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

/* a topic was read here: its count goes from its row at once */
- (void)dialogRead:(NSNotification *)note {
    if (NoshiDialogsApplyingRead(_topics, note.userInfo) && [self isViewLoaded]) [self.tableView reloadData];
}

- (BOOL)showsForum:(NoshiDialog *)forum {
    return forum.peerKind == _forum.peerKind && forum.peerId == _forum.peerId;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiDialogReadNotification object:nil];
    [_weak clear];
    [_weak release];
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_forum release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_topicsSeen release];
    [_topics release];
    [_status release];
    [_closeHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    NoshiClassicStyleTable(table);
    table.rowHeight = [NoshiClassicDialogCell rowHeight];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = [UIColor grayColor];
    _status.textAlignment = NoshiTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.font = [UIFont systemFontOfSize:16];
    _status.frame = table.backgroundView.bounds;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:_status];
    [self reload];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    [self retain];
    /* the favorites list the chats their messages came from, in the place of topics */
    void (^arrived)(NSArray *, NSString *) = ^(NSArray *items, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        if (!items) {
            /* topics already on screen stay; only an empty screen shows the failure */
            if (!_loaded) {
                _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
            } else {
                NSLog(@"noshigram: refresh of the topics failed: %@", errorName);
            }
            return;
        }
        _loaded = YES;
        [_topics release];
        _topics = [items copy];
        _status.text = _topics.count ? @"" : NSLocalizedString(_forum.saved ? @"chat.saved.empty" : @"topics.empty", nil);
        self.tableView.separatorStyle = NoshiClassicListSeparatorStyle(_topics.count > 0);
        [self.tableView reloadData];
        [self loadIcons];
    };
    if (_forum.saved) [_session loadSavedDialogs:arrived];
    else [_session loadTopicsOfDialog:_forum completion:arrived];
}

/* the rows draw the hash until the emoji picture is in memory, then they are configured again */
- (void)loadIcons {
    NSMutableArray *icons = [NSMutableArray array];
    for (NoshiDialog *topic in _topics) {
        if (topic.topicIconEmoji) [icons addObject:[NSNumber numberWithLongLong:topic.topicIconEmoji]];
    }
    if (!icons.count) return;
    NoshiWeakReference *weak = _weak;
    [NoshiCustomEmojiLoader loadDocuments:icons session:_session media:_media documents:nil picture:^{
        NoshiClassicTopicsController *topics = weak.target;
        if (topics) [topics.tableView reloadData];
    }];
}

/* the list is fetched once, so a topic read or written in the chat opened over it kept its old count here, and only a message from someone else made the server say it again;
   coming back to the list asks the server again */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_loaded) [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] && _closeHandler) _closeHandler();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_topics.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"topic";
    NoshiClassicDialogCell *cell = (NoshiClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[NoshiClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithDialog:[_topics objectAtIndex:(NSUInteger)indexPath.row] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NoshiDialog *row = [_topics objectAtIndex:(NSUInteger)indexPath.row];
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:_forum.saved ? [_forum savedDialogFromSource:row] : row
                                                                          avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    /* a topic goes on to the next one with unread messages when the list is pulled past its end, as a channel goes on to the next channel; the topics gone through are forgotten
       when another one is opened from the list */
    [_topicsSeen release];
    _topicsSeen = [[NSMutableSet alloc] init];
    chat.nextChatProvider = ^NoshiDialog *(NoshiDialog *current) { return _forum.saved ? nil : [NoshiNextChatHint nextUnreadTopicIn:_topics after:current seen:_topicsSeen]; };
    /* reading changed the counts of the topics, so they load again once the person is back */
    chat.closeHandler = ^{ [self reload]; };
    [self.navigationController pushViewController:chat animated:YES];
}

@end

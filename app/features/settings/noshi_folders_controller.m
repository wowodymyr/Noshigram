#import "noshi_folders_controller.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_settings_extras.h"

#import "noshi_alert.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_custom_emoji_picker.h"
#import "noshi_emoji_text_view.h"
#import "noshi_gift_screen.h"
#import "noshi_lottie_view.h"
#import "noshi_message.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

static BOOL same_peer(noshi_peer_ref a, noshi_peer_ref b) {
    return a.self || b.self ? a.self == b.self : a.kind == b.kind && a.id == b.id;
}
static BOOL has_peer(NSData *data, noshi_peer_ref peer) {
    const noshi_peer_ref *peers = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(peer); ++i)
        if (same_peer(peers[i], peer))
            return YES;
    return NO;
}
static NSData *toggle_peer(NSData *data, noshi_peer_ref peer, BOOL include) {
    NSMutableData *updated = [NSMutableData data];
    const noshi_peer_ref *peers = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(peer); ++i)
        if (!same_peer(peers[i], peer))
            [updated appendBytes:&peers[i] length:sizeof(peer)];
    if (include && updated.length / sizeof(peer) < NOSHI_FOLDER_PEERS_MAX)
        [updated appendBytes:&peer length:sizeof(peer)];
    return updated;
}
static noshi_peer_ref dialog_peer(NoshiDialog *dialog) {
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    peer.kind = dialog.peerKind;
    peer.id = dialog.peerId;
    peer.access_hash = dialog.peerHash;
    peer.self = dialog.saved;
    return peer;
}

@interface NoshiFolderNameController : UIViewController <UITextViewDelegate, NoshiCustomEmojiPickerDelegate> {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NoshiEmojiTextView *_text;
    NoshiCustomEmojiPicker *_picker;
    UIButton *_emojiButton;
    NSMutableArray *_entities;
    NSString *_initialTitle;
    BOOL _changed;
    void (^_done)(NSString *, NSArray *, BOOL);
}
- (id)initWithSession:(NoshiSession *)session folder:(NoshiChatFolder *)folder done:(void (^)(NSString *, NSArray *, BOOL))done;
@end

@implementation NoshiFolderNameController
- (id)initWithSession:(NoshiSession *)session folder:(NoshiChatFolder *)folder done:(void (^)(NSString *, NSArray *, BOOL))done {
    self = [super init];
    if (self) {
        _session = [session retain];
        _initialTitle = [folder.title copy];
        _entities = [[NSMutableArray alloc] initWithArray:folder.titleEntities ? folder.titleEntities : [NSArray array]];
        _done = [done copy];
        if ([self respondsToSelector:NSSelectorFromString(@"setEdgesForExtendedLayout:")])
            [self setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
        self.title = NSLocalizedString(@"folders.name", nil);
    }
    return self;
}
- (void)dealloc {
    _text.delegate = nil;
    _picker.delegate = nil;
    [_session release];
    [_media release];
    [_text release];
    [_picker release];
    [_emojiButton release];
    [_entities release];
    [_initialTitle release];
    [_done release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NoshiColorScreen();
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"folders.save", nil)
        style:UIBarButtonItemStyleDone target:self action:@selector(done)] autorelease];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    _media = [[NoshiMediaCache alloc] initWithSession:_session directory:[[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"media"]];
    _text = [[NoshiEmojiTextView alloc] initWithFrame:CGRectZero];
    _text.backgroundColor = NoshiColorField();
    _text.emojiBackgroundColor = NoshiColorField();
    _text.textColor = NoshiColorTitle();
    _text.font = NoshiFontRegular(18);
    _text.delegate = self;
    _text.text = _initialTitle;
    _text.customEmojiEntities = _entities;
    [self.view addSubview:_text];
    _emojiButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_emojiButton setTitle:NSLocalizedString(@"folders.emoji", nil) forState:UIControlStateNormal];
    [_emojiButton setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_emojiButton addTarget:self action:@selector(showEmoji) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_emojiButton];
    _picker = [[NoshiCustomEmojiPicker alloc] initWithSession:_session media:_media];
    _picker.delegate = self;
    [self.view addSubview:_picker];
    [_picker prepare];
    NSMutableArray *documents = [NSMutableArray array];
    for (NoshiTextEntity *entity in _entities) [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
    if (documents.count) [NoshiCustomEmojiLoader loadDocuments:documents session:_session media:_media documents:nil picture:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
    _text.frame = CGRectMake(12, 12, MAX(0, width - 24), 54);
    _emojiButton.frame = CGRectMake(12, 70, MAX(0, width - 24), 40);
    _picker.frame = CGRectMake(0, 112, width, MAX(0, height - 112));
}
- (void)showEmoji {
    [_text resignFirstResponder];
    [_picker prepare];
}
- (void)shiftForRange:(NSRange)range replacementLength:(NSUInteger)length {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_entities.count];
    for (NoshiTextEntity *entity in _entities) {
        size_t offset = entity.range.location;
        if (!noshi_folder_shift_emoji(&offset, entity.range.length, range.location, range.length, length)) continue;
        NoshiTextEntity *moved = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji
            range:NSMakeRange(offset, entity.range.length) url:nil] autorelease];
        moved.documentId = entity.documentId;
        [kept addObject:moved];
    }
    [_entities setArray:kept];
}
- (BOOL)textView:(UITextView *)view shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)replacement {
    if (range.location > view.text.length || range.length > view.text.length - range.location) return NO;
    [self shiftForRange:range replacementLength:replacement.length];
    _changed = YES;
    return YES;
}
- (void)textViewDidChange:(UITextView *)view {
    (void)view;
    _text.customEmojiEntities = _entities;
}
- (void)customEmojiPicker:(NoshiCustomEmojiPicker *)picker didPickEmoji:(NoshiCustomEmojiDocument *)emoji {
    (void)picker;
    NSRange range = _text.selectedRange;
    NSString *text = _text.text;
    if (emoji.documentId <= 0 || !emoji.alt.length || range.location > text.length || range.length > text.length - range.location) return;
    [self shiftForRange:range replacementLength:emoji.alt.length];
    _text.text = [text stringByReplacingCharactersInRange:range withString:emoji.alt];
    NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji
        range:NSMakeRange(range.location, emoji.alt.length) url:nil] autorelease];
    entity.documentId = emoji.documentId;
    [_entities addObject:entity];
    _text.customEmojiEntities = _entities;
    _text.selectedRange = NSMakeRange(range.location + emoji.alt.length, 0);
    _changed = YES;
}
- (void)done {
    NSString *text = _text.text;
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger start = 0, end = text.length;
    while (start < end && [spaces characterIsMember:[text characterAtIndex:start]]) ++start;
    while (end > start && [spaces characterIsMember:[text characterAtIndex:end - 1]]) --end;
    if (end == start || end - start > 12) {
        NoshiShowNotice(nil, NSLocalizedString(@"folders.name.info", nil));
        return;
    }
    if (end < text.length) [self shiftForRange:NSMakeRange(end, text.length - end) replacementLength:0];
    if (start) [self shiftForRange:NSMakeRange(0, start) replacementLength:0];
    if (_done) _done([text substringWithRange:NSMakeRange(start, end - start)], _entities, _changed || start || end != text.length);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface NoshiFolderPeersController : NoshiSettingsPageController {
    NoshiChatFolder *_folder;
    NSArray *_dialogs;
    NSInteger _kind;
    NoshiWeakReference *_weak;
}
- (id)initWithFolder:(NoshiChatFolder *)folder dialogs:(NSArray *)dialogs kind:(NSInteger)kind;
@end

@implementation NoshiFolderPeersController
- (id)initWithFolder:(NoshiChatFolder *)folder dialogs:(NSArray *)dialogs kind:(NSInteger)kind {
    self = [super init];
    if (self) {
        _folder = [folder retain];
        _dialogs = [dialogs copy];
        _kind = kind;
        _weak = [[NoshiWeakReference referenceTo:self] retain];
        self.pageTitle = NSLocalizedString(kind == 0 ? @"folders.include" : (kind == 1 ? @"folders.exclude" : @"folders.pinned"), nil);
        self.searchable = YES;
    }
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_folder release];
    [_dialogs release];
    [super dealloc];
}
- (NSData *)selection {
    return _kind == 0 ? _folder.included : (_kind == 1 ? _folder.excluded : _folder.pinned);
}
- (void)toggle:(NSData *)packed {
    noshi_peer_ref peer;
    [packed getBytes:&peer length:sizeof(peer)];
    BOOL on = !has_peer([self selection], peer);
    if (on && [self selection].length / sizeof(peer) >= NOSHI_FOLDER_PEERS_MAX) {
        NoshiShowNotice(nil, NSLocalizedString(@"folders.limit", nil));
        return;
    }
    NSData *updated = toggle_peer([self selection], peer, on);
    if (_kind == 0) {
        _folder.included = updated;
        if (on)
            _folder.excluded = toggle_peer(_folder.excluded, peer, NO);
    } else if (_kind == 1) {
        _folder.excluded = updated;
        if (on) {
            _folder.included = toggle_peer(_folder.included, peer, NO);
            _folder.pinned = toggle_peer(_folder.pinned, peer, NO);
        }
    } else {
        _folder.pinned = updated;
        if (on)
            _folder.excluded = toggle_peer(_folder.excluded, peer, NO);
    }
    [self rebuild];
    [self reloadSearchResults];
}
- (NSArray *)sectionsMatching:(NSString *)query {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableData *known = [NSMutableData data];
    NoshiWeakReference *weak = _weak;
    for (NoshiDialog *dialog in _dialogs) {
        if (dialog.folder || (_folder.shared && dialog.peerKind != 3))
            continue;
        noshi_peer_ref peer = dialog_peer(dialog);
        if (has_peer(known, peer))
            continue;
        [known appendBytes:&peer length:sizeof(peer)];
        if (query.length && [dialog.title rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound)
            continue;
        NSData *packed = [NSData dataWithBytes:&peer length:sizeof(peer)];
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:dialog.title
                                                     subtitle:nil
                                                      checked:has_peer([self selection], peer)
                                                          tap:^{
                                                              [(NoshiFolderPeersController *)weak.target toggle:packed];
                                                          }]];
    }
    if (!query.length) {
        NSData *selection = [self selection];
        const noshi_peer_ref *peers = selection.bytes;
        for (NSUInteger i = 0; i < selection.length / sizeof(*peers); ++i) {
            if (has_peer(known, peers[i]))
                continue;
            NSData *packed = [NSData dataWithBytes:&peers[i] length:sizeof(*peers)];
            [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"folders.unknown", nil)
                                                         subtitle:nil
                                                          checked:YES
                                                              tap:^{
                                                                  [(NoshiFolderPeersController *)weak.target toggle:packed];
                                                              }]];
        }
    }
    return [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:rows]];
}
- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    return [self sectionsMatching:query];
}
- (void)rebuild {
    self.sections = [self sectionsMatching:@""];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}
@end

@interface NoshiFolderEditController : NoshiSettingsPageController {
    NoshiSession *_session;
    NoshiChatFolder *_folder;
    NSArray *_dialogs;
    BOOL _saving;
    BOOL _loading;
    id<NoshiFolderDialogRequest> _folderLoad;
    NoshiWeakReference *_weak;
}
- (id)initWithSession:(NoshiSession *)session folder:(NoshiChatFolder *)folder;
@end

@implementation NoshiFolderEditController
- (id)initWithSession:(NoshiSession *)session folder:(NoshiChatFolder *)folder {
    self = [super init];
    if (self) {
        _session = [session retain];
        _folder = [folder copy];
        _weak = [[NoshiWeakReference referenceTo:self] retain];
        self.pageTitle = folder.title;
    }
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_session release];
    [_folder release];
    [_dialogs release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadChats];
}
- (void)loadChats {
    if (_loading)
        return;
    _loading = YES;
    [self rebuild];
    NoshiChatFolder *all = [[[NoshiChatFolder alloc] init] autorelease];
    all.folderId = 2;
    all.flags = 31;
    NoshiWeakReference *weak = _weak;
    [_folderLoad release];
    _folderLoad = [[_session loadDialogsForChatFolder:all
                                           completion:^(NSArray *dialogs, NSString *errorName) {
                                               NoshiFolderEditController *me = weak.target;
                                               if (!me)
                                                   return;
                                               me->_loading = NO;
                                               if (errorName)
                                                   NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
                                               else {
                                                   [me->_dialogs release];
                                                   me->_dialogs = [dialogs retain];
                                               }
                                               [me rebuild];
                                           }] retain];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self isViewLoaded])
        [self rebuild];
}
- (void)rename {
    if (_saving)
        return;
    NoshiWeakReference *weak = _weak;
    NoshiFolderNameController *page = [[[NoshiFolderNameController alloc] initWithSession:_session folder:_folder done:^(NSString *name, NSArray *entities, BOOL changed) {
        NoshiFolderEditController *me = weak.target;
        if (!me)
            return;
        if (changed) {
            me->_folder.title = name;
            me->_folder.titleEntities = entities;
        }
        me.pageTitle = name;
        [me rebuild];
    }] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)pick:(NSInteger)kind {
    if (_saving)
        return;
    if (!_dialogs) {
        [self loadChats];
        return;
    }
    NoshiFolderPeersController *page = [[[NoshiFolderPeersController alloc] initWithFolder:_folder dialogs:_dialogs kind:kind] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)save {
    if (_saving)
        return;
    if (!_folder.title.length || _folder.title.length > 12 || (!(_folder.flags & 31u) && !_folder.included.length && !_folder.pinned.length)) {
        NoshiShowNotice(nil, NSLocalizedString(@"folders.empty", nil));
        return;
    }
    _saving = YES;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session saveChatFolder:_folder
                  completion:^(NSString *errorName) {
                      NoshiFolderEditController *me = weak.target;
                      if (!me)
                          return;
                      me->_saving = NO;
                      if (errorName) {
                          NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
                          [me rebuild];
                      } else
                          [me goBack];
                  }];
}
- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection
                            sectionWithHeader:nil
                                       footer:NSLocalizedString(@"folders.sync.info", nil)
                                         rows:[NSArray arrayWithObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"folders.name", nil)
                                                                                                  value:_folder.title
                                                                                                    tap:^{
                                                                                                        [(NoshiFolderEditController *)weak.target rename];
                                                                                                    }]]]];
    NSMutableArray *rules = [NSMutableArray array];
    NSArray *keys = [NSArray arrayWithObjects:@"folders.contacts", @"folders.noncontacts", @"folders.groups", @"folders.channels", @"folders.bots",
                                              @"folders.muted", @"folders.read", @"folders.archived", nil];
    if (!_folder.shared)
        for (NSUInteger i = 0; i < keys.count; ++i) {
            uint32_t mask = 1u << i;
            NoshiSettingsRow *row = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil)
                                                                    subtitle:nil
                                                                          on:(_folder.flags & mask) != 0
                                                                      toggle:^(BOOL on) {
                                                                          NoshiFolderEditController *me = weak.target;
                                                                          if (!me || me->_saving)
                                                                              return;
                                                                          me->_folder.flags = on ? me->_folder.flags | mask : me->_folder.flags & ~mask;
                                                                      }];
            row.disabled = _saving;
            [rules addObject:row];
        }
    if (rules.count)
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"folders.rules", nil) footer:nil rows:rules]];
    NSMutableArray *choices = [NSMutableArray array];
    for (NSInteger kind = 0; kind < 3; ++kind) {
        if (_folder.shared && kind == 1)
            continue;
        NSData *data = kind == 0 ? _folder.included : (kind == 1 ? _folder.excluded : _folder.pinned);
        NSString *key = kind == 0 ? @"folders.include" : (kind == 1 ? @"folders.exclude" : @"folders.pinned");
        [choices addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(key, nil)
                                                      value:[NSString stringWithFormat:@"%lu", (unsigned long)(data.length / sizeof(noshi_peer_ref))]
                                                        tap:^{
                                                            [(NoshiFolderEditController *)weak.target pick:kind];
                                                        }]];
    }
    if (!_dialogs)
        [choices addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(_loading ? @"folders.loading" : @"folders.retry", nil)
                                                      value:nil
                                                        tap:^{
                                                            [(NoshiFolderEditController *)weak.target loadChats];
                                                        }]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"folders.priority", nil) rows:choices]];
    [sections
        addObject:[NoshiSettingsSection
                      sectionWithHeader:nil
                                 footer:nil
                                   rows:[NSArray arrayWithObject:[NoshiSettingsRow
                                                                     actionRowWithSymbol:NoshiSymbolCheckMark()
                                                                                   title:NSLocalizedString(_saving ? @"folders.saving" : @"folders.save", nil)
                                                                             destructive:NO
                                                                                     tap:^{
                                                                                         [(NoshiFolderEditController *)weak.target save];
                                                                                     }]]]];
    self.sections = sections;
}
@end

#define HINT_STICKER 130.0
#define HINT_INSET 12.0

@interface NoshiFoldersController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    BOOL _busy;
    NSArray *_suggested;
    /* the animated sticker over the list is made once and moved into each header that is built */
    NoshiLottieView *_sticker;
    CGFloat _headerWidth;
}
@end

@implementation NoshiFoldersController
- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (self) {
        _session = [session retain];
        _weak = [[NoshiWeakReference referenceTo:self] retain];
        self.pageTitle = NSLocalizedString(@"folders.title", nil);
    }
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_suggested release];
    [_sticker release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:NoshiChatFoldersDidChangeNotification object:_session];
    [self rebuild];
    [self refresh];
}
/* the sticker is loaded before the screen is on, so its first frame is drawn while the push still moves and the card is not empty until the animation parses */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_sticker setLoaded:YES];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_sticker playOnce];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_sticker setPlaying:NO];
    [_sticker setLoaded:NO];
}
- (void)themeDidChange {
    [self rebuildHeader];
    [self rebuild];
}
- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiFoldersController alloc] initWithSession:_session] autorelease];
}

/* the animated sticker over a line that says what folders are for, in a card like the one of the devices screen */
- (void)rebuildHeader {
    CGFloat width = self.table.bounds.size.width;
    if (width <= 0) return;
    _headerWidth = width;
    if (!_sticker) {
        _sticker = [[NoshiLottieView alloc] initWithAnimationNamed:@"folders_hint"];
        /* the first frame of the visit before stands in while the animation parses */
        _sticker.cachesPoster = YES;
        [_sticker setLoaded:YES];
        _sticker.userInteractionEnabled = YES;
        [_sticker addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replaySticker)] autorelease]];
    }
    CGFloat cardWidth = width - 2 * HINT_INSET;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 100)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.textColor = NoshiColorSecondary();
    text.font = NoshiFontRegular(15);
    text.textAlignment = NoshiTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = NSLocalizedString(@"folders.hint", nil);
    CGSize fit = [text sizeThatFits:CGSizeMake(cardWidth - 40, 400)];
    _sticker.frame = CGRectMake((cardWidth - HINT_STICKER) / 2, 12, HINT_STICKER, HINT_STICKER);
    text.frame = CGRectMake(20, CGRectGetMaxY(_sticker.frame) + 8, cardWidth - 40, ceil(fit.height));
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = NoshiColorCard();
    card.layer.cornerRadius = 22;
    card.frame = CGRectMake(HINT_INSET, 12, cardWidth, CGRectGetMaxY(text.frame) + 16);
    [card addSubview:_sticker];
    [card addSubview:text];
    [header addSubview:card];
    header.frame = CGRectMake(0, 0, width, CGRectGetMaxY(card.frame) + 8);
    self.headerView = header;
}
- (void)replaySticker {
    [_sticker rewind];
    [_sticker playOnce];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* the card is laid out for the width of the table, so a turn of the phone builds it again */
    if (fabs(self.table.bounds.size.width - _headerWidth) > 0.5) [self rebuildHeader];
}
- (void)refresh {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        (void)folders;
        NoshiFoldersController *me = weak.target;
        if (!me)
            return;
        me->_busy = NO;
        if (errorName)
            NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
        [me rebuild];
    }];
    [_session loadSuggestedChatFoldersWithCompletion:^(NSArray *items, NSString *errorName) {
        NoshiFoldersController *me = weak.target;
        if (!me)
            return;
        if (!items)
            NSLog(@"noshigram: the recommended folders did not load: %@", errorName);
        [me->_suggested release];
        me->_suggested = [items retain];
        [me rebuild];
    }];
}
/* the lowest id the account has not used, from 2: the first is the list of all chats */
- (int32_t)freeIdentifierAmong:(NSArray *)folders {
    int32_t identifier = 2;
    for (; identifier <= NOSHI_FOLDERS_MAX + 2; ++identifier) {
        BOOL taken = NO;
        for (NoshiChatFolder *existing in folders)
            if (existing.folderId == identifier)
                taken = YES;
        if (!taken)
            break;
    }
    return identifier;
}
- (void)create {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        NoshiFoldersController *me = weak.target;
        if (!me)
            return;
        me->_busy = NO;
        [me rebuild];
        if (errorName) {
            NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
            return;
        }
        NoshiChatFolder *folder = [[[NoshiChatFolder alloc] init] autorelease];
        folder.folderId = [me freeIdentifierAmong:folders];
        folder.title = NSLocalizedString(@"folders.new", nil);
        [me.navigationController pushViewController:[[[NoshiFolderEditController alloc] initWithSession:me->_session folder:folder] autorelease]
                                           animated:YES];
    }];
}
/* a recommended folder is saved as it came, under an id the account does not use */
- (void)addSuggested:(NoshiSuggestedFolder *)suggestion {
    if (_busy)
        return;
    _busy = YES;
    [self rebuild];
    NoshiChatFolder *folder = [[suggestion.folder copy] autorelease];
    folder.folderId = [self freeIdentifierAmong:_session.chatFolders];
    NoshiWeakReference *weak = _weak;
    [_session saveChatFolder:folder completion:^(NSString *errorName) { [(NoshiFoldersController *)weak.target finish:errorName]; }];
}
- (void)finish:(NSString *)errorName {
    _busy = NO;
    if (errorName)
        NoshiShowNotice(nil, NoshiGiftErrorText(errorName));
    [self rebuild];
}
- (void)choose:(NoshiChatFolder *)folder {
    if (_busy)
        return;
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"folders.edit", nil), NSLocalizedString(@"folders.up", nil),
                                                 NSLocalizedString(@"folders.down", nil), NSLocalizedString(@"folders.delete", nil), nil];
    NoshiSettingsChoose(self, folder.title, options, ^(NSUInteger choice) {
        NoshiFoldersController *me = weak.target;
        if (!me || me->_busy)
            return;
        if (choice == 0) {
            [me.navigationController pushViewController:[[[NoshiFolderEditController alloc] initWithSession:me->_session folder:folder] autorelease]
                                               animated:YES];
            return;
        }
        if (choice == 3) {
            NoshiConfirmAction(me, NSLocalizedString(@"folders.delete.info", nil), NSLocalizedString(@"folders.delete", nil), ^{
                NoshiFoldersController *page = weak.target;
                if (!page || page->_busy)
                    return;
                page->_busy = YES;
                [page rebuild];
                [page->_session deleteChatFolder:folder.folderId
                                      completion:^(NSString *errorName) {
                                          [(NoshiFoldersController *)weak.target finish:errorName];
                                      }];
            });
            return;
        }
        NSMutableArray *ordered = [NSMutableArray arrayWithArray:me->_session.chatFolders];
        NSUInteger index = [ordered indexOfObject:folder];
        if (index == NSNotFound)
            return;
        NSInteger to = (NSInteger)index + (choice == 1 ? -1 : 1);
        if (to < 0 || (NSUInteger)to >= ordered.count)
            return;
        [ordered exchangeObjectAtIndex:index withObjectAtIndex:(NSUInteger)to];
        me->_busy = YES;
        [me rebuild];
        [me->_session orderChatFolders:ordered
                            completion:^(NSString *errorName) {
                                [(NoshiFoldersController *)weak.target finish:errorName];
                            }];
    });
}

/* what a folder holds, in the words: the kinds of chat it takes and how many chats are named, or that it is empty */
static NSString *NoshiFolderSummary(NoshiChatFolder *folder) {
    if (folder.shared)
        return NSLocalizedString(@"folders.shared", nil);
    static NSString *const keys[] = {@"folders.contacts", @"folders.noncontacts", @"folders.groups", @"folders.channels", @"folders.bots"};
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 5; ++i)
        if (folder.flags & (1u << i))
            [parts addObject:NSLocalizedString(keys[i], nil)];
    NSUInteger named = folder.included.length / sizeof(noshi_peer_ref);
    if (named)
        [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"folders.chats.count", nil), (unsigned long)named]];
    return parts.count ? [parts componentsJoinedByString:@", "] : NSLocalizedString(@"folders.nochats", nil);
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    if (!self.headerView) [self rebuildHeader];
    NSMutableArray *sections = [NSMutableArray array];
    NSArray *folders = _session.chatFolders;
    NSMutableArray *mine = [NSMutableArray array];
    for (NoshiChatFolder *folder in folders)
        if (folder.folderId)
            [mine addObject:folder];
    /* the recommended folders show while the account has room, and the ones it already made are not offered again */
    if (_suggested.count && mine.count < 10) {
        NSMutableArray *offers = [NSMutableArray array];
        for (NoshiSuggestedFolder *suggestion in _suggested) {
            BOOL have = NO;
            for (NoshiChatFolder *folder in mine)
                if ([folder.title isEqualToString:suggestion.folder.title])
                    have = YES;
            if (have)
                continue;
            [offers addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsFolders
                                                           tone:NoshiSettingsToneGreen
                                                          title:suggestion.folder.title
                                                       subtitle:suggestion.info.length ? suggestion.info : nil
                                                          value:NSLocalizedString(@"folders.add", nil)
                                                            tap:^{
                                                                [(NoshiFoldersController *)weak.target addSuggested:suggestion];
                                                            }]];
        }
        if (offers.count)
            [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"folders.recommended", nil) footer:nil rows:offers]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiChatFolder *folder in mine) {
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsFolders
                                                     tone:NoshiSettingsToneBlue
                                                    title:folder.title
                                                 subtitle:NoshiFolderSummary(folder)
                                                    value:nil
                                                      tap:^{
                                                          [(NoshiFoldersController *)weak.target choose:folder];
                                                      }]];
    }
    if (mine.count < NOSHI_FOLDERS_MAX)
        [rows addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle
                                                          title:NSLocalizedString(@"folders.create", nil)
                                                    destructive:NO
                                                            tap:^{
                                                                [(NoshiFoldersController *)weak.target create];
                                                            }]];
    NSString *footer = _busy ? NSLocalizedString(@"folders.loading", nil) : NSLocalizedString(@"folders.sync.info", nil);
    [sections addObject:[NoshiSettingsSection sectionWithHeader:mine.count ? NSLocalizedString(@"folders.list", nil) : nil footer:footer rows:rows]];
    [sections addObject:NoshiFolderTabsSection(weak)];
    self.sections = sections;
    [self reloadSettings];
}
@end

#import "noshi_dialog_picker_controller.h"

#import "noshi_gift_screen.h"
#import "noshi_avatar_view.h"
#import "noshi_plural.h"
#import "noshi_time.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_people_avatars.h"
#import "noshi_person.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* the pages of the list the picker asks for after the first page of each folder: the chats that matter are among the first ones, the list the main screen kept already fills the
   picker, and the search reaches the rest on the server. twenty pages in a row on every opening made the server answer FLOOD_WAIT to the dialog requests of the whole account, and
   the forward that followed waited behind them for seconds and was refused */
#define PICKER_PAGES_MAX 2

/* seconds between a touch and the moment the app handles it, after which a tap is dropped: forwarding is sent at once and cannot be taken back */
#define PICKER_STALE_TAP 0.6

/* a frozen main thread queues the touches and handles them seconds later: the finger that began a scroll on a row then selects that row. this watches the
   touches without taking part in them and tells whether the last tap was handled long after the finger made it */
@interface NoshiStaleTapWatcher : UIGestureRecognizer {
    BOOL _stale;
}
@property (nonatomic, readonly) BOOL stale;
- (void)clear;
@end

@implementation NoshiStaleTapWatcher
@synthesize stale = _stale;

- (id)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        self.cancelsTouchesInView = NO;
        self.delaysTouchesBegan = NO;
        self.delaysTouchesEnded = NO;
    }
    return self;
}

- (void)noteTouches:(NSSet *)touches {
    NSTimeInterval now = [[NSProcessInfo processInfo] systemUptime];
    for (UITouch *touch in touches) if (now - touch.timestamp > PICKER_STALE_TAP) _stale = YES;
}

- (void)clear { _stale = NO; }

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _stale = NO;
    [self noteTouches:touches];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self noteTouches:touches];
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }

@end

@interface NoshiDialogPickerController () {
    NoshiStaleTapWatcher *_tapWatcher;
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiWeakReference *_weak;
    NoshiPeopleAvatars *_faces;
    NSArray *_all;
    NSString *_status;
    NSMutableArray *_picked;
    UIButton *_done;
    BOOL (^_filter)(NoshiDialog *dialog);
    void (^_pickHandler)(NSArray *dialogs);
    void (^_cancelHandler)(void);
    BOOL _resolved;
    NSUInteger _limit;
    BOOL _forwarding;
    NSString *_remoteQuery;
    NSArray *_remoteResults;
    NSString *_remoteError;
    NSMutableSet *_pageCursors;
    /* the chats held, by kind and id, so a page of the list is added in one pass; and whether the rows are due to be built again */
    NSMutableSet *_heldKeys;
    BOOL _rebuildScheduled;
    NSUInteger _pagesLoaded;
}
@end

@implementation NoshiDialogPickerController

@synthesize filter = _filter;
@synthesize forwarding = _forwarding;
@synthesize limit = _limit;
@synthesize pickHandler = _pickHandler;
@synthesize cancelHandler = _cancelHandler;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    (void)media;
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _picked = [[NSMutableArray alloc] init];
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    /* a picker dropped from the stack without being on screen again (popToRoot) never gets viewDidDisappear */
    [self resolveCancelled];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_all release];
    [_remoteQuery release];
    [_remoteResults release];
    [_remoteError release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_heldKeys release];
    [_pageCursors release];
    [_status release];
    [_picked release];
    [_done release];
    [_filter release];
    [_pickHandler release];
    [_cancelHandler release];
    [_tapWatcher release];
    [super dealloc];
}

- (void)resolveCancelled {
    if (_resolved) return;
    _resolved = YES;
    void (^handler)(void) = [_cancelHandler retain];
    if (handler) handler();
    [handler release];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    /* a picker presented in a navigation of its own is dismissed with that navigation, which does not move the picker out of its parent */
    if ([self isMovingFromParentViewController] || [self.navigationController isBeingDismissed]) [self resolveCancelled];
}

/* a screen that has no navigation stack to push on, such as the story viewer, presents the picker as the first page of a navigation of its own, and the picker
   then leaves by dismissing it */
- (void)leave {
    if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)goBack {
    if (self.searching) { [super goBack]; return; }
    [self leave];
}

- (UINavigationController *)presentableNavigation {
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
    navigation.navigationBarHidden = NO;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"story.close", nil)
        style:UIBarButtonItemStyleDone target:self action:@selector(goBack)] autorelease];
    return navigation;
}

- (NSString *)screenTitle {
    return self.pageTitle;
}

- (void)setScreenTitle:(NSString *)title {
    self.pageTitle = title;
}

- (NSUInteger)limit {
    return _limit ? _limit : 1;
}

/* a chat can be picked when it is a real chat the person can write in */
- (BOOL)usable:(NoshiDialog *)dialog {
    if (dialog.folder || dialog.community || dialog.left || dialog.topicId || dialog.replies) return NO;
    if (dialog.kind == NOSHI_DIALOG_CHANNEL && !dialog.canPost) return NO;
    return _filter ? _filter(dialog) : YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_forwarding) {
        long long account = [NoshiSession accountIdInDirectory:_session.directory];
        NoshiDialog *saved = account > 0 ? [NoshiDialog savedMessagesOfUserId:account] : nil;
        if (saved && [self usable:saved]) _all = [[NSArray alloc] initWithObjects:saved, nil];
    }
    _tapWatcher = [[NoshiStaleTapWatcher alloc] initWithTarget:nil action:NULL];
    [self.table addGestureRecognizer:_tapWatcher];
    [self rebuild];
    [self refreshAction];
    NoshiWeakReference *weak = _weak;
    if (!_forwarding) {
        [_session loadDialogs:^(NSArray *items, NSString *errorName) {
            NoshiDialogPickerController *me = weak.target;
            if (!me) return;
            if (items) [me addDestinations:items];
            else { [me->_status release]; me->_status = [NoshiGiftErrorText(errorName) copy]; [me rebuild]; }
        }];
    }
    if (_forwarding) {
        /* the chat list the main screen kept fills the picker at once, as the list of the destinations of the official clients does; the
           pages from the network then add what was not kept, so a slow or refused page no longer leaves only the contacts */
        for (int32_t kept = 0; kept <= 1; ++kept) {
            [_session loadCachedDialogsInFolder:kept completion:^(NSArray *items, NSString *errorName) {
                NoshiDialogPickerController *me = weak.target;
                if (me && items) [me addDestinations:items];
            }];
        }
        [self loadFolder:0 after:nil];
        [self loadFolder:1 after:nil];
        [_session loadContacts:^(NSArray *items, NSString *errorName) {
            NoshiDialogPickerController *me = weak.target;
            if (!me) return;
            if (!items) { NSLog(@"noshigram: forwarding contacts did not load: %@", errorName); return; }
            NSMutableArray *dialogs = [NSMutableArray array];
            for (NoshiPerson *person in items) {
                NoshiDialog *dialog = [NoshiDialog dialogWithPerson:person];
                if (dialog) [dialogs addObject:dialog];
            }
            [me addDestinations:dialogs];
        }];
    }
}

- (void)loadFolder:(int32_t)folder after:(NoshiDialog *)cursor {
    if (cursor) {
        if (!_pageCursors) _pageCursors = [[NSMutableSet alloc] init];
        NSString *key = [NSString stringWithFormat:@"%d:%d:%lld:%d", (int)folder, cursor.peerKind, cursor.peerId, cursor.topMessage];
        if ([_pageCursors containsObject:key]) {
            [_status release]; _status = [NoshiGiftErrorText(@"DIALOG_PAGINATION_FAILED") copy];
            [self rebuild];
            return;
        }
        [_pageCursors addObject:key];
    }
    NoshiWeakReference *weak = _weak;
    [_session loadDialogPageInFolder:folder after:cursor completion:^(NSArray *items, NoshiDialog *next, NSString *errorName) {
        NoshiDialogPickerController *me = weak.target;
        if (!me) return;
        if (items) [me addDestinations:items];
        if (errorName) {
            NSLog(@"noshigram: forwarding folder %d did not load: %@", (int)folder, errorName);
            [me->_status release]; me->_status = [NoshiGiftErrorText(errorName) copy];
            [me rebuild];
        } else if (next && ++me->_pagesLoaded <= PICKER_PAGES_MAX) [me loadFolder:folder after:next];
    }];
}

/* a page of the list comes in a moment after the one before, and every one of them built the whole table again and searched the whole list for each chat of the page, which froze a phone with
   a long list of chats; the chats are kept by key, and the table is built once after the pages have stopped coming */
- (void)addDestinations:(NSArray *)items {
    if (!_heldKeys) {
        _heldKeys = [[NSMutableSet alloc] init];
        for (NoshiDialog *row in _all) [_heldKeys addObject:[NSString stringWithFormat:@"%d:%lld", row.peerKind, row.peerId]];
    }
    NSMutableArray *rows = [NSMutableArray arrayWithArray:_all ? _all : [NSArray array]];
    BOOL added = NO;
    for (NoshiDialog *candidate in items) {
        if (![self usable:candidate]) continue;
        NSString *key = [NSString stringWithFormat:@"%d:%lld", candidate.peerKind, candidate.peerId];
        if ([_heldKeys containsObject:key]) continue;
        [_heldKeys addObject:key];
        [rows addObject:candidate];
        added = YES;
    }
    if (!added) return;
    [_all release]; _all = [rows copy];
    if (_all.count) { [_status release]; _status = nil; }
    [self scheduleRebuild];
}

- (void)scheduleRebuild {
    if (_rebuildScheduled) return;
    _rebuildScheduled = YES;
    [self performSelector:@selector(runScheduledRebuild) withObject:nil afterDelay:0.2];
}

- (void)runScheduledRebuild {
    _rebuildScheduled = NO;
    [self rebuild];
    if (self.searching) [self reloadSearchResults];
}

- (void)themeDidChange {
    [self rebuild];
    [self refreshAction];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

#pragma mark picking

- (BOOL)pickedDialog:(NoshiDialog *)dialog {
    for (NoshiDialog *one in _picked) if (one.peerKind == dialog.peerKind && one.peerId == dialog.peerId) return YES;
    return NO;
}

/* the action of the bar appears with the first tick and says how many there are */
- (void)refreshAction {
    if (self.limit <= 1) return;
    NSString *title = _picked.count ? [NSString stringWithFormat:@"%@ (%lu)", NSLocalizedString(@"bots.pick.done", nil), (unsigned long)_picked.count] : nil;
    self.navigationItem.rightBarButtonItem = title ? [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:@selector(finish)] autorelease] : nil;
}

- (void)finish {
    if (!_picked.count || _resolved) return;
    _resolved = YES;
    void (^handler)(NSArray *) = [_pickHandler retain];
    NSArray *chosen = [[_picked copy] autorelease];
    [self leave];
    if (handler) handler(chosen);
    [handler release];
}

- (void)choose:(NoshiDialog *)dialog {
    /* taps queued behind a blocked main thread arrive after the first one resolved the picker, and each would send again */
    if (_resolved) return;
    if (_tapWatcher.stale) {
        [_tapWatcher clear];
        NSLog(@"noshigram: picker dropped a tap handled late, the main thread was blocked");
        return;
    }
    if (self.limit <= 1) {
        _resolved = YES;
        void (^handler)(NSArray *) = [_pickHandler retain];
        [self leave];
        if (handler) handler([NSArray arrayWithObject:dialog]);
        [handler release];
        return;
    }
    if ([self pickedDialog:dialog]) {
        for (NoshiDialog *one in [[_picked copy] autorelease]) if (one.peerKind == dialog.peerKind && one.peerId == dialog.peerId) [_picked removeObject:one];
    } else if (_picked.count < self.limit) {
        [_picked addObject:dialog];
    }
    if (self.searching) [self reloadSearchResults];
    else [self rebuild];
    [self refreshAction];
}

#pragma mark rows

static UIImage *NoshiSavedPickerImage(void) {
    NoshiAvatarView *avatar = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)] autorelease];
    avatar.circular = YES; avatar.accent = YES; avatar.showsSymbol = YES; avatar.symbol = NoshiSymbolBookmark;
    UIGraphicsBeginImageContextWithOptions(avatar.bounds.size, NO, 0);
    [avatar.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (NSString *)subtitleOfDialog:(NoshiDialog *)dialog {
    if (!_forwarding) return nil;
    if (dialog.saved) return NSLocalizedString(@"forward.saved.hint", nil);
    if (dialog.kind == NOSHI_DIALOG_USER) return NoshiLastSeenText(dialog.presence, dialog.seen);
    if (dialog.kind == NOSHI_DIALOG_BOT) return NSLocalizedString(@"seen.bot", nil);
    if (dialog.participantsCount > 0) {
        NSString *base = dialog.kind == NOSHI_DIALOG_CHANNEL ? @"chat.subscribers" : @"chat.members";
        NSString *key = [NSString stringWithFormat:@"%@.%@", base, NoshiPluralForm(dialog.participantsCount)];
        return [NSString stringWithFormat:NSLocalizedString(key, nil), (long)dialog.participantsCount];
    }
    return nil;
}

- (NoshiSettingsRow *)rowOfDialog:(NoshiDialog *)dialog {
    NoshiWeakReference *weak = _weak;
    if (!_faces) {
        _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{
            NoshiDialogPickerController *me = weak.target;
            if (me.searching) [me reloadSearchResults];
            else [me rebuild];
        }];
    }
    UIImage *face = _forwarding && dialog.saved ? NoshiSavedPickerImage() : [_faces imageForKey:[NSString stringWithFormat:@"%d:%lld", dialog.peerKind, dialog.peerId] initials:dialog.initials seed:dialog.avatarSeed deleted:dialog.deleted photo:dialog.photo];
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTileImage:face title:dialog.title subtitle:[self subtitleOfDialog:dialog] tap:^{ [(NoshiDialogPickerController *)weak.target choose:dialog]; }];
    if ([self pickedDialog:dialog]) row.trailingImage = NoshiSymbolImage(NoshiSymbolCheck, 22, NoshiColorAccent());
    return row;
}

- (NSArray *)sectionsForDialogs:(NSArray *)dialogs footer:(NSString *)footer {
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiDialog *dialog in dialogs) [rows addObject:[self rowOfDialog:dialog]];
    return [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
}

- (void)rebuild {
    self.sections = [self sectionsForDialogs:_all footer:_status];
    [self reloadSettings];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
        [_remoteQuery release]; _remoteQuery = nil;
        [_remoteResults release]; _remoteResults = nil;
        [_remoteError release]; _remoteError = nil;
        return nil;
    }
    if (_forwarding && ![_remoteQuery isEqualToString:query]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchRemote) object:nil];
        [_remoteQuery release]; _remoteQuery = [query copy];
        [_remoteResults release]; _remoteResults = nil;
        [_remoteError release]; _remoteError = nil;
        [self performSelector:@selector(searchRemote) withObject:nil afterDelay:0.3];
    }
    NSMutableArray *matches = [NSMutableArray array];
    for (NoshiDialog *dialog in _all) {
        if ([dialog.title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:dialog];
    }
    for (NoshiDialog *candidate in _remoteResults) {
        if (![self usable:candidate]) continue;
        BOOL found = NO;
        for (NoshiDialog *row in matches) if (row.peerKind == candidate.peerKind && row.peerId == candidate.peerId) { found = YES; break; }
        if (!found) [matches addObject:candidate];
    }
    return [self sectionsForDialogs:matches footer:matches.count ? nil : (_remoteError ? NoshiGiftErrorText(_remoteError) : NSLocalizedString(@"chats.nothing", nil))];
}

- (void)searchRemote {
    NSString *query = [[_remoteQuery copy] autorelease];
    if (!query.length) return;
    NoshiWeakReference *weak = _weak;
    [_session searchPeers:query completion:^(NSArray *items, NSString *errorName) {
        NoshiDialogPickerController *me = weak.target;
        if (!me || !me.searching || ![me->_remoteQuery isEqualToString:query]) return;
        [me->_remoteResults release]; me->_remoteResults = [items copy];
        [me->_remoteError release]; me->_remoteError = [errorName copy];
        [me reloadSearchResults];
    }];
}

@end

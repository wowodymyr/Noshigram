#import "noshi_folder_tabs.h"
#import "noshi_chat_settings.h"
#import "noshi_filter_bar.h"
#import "noshi_custom_emoji.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_message.h"
#import "noshi_weak_reference.h"
#import "noshi_folder_icon.h"

@interface NoshiFolderTabs () <NoshiFilterBarDelegate, UIGestureRecognizerDelegate> {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NSSet *_emojiDocuments;
    NoshiFilterBar *_bar;
    NSArray *_folders;
    int32_t _selectedId;
    NSInteger _shownIndex;
    NSInteger _slideDirection;
    void (^_changed)(void);
    NSArray *_pagingRecognizers;
    NSArray *_countedDialogs;
}
@end

@implementation NoshiFolderTabs
@synthesize slideDirection = _slideDirection;
- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media changed:(void (^)(void))changed {
    self = [super initWithFrame:CGRectZero];
    if (!self)
        return nil;
    _session = [session retain];
    _media = [media retain];
    _changed = [changed copy];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:NoshiChatFoldersDidChangeNotification object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiLoaded:) name:NoshiCustomEmojiDidLoadNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabStyleChanged) name:NoshiFolderTabStyleDidChangeNotification object:nil];
    [self rebuild];
    return self;
}
- (void)dealloc {
    for (UIGestureRecognizer *gesture in _pagingRecognizers) {
        gesture.delegate = nil;
        [gesture.view removeGestureRecognizer:gesture];
    }
    [_pagingRecognizers release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_session release];
    [_media release];
    [_emojiDocuments release];
    [_folders release];
    [_countedDialogs release];
    [_bar release];
    [_changed release];
    [super dealloc];
}
- (CGFloat)height {
    return _folders.count > 1 ? 48 : 0;
}
- (NoshiChatFolder *)selectedFolder {
    for (NoshiChatFolder *folder in _folders)
        if (folder.folderId == _selectedId)
            return folder;
    return nil;
}
- (void)refresh {
    [_session loadChatFoldersWithCompletion:^(NSArray *folders, NSString *errorName) {
        (void)folders;
        if (errorName)
            NSLog(@"noshigram: chat folders did not refresh: %@", errorName);
    }];
}
- (void)rebuild {
    NSMutableArray *folders = [NSMutableArray arrayWithArray:_session.chatFolders];
    BOOL hasDefault = NO;
    for (NoshiChatFolder *folder in folders)
        if (!folder.folderId)
            hasDefault = YES;
    if (!hasDefault) {
        NoshiChatFolder *all = [[[NoshiChatFolder alloc] init] autorelease];
        all.title = NSLocalizedString(@"folders.all", nil);
        [folders insertObject:all atIndex:0];
    }
    /* the person may hide the tab of all chats, as long as two folders are left to switch between */
    if (NoshiChatFlagGet(NoshiChatFlagHideAllChatsTab) && folders.count > 2) {
        for (NSInteger i = (NSInteger)folders.count - 1; i >= 0; --i)
            if (![(NoshiChatFolder *)[folders objectAtIndex:(NSUInteger)i] folderId])
                [folders removeObjectAtIndex:(NSUInteger)i];
    }
    [_folders release];
    _folders = [folders copy];
    NSMutableArray *titles = [NSMutableArray array];
    NSInteger selected = 0;
    for (NSUInteger i = 0; i < _folders.count; ++i) {
        NoshiChatFolder *folder = [_folders objectAtIndex:i];
        [titles addObject:folder.title];
        if (folder.folderId == _selectedId)
            selected = (NSInteger)i;
    }
    _selectedId = ((NoshiChatFolder *)[_folders objectAtIndex:(NSUInteger)selected]).folderId;
    [_bar removeFromSuperview];
    [_bar release];
    _bar = [[NoshiFilterBar alloc] initWithTitles:titles];
    NSMutableSet *documents = [NSMutableSet set];
    for (NSUInteger i = 0; i < _folders.count; ++i) {
        NoshiChatFolder *folder = [_folders objectAtIndex:i];
        [_bar setEntities:folder.titleEntities forIndex:(NSInteger)i];
        /* the tab of all chats has no emoticon of its own: the server draws it as the speech bubble */
        [_bar setIconName:NoshiFolderIconName(folder.folderId ? folder.emoticon : @"\U0001F4AC", folder.flags) forIndex:(NSInteger)i];
        for (NoshiTextEntity *entity in folder.titleEntities)
            [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
    }
    [_emojiDocuments release];
    _emojiDocuments = [documents copy];
    if (_media && documents.count)
        [NoshiCustomEmojiLoader loadDocuments:[documents allObjects] session:_session media:_media documents:nil picture:nil];
    _bar.delegate = self;
    _bar.selectedIndex = selected;
    _shownIndex = selected;
    /* folders that arrive or go replace the list where it is, with no slide */
    _slideDirection = 0;
    [self addSubview:_bar];
    [self applyCounts];
    self.hidden = self.height == 0;
    [self setNeedsLayout];
    if (_changed)
        _changed();
}
- (void)updateCountsFromDialogs:(NSArray *)dialogs {
    if (dialogs != _countedDialogs) {
        [_countedDialogs release];
        _countedDialogs = [dialogs retain];
    }
    [self applyCounts];
}
- (void)applyCounts {
    for (NSUInteger i = 0; i < _folders.count; ++i) {
        NoshiChatFolder *folder = [_folders objectAtIndex:i];
        NSInteger count = 0;
        for (NoshiDialog *dialog in _countedDialogs) {
            if (dialog.folder || dialog.community || !dialog.unread || dialog.muted || (dialog.peerKind == 3 && dialog.left)) continue;
            if ([folder containsDialog:dialog]) ++count;
        }
        [_bar setCount:count forIndex:(NSInteger)i];
    }
}
- (void)tabStyleChanged {
    [_bar setTabStyle:NoshiFolderTabStyleStored() animated:YES];
    /* the bar is wider or narrower now, and the list under it does not move */
}
- (void)emojiLoaded:(NSNotification *)notification {
    if ([_emojiDocuments containsObject:notification.object]) [_bar redrawTitles];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _bar.frame = self.bounds;
}
- (void)filterBar:(NoshiFilterBar *)bar didSelectIndex:(NSInteger)index {
    (void)bar;
    if (index < 0 || (NSUInteger)index >= _folders.count)
        return;
    _selectedId = ((NoshiChatFolder *)[_folders objectAtIndex:(NSUInteger)index]).folderId;
    _slideDirection = index > _shownIndex ? 1 : (index < _shownIndex ? -1 : 0);
    _shownIndex = index;
    if (_changed)
        _changed();
}

- (NSArray *)pagingRecognizers { return _pagingRecognizers; }

- (void)installPagingInView:(UIView *)view {
    if (!_pagingRecognizers) {
        NSMutableArray *gestures = [NSMutableArray array];
        for (NSNumber *direction in [NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:UISwipeGestureRecognizerDirectionLeft],
                                                             [NSNumber numberWithUnsignedInteger:UISwipeGestureRecognizerDirectionRight], nil]) {
            UISwipeGestureRecognizer *gesture = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pageSwiped:)] autorelease];
            gesture.direction = direction.unsignedIntegerValue;
            gesture.delegate = self;
            [gestures addObject:gesture];
        }
        _pagingRecognizers = [gestures copy];
    }
    for (UIGestureRecognizer *gesture in _pagingRecognizers) [view addGestureRecognizer:gesture];
}

- (NSInteger)pageAfterSwipe:(UISwipeGestureRecognizer *)gesture {
    return _bar.selectedIndex + (gesture.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    UIView *hit = [gesture.view hitTest:[gesture locationInView:gesture.view] withEvent:nil];
    for (UIView *view = hit; view && view != gesture.view; view = view.superview) {
        if ([view isKindOfClass:[UITableViewCell class]] &&
            ((UISwipeGestureRecognizer *)gesture).direction == UISwipeGestureRecognizerDirectionLeft &&
            NoshiChatSwipeStored() != NoshiChatSwipeFolders) return NO;
    }
    NSInteger index = [self pageAfterSwipe:(UISwipeGestureRecognizer *)gesture];
    return _folders.count > 1 && index >= 0 && (NSUInteger)index < _folders.count;
}

- (void)pageSwiped:(UISwipeGestureRecognizer *)gesture {
    NSInteger index = [self pageAfterSwipe:gesture];
    if (index < 0 || (NSUInteger)index >= _folders.count) return;
    _bar.selectedIndex = index;
    [self filterBar:_bar didSelectIndex:index];
}
@end

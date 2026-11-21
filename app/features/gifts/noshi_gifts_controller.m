#import "noshi_gifts_controller.h"

#import "noshi_custom_gift.h"
#import "noshi_gift_catalog_controller.h"
#import "noshi_gift_detail_controller.h"
#import "noshi_gift_folder_bar.h"
#import "noshi_gift_grid_view.h"
#import "noshi_gift_tiles.h"
#import "noshi_person.h"
#import "noshi_star_gift.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiGiftsController () <NoshiGiftGridDelegate, NoshiGiftFolderBarDelegate> {
    NoshiGiftFolderBar *_folderBar;
    int32_t _folderId;
    NoshiDialog *_dialog;
    BOOL _mine;
    NoshiGiftGridView *_grid;
    UIActivityIndicatorView *_spinner;
    UILabel *_status;
    UIButton *_retry;
    UIImageView *_balance;
    NSMutableArray *_gifts;
    NSString *_nextOffset;
    BOOL _loading;
    BOOL _loaded;
    NSUInteger _generation;
    NSString *_ownerName;
    NoshiStickerLibrary *_stickers;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiGiftsController

@synthesize stickers = _stickers;

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog mine:(BOOL)mine avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _mine = mine;
    _gifts = [[NSMutableArray alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(@"gifts.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    _folderBar.delegate = nil;
    [_folderBar release];
    [_dialog release];
    [_grid release];
    [_spinner release];
    [_status release];
    [_retry release];
    [_balance release];
    [_gifts release];
    [_nextOffset release];
    [_ownerName release];
    [_stickers release];
    [super dealloc];
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[NoshiGiftGridView alloc] initWithMedia:self.media];
    _grid.avatars = self.avatars;
    _grid.delegate = self;
    [root addSubview:_grid];
    _folderBar = [[NoshiGiftFolderBar alloc] initWithSession:self.session dialog:_dialog mine:_mine];
    _folderBar.delegate = self;
    [root addSubview:_folderBar];
    /* the saved messages dialog is titled by its own name, so the owner of a gift on it comes from the account */
    if (_dialog.saved) {
        [self retain];
        [self.session loadSelf:^(NSArray *people, NSString *errorName) {
            [self autorelease];
            if (people.count) _ownerName = [[(NoshiPerson *)[people objectAtIndex:0] name] copy];
            else NSLog(@"noshigram: own name for the gift owner not loaded: %@", errorName);
        }];
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:NoshiThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = NoshiColorSecondary();
    _status.textAlignment = NoshiTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reloadFromStart) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];
    if (_mine) {
        _balance = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 320, 30)];
        _balance.contentMode = UIViewContentModeCenter;
        _balance.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }
    /* a gift can go to a person, not to a bot, a group or the chat with oneself */
    if (!_mine && _dialog.kind == NOSHI_DIALOG_USER && !_dialog.saved) {
        /* the screen owns this block, so it must not hold the screen */
        NoshiWeakReference *me = [NoshiWeakReference referenceTo:self];
        [self setActionTitle:NSLocalizedString(@"gifts.send", nil) handler:^{ [(NoshiGiftsController *)me.target openCatalog]; }];
    }
}

- (void)layoutBody:(CGRect)body {
    CGFloat folders = [_folderBar height];
    _folderBar.frame = CGRectMake(body.origin.x, body.origin.y, body.size.width, folders);
    body.origin.y += folders;
    body.size.height -= folders;
    _grid.frame = body;
    _spinner.center = CGPointMake(CGRectGetMidX(body), CGRectGetMidY(body));
    _status.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 60);
    _retry.frame = CGRectMake(CGRectGetMidX(body) - 70, CGRectGetMidY(body) + 24, 140, 40);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_folderBar reload];
    [self reloadFromStart];
    if (_mine) [self loadBalance];
}

- (void)loadBalance {
    [self retain];
    [self.session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"noshigram: star balance not loaded: %@", errorName);
            return;
        }
        _balance.image = NoshiStarsImage(NSLocalizedString(@"gifts.balance", nil), stars, NoshiFontRegular(14), NoshiColorSecondary());
        _grid.headerView = _balance;
    }];
}

- (void)openCatalog {
    NoshiGiftCatalogController *catalog = [[[NoshiGiftCatalogController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
                                                                                              media:self.media] autorelease];
    catalog.sentHandler = ^{ [self reloadFromStart]; };
    [self.navigationController pushViewController:catalog animated:YES];
}

#pragma mark loading

- (void)reloadFromStart {
    ++_generation;
    _loading = NO;
    [_nextOffset release];
    _nextOffset = nil;
    [self loadPage];
}

- (void)loadPage {
    if (_loading) return;
    _loading = YES;
    BOOL first = _nextOffset == nil;
    NSString *offset = _nextOffset;
    NSUInteger generation = _generation;
    _retry.hidden = YES;
    if (first && !_loaded) [_spinner startAnimating];
    [self retain];
    if (first && !_folderId && NoshiCustomGiftNeedsSender(_dialog)) {
        /* the gift of the app names @sqmrak with his picture, so the first page waits for him, once per run */
        NoshiCustomGiftLoadSender(self.session, ^{
            [self autorelease];
            if (generation != _generation) return;
            _loading = NO;
            [self loadPage];
        });
        return;
    }
    [self.session loadSavedGiftsOfDialog:_dialog folder:_folderId offset:offset completion:^(NSArray *gifts, NSInteger total, NSString *next, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) return;
        _loading = NO;
        [_spinner stopAnimating];
        if (!gifts) {
            if (_loaded) {
                NSLog(@"noshigram: more gifts not loaded: %@", errorName);
                return;
            }
            _status.text = NoshiGiftErrorText(errorName);
            _retry.hidden = NO;
            return;
        }
        if (first) {
            [_gifts removeAllObjects];
            /* the gifts of the app stand before every gift of the profile, and not in a folder of them */
            if (!_folderId) [_gifts addObjectsFromArray:NoshiCustomGiftsForDialog(_dialog)];
        }
        [_gifts addObjectsFromArray:gifts];
        [_nextOffset release];
        _nextOffset = [next copy];
        _loaded = YES;
        _status.text = _gifts.count ? @"" : NSLocalizedString(_mine ? @"gifts.mine.empty" : @"gifts.empty", nil);
        [self showTiles];
    }];
}

- (void)showTiles {
    NSMutableArray *tiles = [NSMutableArray arrayWithCapacity:_gifts.count];
    for (NoshiSavedGift *saved in _gifts) [tiles addObject:NoshiTileForSavedGift(saved, _mine)];
    [_grid setTiles:tiles];
}

- (void)giftFolderBar:(NoshiGiftFolderBar *)bar didSelectFolder:(NoshiGiftFolder *)folder {
    _folderId = folder.folderId;
    [self reloadFromStart];
}

- (void)giftFolderBarDidChange:(NoshiGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) {
        _folderId = bar.selectedFolder.folderId;
        [self reloadFromStart];
    }
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(NoshiGiftGridView *)grid {
    (void)grid;
    if (_nextOffset && !_loading) [self loadPage];
}

- (void)giftGrid:(NoshiGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _gifts.count) return;
    NoshiGiftDetailController *detail = [[[NoshiGiftDetailController alloc] initWithSession:self.session gift:[_gifts objectAtIndex:index] mine:_mine
                                                                                        avatars:self.avatars media:self.media] autorelease];
    detail.ownerName = _dialog.saved ? _ownerName : _dialog.title;
    detail.stickers = _stickers;
    if (_mine) detail.folderDialog = _dialog;
    detail.pinnedGifts = [_gifts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pinned == YES"]];
    NoshiWeakReference *weak = _weak;
    detail.changedHandler = ^{
        NoshiGiftsController *controller = weak.target;
        if (!controller) return;
        [controller reloadFromStart];
        [controller->_folderBar reload];
        if (controller->_mine) [controller loadBalance];
    };
    [detail showInViewController:self];
}

@end

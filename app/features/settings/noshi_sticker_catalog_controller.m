#import "noshi_sticker_catalog_controller.h"

#import "noshi_gift_screen.h"
#import "noshi_session_stickermanage.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define ARCHIVE_PAGE 100

@interface NoshiStickerCatalogController () {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NoshiStickerCatalogKind _kind;
    NSArray *_sets;
    BOOL _loaded;
    BOOL _busy;
    /* the cover of each set by id: the picture once the cache has it, and the ones already asked for */
    NSMutableDictionary *_covers;
    NSMutableSet *_asked;
}
@end

@implementation NoshiStickerCatalogController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media kind:(NoshiStickerCatalogKind)kind {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _kind = kind;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _covers = [[NSMutableDictionary alloc] init];
    _asked = [[NSMutableSet alloc] init];
    NSString *keys[] = {@"stickers.featured", @"stickers.archived", @"stickers.emoji"};
    self.pageTitle = NSLocalizedString(keys[kind], nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_sets release];
    [_covers release];
    [_asked release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self load];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiStickerCatalogController alloc] initWithSession:_session media:_media kind:_kind] autorelease];
}

- (void)load {
    NoshiWeakReference *weak = _weak;
    void (^got)(NSArray *, NSString *) = ^(NSArray *sets, NSString *errorName) {
        NoshiStickerCatalogController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"noshigram: the sticker sets did not load: %@", errorName);
        [me->_sets release];
        me->_sets = [sets retain];
        me->_loaded = YES;
        [me rebuild];
    };
    switch (_kind) {
    case NoshiStickerCatalogFeatured:
        [_session loadFeaturedStickerSets:got];
        break;
    case NoshiStickerCatalogArchived:
        [_session loadArchivedStickerSetsLimit:ARCHIVE_PAGE completion:^(NSArray *sets, int32_t total, NSString *errorName) {
            (void)total;
            got(sets, errorName);
        }];
        break;
    case NoshiStickerCatalogEmoji:
        [_session loadEmojiSets:got];
        break;
    }
}

/* the cover comes from the cache and takes the place of the symbol, and the page is built again */
- (UIImage *)coverOfSet:(NoshiStickerSet *)set {
    NSNumber *key = [NSNumber numberWithLongLong:set.setId];
    UIImage *image = [_covers objectForKey:key];
    if (image || !_media || [_asked containsObject:key]) return image;
    NoshiRemoteFile *file = set.coverFile;
    if (!file) return nil;
    [_asked addObject:key];
    NoshiWeakReference *weak = _weak;
    [_media loadImageForFile:file maxSide:96 completion:^(UIImage *loaded) {
        NoshiStickerCatalogController *me = weak.target;
        if (!me || !loaded) return;
        [me->_covers setObject:loaded forKey:key];
        [me rebuild];
    }];
    return nil;
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
        return;
    }
    /* the server has the new lists, and the page shows what it says */
    [self load];
}

- (void)install:(NoshiStickerSet *)set {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [_session installStickerSet:set completion:^(NSString *errorName) { [(NoshiStickerCatalogController *)weak.target finishWithError:errorName]; }];
}

- (void)uninstall:(NoshiStickerSet *)set {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [_session uninstallStickerSet:set completion:^(NSString *errorName) { [(NoshiStickerCatalogController *)weak.target finishWithError:errorName]; }];
}

- (void)tapSet:(NoshiStickerSet *)set {
    NoshiWeakReference *weak = _weak;
    switch (_kind) {
    case NoshiStickerCatalogFeatured:
        if (!set.row.installed) [self install:set];
        else NoshiConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil),
                                  ^{ [(NoshiStickerCatalogController *)weak.target uninstall:set]; });
        break;
    case NoshiStickerCatalogArchived:
        [NoshiSheet presentInView:self.view title:set.title message:nil options:[NSArray arrayWithObject:NSLocalizedString(@"stickers.restore", nil)] destructive:nil
                        cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
            (void)index;
            [(NoshiStickerCatalogController *)weak.target install:set];
        }];
        break;
    case NoshiStickerCatalogEmoji:
        NoshiConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil),
                             ^{ [(NoshiStickerCatalogController *)weak.target uninstall:set]; });
        break;
    }
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiStickerSet *set in _sets) {
        NSString *count = [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.count", nil), (long)set.row.count];
        void (^tap)(void) = ^{ [(NoshiStickerCatalogController *)weak.target tapSet:set]; };
        UIImage *cover = [self coverOfSet:set];
        NoshiSettingsRow *row = cover ? [NoshiSettingsRow rowWithTileImage:cover title:set.title subtitle:count tap:tap]
                                        : [NoshiSettingsRow rowWithSymbol:_kind == NoshiStickerCatalogEmoji ? NoshiSymbolSmiley : NoshiSymbolSticker tone:NoshiSettingsToneOrangeDeep
                                                                      title:set.title subtitle:count value:nil tap:tap];
        /* a trending set the account has is ticked; the others add on a tap */
        if (_kind == NoshiStickerCatalogFeatured && set.row.installed) row.trailingImage = NoshiSymbolImage(NoshiSymbolCheckMark(), 22, NoshiColorAccent());
        [rows addObject:row];
    }
    NSString *empty[] = {@"stickers.empty.featured", @"stickers.empty.archived", @"stickers.empty.emoji"};
    NSString *footer = !_loaded ? NSLocalizedString(@"chatset.stickers.loading", nil)
                     : (_sets ? (_sets.count ? NSLocalizedString(@"stickers.info.catalog", nil) : NSLocalizedString(empty[_kind], nil))
                              : NSLocalizedString(@"chatset.stickers.failed", nil));
    self.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}

@end

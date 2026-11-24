#import "noshi_stickers_settings_controller.h"

#import "noshi_chat_settings.h"
#import "noshi_custom_emoji.h"
#import "noshi_gift_screen.h"
#import "noshi_session_stickermanage.h"
#import "noshi_sheet.h"
#import "noshi_quick_reaction_controller.h"
#import "noshi_sticker_catalog_controller.h"
#import "noshi_sticker_maker.h"
#import "noshi_symbol.h"
#import "noshi_weak_reference.h"
#import "noshi_settings_extras.h"
#include "noshi_reactions.h"

@interface NoshiStickersSettingsController () {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NSArray *_sets;
    NSArray *_archived;
    NSArray *_emoji;
    NSArray *_featured;
    int32_t _archivedTotal;
    BOOL _loaded;
    BOOL _busy;
}
@end

@implementation NoshiStickersSettingsController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.stickers", nil);
    return self;
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiStickersSettingsController alloc] initWithSession:_session media:_media] autorelease];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiCustomEmojiDidLoadNotification object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_sets release];
    [_archived release];
    [_emoji release];
    [_featured release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(quickReactionPictureLoaded:) name:NoshiCustomEmojiDidLoadNotification object:nil];
    [self rebuild];
    [self load];
}

- (void)quickReactionPictureLoaded:(NSNotification *)notification {
    if ([notification.object longLongValue] == noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String)) [self rebuild];
}

/* a page opened from here may have changed what is counted, so coming back asks again */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NoshiLoadQuickReactionPicture(_session, _media, nil);
    if (_loaded) { [self rebuild]; [self load]; }
}

- (void)load {
    NoshiWeakReference *weak = _weak;
    [_session loadStickerSets:^(NSArray *sets, NSString *errorName) {
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"noshigram: the sticker sets did not load: %@", errorName);
        [me->_sets release];
        me->_sets = [sets retain];
        me->_loaded = YES;
        [me rebuild];
    }];
    /* the counts of the rows above the list: how many the archive and the emoji sets hold, and whether the trending ones show */
    [_session loadArchivedStickerSetsLimit:1 completion:^(NSArray *sets, int32_t total, NSString *errorName) {
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"noshigram: the archive did not load: %@", errorName);
        [me->_archived release];
        me->_archived = [sets retain];
        me->_archivedTotal = total;
        [me rebuild];
    }];
    [_session loadEmojiSets:^(NSArray *sets, NSString *errorName) {
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"noshigram: the emoji sets did not load: %@", errorName);
        [me->_emoji release];
        me->_emoji = [sets retain];
        [me rebuild];
    }];
    [_session loadFeaturedStickerSets:^(NSArray *sets, NSString *errorName) {
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        if (!sets) NSLog(@"noshigram: the trending sets did not load: %@", errorName);
        [me->_featured release];
        me->_featured = [sets retain];
        [me rebuild];
    }];
}

- (void)openCatalog:(NoshiStickerCatalogKind)kind {
    [self.navigationController pushViewController:[[[NoshiStickerCatalogController alloc] initWithSession:_session media:_media kind:kind] autorelease] animated:YES];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    NoshiSettingsRow *featured = [NoshiSettingsRow rowWithSymbol:NoshiSymbolStars tone:NoshiSettingsToneOrange title:NSLocalizedString(@"stickers.featured", nil) subtitle:nil
                                                               value:_featured.count ? [NSString stringWithFormat:@"%lu", (unsigned long)_featured.count] : nil
                                                                 tap:^{ [(NoshiStickersSettingsController *)weak.target openCatalog:NoshiStickerCatalogFeatured]; }];
    NoshiSettingsRow *archived = [NoshiSettingsRow rowWithSymbol:NoshiSymbolArchive tone:NoshiSettingsToneBlue title:NSLocalizedString(@"stickers.archived", nil) subtitle:nil
                                                               value:[NSString stringWithFormat:@"%d", (int)_archivedTotal]
                                                                 tap:^{ [(NoshiStickersSettingsController *)weak.target openCatalog:NoshiStickerCatalogArchived]; }];
    NoshiSettingsRow *emoji = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSmiley tone:NoshiSettingsToneBlueDeep title:NSLocalizedString(@"stickers.emoji", nil) subtitle:nil
                                                            value:_emoji.count ? [NSString stringWithFormat:@"%lu", (unsigned long)_emoji.count] : nil
                                                              tap:^{ [(NoshiStickersSettingsController *)weak.target openCatalog:NoshiStickerCatalogEmoji]; }];
    NSMutableArray *catalog = [NSMutableArray arrayWithObject:featured];
    /* an archive with nothing in it is not offered */
    if (_archivedTotal > 0) [catalog addObject:archived];
    [catalog addObject:emoji];
    BOOL quickEnabled = NoshiChatQuickReactionEnabled();
    NoshiSettingsRow *quick = [NoshiSettingsRow rowWithSymbol:NoshiSymbolHeart tone:NoshiSettingsTonePurple title:NSLocalizedString(@"chatset.quickreaction", nil) subtitle:nil value:quickEnabled ? NoshiChatQuickReactionDisplay() : NSLocalizedString(@"chatset.quickreaction.off", nil) tap:^{
        NoshiStickersSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[NoshiQuickReactionController alloc] initWithSession:me->_session] autorelease] animated:YES];
    }];
    quick.valueIsEmoji = quickEnabled;
    quick.valueEmojiDocument = quickEnabled ? noshi_quick_reaction_document(NoshiChatQuickReaction().UTF8String) : 0;
    [catalog addObject:quick];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:catalog]];
    NoshiSettingsRow *large = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.largeemoji", nil) subtitle:NSLocalizedString(@"chatset.largeemoji.info", nil)
                                                                    on:NoshiChatLargeEmoji() toggle:^(BOOL on) { NoshiChatSetLargeEmoji(on); }];
    NoshiSettingsRow *order = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.dynamicorder", nil) subtitle:nil
                                                                    on:NoshiChatDynamicPackOrder() toggle:^(BOOL on) { NoshiChatSetDynamicPackOrder(on); }];
    NSMutableArray *settings = [NSMutableArray arrayWithArray:NoshiStickerLookRows(weak)];
    [settings addObject:large];
    [settings addObject:order];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.stickers.settings", nil) footer:NSLocalizedString(@"chatset.dynamicorder.info", nil)
                                                             rows:settings]];

    NoshiSettingsRow *make = [NoshiSettingsRow rowWithSymbol:NoshiSymbolPlusCircle tone:NoshiSettingsToneGreen title:NSLocalizedString(@"sticker.make.row", nil)
                                                        subtitle:NSLocalizedString(@"sticker.make.row.info", nil) value:nil tap:^{
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        [NoshiStickerMaker startWithSession:me->_session host:me done:^(NSString *shortName) {
            (void)shortName;
            [(NoshiStickersSettingsController *)weak.target load];
        }];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:make]]];

    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiStickerSet *set in _sets) {
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolSticker tone:NoshiSettingsToneOrangeDeep title:set.title
                                                 subtitle:[NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.count", nil), (long)set.row.count] value:nil tap:^{
            [(NoshiStickersSettingsController *)weak.target showActionsOfSet:set];
        }]];
    }
    NSString *footer = !_loaded ? NSLocalizedString(@"chatset.stickers.loading", nil)
                     : (_sets ? (_sets.count ? NSLocalizedString(@"chatset.stickers.info", nil) : NSLocalizedString(@"chatset.stickers.none", nil))
                              : NSLocalizedString(@"chatset.stickers.failed", nil));
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.stickers.header", nil) footer:footer rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)showActionsOfSet:(NoshiStickerSet *)set {
    if (_busy) return;
    NoshiWeakReference *weak = _weak;
    NSMutableArray *options = [NSMutableArray array];
    BOOL first = _sets.count && [_sets objectAtIndex:0] == set;
    if (!first) [options addObject:NSLocalizedString(@"chatset.stickers.first", nil)];
    [options addObject:NSLocalizedString(@"chatset.stickers.remove", nil)];
    NoshiSettingsChoose(self, set.title, options, ^(NSUInteger index) {
        NoshiStickersSettingsController *me = weak.target;
        if (!me) return;
        BOOL removes = index == options.count - 1;
        if (removes) {
            NoshiConfirmAction(me, [NSString stringWithFormat:NSLocalizedString(@"chatset.stickers.remove.confirm", nil), set.title], NSLocalizedString(@"chatset.stickers.remove", nil), ^{
                [(NoshiStickersSettingsController *)weak.target removeSet:set];
            });
        } else {
            [me moveSetToTop:set];
        }
    });
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
        return;
    }
    /* the server has the new list, and the screen shows what it says */
    [self load];
}

- (void)moveSetToTop:(NoshiStickerSet *)set {
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [_session moveStickerSetToTop:set among:_sets completion:^(NSString *errorName) { [(NoshiStickersSettingsController *)weak.target finishWithError:errorName]; }];
}

- (void)removeSet:(NoshiStickerSet *)set {
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [_session uninstallStickerSet:set completion:^(NSString *errorName) { [(NoshiStickersSettingsController *)weak.target finishWithError:errorName]; }];
}

@end

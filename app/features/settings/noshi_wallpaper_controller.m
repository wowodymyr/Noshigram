#import "noshi_wallpaper_controller.h"

#import "noshi_animation.h"
#import "noshi_avatar_cache.h"
#import "noshi_chat_preview_view.h"
#import "noshi_chat_settings.h"
#import "noshi_customization_views.h"
#import "noshi_person.h"
#import "noshi_pill_tabs_view.h"
#import "noshi_shape.h"
#import "noshi_gift_screen.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_session.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_tint_picker.h"
#import "noshi_wallpaper.h"
#import "noshi_wallpaper_grid_view.h"
#import "noshi_weak_reference.h"


@interface NoshiWallpaperController () {
    NoshiWeakReference *_weak;
    NoshiChatPreviewView *_preview;
    NoshiWallpaperGridView *_grid;
    UIControl<NoshiTintControl> *_picker;
    /* the modern page has two tabs, the wallpapers and the customization of the look of the app; the second is not offered for the wallpaper of one chat */
    NSUInteger _tab;
    NoshiPillTabsView *_tabs;
    NoshiClassicPreviewView *_classicPreview;
    /* the classic style makes every page again after a change of the color, and the new table starts at the top; the offset of the old one is brought back */
    CGFloat _restoreOffset;
    BOOL _restoresOffset;
    /* the chat the page edits the wallpaper of, zero for every chat */
    int32_t _peerKind;
    long long _peerId;
    NoshiSession *_session;
}
@end

@implementation NoshiWallpaperController
@synthesize session = _session;


- (id)init {
    return [self initWithPeerKind:0 peerId:0];
}

- (id)initWithPeerKind:(int32_t)peerKind peerId:(long long)peerId {
    self = [super init];
    if (!self) return nil;
    _peerKind = peerId ? peerKind : 0;
    _peerId = peerId;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(_peerId ? @"chatset.wallpaper.chat" : @"chatset.wallpaper", nil);
    return self;
}

/* what the page reads and writes: the wallpaper of its chat, or the one of every chat */
- (NoshiWallpaperSetting)stored {
    if (!_peerId) return NoshiWallpaperStored();
    NoshiWallpaperSetting setting = NoshiWallpaperStoredForChat(_peerKind, _peerId);
    /* a chat without a wallpaper of its own starts from the colors of every chat, but not from their photo, which is a file this chat does not have */
    if (setting.kind == NoshiWallpaperPhoto && !NoshiWallpaperChatHasOwn(_peerKind, _peerId)) setting.kind = NoshiWallpaperStandard;
    return setting;
}

/* a setting taken from the stored one or a preset belongs to this page's chat */
- (void)store:(NoshiWallpaperSetting)setting {
    setting.chatKind = _peerKind;
    setting.chatId = _peerId;
    NoshiWallpaperStore(setting);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_preview release];
    [_grid release];
    [_picker release];
    [_tabs release];
    [_classicPreview release];
    [_session release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [super dealloc];
}

/* the settings table does not move for the keyboard of the hex field, which stands low on this page: the table gets room under it and brings the field up */
- (void)keyboardWillChange:(NSNotification *)note {
    NSValue *end = [note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (![end isKindOfClass:[NSValue class]]) return;
    CGRect keyboard = [self.view convertRect:[end CGRectValue] fromView:nil];
    CGFloat covered = MAX(0, CGRectGetMaxY(self.table.frame) - keyboard.origin.y);
    UIEdgeInsets insets = self.table.contentInset;
    insets.bottom = covered;
    self.table.contentInset = insets;
    self.table.scrollIndicatorInsets = insets;
    if (covered > 0 && _picker.window) {
        [self.table scrollRectToVisible:[self.table convertRect:_picker.editingRect fromView:_picker] animated:YES];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    NoshiWallpaperController *again = [[[NoshiWallpaperController alloc] initWithPeerKind:_peerKind peerId:_peerId] autorelease];
    if ([self isViewLoaded]) {
        again->_restoreOffset = self.table.contentOffset.y;
        again->_restoresOffset = YES;
    }
    again->_tab = _tab;
    again.session = _session;
    return again;
}

/* the offset is set once the new table has its size and its rows, clamped to what the page can scroll now */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_restoresOffset) return;
    UITableView *table = self.table;
    if (table.bounds.size.height <= 0 || table.contentSize.height <= 0) return;
    _restoresOffset = NO;
    CGFloat low = -table.contentInset.top;
    CGFloat high = MAX(low, table.contentSize.height - table.bounds.size.height + table.contentInset.bottom);
    table.contentOffset = CGPointMake(0, MIN(high, MAX(low, _restoreOffset)));
}

/* the preview and the tiles read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[NoshiChatPreviewView alloc] init];
    _preview.wallpaperPeerKind = _peerKind;
    _preview.wallpaperPeerId = _peerId;
    NoshiWeakReference *previewWeak = _weak;
    _preview.heightHandler = ^{ [(NoshiWallpaperController *)previewWeak.target updateRowHeights]; };
    [_picker release];
    /* the classic look keeps the square with metal discs; the modern one has the expressive editor */
    _picker = (UIControl<NoshiTintControl> *)[[NoshiTintPicker alloc] init];
    [_picker addTarget:self action:@selector(tintCommitted:) forControlEvents:UIControlEventTouchUpInside];
    [_grid release];
    _grid = [[NoshiWallpaperGridView alloc] init];
    NoshiWeakReference *weak = _weak;
    _grid.galleryHandler = ^{ [(NoshiWallpaperController *)weak.target pickPhoto]; };
    _grid.standardHandler = ^{
        NoshiWallpaperController *me = weak.target;
        if (!me) return;
        /* the standard tile of a chat is the way back to the wallpaper every chat wears */
        if (me->_peerId) {
            NoshiWallpaperClearChat(me->_peerKind, me->_peerId);
        } else {
            NoshiWallpaperSetting standard = NoshiWallpaperStored();
            standard.kind = NoshiWallpaperStandard;
            NoshiWallpaperStore(standard);
        }
        [me rebuild];
    };
    _grid.chooseHandler = ^(NSUInteger index) {
        NoshiWallpaperController *me = weak.target;
        if (!me) return;
        [me store:NoshiWallpaperPreset(index)];
        [me rebuild];
    };    [self buildCustomizationViews];
}

/* the rows under the tabs come in from the side the new tab lies on: with a wobble, a spring that overshoots and settles back, in the modern style, and with a plain ease in the
   skeuomorphic one. the tabs themselves stay where they are */
- (void)animateTabChangeFrom:(NSUInteger)previous {
    if (previous == _tab || !self.isViewLoaded) return;
    [self.table layoutIfNeeded];
    CGFloat direction = _tab > previous ? 1 : -1;
    BOOL modern = NO;
    for (UITableViewCell *cell in self.table.visibleCells) {
        if ([_tabs isDescendantOfView:cell]) continue;
        if (modern) NoshiAnimateEnter(cell, CGAffineTransformConcat(CGAffineTransformMakeScale(0.94f, 0.94f), CGAffineTransformMakeTranslation(direction * 56, 0)), 0, NOSHI_MOTION_WOBBLE);
        else NoshiAnimateEnter(cell, CGAffineTransformMakeTranslation(direction * 24, 0), 0, NOSHI_MOTION_ENTER);
    }
}

/* the tabs and the views of the customization, made again with the colors of a new theme */
- (void)buildCustomizationViews {
    [_tabs release];
    _tabs = [[NoshiPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"custom.tab.wallpapers", nil), NSLocalizedString(@"custom.tab.look", nil), nil]];
    _tabs.selectedIndex = _tab;
    NoshiWeakReference *weak = _weak;
    _tabs.changeHandler = ^(NSUInteger index) {
        NoshiWallpaperController *me = weak.target;
        if (!me) return;
        NSUInteger previous = me->_tab;
        me->_tab = index;
        [me rebuild];
        [me animateTabChangeFrom:previous];
    };
    [_classicPreview release];
    _classicPreview = [[NoshiClassicPreviewView alloc] init];
}

/* every screen reads its settings when it is built, so the main controller builds them again on this notification; this page stays and is made again */
- (void)applyLook {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyLookNow) object:nil];
    [self performSelector:@selector(applyLookNow) withObject:nil afterDelay:0.5];
    [_classicPreview refresh];
}

/* a tap on a choice starts the duck at once, from the point that was touched; a slider waits until it rests */
- (void)applyLookNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyLookNow) object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:NoshiThemeOriginKey]];
}

- (NoshiSettingsSection *)tabsSection {
    NoshiPillTabsView *tabs = _tabs;
    return [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:[NoshiSettingsRow viewRowWithView:tabs height:^CGFloat(CGFloat width) { (void)width; return 40; }]]];
}

/* a group of rows of which one is chosen: a tap stores it, starts the duck and makes the page again */
- (NSArray *)choiceRowsWithKeys:(NSArray *)keys current:(NSInteger)current store:(void (^)(NSInteger))store {
    NoshiWeakReference *weak = _weak;
    void (^keep)(NSInteger) = [[store copy] autorelease];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil) subtitle:nil checked:(NSUInteger)current == i tap:^{
            NoshiWallpaperController *me = weak.target;
            if (!me || (NSInteger)i == current) return;
            keep((NSInteger)i);
            [me applyLook];
            [me applyLookNow];
        }]];
    }
    return rows;
}

- (NSArray *)classicCustomizationSections {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self tabsSection]];
    NoshiClassicPreviewView *preview = _classicPreview;
    [preview refresh];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return [NoshiClassicPreviewView height]; }]]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"custom.gloss.header", nil) footer:NSLocalizedString(@"custom.gloss.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.gloss.off", @"custom.gloss.normal", @"custom.gloss.strong", nil] current:NoshiClassicGlossLevel()
                                store:^(NSInteger value) { NoshiClassicGlossStore(value); }]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"custom.material.header", nil) footer:NSLocalizedString(@"custom.material.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.material.accent", @"custom.material.steel", @"custom.material.graphite", @"custom.material.black", nil]
                              current:NoshiClassicMaterial() store:^(NSInteger value) { NoshiClassicMaterialStore(value); }]]];
    NSMutableArray *texture = [NSMutableArray arrayWithArray:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.texture.linen", @"custom.texture.plain", nil]
                                                                              current:NoshiClassicTextureStyle() store:^(NSInteger value) { NoshiClassicTextureStyleStore(value); }]];
    if (NoshiClassicTextureStyle() == 0) {
        [texture addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"custom.texture.strength", nil) format:@"%.0f%%" value:(float)NoshiClassicTextureStrength()
                                                          minimum:0 maximum:100 change:^(float value) {
            NoshiClassicTextureStrengthStore((NSInteger)(value + 0.5f));
            [(NoshiWallpaperController *)weak.target applyLook];
        }]];
        /* the linen follows the accent unless a hue of its own is set, which the slider below then moves */
        BOOL ownHue = NoshiClassicTextureHue() >= 0;
        [texture addObjectsFromArray:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.texture.follow", @"custom.texture.own", nil] current:ownHue ? 1 : 0
                                                        store:^(NSInteger value) { NoshiClassicTextureHueStore(value ? 262 : -1); }]];
        if (ownHue) {
            [texture addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"custom.texture.hue", nil) format:@"%.0f°" value:(float)NoshiClassicTextureHue()
                                                              minimum:0 maximum:359 change:^(float value) {
                NoshiClassicTextureHueStore((NSInteger)(value + 0.5f));
                [(NoshiWallpaperController *)weak.target applyLook];
            }]];
        }
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"custom.texture.header", nil) footer:NSLocalizedString(@"custom.texture.info", nil) rows:texture]];
    NoshiSettingsRow *avatarGloss = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"custom.avatar.gloss", nil) subtitle:nil on:NoshiClassicAvatarGloss() toggle:^(BOOL on) {
        NoshiClassicAvatarGlossStore(on);
        [(NoshiWallpaperController *)weak.target applyLookNow];
    }];
    NoshiSettingsRow *avatarShadow = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"custom.avatar.shadow", nil) subtitle:nil on:NoshiClassicAvatarShadow() toggle:^(BOOL on) {
        NoshiClassicAvatarShadowStore(on);
        [(NoshiWallpaperController *)weak.target applyLookNow];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"custom.avatars.header", nil) footer:nil rows:[NSArray arrayWithObjects:avatarGloss, avatarShadow, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"custom.separators.header", nil) footer:NSLocalizedString(@"custom.separators.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.separators.thin", @"custom.separators.etched", @"custom.separators.none", nil] current:NoshiClassicSeparators()
                                store:^(NSInteger value) { NoshiClassicSeparatorsStore(value); }]]];
    return sections;
}

- (NSArray *)customizationSections {
    return [self classicCustomizationSections];
}

- (void)tintCommitted:(UIControl<NoshiTintControl> *)picker {
    NoshiThemeStoreCustomTint(picker.hue, picker.saturation, picker.brightness);
    CGPoint origin = [picker convertPoint:CGPointMake(CGRectGetMidX(picker.bounds), CGRectGetMidY(picker.bounds)) toView:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:NoshiThemeOriginKey]];
}

- (void)themeDidChange {
    [self buildThemedViews];
    [self rebuild];
}

/* the index of the gradient the stored wallpaper is, NSNotFound when it is none of them (a photo, or the standard wallpaper) */
static NSUInteger NoshiChosenPreset(NoshiWallpaperSetting stored) {
    if (stored.kind != NoshiWallpaperColors) return NSNotFound;
    for (NSUInteger i = 0; i < NoshiWallpaperPresetCount(); ++i) {
        NoshiWallpaperSetting preset = NoshiWallpaperPreset(i);
        if (preset.top == stored.top && preset.bottom == stored.bottom && preset.angle == stored.angle) return i;
    }
    return NSNotFound;
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiWallpaperSetting setting = [self stored];
    BOOL tabbed = !_peerId;
    if (tabbed && _tab == 1) {
        self.sections = [self customizationSections];
        [self reloadSettings];
        return;
    }
    NSMutableArray *sections = [NSMutableArray array];
    if (tabbed) [sections addObject:[self tabsSection]];

    NoshiChatPreviewView *preview = _preview;
    NoshiSettingsRow *picture = [NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:picture]]];

    /* the purple of the app until a color is picked; the wallpaper does not give the app its color */
    float hue = 286, saturation = 0.6f, brightness = 1;
    NoshiThemeStoredCustomTint(&hue, &saturation, &brightness);
    _picker.hue = hue;
    _picker.saturation = saturation;
    _picker.brightness = brightness;
    UIControl<NoshiTintControl> *picker = _picker;
    NoshiSettingsRow *tint = [NoshiSettingsRow viewRowWithView:picker height:^CGFloat(CGFloat width) { (void)width; return picker.preferredHeight; }];
    /* the color of the app is the app's, not the chat's */
    if (!_peerId) [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.tint.header", nil) footer:nil rows:[NSArray arrayWithObject:tint]]];

    NoshiWallpaperGridView *grid = _grid;
    grid.chosenIndex = NoshiChosenPreset(setting);
    grid.photoChosen = setting.kind == NoshiWallpaperPhoto;
    grid.standardChosen = _peerId ? !NoshiWallpaperChatHasOwn(_peerKind, _peerId) : setting.kind == NoshiWallpaperStandard;
    NoshiSettingsRow *tiles = [NoshiSettingsRow viewRowWithView:grid height:^CGFloat(CGFloat width) { (void)width; return [NoshiWallpaperGridView height]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.wallpaper.colors", nil) footer:nil rows:[NSArray arrayWithObject:tiles]]];

    if (setting.kind == NoshiWallpaperColors) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.pattern", nil) subtitle:nil on:setting.pattern != 0 toggle:^(BOOL on) {
            NoshiWallpaperController *me = weak.target;
            if (!me) return;
            NoshiWallpaperSetting next = [me stored];
            next.pattern = on ? 1 : 0;
            [me store:next];
            [me rebuild];
        }]];
        if (setting.pattern) {
            [options addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.intensity", nil) format:@"%.0f%%" value:(float)setting.intensity
                                                              minimum:0 maximum:100 change:^(float value) {
                NoshiWallpaperController *me = weak.target;
                if (!me) return;
                NoshiWallpaperSetting next = [me stored];
                int intensity = (int)(value + 0.5f);
                if (intensity == next.intensity) return;
                next.intensity = intensity;
                [me store:next];
            }]];
        }
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    } else if (setting.kind == NoshiWallpaperPhoto) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.blur", nil) subtitle:nil on:setting.blur != 0 toggle:^(BOOL on) {
            NoshiWallpaperController *me = weak.target;
            if (!me) return;
            NoshiWallpaperSetting next = [me stored];
            next.blur = on ? 1 : 0;
            [me store:next];
        }]];
        [options addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.dim", nil) format:@"%.0f%%" value:(float)setting.dim
                                                          minimum:0 maximum:100 change:^(float value) {
            NoshiWallpaperController *me = weak.target;
            if (!me) return;
            NoshiWallpaperSetting next = [me stored];
            int dim = (int)(value + 0.5f);
            if (dim == next.dim) return;
            next.dim = dim;
            [me store:next];
        }]];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    }
    self.sections = sections;
    [self reloadSettings];
}

- (void)pickPhoto {
    NoshiWeakReference *weak = _weak;
    int32_t peerKind = _peerKind;
    long long peerId = _peerId;
    [NoshiProfilePhotoPicker pickWholeFrom:self picked:^(NSString *path) {
        NoshiWallpaperController *me = weak.target;
        BOOL used = path && NoshiWallpaperUsePhotoAtPathForChat(path, peerKind, peerId);
        if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (!used) {
            NSLog(@"noshigram: the wallpaper photo could not be prepared");
            NoshiGiftAlert(nil, NSLocalizedString(@"chatset.wallpaper.failed", nil));
            return;
        }
        [me rebuild];
    } unavailable:^{
        NoshiGiftAlert(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

@end

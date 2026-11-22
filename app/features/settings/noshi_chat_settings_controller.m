#import "noshi_chat_settings_controller.h"

#import "noshi_chat_preview_view.h"
#import "noshi_platform.h"
#import "noshi_theme_busy_view.h"
#import "noshi_proximity.h"
#import "noshi_gift_screen.h"
#import "noshi_app_icon.h"
#import "noshi_alert.h"
#import "noshi_app_icon_list_view.h"
#import "noshi_audio_session.h"
#import "noshi_chat_settings.h"
#import "noshi_wallpaper.h"
#import "noshi_lite_mode_controller.h"
#import "noshi_night_mode.h"
#import "noshi_night_mode_controller.h"
#import "noshi_popup_menu.h"
#import "noshi_session_content.h"
#import "noshi_settings_pages.h"
#import "noshi_symbol.h"
#import "noshi_theme_list_view.h"
#import "noshi_wallpaper_controller.h"
#import "noshi_theme.h"
#import "noshi_file_picker.h"
#import "noshi_imported_theme.h"
#import "noshi_imported_theme_preview_controller.h"
#import "noshi_font_choice.h"
#import "noshi_sheet.h"
#import "noshi_classic_chrome.h"
#import "noshi_weak_reference.h"

@interface NoshiChatSettingsController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    /* the content settings of the account, which only the server knows: loaded when the screen opens, and the row of sensitive content waits for them */
    BOOL _contentLoaded;
    BOOL _canChangeContent;
    BOOL _sensitiveShown;
    NoshiChatPreviewView *_preview;
    UIButton *_more;
    BOOL _interfaceScaleDirty;
}
- (void)customFontTapped;
- (void)chooseFontFile;
- (void)fontsChanged;
- (void)interfaceScaleLetGo;
- (void)chooseThemeFile;
@end

/* the duck of the theme change covers the window while the icon is written, which takes a moment and ends the app
   on the systems that restart SpringBoard; the view is kept, so its parsed animation is ready for the next change */
static NoshiThemeBusyView *NoshiIconBusy;
static NSTimeInterval NoshiIconBusyShownAt;

static NoshiThemeBusyView *NoshiIconBusyShow(void) {
    UIView *window = NoshiOverlayHost();
    if (!window) return nil;
    if (!NoshiIconBusy) NoshiIconBusy = [[NoshiThemeBusyView alloc] initWithFrame:window.bounds];
    NoshiIconBusy.text = NSLocalizedString(@"icon.applying", nil);
    NoshiIconBusy.frame = window.bounds;
    NoshiIconBusy.alpha = NoshiReduceMotionEnabled() ? 1 : 0;
    [window addSubview:NoshiIconBusy];
    [NoshiIconBusy startAnimating];
    NoshiIconBusyShownAt = [NSDate timeIntervalSinceReferenceDate];
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.22 animations:^{ NoshiIconBusy.alpha = 1; }];
    return NoshiIconBusy;
}

/* a change that returns at once still shows the duck for a moment, or it would flash */
static void NoshiIconBusyHide(NoshiThemeBusyView *busy) {
    if (!busy) return;
    NSTimeInterval left = 1.2 - ([NSDate timeIntervalSinceReferenceDate] - NoshiIconBusyShownAt);
    [busy retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(left, 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.3 animations:^{ busy.alpha = 0; } completion:^(BOOL finished) {
            (void)finished;
            if (busy.alpha > 0) return;
            [busy stopAnimating];
            [busy removeFromSuperview];
        }];
        [busy release];
    });
}

@implementation NoshiChatSettingsController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.title", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_preview release];
    [_more release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildThemedViews];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nightModeChanged) name:NoshiNightModeDidChangeNotification object:nil];
    [self rebuild];
    [self loadContent];
}

/* the preview and the button of the menu read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[NoshiChatPreviewView alloc] init];
    NoshiWeakReference *weak = _weak;
    _preview.heightHandler = ^{ [(NoshiChatSettingsController *)weak.target updateRowHeights]; };
    [_more release];
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _more.frame = CGRectMake(0, 0, 44, 44);
    [_more setImage:NoshiSymbolImage(NoshiSymbolEllipsis, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    _more.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [self refreshMenu];
}

/* the page stays up when the theme changes; its views are made again in the new colors under the circle that spreads over the screen */
- (void)themeDidChange {
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiChatSettingsController alloc] initWithSession:_session] autorelease];
}


- (void)loadContent {
    NoshiWeakReference *weak = _weak;
    [_session loadContentSettings:^(BOOL enabled, BOOL canChange, NSString *errorName) {
        NoshiChatSettingsController *me = weak.target;
        if (!me) return;
        if (errorName) {
            NSLog(@"noshigram: the content settings did not load: %@", errorName);
            return;
        }
        me->_contentLoaded = YES;
        me->_canChangeContent = canChange;
        me->_sensitiveShown = enabled;
        [me rebuild];
    }];
}

/* the screen shows the night setup in a row, and the page of it is pushed over this one, so the row is made again when the person comes back */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.sections) [self rebuild];
}

- (void)nightModeChanged {
    if (self.isViewLoaded) [self rebuild];
}

#pragma mark rows

static NSString *NoshiNightStateText(void) {
    switch (NoshiNightConfig().mode) {
    case NOSHI_NIGHT_SCHEDULED: return NSLocalizedString(@"chatset.night.scheduled", nil);
    case NOSHI_NIGHT_ADAPTIVE: return NSLocalizedString(@"chatset.night.adaptive", nil);
    default: return NSLocalizedString(@"chatset.night.off", nil);
    }
}

/* the sizes move under the finger, so a change repaints the preview and leaves the rows alone */
- (void)textSizeMoved:(float)value {
    NSInteger size = (NSInteger)(value + 0.5f);
    if (size == NoshiChatTextSize()) return;
    NoshiChatSetTextSize(size);
    [self updateRowHeights];
    [self refreshMenu];
}

/* the screens are made again when the finger leaves the slider, not at every step of the drag: the rebuild takes the main thread for a moment */
- (void)interfaceScaleMoved:(float)value {
    NSInteger percent = (NSInteger)(value + 0.5f);
    if (percent == NoshiInterfaceScaleStored()) return;
    NoshiInterfaceScaleStore(percent);
    _interfaceScaleDirty = YES;
}

- (void)interfaceScaleLetGo {
    if (!_interfaceScaleDirty) return;
    _interfaceScaleDirty = NO;
    [self fontsChanged];
}

- (void)radiusMoved:(float)value {
    NSInteger radius = (NSInteger)(value + 0.5f);
    if (radius == NoshiChatBubbleRadius()) return;
    NoshiChatSetBubbleRadius(radius);
    [self refreshMenu];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *size = [NSMutableArray array];
    [size addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.textsize.row", nil) format:@"%.0f" value:(float)NoshiChatTextSize()
                                                   minimum:NOSHI_CHAT_TEXT_SIZE_MIN maximum:NOSHI_CHAT_TEXT_SIZE_MAX change:^(float value) {
        [(NoshiChatSettingsController *)weak.target textSizeMoved:value];
    }]];
    if (_preview) {
        NoshiChatPreviewView *preview = _preview;
        [size addObject:[NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }]];
    }
    /* the modern page has the reset in its menu; the classic one has no bar of its own to hold a menu, so the row stands under the preview */
    if (NoshiChatAppearanceChanged()) {
        NoshiSettingsRow *reset = [NoshiSettingsRow rowWithSymbol:NoshiSymbolRepeat tone:NoshiSettingsToneOrange title:NSLocalizedString(@"chatset.reset", nil) subtitle:nil
                                                                value:nil tap:^{
            NoshiChatResetAppearance();
            [(NoshiChatSettingsController *)weak.target rebuild];
        }];
        [size addObject:reset];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.textsize.header", nil) footer:nil rows:size]];

    /* the classic style is drawn by the system with its own sizes, so the scale changes nothing there and the slider is not offered */

    /* the fonts of the app grow with the scale; the few labels the system draws with its own sizes keep them */
    NoshiSettingsRow *interfaceScale = [NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.uiscale.row", nil) format:@"%.0f%%" value:(float)NoshiInterfaceScaleStored()
                                                                     minimum:NOSHI_INTERFACE_SCALE_MIN maximum:NOSHI_INTERFACE_SCALE_MAX change:^(float value) {
        [(NoshiChatSettingsController *)weak.target interfaceScaleMoved:value];
    }];
    interfaceScale.slideEnded = ^{ [(NoshiChatSettingsController *)weak.target interfaceScaleLetGo]; };
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.uiscale.header", nil) footer:nil
                                                             rows:[NSArray arrayWithObject:interfaceScale]]];

    NSMutableArray *looks = [NSMutableArray array];
    [looks addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolGallery tone:NoshiSettingsToneBlue title:NSLocalizedString(@"chatset.wallpaper", nil) subtitle:nil
                                                 value:nil tap:^{
        NoshiChatSettingsController *me = weak.target;
        NoshiWallpaperController *wallpapers = [[[NoshiWallpaperController alloc] init] autorelease];
        wallpapers.session = me->_session;
        [me.navigationController pushViewController:wallpapers animated:YES];
    }]];
    [looks addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.blurdefault", nil) subtitle:NSLocalizedString(@"chatset.wallpaper.blurdefault.info", nil)
                                                         on:NoshiChatFlagGet(NoshiChatFlagBlurWallpaper) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagBlurWallpaper, on);
        /* the wallpapers whose blur was never chosen are drawn again */
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiWallpaperDidChangeNotification object:nil];
    }]];
    if (looks.count) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:looks]];

    /* the bottom bar of telegram for ios 4 is contacts, calls, chats and settings; the first two can be taken off it */
    NSMutableArray *tabRows = [NSMutableArray array];
    static const NoshiTabKind optional[] = {NoshiTabContacts, NoshiTabCalls};
    static NSString *const optionalKeys[] = {@"chatset.tabs.contacts", @"chatset.tabs.calls"};
    for (NSUInteger i = 0; i < 2; ++i) {
        NoshiTabKind kind = optional[i];
        [tabRows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(optionalKeys[i], nil) subtitle:nil on:NoshiTabShown(kind) toggle:^(BOOL on) {
            NoshiTabSetShown(kind, on);
        }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.tabs", nil) footer:NSLocalizedString(@"chatset.tabs.info", nil) rows:tabRows]];

    NSMutableArray *themeRows = [NSMutableArray array];
    {
        NoshiThemeListView *themes = [[[NoshiThemeListView alloc] init] autorelease];
        NoshiWeakReference *shownThemes = [NoshiWeakReference referenceTo:themes];
        themes.chooseHandler = ^(BOOL toDark) {
            [(NoshiChatSettingsController *)weak.target applyThemeDark:toDark from:((NoshiThemeListView *)shownThemes.target).tapPoint];
        };
        [themeRows addObject:[NoshiSettingsRow viewRowWithView:themes height:^CGFloat(CGFloat width) { (void)width; return [NoshiThemeListView height]; }]];
    }
    [themeRows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolGallery tone:NoshiSettingsToneBlue title:NSLocalizedString(@"theme.import.title", nil) subtitle:nil value:nil tap:^{
        [(NoshiChatSettingsController *)weak.target chooseThemeFile];
    }]];
    NSString *themeFooter = NoshiImportedThemeSelected(NoshiThemeIsDark()) ? NSLocalizedString(@"theme.import.active", nil) : nil;
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.colortheme.header", nil) footer:themeFooter rows:themeRows]];
    [sections addObject:[self fontSection]];

    {
        NoshiSettingsRow *radius = [NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.corners.row", nil) format:@"%.0f" value:(float)NoshiChatBubbleRadius()
                                                                    minimum:NOSHI_CHAT_BUBBLE_RADIUS_MIN maximum:NOSHI_CHAT_BUBBLE_RADIUS_MAX change:^(float value) {
            [(NoshiChatSettingsController *)weak.target radiusMoved:value];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.corners.header", nil) footer:nil rows:[NSArray arrayWithObject:radius]]];

        NoshiChatListStyle style = NoshiChatListStyleStored();
        NoshiSettingsRow *two = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"chatset.list.two", nil) subtitle:nil checked:style == NoshiChatListTwoLines tap:^{
            [(NoshiChatSettingsController *)weak.target chooseListStyle:NoshiChatListTwoLines];
        }];
        NoshiSettingsRow *three = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"chatset.list.three", nil) subtitle:nil checked:style == NoshiChatListThreeLines tap:^{
            [(NoshiChatSettingsController *)weak.target chooseListStyle:NoshiChatListThreeLines];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.list.header", nil) footer:nil rows:[NSArray arrayWithObjects:two, three, nil]]];
    }

    [sections addObject:[self swipeSection]];
    [sections addObject:[self recordLockSection]];
    [sections addObject:[self lastSeenSection]];
    /* ios 10.3 has the call; older systems change the icon only through a bundle the app can write, which a jailbreak install gives, and the row says so
       where it does not */
    if (NoshiAlternateIconNames().count > 0) {
        NoshiAppIconListView *icons = [[[NoshiAppIconListView alloc] init] autorelease];
        NoshiAppIconMode mode = NoshiAppIconCurrentMode();
        icons.enabled = mode != NoshiAppIconUnavailable;
        /* the list holds the handler, so the handler holds the list only through a reference that does not keep it alive */
        NoshiWeakReference *shown = [NoshiWeakReference referenceTo:icons];
        icons.chooseHandler = ^(NSString *name) {
            /* before ios 10.3 the change ends with SpringBoard starting again, which takes the app with it */
            void (^change)(void) = ^{
                /* a rebuild of the page lets the list go while the change is running, so the change keeps the list until it ends */
                NoshiAppIconListView *list = [(NoshiAppIconListView *)shown.target retain];
                list.enabled = NO;
                NoshiThemeBusyView *busy = NoshiIconBusyShow();
                NoshiSetAlternateIcon(name, ^(NSError *error) {
                    NoshiIconBusyHide(busy);
                    list.enabled = YES;
                    [list refreshSelection];
                    if (!error) { [list release]; return; }
                    NSLog(@"noshigram: the app icon was not changed: %@", error);
                    NSString *detail = [NSString stringWithFormat:@"%@\n\n%@ (%@ %ld)", NSLocalizedString(@"chatset.appicon.failed", nil), error.localizedDescription, error.domain, (long)error.code];
                    if (mode == NoshiAppIconNative && NoshiAppIconCanRewrite()) {
                        NSString *question = [detail stringByAppendingFormat:@"\n\n%@", NSLocalizedString(@"chatset.appicon.restart.message", nil)];
                        NoshiConfirm(nil, question, NSLocalizedString(@"chatset.appicon.restart.action", nil), ^{
                            NoshiAppIconListView *fallbackList = [list retain];
                            fallbackList.enabled = NO;
                            NoshiThemeBusyView *fallbackBusy = NoshiIconBusyShow();
                            NoshiRewriteAppIcon(name, ^(NSError *rewriteError) {
                                NoshiIconBusyHide(fallbackBusy);
                                fallbackList.enabled = YES;
                                [fallbackList refreshSelection];
                                [fallbackList release];
                                if (rewriteError) NoshiGiftAlert(nil, rewriteError.localizedDescription);
                            });
                        });
                    } else {
                        NoshiGiftAlert(nil, detail);
                    }
                    [list release];
                });
            };
            if (NoshiAppIconCurrentMode() == NoshiAppIconRewrite) {
                NoshiConfirm(nil, NSLocalizedString(@"chatset.appicon.restart.message", nil), NSLocalizedString(@"chatset.appicon.restart.action", nil), change);
            } else {
                change();
            }
        };
        NSString *footer = mode == NoshiAppIconUnavailable ? NSLocalizedString(@"chatset.appicon.jailbreak", nil) : nil;
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.appicon", nil) footer:footer rows:[NSArray arrayWithObject:
            [NoshiSettingsRow viewRowWithView:icons height:^CGFloat(CGFloat width) { (void)width; return [NoshiAppIconListView height]; }]]]];
    }

    NoshiSettingsRow *night = [NoshiSettingsRow rowWithSymbol:NoshiSymbolMoon tone:NoshiSettingsTonePurple title:NSLocalizedString(@"chatset.night", nil)
                                                         subtitle:NoshiNightStateText() value:nil tap:^{
        [[(NoshiChatSettingsController *)weak.target navigationController] pushViewController:[[[NoshiNightModeController alloc] init] autorelease] animated:YES];
    }];
    NoshiSettingsRow *animations = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsPower tone:NoshiSettingsToneOrangeDeep title:NSLocalizedString(@"chatset.animations", nil)
                                                              subtitle:NSLocalizedString(@"chatset.animations.info", nil) value:nil tap:^{
        [[(NoshiChatSettingsController *)weak.target navigationController] pushViewController:[[[NoshiLiteModeSettingsController alloc] init] autorelease] animated:YES];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:night, animations, nil]]];
    [sections addObject:[self mediaSection]];
    [sections addObject:[self otherSection]];

    self.sections = sections;
    [self reloadSettings];
    [self refreshMenu];
}

#pragma mark sections



/* what a swipe to the left on a chat does: the archive until another is chosen */
- (NoshiSettingsSection *)swipeSection {
    NoshiWeakReference *weak = _weak;
    NoshiChatSwipe current = NoshiChatSwipeStored();
    static NSString *const keys[] = {@"chatset.swipe.archive", @"chatset.swipe.pin", @"chatset.swipe.read", @"chatset.swipe.mute", @"chatset.swipe.delete", @"chatset.swipe.folders"};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(keys[i], nil) subtitle:nil checked:(NSUInteger)current == i tap:^{
            NoshiChatSetSwipe((NoshiChatSwipe)i);
            [(NoshiChatSettingsController *)weak.target rebuild];
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.swipe.header", nil) footer:NSLocalizedString(@"chatset.swipe.info", nil) rows:rows];
}

/* how the status line of a person shows when they were last online: as a time ago while it is under a day (7 h ago), or always as the time itself (last seen at 12:54) */
- (NoshiSettingsSection *)lastSeenSection {
    NoshiWeakReference *weak = _weak;
    BOOL relative = NoshiChatFlagGet(NoshiChatFlagRelativeSeen);
    static NSString *const keys[] = {@"chatset.seen.exact", @"chatset.seen.relative"};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2; ++i) {
        BOOL value = i == 1;
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(keys[i], nil) subtitle:nil checked:relative == value tap:^{
            NoshiChatFlagSet(NoshiChatFlagRelativeSeen, value);
            [(NoshiChatSettingsController *)weak.target rebuild];
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.seen.header", nil) footer:NSLocalizedString(@"chatset.seen.info", nil) rows:rows];
}

/* how long a held record button waits before the recording locks by itself */
- (NoshiSettingsSection *)recordLockSection {
    NoshiWeakReference *weak = _weak;
    NSInteger current = NoshiChatRecordLockSeconds();
    static const NSInteger seconds[] = {0, 3, 5, 10, 15};
    static NSString *const keys[] = {@"chatset.reclock.off", @"chatset.reclock.3", @"chatset.reclock.5", @"chatset.reclock.10", @"chatset.reclock.15"};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        NSInteger value = seconds[i];
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(keys[i], nil) subtitle:nil checked:current == value tap:^{
            NoshiChatSetRecordLockSeconds(value);
            [(NoshiChatSettingsController *)weak.target rebuild];
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.reclock.header", nil) footer:NSLocalizedString(@"chatset.reclock.info", nil) rows:rows];
}

/* media and sound; the ear features only exist where there is a sensor to hear the ear with, "raise to speak"
   waits for "raise to listen" as in the original */
- (NoshiSettingsSection *)mediaSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.nexttap", nil) subtitle:NSLocalizedString(@"chatset.nexttap.info", nil)
                                                        on:NoshiChatNextMediaTap() toggle:^(BOOL on) { NoshiChatSetNextMediaTap(on); }]];
    if (NoshiProximityAvailable()) {
        NoshiWeakReference *weak = _weak;
        [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.raiselisten", nil) subtitle:NSLocalizedString(@"chatset.raiselisten.info", nil)
                                                            on:NoshiChatRaiseToListen() toggle:^(BOOL on) {
            NoshiChatSetRaiseToListen(on);
            [(NoshiChatSettingsController *)weak.target rebuild];
        }]];
        if (NoshiChatRaiseToListen()) {
            [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.raisespeak", nil) subtitle:NSLocalizedString(@"chatset.raisespeak.info", nil)
                                                                on:NoshiChatRaiseToSpeak() toggle:^(BOOL on) { NoshiChatSetRaiseToSpeak(on); }]];
        }
    }
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.pauserecord", nil) subtitle:NSLocalizedString(@"chatset.pauserecord.info", nil)
                                                        on:NoshiChatPauseMusicOnRecord() toggle:^(BOOL on) { NoshiChatSetPauseMusicOnRecord(on); }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.pausemedia", nil) subtitle:nil
                                                        on:NoshiChatPauseMusicOnMedia() toggle:^(BOOL on) { NoshiChatSetPauseMusicOnMedia(on); }]];
    if (NoshiAudioSessionCanUseBluetoothMicrophone()) {
        NoshiWeakReference *weak = _weak;
        BOOL bluetooth = NoshiChatRecordViaBluetooth();
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"chatset.mic", nil) value:NSLocalizedString(bluetooth ? @"chatset.mic.bluetooth" : @"chatset.mic.builtin", nil) tap:^{
            NoshiChatSettingsController *me = weak.target;
            if (!me) return;
            NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"chatset.mic.builtin", nil), NSLocalizedString(@"chatset.mic.bluetooth", nil), nil];
            NoshiSettingsChoose(me, NSLocalizedString(@"chatset.mic", nil), options, ^(NSUInteger index) {
                NoshiChatSetRecordViaBluetooth(index == 1);
                [(NoshiChatSettingsController *)weak.target rebuild];
            });
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.media.header", nil) footer:nil rows:rows];
}







/* other settings; "show 18+ materials" is the account's own setting on the server and is offered only when the
   server says this account may change it; Direct Share and the distance units are Android's share sheet and a map
   the app does not have */
- (NoshiSettingsSection *)otherSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    if (_contentLoaded && _canChangeContent) {
        [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.sensitive", nil) subtitle:NSLocalizedString(@"chatset.sensitive.info", nil)
                                                            on:_sensitiveShown toggle:^(BOOL on) {
            [(NoshiChatSettingsController *)weak.target setSensitive:on];
        }]];
    }
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.sendenter", nil) subtitle:nil on:NoshiChatSendByEnter() toggle:^(BOOL on) {
        NoshiChatSetSendByEnter(on);
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.other.header", nil) footer:nil rows:rows];
}

- (void)setSensitive:(BOOL)on {
    NoshiWeakReference *weak = _weak;
    _sensitiveShown = on;
    [_session setSensitiveContent:on completion:^(NSString *errorName) {
        NoshiChatSettingsController *me = weak.target;
        if (!me || !errorName) return;
        /* the server refused, so the switch goes back to what it has */
        NSLog(@"noshigram: the sensitive content setting was refused: %@", errorName);
        me->_sensitiveShown = !on;
        NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
        [me rebuild];
    }];
}

#pragma mark font

/* the font file row and, under it, the switch that sets the whole app in Rubik; a font file wins over the switch */
- (NoshiSettingsSection *)fontSection {
    NoshiWeakReference *weak = _weak;
    NSString *custom = NoshiFontCustomName();
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolDocument tone:NoshiSettingsTonePurple title:NSLocalizedString(@"font.custom", nil) subtitle:nil
                                                value:custom ? custom : NSLocalizedString(@"font.custom.none", nil) tap:^{
        [(NoshiChatSettingsController *)weak.target customFontTapped];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"font.rubik", nil) subtitle:nil on:NoshiFontRubikEverywhere() toggle:^(BOOL on) {
        NoshiFontStoreRubikEverywhere(on);
        [(NoshiChatSettingsController *)weak.target fontsChanged];
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"font.header", nil) footer:nil rows:rows];
}

- (void)customFontTapped {
    if (!NoshiFontCustomName()) {
        [self chooseFontFile];
        return;
    }
    NoshiWeakReference *weak = _weak;
    [NoshiSheet presentInView:self.view.window title:NoshiFontCustomName() message:nil
                        options:[NSArray arrayWithObjects:NSLocalizedString(@"font.change", nil), NSLocalizedString(@"font.remove", nil), nil]
                    destructive:[NSIndexSet indexSetWithIndex:1] cancelTitle:NSLocalizedString(@"common.close", nil) handler:^(NSUInteger index) {
        NoshiChatSettingsController *me = weak.target;
        if (!me) return;
        if (index == 0) {
            [me chooseFontFile];
        } else if (index == 1) {
            NoshiFontRemoveCustom();
            [me fontsChanged];
        }
    }];
}

- (void)chooseFontFile {
    NoshiWeakReference *weak = _weak;
    NoshiFilePicker *picker = [[[NoshiFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        NoshiChatSettingsController *me = weak.target;
        if (!me) return;
        NSString *failure = NoshiFontImportCustom(path);
        if (failure) NoshiShowNotice(NSLocalizedString(@"font.header", nil), failure);
        else [me fontsChanged];
    } cancel:nil] autorelease];
    picker.extensions = [NSArray arrayWithObjects:@"ttf", @"otf", nil];
    picker.rootTitle = NSLocalizedString(@"font.pick.title", nil);
    picker.searchPlaceholder = NSLocalizedString(@"font.pick.search", nil);
    picker.emptyText = NSLocalizedString(@"font.pick.empty", nil);
    picker.fileSymbol = NoshiSymbolDocument;
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    NoshiClassicStyleNavigationBar(navigation.navigationBar);
    [self presentViewController:navigation animated:YES completion:nil];
}

/* every screen asks for its fonts when it is built, so the main controller builds them again, from the row that was touched */
- (void)fontsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:NoshiThemeOriginKey]];
}

#pragma mark actions

- (void)chooseThemeFile {
    /* the same browser as the one that picks a file to send, asking for a theme: only folders and .tgios-theme files show, and the one that is tapped opens its preview */
    NoshiWeakReference *weak = _weak;
    NoshiFilePicker *picker = [[[NoshiFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        NoshiChatSettingsController *me = weak.target;
        if (me) [NoshiImportedThemePreviewController openURL:[NSURL fileURLWithPath:path] fromController:me];
    } cancel:nil] autorelease];
    picker.extensions = [NSArray arrayWithObject:@"tgios-theme"];
    picker.rootTitle = NSLocalizedString(@"theme.pick.title", nil);
    picker.searchPlaceholder = NSLocalizedString(@"theme.pick.search", nil);
    picker.emptyText = NSLocalizedString(@"theme.import.empty", nil);
    picker.fileSymbol = NoshiSymbolBackground;
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    NoshiClassicStyleNavigationBar(navigation.navigationBar);
    [self presentViewController:navigation animated:YES completion:nil];
}

/* the colors spread from the point that was touched; a built-in card puts the colors of the app back over an imported theme */
- (void)applyThemeDark:(BOOL)dark from:(CGPoint)origin {
    NoshiImportedThemeUseBuiltin(dark);
    NoshiThemeStoreDark(dark);
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:NoshiThemeOriginKey]];
}

- (void)chooseListStyle:(NoshiChatListStyle)style {
    if (style == NoshiChatListStyleStored()) return;
    NoshiChatSetListStyle(style);
    [self rebuild];
}

/* the menu of the screen has one entry, which puts the size and the corners back, and it only exists while they differ from the defaults */
- (void)refreshMenu {
    /* the classic page has no bar of its own to hold the button, and the button would sit in the corner of the screen */
}

- (void)showMenu {
    NoshiWeakReference *weak = _weak;
    NoshiSymbol symbols[] = {NoshiSymbolRotate};
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"chatset.reset", nil)] symbols:symbols
                                                               handler:^(NSUInteger index) {
        (void)index;
        NoshiChatSettingsController *me = weak.target;
        if (!me) return;
        NoshiChatResetAppearance();
        [me rebuild];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_more.frame) - 6, CGRectGetMaxY(_more.frame) - 8)];
}

@end

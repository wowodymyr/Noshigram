#import "noshi_settings_pages.h"

#import "noshi_alert.h"
#import "noshi_avatar_view.h"
#import "noshi_chat_settings.h"
#import "noshi_platform.h"
#include <math.h>
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define PREVIEW_AVATARS 4
#define PREVIEW_SIDE 56.0

/* a row of four pictures that take the corner the slider gives them as it moves, so the person sees the shape before it reaches the rest of the app */
@interface NoshiAvatarCornerPreview : UIView {
    NSMutableArray *_avatars;
}
- (void)refresh;
@end

@implementation NoshiAvatarCornerPreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    static NSString *const initials[PREVIEW_AVATARS] = {@"A", @"Б", @"V", @"Ж"};
    _avatars = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < PREVIEW_AVATARS; ++i) {
        NoshiAvatarView *avatar = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(0, 0, PREVIEW_SIDE, PREVIEW_SIDE)] autorelease];
        avatar.initials = initials[i];
        avatar.seed = i * 3 + 1;
        [self addSubview:avatar];
        [_avatars addObject:avatar];
    }
    return self;
}

- (void)dealloc {
    [_avatars release];
    [super dealloc];
}

- (void)refresh {
    for (NoshiAvatarView *avatar in _avatars) [avatar setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat gap = (self.bounds.size.width - PREVIEW_AVATARS * PREVIEW_SIDE) / (PREVIEW_AVATARS + 1);
    CGFloat scale = NoshiScreenScale();
    for (NSUInteger i = 0; i < PREVIEW_AVATARS; ++i) {
        CGFloat x = round((gap + i * (PREVIEW_SIDE + gap)) * scale) / scale;
        CGFloat y = round((self.bounds.size.height - PREVIEW_SIDE) * scale / 2) / scale;
        ((UIView *)[_avatars objectAtIndex:i]).frame = CGRectMake(x, y, PREVIEW_SIDE, PREVIEW_SIDE);
    }
}

@end

@interface NoshiAppearanceSettingsController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NoshiAvatarCornerPreview *_preview;
}
@end

@implementation NoshiAppearanceSettingsController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.noshigram.look", nil);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

/* every screen reads its settings when it is built, so the main controller builds them again on this notification, from the row that was touched; this page
   stays and is made again */
- (void)apply {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:NoshiThemeOriginKey]];
}

/* a slider moves in many small steps, and the screens are built once it rests */
- (void)applySoon {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(apply) object:nil];
    [self performSelector:@selector(apply) withObject:nil afterDelay:0.7];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiAppearanceSettingsController alloc] initWithSession:_session] autorelease];
}

#pragma mark sections

- (NoshiSettingsSection *)layoutSection {
    NoshiWeakReference *weak = _weak;
    NoshiTabLayout current = NoshiTabLayoutStored();
    NSArray *keys = [NSArray arrayWithObjects:@"look.layout.messenger", @"look.layout.calls", nil];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil) subtitle:nil checked:!NoshiTabOrderIsCustom() && (NSUInteger)current == i tap:^{
            if (!NoshiTabOrderIsCustom() && (NSUInteger)NoshiTabLayoutStored() == i) return;
            NoshiTabLayoutStore((NoshiTabLayout)i);
            [(NoshiAppearanceSettingsController *)weak.target apply];
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.layout.header", nil) footer:NSLocalizedString(@"look.layout.info", nil) rows:rows];
}

- (NoshiSettingsSection *)avatarSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    if (!_preview) _preview = [[NoshiAvatarCornerPreview alloc] initWithFrame:CGRectMake(0, 0, 320, 88)];
    NoshiAvatarCornerPreview *preview = _preview;
    [rows addObject:[NoshiSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return 88; }]];
    [rows addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.avatar.corners", nil) format:@"%.0f%%" value:(float)NoshiAvatarCornerPercent()
                                                   minimum:0 maximum:100 change:^(float value) {
        NoshiAvatarCornerStore((NSInteger)(value + 0.5f));
        [preview refresh];
        [(NoshiAppearanceSettingsController *)weak.target applySoon];
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.avatar.header", nil) footer:NSLocalizedString(@"look.avatar.info", nil) rows:rows];
}

- (void)chooseTitle {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"look.title.default", nil), NSLocalizedString(@"look.title.username", nil),
                        NSLocalizedString(@"look.title.name", nil), NSLocalizedString(@"look.title.custom", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"look.title", nil), options, ^(NSUInteger index) {
        NoshiAppearanceSettingsController *me = weak.target;
        if (!me) return;
        if (index == NoshiChatListTitleCustom) {
            NoshiPromptText(NSLocalizedString(@"look.title.custom", nil), nil, NoshiChatListCustomTitle(), NSLocalizedString(@"look.title.hint", nil), ^(NSString *text) {
                NoshiAppearanceSettingsController *page = weak.target;
                if (!page) return;
                NoshiChatListSetCustomTitle(text);
                NoshiChatListTitleStore(NoshiChatListTitleCustom);
                [page apply];
            });
            return;
        }
        NoshiChatListTitleStore((NoshiChatListTitle)index);
        [me apply];
    });
}

- (NoshiSettingsSection *)chatListSection {
    NoshiWeakReference *weak = _weak;
    static NSString *const titleKeys[] = {@"look.title.default", @"look.title.username", @"look.title.name", @"look.title.custom"};
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.stories", nil) subtitle:nil on:!NoshiChatFlagGet(NoshiChatFlagHideStories) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideStories, !on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidesearch", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagHideSearchBar) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideSearchBar, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidevpn", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagHideVpnButton) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideVpnButton, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"look.title", nil) value:NSLocalizedString(titleKeys[NoshiChatListTitleStored()], nil) tap:^{
        [(NoshiAppearanceSettingsController *)weak.target chooseTitle];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.senderavatars", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagSenderAvatars) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagSenderAvatars, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidewaves", nil) subtitle:NSLocalizedString(@"look.hidewaves.info", nil) on:NoshiChatFlagGet(NoshiChatFlagHideWaves) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideWaves, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.chatlist.header", nil) footer:nil rows:rows];
}

/* what falls over the lists and the chats: snowflakes, the foxes of Senko, and the boykissers that take the place of the waves of the background */
- (NoshiSettingsSection *)effectsSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.snow", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagSnow) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagSnow, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"look.foxes", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagFoxes) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagFoxes, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"more.boykisser", nil) subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagBoykisser) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagBoykisser, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.effects.header", nil) footer:nil rows:rows];
}

- (NoshiSettingsSection *)foldersSection {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *hide = [NoshiSettingsRow switchRowWithTitle:[NSString stringWithFormat:NSLocalizedString(@"look.hidealltab", nil), NSLocalizedString(@"folders.all", nil)]
                                                             subtitle:nil on:NoshiChatFlagGet(NoshiChatFlagHideAllChatsTab) toggle:^(BOOL on) {
        NoshiChatFlagSet(NoshiChatFlagHideAllChatsTab, on);
        [(NoshiAppearanceSettingsController *)weak.target apply];
    }];
    NSArray *styles = [NSArray arrayWithObjects:NSLocalizedString(@"look.folders.style.names", nil), NSLocalizedString(@"look.folders.style.icons", nil),
                       NSLocalizedString(@"look.folders.style.both", nil), nil];
    NoshiSettingsRow *style = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"look.folders.style", nil)
                                                           value:[styles objectAtIndex:(NSUInteger)NoshiFolderTabStyleStored()] tap:^{
        [(NoshiAppearanceSettingsController *)weak.target chooseFolderStyle];
    }];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.folders.header", nil) footer:NSLocalizedString(@"look.folders.info", nil)
                                                rows:[NSArray arrayWithObjects:style, hide, nil]];
}

/* the menu of the three looks of a tab; the bar of folders on the screen changes in place, so the page only has to show the choice */
- (void)chooseFolderStyle {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"look.folders.style.names", nil), NSLocalizedString(@"look.folders.style.icons", nil),
                        NSLocalizedString(@"look.folders.style.both", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"look.folders.style", nil), options, ^(NSUInteger index) {
        NoshiFolderTabStyleStore((NoshiFolderTabStyle)index);
        [(NoshiAppearanceSettingsController *)weak.target rebuild];
    });
}

- (NoshiSettingsSection *)cardsSection {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *radius = [NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.cards.radius", nil) format:@"%.0f" value:(float)NoshiSectionRadius()
                                                                minimum:0 maximum:NOSHI_SECTION_RADIUS_MAX change:^(float value) {
        NoshiSectionRadiusStore((NSInteger)(value + 0.5f));
        [(NoshiAppearanceSettingsController *)weak.target applySoon];
    }];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"look.cards.header", nil) footer:nil rows:[NSArray arrayWithObject:radius]];
}

- (void)rebuild {
    self.sections = [NSArray arrayWithObjects:[self layoutSection], [self avatarSection], [self chatListSection], [self effectsSection], [self foldersSection], [self cardsSection], nil];
    [self reloadSettings];
}

@end

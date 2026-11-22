#import "noshi_profile_qr_controller.h"

#import <QuartzCore/QuartzCore.h>

#include "noshi_qr.h"

#import "noshi_avatar_view.h"
#import "noshi_classic_chrome.h"
#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_qr_view.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_wallpaper.h"

#define CARD_SIDE_MAX 300.0
#define CARD_RADIUS 24.0
#define CLASSIC_CARD_RADIUS 10.0
#define CODE_INSET 16.0
#define AVATAR 56.0
/* the card is cut away this far round the photo, so the wallpaper shows between the two */
#define PHOTO_GAP 4.0
#define LABEL_HEIGHT 22.0
#define SHEET_RADIUS 22.0
#define SHEET_MARGIN 16.0
#define TILE_CLASSIC 48.0
#define TILE_GAP 8.0
#define SWITCH_HEIGHT 30.0
#define CODE_MIN 120.0
#define PAPER_COUNT 2
/* viewWithTag: matches the view it is sent to first, and the second tile has tag 1 itself */
#define PAPER_TAG 100
/* the two paper choices keep their positions when the background is changed */
#define THEME_KEY @"noshigram.qr.theme.v3"

/* a backdrop and the ink of the code on it, for the tiles after the first */
typedef struct {
    CGFloat back[2][3];
    CGFloat ink[2][3];
    const char *emoji;
} NoshiQrTheme;

static const NoshiQrTheme NoshiQrThemes[] = {
    {{{0.36, 0.66, 0.50}, {0.86, 0.83, 0.56}}, {{0.20, 0.58, 0.42}, {0.46, 0.72, 0.30}}, "\xF0\x9F\x8F\xA0"},
    {{{0.60, 0.80, 0.42}, {0.96, 0.86, 0.46}}, {{0.34, 0.64, 0.24}, {0.62, 0.72, 0.20}}, "\xF0\x9F\x90\xA5"},
    {{{0.44, 0.72, 0.96}, {0.66, 0.56, 0.96}}, {{0.20, 0.52, 0.90}, {0.38, 0.42, 0.88}}, "\xE2\x98\x83\xEF\xB8\x8F"},
    {{{0.72, 0.60, 0.96}, {0.56, 0.90, 0.90}}, {{0.52, 0.36, 0.88}, {0.24, 0.66, 0.78}}, "\xF0\x9F\x92\x8E"},
    {{{0.36, 0.64, 0.86}, {0.44, 0.86, 0.74}}, {{0.20, 0.50, 0.80}, {0.20, 0.68, 0.58}}, "\xF0\x9F\x8E\x93"},
};
#define GRADIENT_COUNT (sizeof(NoshiQrThemes) / sizeof(NoshiQrThemes[0]))
#define THEME_COUNT (GRADIENT_COUNT + PAPER_COUNT)

static UIColor *NoshiQrColor(const CGFloat *rgb, CGFloat darken) {
    return [UIColor colorWithRed:rgb[0] * darken green:rgb[1] * darken blue:rgb[2] * darken alpha:1];
}

static UIColor *NoshiQrPatternColor(CGFloat red, CGFloat green, CGFloat blue) {
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

/* the pattern is a mask, so it stays sharp when the screen changes size */
static UIView *NoshiQrPatternView(CGRect frame) {
    UIView *view = [[[UIView alloc] initWithFrame:frame] autorelease];
    UIImage *pattern = [UIImage imageNamed:@"chat_pattern.png"];
    CALayer *mask = [CALayer layer];
    mask.contents = (id)pattern.CGImage;
    mask.contentsGravity = kCAGravityResizeAspectFill;
    mask.frame = view.bounds;
    view.layer.mask = mask;
    view.userInteractionEnabled = NO;
    if (!pattern) NSLog(@"noshigram: QR background pattern is missing");
    return view;
}

@interface NoshiProfileQrController () {
    NSString *_url;
    NSString *_caption;
    NSString *_missingText;
    NSString *_initials;
    NSUInteger _seed;
    NoshiPhoto *_photoRef;
    UIImageView *_wallpaper;
    UIView *_backdropView;
    CAGradientLayer *_backdrop;
    UIView *_pattern;
    UIScrollView *_scroll;
    UIView *_card;
    CAShapeLayer *_cardMask;
    NoshiQrView *_code;
    NoshiAvatarView *_photo;
    UILabel *_link;
    UILabel *_missing;
    UIView *_sheet;
    CAShapeLayer *_sheetMask;
    UILabel *_sheetTitle;
    UIButton *_mode;
    UISegmentedControl *_modeSwitch;
    UIToolbar *_sheetBar;
    UIScrollView *_tiles;
    NSMutableArray *_tileViews;
    NSUInteger _theme;
    BOOL _night;
    BOOL _statusWasHidden;
    CGFloat _tile;
}
@end

@implementation NoshiProfileQrController

/* the one place both kinds of owner end up: what the code holds, the line under it, and the picture in its middle */
- (id)initWithSession:(NoshiSession *)session url:(NSString *)url caption:(NSString *)caption missing:(NSString *)missing initials:(NSString *)initials
                 seed:(NSUInteger)seed photo:(NoshiPhoto *)photo avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _url = url.length ? [url copy] : nil;
    _caption = [caption copy];
    _missingText = [missing copy];
    _initials = [initials copy];
    _seed = seed;
    _photoRef = [photo retain];
    _night = NoshiThemeIsDark();
    _tile = TILE_CLASSIC;
    /* with no choice stored the screen opens on the wallpaper of the style the app wears */
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:THEME_KEY];
    _theme = saved && saved.integerValue >= 0 && (NSUInteger)saved.integerValue < THEME_COUNT ? (NSUInteger)saved.integerValue : 1;
    self.clearBar = YES;
    self.screenTitle = NSLocalizedString(@"profile.qr", nil);
    return self;
}

- (id)initWithSession:(NoshiSession *)session person:(NoshiPerson *)person avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    NSString *name = person.username;
    return [self initWithSession:session url:name.length ? [@"https://t.me/" stringByAppendingString:name] : nil
                         caption:name.length ? [@"@" stringByAppendingString:[name uppercaseString]] : @""
                         missing:NSLocalizedString(@"profile.qr.nousername", nil) initials:person.initials seed:(NSUInteger)(person.userId % 1000003)
                           photo:person.photo avatars:avatars media:media];
}

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    NoshiDialog *dialog = channel.dialog;
    NSString *caption = channel.username.length ? [@"@" stringByAppendingString:[channel.username uppercaseString]] : [dialog.title uppercaseString];
    return [self initWithSession:session url:channel.webLink caption:caption missing:NSLocalizedString(@"channel.qr.nolink", nil) initials:dialog.initials
                            seed:dialog.avatarSeed photo:dialog.photo avatars:avatars media:media];
}

- (void)dealloc {
    NoshiStatusBarShow(self, UIStatusBarAnimationNone);
    [_url release];
    [_caption release];
    [_missingText release];
    [_initials release];
    [_photoRef release];
    [_wallpaper release];
    [_backdropView release];
    [_backdrop release];
    [_pattern release];
    [_scroll release];
    [_card release];
    [_cardMask release];
    [_code release];
    [_photo release];
    [_link release];
    [_missing release];
    [_sheet release];
    [_sheetMask release];
    [_sheetTitle release];
    [_mode release];
    [_modeSwitch release];
    [_sheetBar release];
    [_tiles release];
    [_tileViews release];
    [super dealloc];
}

static UILabel *NoshiCodeLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    label.font = font;
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _wallpaper = [[UIImageView alloc] init];
    [root addSubview:_wallpaper];
    _backdropView = [[UIView alloc] init];
    _backdrop = [[CAGradientLayer layer] retain];
    _backdrop.startPoint = CGPointMake(0.1, 0);
    _backdrop.endPoint = CGPointMake(0.9, 1);
    [_backdropView.layer addSublayer:_backdrop];
    _pattern = [NoshiQrPatternView(CGRectZero) retain];
    [_backdropView addSubview:_pattern];
    [root addSubview:_backdropView];

    /* the card and the photo scroll above the sheet, which stays at the bottom, so a small screen can still bring the whole code
       into view */
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.backgroundColor = [UIColor clearColor];
    [root addSubview:_scroll];

    _card = [[UIView alloc] init];
    _card.backgroundColor = [UIColor whiteColor];
    _cardMask = [[CAShapeLayer layer] retain];
    _cardMask.fillRule = kCAFillRuleEvenOdd;
    _card.layer.mask = _cardMask;
    [_scroll addSubview:_card];
    _code = [[NoshiQrView alloc] init];
    [_card addSubview:_code];
    _link = NoshiCodeLabel([UIColor blackColor], NoshiFontBold(18), NoshiTextAlignmentCenter);
    _link.adjustsFontSizeToFitWidth = YES;
    _link.minimumFontSize = 12;
    _link.text = _caption;
    [_card addSubview:_link];
    _photo = [[NoshiAvatarView alloc] init];
    _photo.seed = _seed;
    _photo.initials = _initials;
    [_photo setPhoto:_photoRef cache:self.avatars];
    [_scroll addSubview:_photo];

    _missing = NoshiCodeLabel(NoshiColorSecondary(), NoshiFontRegular(15), NoshiTextAlignmentCenter);
    _missing.numberOfLines = 0;
    _missing.text = _missingText;
    _missing.hidden = _url != nil;
    [_scroll addSubview:_missing];

    _sheet = [[UIView alloc] init];
    _tileViews = [[NSMutableArray alloc] init];
    _tiles = [[UIScrollView alloc] init];
    _tiles.showsHorizontalScrollIndicator = NO;
    /* the classic sheet is the system's own toolbar holding the tiles, and the day or night switch sits in the navigation bar, so
           the sheet is no taller than the tiles */
    _sheetBar = [[UIToolbar alloc] init];
    NoshiClassicStyleToolbar(_sheetBar);
    [_sheet addSubview:_sheetBar];
    _modeSwitch = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:NSLocalizedString(@"profile.qr.day", nil),
                                                             NSLocalizedString(@"profile.qr.night", nil), nil]];
    NoshiClassicStyleSegmented(_modeSwitch);
    _modeSwitch.frame = CGRectMake(0, 0, 160, SWITCH_HEIGHT);
    [_modeSwitch addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _modeSwitch;
    [root addSubview:_sheet];
    [_sheet addSubview:_tiles];
    for (NSUInteger i = 0; i < THEME_COUNT; ++i) [self addTile:i];

    _card.hidden = _photo.hidden = _url == nil;
    _sheet.hidden = _url == nil;
    [self applyTheme];
    [self drawCode];
}

/* the first tile shows the chat wallpaper, the second the patterned background */
- (void)addTile:(NSUInteger)index {
    CGRect bounds = CGRectMake(0, 0, _tile, _tile);
    CGFloat chipSide = floor(_tile * 0.46);
    UIControl *tile = [[[UIControl alloc] initWithFrame:bounds] autorelease];
    tile.tag = (NSInteger)index;
    tile.layer.cornerRadius = 6;
    tile.layer.masksToBounds = YES;
    UIColor *ink;
    if (index == 0) {
        UIImageView *paper = [[[UIImageView alloc] initWithFrame:bounds] autorelease];
        paper.tag = PAPER_TAG;
        [tile addSubview:paper];
        ink = NoshiColorAccent();
    } else if (index == 1) {
        CAGradientLayer *fill = [CAGradientLayer layer];
        fill.name = @"fill";
        fill.frame = bounds;
        [tile.layer addSublayer:fill];
        UIView *pattern = NoshiQrPatternView(bounds);
        pattern.tag = PAPER_TAG;
        [tile addSubview:pattern];
        ink = NoshiColorAccent();
    } else {
        CAGradientLayer *fill = [CAGradientLayer layer];
        fill.startPoint = CGPointMake(0.1, 0);
        fill.endPoint = CGPointMake(0.9, 1);
        fill.name = @"fill";
        fill.frame = bounds;
        [tile.layer addSublayer:fill];
        ink = NoshiQrColor(NoshiQrThemes[index - PAPER_COUNT].ink[0], 1);
    }
    UIImageView *chip = [[[UIImageView alloc] initWithFrame:CGRectMake((_tile - chipSide) / 2, index < PAPER_COUNT ? (_tile - chipSide) / 2 : 4, chipSide, chipSide)] autorelease];
    chip.backgroundColor = [UIColor whiteColor];
    chip.layer.cornerRadius = 4;
    chip.contentMode = UIViewContentModeCenter;
    chip.image = NoshiSymbolImage(NoshiSymbolQr, chipSide - 8, ink);
    chip.userInteractionEnabled = NO;
    [tile addSubview:chip];
    if (index >= PAPER_COUNT) {
        NoshiEmojiLabel *emoji = [[[NoshiEmojiLabel alloc] init] autorelease];
        emoji.font = NoshiFontRegular(floor(_tile * 0.27));
        emoji.textAlignment = NoshiTextAlignmentCenter;
        emoji.text = [NSString stringWithUTF8String:NoshiQrThemes[index - PAPER_COUNT].emoji];
        emoji.frame = CGRectMake(0, 6 + chipSide, _tile, _tile - 8 - chipSide);
        [tile addSubview:emoji];
    }
    [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_tiles addSubview:tile];
    [_tileViews addObject:tile];
}

static void NoshiQrApplyPaper(UIImageView *view, NSUInteger index, BOOL night) {
    if (index == 0 && night == NoshiThemeIsDark()) NoshiApplyChatWallpaper(view, night);
    else NoshiApplyWallpaperStyle(view, night);
}

static NSArray *NoshiQrPatternColors(BOOL night) {
    UIColor *top = night ? NoshiQrPatternColor(0.10, 0.18, 0.28) : NoshiQrPatternColor(0.70, 0.84, 0.95);
    UIColor *bottom = night ? NoshiQrPatternColor(0.07, 0.09, 0.15) : NoshiQrPatternColor(0.87, 0.93, 0.98);
    return [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
}

/* the backdrop, the ink of the code, the sheet and the tiles follow the chosen theme and the day or night switch */
- (void)applyTheme {
    BOOL paper = _theme < PAPER_COUNT;
    const NoshiQrTheme *theme = paper ? NULL : &NoshiQrThemes[_theme - PAPER_COUNT];
    CGFloat dim = _night ? 0.32 : 1;
    if (_theme == 0) NoshiQrApplyPaper(_wallpaper, 0, _night);
    _wallpaper.hidden = _theme != 0;
    _backdropView.hidden = _theme == 0;
    _pattern.hidden = _theme != 1;
    _pattern.backgroundColor = _night ? [UIColor colorWithWhite:1 alpha:0.20] : [UIColor colorWithWhite:0 alpha:0.16];
    if (_theme == 1) _backdrop.colors = NoshiQrPatternColors(_night);
    if (theme) {
        _backdrop.colors = [NSArray arrayWithObjects:(id)NoshiQrColor(theme->back[0], dim).CGColor, (id)NoshiQrColor(theme->back[1], dim).CGColor, nil];
    }
    UIColor *top = theme ? NoshiQrColor(theme->ink[0], 1) : NoshiColorAccent();
    UIColor *bottom = theme ? NoshiQrColor(theme->ink[1], 1) : NoshiColorAccentDark();
    [_code setModuleTopColor:top bottomColor:bottom];
    /* the plain paper themes follow the chat color; a gradient theme keeps white, its ink is picked for it */
    UIColor *sheet = paper ? NoshiColorQrPaper() : [UIColor whiteColor];
    _code.paperColor = sheet;
    _card.backgroundColor = sheet;
    _link.textColor = bottom;
    _modeSwitch.selectedSegmentIndex = _night ? 1 : 0;
    for (UIView *tile in _tileViews) {
        if (tile.tag == 0) {
            NoshiQrApplyPaper((UIImageView *)[tile viewWithTag:PAPER_TAG], (NSUInteger)tile.tag, _night);
        } else if (tile.tag == 1) {
            UIView *pattern = [tile viewWithTag:PAPER_TAG];
            pattern.backgroundColor = _night ? [UIColor colorWithWhite:1 alpha:0.20] : [UIColor colorWithWhite:0 alpha:0.16];
            for (CALayer *layer in tile.layer.sublayers) {
                if ([layer.name isEqualToString:@"fill"]) ((CAGradientLayer *)layer).colors = NoshiQrPatternColors(_night);
            }
        } else {
            const NoshiQrTheme *own = &NoshiQrThemes[tile.tag - PAPER_COUNT];
            for (CALayer *layer in tile.layer.sublayers) {
                if (![layer.name isEqualToString:@"fill"]) continue;
                ((CAGradientLayer *)layer).colors = [NSArray arrayWithObjects:(id)NoshiQrColor(own->back[0], dim).CGColor,
                                                     (id)NoshiQrColor(own->back[1], dim).CGColor, nil];
            }
        }
        BOOL chosen = (NSUInteger)tile.tag == _theme;
        tile.layer.borderColor = (chosen ? NoshiColorAccent() : [UIColor colorWithWhite:0.5 alpha:0.6]).CGColor;
        tile.layer.borderWidth = chosen ? 2 : (1);
    }
}

- (void)tileTapped:(UIControl *)tile {
    _theme = (NSUInteger)tile.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)_theme forKey:THEME_KEY];
    [self applyTheme];
}

- (void)modeChanged:(UISegmentedControl *)control {
    _night = control.selectedSegmentIndex == 1;
    [self applyTheme];
}

- (void)toggleNight {
    _night = !_night;
    [self applyTheme];
}

- (void)drawCode {
    static uint8_t modules[NOSHI_QR_MAX_MODULES];
    int side = 0;
    const char *text = _url.UTF8String;
    if (!text || noshi_qr_encode_min_version((const uint8_t *)text, strlen(text), NOSHI_QR_LOGO_MIN_VERSION, modules, sizeof(modules), &side, NULL) != NOSHI_OK) {
        NSLog(@"noshigram: the profile link did not encode as a QR code");
        return;
    }
    [_code setModules:[NSData dataWithBytes:modules length:(NSUInteger)(side * side)] side:side animated:YES];
}

- (void)layoutBody:(CGRect)body {
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGFloat width = body.size.width, height = body.size.height;
    CGRect whole = self.view.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wallpaper.frame = whole;
    _backdropView.frame = whole;
    _backdrop.frame = _backdropView.bounds;
    _pattern.frame = _backdropView.bounds;
    _pattern.layer.mask.frame = _pattern.bounds;
    [CATransaction commit];
    _scroll.frame = body;

    CGSize missing = [_missing sizeThatFits:CGSizeMake(width - 64, 200)];
    _missing.frame = CGRectMake(32, 40, width - 64, missing.height);
    if (!_url) {
        _scroll.contentSize = body.size;
        return;
    }

    /* the sheet: a row of tiles; the modern one has a title and the day or night switch over them, the classic one has the switch in
       the navigation bar */
    CGFloat tilesTop = 6;
    CGFloat sheetHeight = tilesTop + _tile + (6) + MAX(insets.bottom, 4);
    CGFloat sheetTop = CGRectGetMaxY(body) - sheetHeight;
    _sheet.frame = CGRectMake(body.origin.x, sheetTop, width, sheetHeight);
    _sheetBar.frame = _sheet.bounds;
    _tiles.frame = CGRectMake(0, tilesTop, width, _tile);
    for (NSUInteger i = 0; i < _tileViews.count; ++i) {
        UIView *tile = [_tileViews objectAtIndex:i];
        tile.frame = CGRectMake(SHEET_MARGIN + (_tile + TILE_GAP) * (CGFloat)i, 0, _tile, _tile);
    }
    _tiles.contentSize = CGSizeMake(2 * SHEET_MARGIN + (_tile + TILE_GAP) * (CGFloat)_tileViews.count - TILE_GAP, _tile);

    /* the whole card with the photo over its top edge has to show above the sheet, so the code takes the side the
       room allows */
    CGFloat cut = AVATAR / 2 + PHOTO_GAP;
    CGFloat around = cut + 6 + 4 + LABEL_HEIGHT + 12;
    CGFloat room = height - sheetHeight;
    CGFloat code = MIN(MIN(CARD_SIDE_MAX, width - 64) - 2 * CODE_INSET, room - AVATAR / 2 - 6 - 10 - around);
    code = floor(MAX(code, CODE_MIN));
    CGFloat cardWidth = code + 2 * CODE_INSET;
    CGFloat cardHeight = around + code;
    CGFloat top = AVATAR / 2 + MAX(6, (room - AVATAR / 2 - cardHeight) / 2);
    _card.frame = CGRectMake((width - cardWidth) / 2, top, cardWidth, cardHeight);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:CLASSIC_CARD_RADIUS];
    [shape appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(cardWidth / 2 - cut, -cut, 2 * cut, 2 * cut)]];
    shape.usesEvenOddFillRule = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cardMask.frame = _card.bounds;
    _cardMask.path = shape.CGPath;
    [CATransaction commit];
    _code.frame = CGRectMake(CODE_INSET, cut + 6, code, code);
    _link.frame = CGRectMake(CODE_INSET, cut + 6 + code + 4, code, LABEL_HEIGHT);
    _photo.frame = CGRectMake((width - AVATAR) / 2, top - AVATAR / 2, AVATAR, AVATAR);
    _scroll.contentSize = CGSizeMake(width, MAX(height, top + cardHeight + 10 + sheetHeight));
}

/* the modern bar is see-through, so the picture starts at the top edge and the card gets the room the bar would take */
- (CGRect)bodyFrame {
    return [super bodyFrame];
}

/* the wallpaper stops at the status bar on ios 5 and 6, where the window's own lilac shows above it as a strip;
   the modern screen hides the bar like the story viewer does */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (BOOL)prefersStatusBarHidden { return NO; }

@end

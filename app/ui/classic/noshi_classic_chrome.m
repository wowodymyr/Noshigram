#import "noshi_classic_chrome.h"
#import "noshi_tab_icons.h"
#import "noshi_imported_theme.h"
#import "noshi_status_label.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_chat_settings.h"
#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"
#import "noshi_wave_background_view.h"

/* every picture of the classic chrome is drawn once for a palette and then kept: the lists, the bars and the buttons ask for the same few pictures at every configure and every touch, and
   each ask drew a gradient into a new bitmap on the main thread. the key holds the revision of the theme, so a change of colors never finds a picture of the old ones */
static NSCache *NoshiClassicImageCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 120;
    });
    return cache;
}

static UIImage *NoshiClassicRemembered(NSString *key, UIImage *(^make)(void)) {
    NSCache *cache = NoshiClassicImageCache();
    NSString *full = [NSString stringWithFormat:@"%lu|%.1f|%@", (unsigned long)NoshiThemeRevision(), NoshiScreenScale(), key];
    UIImage *image = [[[cache objectForKey:full] retain] autorelease];
    if (image) return image;
    image = make();
    if (image) [cache setObject:image forKey:full];
    return image;
}

static UIColor *NoshiTabBarGround(void);

/* ios 15 draws a bar that has nothing scrolled under it from scrollEdgeAppearance, which is clear by default and ignores barTintColor: the classic bar came out
   white with white buttons and title. the appearance classes are looked up by name, so the slices linked against old sdks never see them */
static void NoshiClassicApplyBarAppearance(UIView *bar) {
    BOOL navigation = [bar isKindOfClass:[UINavigationBar class]];
    Class kind = NSClassFromString(navigation ? @"UINavigationBarAppearance" : @"UIToolbarAppearance");
    SEL opaque = NSSelectorFromString(@"configureWithOpaqueBackground");
    if (!kind || ![kind instancesRespondToSelector:opaque]) return;
    id appearance = [[[kind alloc] init] autorelease];
    [appearance performSelector:opaque];
    [appearance setValue:NoshiTabBarGround() forKey:@"backgroundColor"];
    if (navigation) {
        [appearance setValue:[NSDictionary dictionaryWithObject:NoshiColorTitle() forKey:NSForegroundColorAttributeName] forKey:@"titleTextAttributes"];
    }
    for (NSString *key in [NSArray arrayWithObjects:@"standardAppearance", @"compactAppearance", @"scrollEdgeAppearance", nil]) {
        NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        if ([bar respondsToSelector:NSSelectorFromString(setter)]) [bar setValue:appearance forKey:key];
    }
}

static void NoshiClassicTintBar(id bar) {
    NoshiClassicApplyBarAppearance(bar);
    /* the bars of telegram for ios 4: the light ground of the bottom bar (dark at night), a dark title and the buttons in the accent */
    [bar setValue:NoshiTabBarGround() forKey:@"barTintColor"];
    [bar setValue:NoshiColorAccent() forKey:@"tintColor"];
    [bar setValue:[NSNumber numberWithBool:NO] forKey:@"translucent"];
}

void NoshiClassicStyleNavigationBar(UINavigationBar *bar) {
    bar.barStyle = NoshiThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault;
    NoshiClassicTintBar(bar);
    [bar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    [bar setTitleTextAttributes:[NSDictionary dictionaryWithObject:NoshiColorTitle() forKey:NSForegroundColorAttributeName]];
}

void NoshiClassicStyleToolbar(UIToolbar *bar) {
    bar.barStyle = NoshiThemeIsDark() ? UIBarStyleBlack : UIBarStyleDefault;
    NoshiClassicTintBar(bar);
}

/* a stretchable flat pill, a little darker than the bar; the point under it is left clear so the field keeps the height it had */
static UIImage *NoshiClassicSearchWellMade(void);

static UIImage *NoshiClassicSearchWell(void) {
    return NoshiClassicRemembered(@"well", ^UIImage *{ return NoshiClassicSearchWellMade(); });
}

static UIImage *NoshiClassicSearchWellMade(void) {
    BOOL dark = NoshiThemeIsDark();
    CGFloat side = 30, rim = 1;
    /* one point wider than the two caps, so the middle has a column to stretch */
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side + 1, side), NO, 0);
    CGRect pill = CGRectMake(0, 0, side + 1, side - rim);
    CGFloat radius = (side - rim) / 2;
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:radius];
    [NoshiThemeTinted(dark ? [UIColor colorWithRed:0.07 green:0.11 blue:0.13 alpha:1] : [UIColor colorWithRed:0.89 green:0.89 blue:0.91 alpha:1]) setFill];
    [shape fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius + rim, radius)];
}

/* the text field a search bar keeps inside, which sits one level down on ios 5 and 6 and two on ios 7 and later */
static NSArray *NoshiClassicSearchFieldsIn(UIView *view) {
    NSMutableArray *found = [NSMutableArray array];
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UITextField class]]) [found addObject:child];
        else [found addObjectsFromArray:NoshiClassicSearchFieldsIn(child)];
    }
    return found;
}

void NoshiClassicStyleSearchBar(UISearchBar *bar) {
    bar.barStyle = UIBarStyleBlack;
    NoshiClassicTintBar(bar);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    UIImage *clear = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    bar.backgroundImage = clear;
    [bar setSearchFieldBackgroundImage:NoshiClassicSearchWell() forState:UIControlStateNormal];
    /* the word sat high in the pill of the custom image; the field of the bar puts its line on the middle when it is asked to */
    for (UIView *view in NoshiClassicSearchFieldsIn(bar)) {
        UITextField *field = (UITextField *)view;
        field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        /* the field of the system is black on white; the pill of the dark themes is dark, so the typed words and the placeholder are white on it */
        if (NoshiThemeIsDark()) {
            field.textColor = [UIColor whiteColor];
            if (field.placeholder.length && [field respondsToSelector:@selector(setAttributedPlaceholder:)]) {
                NSDictionary *look = [NSDictionary dictionaryWithObject:[UIColor colorWithWhite:1 alpha:0.6] forKey:@"NSColor"];
                [field setValue:[[[NSAttributedString alloc] initWithString:field.placeholder attributes:look] autorelease] forKey:@"attributedPlaceholder"];
            }
        }
    }
    /* the pill of the image has a clear point under it, which the field counts in its height, so the line sat a point
       or two below the middle of what is seen */
    bar.searchTextPositionAdjustment = UIOffsetMake(0, -3.0f);
}

#define FACADE_WELL_HEIGHT 30.0
#define FACADE_WELL_RIM 1.0
#define FACADE_SIDE 8.0
#define FACADE_GLASS 14.0

/* the pill, the glass and the word, laid out by this view alone */
@interface NoshiClassicSearchFacadeView : UIView {
    UIImageView *_well;
    UIImageView *_glass;
    UILabel *_label;
}
@end

@implementation NoshiClassicSearchFacadeView


- (id)initWithFrame:(CGRect)frame placeholder:(NSString *)placeholder {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.isAccessibilityElement = NO;
    _well = [[UIImageView alloc] initWithImage:NoshiClassicSearchWell()];
    [self addSubview:_well];
    UIColor *ink = NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.82] : [UIColor colorWithWhite:0.42 alpha:1];
    _glass = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, FACADE_GLASS, ink)];
    [self addSubview:_glass];
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.font = [UIFont systemFontOfSize:15];
    _label.textColor = ink;
    _label.text = placeholder;
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_well release];
    [_glass release];
    [_label release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* a clear point lies under the pill, so the pill proper is the well without its last point, and the word stands on the middle of that */
    CGFloat top = floor((size.height - FACADE_WELL_HEIGHT) / 2);
    _well.frame = CGRectMake(FACADE_SIDE, top, MAX(0, size.width - 2 * FACADE_SIDE), FACADE_WELL_HEIGHT);
    CGFloat pillHeight = FACADE_WELL_HEIGHT - FACADE_WELL_RIM;
    CGFloat left = _well.frame.origin.x + 10;
    _glass.frame = CGRectMake(left, top + floor((pillHeight - _glass.image.size.height) / 2), _glass.image.size.width, _glass.image.size.height);
    CGFloat textX = CGRectGetMaxX(_glass.frame) + 6;
    _label.frame = CGRectMake(textX, top, MAX(0, CGRectGetMaxX(_well.frame) - 10 - textX), pillHeight);
}

@end

UIView *NoshiClassicSearchFacade(CGRect frame, NSString *placeholder) {
    NoshiClassicSearchFacadeView *view = [[[NoshiClassicSearchFacadeView alloc] initWithFrame:frame placeholder:placeholder] autorelease];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return view;
}

/* the text of the pill: one line tall on the middle of the pill, for the typed words, the hint and the clear button alike */
@interface NoshiClassicSearchTextField : UITextField
@end

@implementation NoshiClassicSearchTextField

- (CGRect)lineRectForBounds:(CGRect)bounds {
    CGFloat line = ceil(self.font.lineHeight);
    return CGRectMake(0, floor((bounds.size.height - line) / 2), MAX(0, bounds.size.width - 22), line);
}

- (CGRect)textRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }
- (CGRect)editingRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }
- (CGRect)placeholderRectForBounds:(CGRect)bounds { return [self lineRectForBounds:bounds]; }

- (CGRect)clearButtonRectForBounds:(CGRect)bounds {
    return CGRectMake(bounds.size.width - 22, floor((bounds.size.height - 22) / 2), 22, 22);
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [[self.textColor colorWithAlphaComponent:0.6] set];
    NoshiDrawStringIn(self.placeholder, self.font, rect, NoshiStringTailTruncate, NoshiTextAlignmentLeft);
}

@end

@implementation NoshiClassicSearchInput

@synthesize changeHandler = _changeHandler;

- (id)initWithFrame:(CGRect)frame placeholder:(NSString *)placeholder {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _well = [[UIImageView alloc] initWithImage:NoshiClassicSearchWell()];
    [self addSubview:_well];
    UIColor *ink = NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.82] : [UIColor colorWithWhite:0.42 alpha:1];
    _glass = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, FACADE_GLASS, ink)];
    [self addSubview:_glass];
    _field = [[NoshiClassicSearchTextField alloc] init];
    _field.backgroundColor = [UIColor clearColor];
    _field.borderStyle = UITextBorderStyleNone;
    _field.font = [UIFont systemFontOfSize:15];
    _field.textColor = NoshiThemeIsDark() ? [UIColor whiteColor] : [UIColor colorWithWhite:0.12 alpha:1];
    _field.placeholder = placeholder;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.returnKeyType = UIReturnKeySearch;
    _field.enablesReturnKeyAutomatically = YES;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.delegate = self;
    [_field addTarget:self action:@selector(edited) forControlEvents:UIControlEventEditingChanged];
    [self addSubview:_field];
    return self;
}

- (void)dealloc {
    _field.delegate = nil;
    [_well release];
    [_glass release];
    [_field release];
    [_changeHandler release];
    [super dealloc];
}

- (NSString *)text { return _field.text; }

- (void)setText:(NSString *)text {
    _field.text = text;
}

- (BOOL)becomeFirstResponder { return [_field becomeFirstResponder]; }
- (BOOL)resignFirstResponder { return [_field resignFirstResponder]; }

- (void)edited {
    if (_changeHandler) _changeHandler(_field.text);
}

- (BOOL)textFieldShouldClear:(UITextField *)field {
    field.text = @"";
    [self edited];
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat top = floor((size.height - FACADE_WELL_HEIGHT) / 2);
    _well.frame = CGRectMake(FACADE_SIDE, top, MAX(0, size.width - 2 * FACADE_SIDE), FACADE_WELL_HEIGHT);
    /* a clear point lies under the pill, so the line is centered on the pill without it */
    CGFloat pillHeight = FACADE_WELL_HEIGHT - FACADE_WELL_RIM;
    _glass.frame = CGRectMake(FACADE_SIDE + 10, top + floor((pillHeight - _glass.image.size.height) / 2), _glass.image.size.width, _glass.image.size.height);
    CGFloat fieldX = CGRectGetMaxX(_glass.frame) + 6;
    _field.frame = CGRectMake(fieldX, top, MAX(0, CGRectGetMaxX(_well.frame) - 8 - fieldX), pillHeight);
}

@end

void NoshiClassicStyleSegmented(UISegmentedControl *control) {
    /* the segments sit on the light bars, so they take the accent as the buttons beside them do */
    control.tintColor = NoshiColorAccent();
}

static CGFloat NoshiClassicRealTabBarHeight = 0;

void NoshiClassicNoteTabBarHeight(CGFloat height) {
    if (height > 0) NoshiClassicRealTabBarHeight = height;
}

CGFloat NoshiClassicTabBarHeight(void) {
    if (NoshiClassicRealTabBarHeight > 0) return NoshiClassicRealTabBarHeight;
    static CGFloat height = 0;
    if (height <= 0) {
        UITabBar *bar = [[UITabBar alloc] init];
        height = ceil([bar sizeThatFits:CGSizeZero].height);
        [bar release];
        if (height <= 0) height = 49;
    }
    return height;
}

/* the bottom bar of telegram for ios of the 2014 to 2018 years: flat and light (dark at night), a hairline on top, grey pictures and the
   accent on the chosen one */
static UIColor *NoshiTabBarGround(void) { return NoshiThemeIsDark() ? [UIColor colorWithRed:0.11 green:0.11 blue:0.114 alpha:1] : [UIColor colorWithRed:0.969 green:0.969 blue:0.969 alpha:1]; }
UIColor *NoshiTabBarRestingColor(void) { return NoshiThemeIsDark() ? [UIColor colorWithRed:0.5 green:0.5 blue:0.52 alpha:1] : [UIColor colorWithRed:0.573 green:0.573 blue:0.573 alpha:1]; }

void NoshiClassicStyleTabBar(UITabBar *bar) {
    [bar setValue:NoshiTabBarGround() forKey:@"barTintColor"];
    [bar setValue:NoshiColorAccent() forKey:@"tintColor"];
    [bar setValue:[NSNumber numberWithBool:NO] forKey:@"translucent"];
}

UITableViewCellSeparatorStyle NoshiClassicListSeparatorStyle(BOOL hasRows) {
    if (!hasRows) return UITableViewCellSeparatorStyleNone;
    return NoshiClassicSeparators() ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
}

void NoshiClassicStyleTable(UITableView *table) {
    if (![table.backgroundView isKindOfClass:[NoshiWaveBackgroundView class]]) {
        NoshiWaveBackgroundView *background = [[[NoshiWaveBackgroundView alloc] initWithFrame:table.bounds] autorelease];
        background.plain = YES;
        background.userInteractionEnabled = YES;
        table.backgroundView = background;
    }
    /* the lines the person chose in the customization; the thin line is what each page had before, so it is left to the code below */
    if (NoshiClassicSeparators() != 0) table.separatorStyle = NoshiClassicListSeparatorStyle(YES);
    if (!NoshiThemeIsDark()) return;
    table.backgroundColor = NoshiColorScreen();
    /* a single faint line sits quietly between the dark rows and along the edge of each card */
    if (NoshiClassicSeparators() == 0) table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    table.separatorColor = [UIColor colorWithWhite:1 alpha:0.055];
}

CGFloat NoshiClassicGroupedTextInset(CGFloat width) {
    if ([UITableView instancesRespondToSelector:@selector(setSeparatorInset:)]) return 10;
    if (width <= 400) return 20;
    return MAX(31, MIN(45, floor(width * 0.06f))) + 10;
}

@interface NoshiClassicGroupedHeaderView : UIView {
    UILabel *_label;
}
- (id)initWithText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color;
@end

@implementation NoshiClassicGroupedHeaderView
- (id)initWithText:(NSString *)text frame:(CGRect)frame color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = color;
    /* the small capitals of the grouped lists of ios 7 */
    _label.font = [UIFont systemFontOfSize:13];
    _label.numberOfLines = 0;
    _label.text = [text uppercaseString];
    [self addSubview:_label];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat edge = NoshiClassicGroupedTextInset(self.bounds.size.width);
    _label.frame = CGRectMake(edge, 0, MAX(0, self.bounds.size.width - 2 * edge), self.bounds.size.height);
}
- (void)dealloc {
    [_label release];
    [super dealloc];
}
@end

UIView *NoshiClassicGroupedHeader(NSString *text, CGFloat width, CGFloat height, UIColor *color) {
    return [[[NoshiClassicGroupedHeaderView alloc] initWithText:text frame:CGRectMake(0, 0, width, height) color:color] autorelease];
}

@interface NoshiClassicGroupedFooterView : UIView {
    UILabel *_label;
}
- (id)initWithText:(NSString *)text frame:(CGRect)frame;
@end

@implementation NoshiClassicGroupedFooterView
- (id)initWithText:(NSString *)text frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = NoshiColorSecondary();
    _label.font = [UIFont systemFontOfSize:14];
    _label.numberOfLines = 0;
    _label.text = text;
    [self addSubview:_label];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat edge = NoshiClassicGroupedTextInset(self.bounds.size.width);
    _label.frame = CGRectMake(edge, 6, MAX(0, self.bounds.size.width - 2 * edge), MAX(0, self.bounds.size.height - 12));
}
- (void)dealloc { [_label release]; [super dealloc]; }
@end

UIView *NoshiClassicGroupedFooter(NSString *text, CGFloat width, CGFloat height) {
    return [[[NoshiClassicGroupedFooterView alloc] initWithText:text frame:CGRectMake(0, 0, width, height)] autorelease];
}

UIColor *NoshiClassicSelectionColor(void) {
    return NoshiMixedColor(NoshiColorField(), NoshiColorAccent(), NoshiThemeIsDark() ? 0.24 : 0.18);
}

void NoshiClassicStyleCell(UITableViewCell *cell) {
    if (!NoshiThemeIsDark()) return;
    cell.backgroundColor = NoshiColorCard();
    cell.textLabel.textColor = NoshiColorTitle();
    cell.detailTextLabel.textColor = NoshiColorSecondary();
}

void NoshiClassicStyleTabItem(UITabBarItem *item, NoshiTabIcon icon) {
    UIColor *resting = NoshiTabBarRestingColor(), *chosen = NoshiColorAccent();
    UIFont *font = [UIFont systemFontOfSize:10];
    NSDictionary *restingText = [NSDictionary dictionaryWithObjectsAndKeys:resting, UITextAttributeTextColor, font, UITextAttributeFont,
                                 [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    NSDictionary *chosenText = [NSDictionary dictionaryWithObjectsAndKeys:chosen, UITextAttributeTextColor, font, UITextAttributeFont,
                                [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    [item setTitleTextAttributes:restingText forState:UIControlStateNormal];
    [item setTitleTextAttributes:chosenText forState:UIControlStateSelected];
    /* both pictures carry their own color, so the system does not grey them */
    if ([item respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) {
        [item setFinishedSelectedImage:NoshiTabIconImage(icon, chosen) withFinishedUnselectedImage:NoshiTabIconImage(icon, resting)];
    }
}

static UIImage *NoshiClassicRoundImageMade(NoshiSymbol symbol, CGFloat side, BOOL pressed, BOOL red);

static UIImage *NoshiClassicRoundImage(NoshiSymbol symbol, CGFloat side, BOOL pressed, BOOL red) {
    NSString *key = [NSString stringWithFormat:@"round|%d|%.1f|%d|%d", (int)symbol, side, pressed, red];
    return NoshiClassicRemembered(key, ^UIImage *{ return NoshiClassicRoundImageMade(symbol, side, pressed, red); });
}

/* a round key of telegram for ios 4: a flat circle in the accent (or red) with a white glyph, a little deeper while pressed */
static UIImage *NoshiClassicRoundImageMade(NoshiSymbol symbol, CGFloat side, BOOL pressed, BOOL red) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    UIColor *fill = red ? NoshiColorBadgeRed() : NoshiColorAccent();
    if (pressed) fill = NoshiMixedColor(fill, [UIColor blackColor], 0.2);
    [fill setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    CGFloat glyphSide = symbol == NoshiSymbolSendArrow ? side * 0.5 : side * 0.58;
    UIImage *glyph = NoshiSymbolImage(symbol, glyphSide, [UIColor whiteColor]);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the key that takes a chat down to its newest message, as telegram for ios 4 had it: a white circle with a grey rim and a grey arrow (dark at night) */
UIImage *NoshiFlatDownButtonImage(CGFloat side, BOOL pressed) {
    BOOL dark = NoshiThemeIsDark();
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGRect ring = CGRectMake(0.5f, 0.5f, side - 1, side - 1);
    UIColor *fill = dark ? [UIColor colorWithWhite:0.16 alpha:1] : [UIColor whiteColor];
    if (pressed) fill = NoshiMixedColor(fill, dark ? [UIColor whiteColor] : [UIColor blackColor], 0.08);
    [fill setFill];
    [[UIBezierPath bezierPathWithOvalInRect:ring] fill];
    [(dark ? [UIColor colorWithWhite:0.3 alpha:1] : [UIColor colorWithWhite:0.82 alpha:1]) setStroke];
    UIBezierPath *rim = [UIBezierPath bezierPathWithOvalInRect:ring];
    rim.lineWidth = 1;
    [rim stroke];
    UIImage *glyph = NoshiSymbolImage(NoshiSymbolArrowDown, side * 0.5f, dark ? [UIColor colorWithWhite:0.7 alpha:1] : [UIColor colorWithWhite:0.55 alpha:1]);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the back arrow of the bars of ios 7: a chevron of two strokes, drawn in black for the bar to tint */
UIImage *NoshiBackChevronImage(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(13, 22), NO, 0);
    UIBezierPath *chevron = [UIBezierPath bezierPath];
    [chevron moveToPoint:CGPointMake(11, 1.5f)];
    [chevron addLineToPoint:CGPointMake(2, 11)];
    [chevron addLineToPoint:CGPointMake(11, 20.5f)];
    chevron.lineWidth = 3;
    chevron.lineCapStyle = kCGLineCapRound;
    chevron.lineJoinStyle = kCGLineJoinRound;
    [[UIColor blackColor] setStroke];
    [chevron stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIImage *NoshiClassicRoundButtonImage(NoshiSymbol symbol, CGFloat side, BOOL pressed) {
    return NoshiClassicRoundImage(symbol, side, pressed, NO);
}

UIImage *NoshiClassicRedRoundButtonImage(NoshiSymbol symbol, CGFloat side, BOOL pressed) {
    return NoshiClassicRoundImage(symbol, side, pressed, YES);
}

UIImage *NoshiClassicProfileTabImage(UIImage *photo) {
    CGSize size = CGSizeMake(30, 30);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    /* a profile photo comes as a jpeg, so a round picture arrives with white corners; a circle clip, as the modern tab has, takes them off */
    UIBezierPath *shape = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size.width, size.height)];
    CGContextSaveGState(context);
    [shape addClip];
    [photo drawInRect:CGRectMake(0, 0, size.width, size.height)];
    CGContextRestoreGState(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIView *NoshiClassicTitleView(NSString *title, NSString *subtitle) {
    return NoshiClassicTitleViewWithStatus(title, subtitle, 0);
}

UIView *NoshiClassicTitleViewWithStatus(NSString *title, NSString *subtitle, int kind) {
    /* a tablet's bar has the room for a long name, and the 190 points of a phone cut it and its emoji short */
    return NoshiClassicTitleViewWithStatusWidth(title, subtitle, kind, NoshiIsPad() ? 420 : 190);
}

UIView *NoshiClassicTitleViewWithStatusWidth(NSString *title, NSString *subtitle, int kind, CGFloat titleWidth) {
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, titleWidth, 44)] autorelease];
    view.backgroundColor = [UIColor clearColor];
    BOOL hasSubtitle = subtitle.length > 0;
    /* the title is a chat name, so its emoji come from the app's pictures; an old system font shows boxes for the newer ones */
    NoshiEmojiLabel *top = [[[NoshiEmojiLabel alloc] initWithFrame:CGRectMake(0, hasSubtitle ? 3 : 0, titleWidth, hasSubtitle ? 24 : 44)] autorelease];
    /* the system font of an old bar lacks the letters of a styled nick, and the bundled fallback shows them as boxes with a code in them: they are left out, as in every other name */
    top.dropsUndrawable = YES;
    top.text = title;
    top.textAlignment = NoshiTextAlignmentCenter;
    top.font = [UIFont boldSystemFontOfSize:hasSubtitle ? 17 : 20];
    top.textColor = NoshiColorTitle();
    top.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [view addSubview:top];
    if (hasSubtitle) {
        NoshiStatusLabel *bottom = [[[NoshiStatusLabel alloc] initWithFrame:CGRectMake(0, 25, titleWidth, 16)] autorelease];
        bottom.textAlignment = NoshiTextAlignmentCenter;
        bottom.backgroundColor = [UIColor clearColor];
        bottom.font = [UIFont systemFontOfSize:12];
        bottom.plainColor = NoshiColorSecondary();
        bottom.activeColor = NoshiColorAccent();
        [bottom setStatus:subtitle kind:(NoshiStatusKind)kind];
        bottom.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [view addSubview:bottom];
    }
    return view;
}

/* the count of the other unread chats beside the back arrow: the flat capsule of the list in the accent */
UIView *NoshiClassicCounterBadge(NSString *text) {
    return NoshiClassicBadge(text, NO);
}

/* the count of a row: a capsule in the accent, drawn as a stretched picture under the text. a layer with a corner radius and a mask is drawn off screen at every frame of a scroll, and a
   list has one of these on every row that has unread messages */
@interface NoshiClassicBadgeLabel : UILabel {
    BOOL _muted;
    BOOL _alert;
}
@property (nonatomic, assign) BOOL muted;
/* the red of the counts on the bottom bar of telegram, in place of the accent of the list */
@property (nonatomic, assign) BOOL alert;
@end

@implementation NoshiClassicBadgeLabel
@synthesize muted = _muted;
@synthesize alert = _alert;
- (void)drawRect:(CGRect)rect {
    UIColor *color = _muted ? [UIColor colorWithRed:0.62 green:0.66 blue:0.71 alpha:1] : (_alert ? NoshiColorBadgeRed() : NoshiColorAccent());
    NSString *key = [NSString stringWithFormat:@"badge|%d|%d", _muted, _alert];
    UIImage *capsule = NoshiClassicRemembered(key, ^UIImage *{
        /* one point of stretch between the caps: with none, ios 6 leaves a seam down the middle of the capsule */
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(23, 22), NO, 0);
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 23, 22) cornerRadius:11] fill];
        UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [made resizableImageWithCapInsets:UIEdgeInsetsMake(0, 11, 0, 11)];
    });
    [capsule drawInRect:self.bounds];
    [super drawRect:rect];
}
@end

UILabel *NoshiClassicBadge(NSString *text, BOOL muted) {
    UIFont *font = [UIFont boldSystemFontOfSize:13];
    CGFloat width = MAX(22, ceil(NoshiStringSize(text, font).width) + 14);
    NoshiClassicBadgeLabel *label = [[[NoshiClassicBadgeLabel alloc] initWithFrame:CGRectMake(0, 0, width, 22)] autorelease];
    label.muted = muted;
    label.text = text;
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NoshiTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    label.opaque = NO;
    return label;
}

UILabel *NoshiClassicAlertBadge(NSString *text) {
    NoshiClassicBadgeLabel *label = (NoshiClassicBadgeLabel *)NoshiClassicBadge(text, NO);
    label.alert = YES;
    return label;
}

/* one image for the keys and plates: a rounded rect in one color, stretched from its middle */
static UIImage *NoshiClassicFlatImage(UIColor *color, CGFloat radius) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&a];
        r = g = b = white;
    }
    NSString *key = [NSString stringWithFormat:@"flat|%.1f|%.3f|%.3f|%.3f|%.3f", radius, r, g, b, a];
    return NoshiClassicRemembered(key, ^UIImage *{
        CGFloat side = radius * 2 + 4;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:radius] fill];
        UIImage *flat = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [flat resizableImageWithCapInsets:UIEdgeInsetsMake(radius + 1, radius + 1, radius + 1, radius + 1)];
    });
}

static UIColor *NoshiClassicDimmed(UIColor *color, CGFloat dim) {
    return dim >= 1 ? color : NoshiMixedColor(color, [UIColor blackColor], 1 - dim);
}

UIImage *NoshiClassicKeyImage(NoshiClassicKeyColor color, BOOL pressed) {
    CGFloat dim = pressed ? 0.78 : 1;
    if (color == NoshiClassicKeyAccent) return NoshiClassicTintedKeyImage(NoshiColorAccent(), 8, pressed);
    UIColor *fill;
    if (color == NoshiClassicKeyGreen) fill = [UIColor colorWithRed:0.30 green:0.62 blue:0.20 alpha:1];
    else if (color == NoshiClassicKeyAmber) fill = [UIColor colorWithRed:0.97 green:0.70 blue:0.20 alpha:1];
    else fill = [UIColor colorWithRed:0.80 green:0.18 blue:0.14 alpha:1];
    return NoshiClassicFlatImage(NoshiClassicDimmed(fill, dim), 8);
}

UIImage *NoshiClassicPlateImage(void) {
    return NoshiClassicFlatImage(NoshiColorCard(), 12);
}

void NoshiClassicApplyMenuPlate(UIView *view, CGFloat radius) {
    BOOL charcoal = NoshiThemeIsDark();
    view.layer.cornerRadius = radius;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = charcoal ? 0.6 : 0.35;
    view.layer.shadowRadius = 10;
    view.layer.shadowOffset = CGSizeMake(0, 4);
    /* a flat plate, pale grey or charcoal, in a layer of its own so that a view with a color of its own keeps it */
    CALayer *plate = [CALayer layer];
    plate.backgroundColor = (charcoal ? [UIColor colorWithRed:0.18 green:0.18 blue:0.21 alpha:1] : [UIColor colorWithRed:0.97 green:0.97 blue:0.98 alpha:1]).CGColor;
    plate.cornerRadius = radius;
    plate.name = @"plate";
    plate.frame = view.bounds;
    [view.layer insertSublayer:plate atIndex:0];
    NoshiClassicFitPlate(view, 0);
}

void NoshiClassicFitPlate(UIView *view, CGFloat bleed) {
    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"plate"]) layer.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height + bleed);
    }
    CGPathRef path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:view.layer.cornerRadius].CGPath;
    if (!view.layer.shadowPath || !CGPathEqualToPath(view.layer.shadowPath, path)) view.layer.shadowPath = path;
    [CATransaction commit];
}

UIColor *NoshiClassicMenuTextColor(void) {
    return NoshiThemeIsDark() ? [UIColor whiteColor] : NoshiColorTitle();
}

UIColor *NoshiClassicMenuRedColor(void) {
    return NoshiThemeIsDark() ? [UIColor colorWithRed:1 green:0.45 blue:0.40 alpha:1] : NoshiColorBadgeRed();
}

UIColor *NoshiClassicMenuPressColor(void) {
    return NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.14] : [UIColor colorWithWhite:0 alpha:0.08];
}

void NoshiClassicStyleMenuLabel(UILabel *label, CGFloat size) {
    label.font = [UIFont boldSystemFontOfSize:size];
    label.shadowColor = nil;
}

/* the text box of telegram for ios 4: white with a grey rim on the light bar, a dark grey box with a darker rim at night; opaque since the emoji of the text are drawn over it */
UIColor *NoshiClassicInputFill(void) {
    return NoshiThemeIsDark() ? [UIColor colorWithWhite:0.16 alpha:1] : [UIColor whiteColor];
}

UIColor *NoshiClassicInputRim(void) {
    return NoshiThemeIsDark() ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithRed:0.78 green:0.78 blue:0.8 alpha:1];
}

UIImage *NoshiClassicTintedKeyImage(UIColor *base, CGFloat radius, BOOL pressed) {
    return NoshiClassicFlatImage(NoshiClassicDimmed(base, pressed ? 0.8 : 1), radius);
}

UIImage *NoshiClassicGroundKeyImage(UIColor *ground, BOOL pressed) {
    return NoshiClassicFlatImage(NoshiClassicDimmed(ground, pressed ? 0.78 : 1), 8);
}

UIColor *NoshiClassicStripGround(void) {
    /* a dark grey or white with a little of the accent in it, so the strips read as part of the theme and not as holes: the first version was near black */
    BOOL dark = NoshiThemeIsDark();
    return NoshiMixedColor(dark ? [UIColor colorWithWhite:0.17 alpha:1] : [UIColor whiteColor], NoshiColorAccent(), dark ? 0.16 : 0.07);
}
UIColor *NoshiClassicStripInk(void) { return NoshiThemeIsDark() ? [UIColor whiteColor] : [UIColor colorWithWhite:0.1 alpha:1]; }
UIColor *NoshiClassicStripEdge(void) { return NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.16] : [UIColor colorWithWhite:0 alpha:0.22]; }

UIImageView *NoshiClassicStripBackdrop(void) {
    /* the flat ground of the bars of telegram for ios 4; the strips draw their own hairlines where they need them */
    UIImageView *view = [[[UIImageView alloc] initWithImage:nil] autorelease];
    view.backgroundColor = NoshiTabBarGround();
    view.contentMode = UIViewContentModeScaleToFill;
    view.userInteractionEnabled = NO;
    return view;
}

/* a color disc as the thumbs of ios 7 draw it: the face in a white ring with a hairline round it */
UIImage *NoshiClassicColorDisc(UIColor *color, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGRect outer = CGRectMake(0.5, 0.5, side - 1, side - 1);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:outer] fill];
    [[UIColor colorWithWhite:0 alpha:0.2] setStroke];
    [[UIBezierPath bezierPathWithOvalInRect:outer] stroke];
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectInset(outer, side * 0.1, side * 0.1)] fill];
    UIImage *disc = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return disc;
}

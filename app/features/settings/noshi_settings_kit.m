#import "noshi_settings_kit.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_chat_settings.h"
#import "noshi_classic_chrome.h"
#import "noshi_expressive_slider.h"
#import "noshi_emoji_label.h"
#import "noshi_message.h"
#import "noshi_platform.h"
#import "noshi_split_controller.h"
#import "noshi_sheet.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#import "noshi_wave_background_view.h"

#define BAR_HEIGHT 56.0
#define CARD_INSET 12.0
/* the corner of a card is the one the person chose in the look of the app */
#define CARD_RADIUS NoshiSectionRadius()
#define INNER_RADIUS 6.0
#define ROW_GAP 2.0
#define ICON_PAD 18.0
#define TILE 36.0
/* the side of the face picture of a people row, as noshi_people_avatars.m draws it */
#define CLASSIC_FACE 48.0
#define TRAILING_SIDE 34.0
#define SESSION_ICON 42.0

#pragma mark tones

static UIColor *NoshiToneRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/* IconBackgroundColors, top and bottom */
static void NoshiToneEnds(NoshiSettingsTone tone, uint32_t *top, uint32_t *bottom) {
    static const uint32_t table[][2] = {
        {0x1CA5ED, 0x1488E1}, {0x4F85F6, 0x3568E8}, {0x1BA4ED, 0x1488E1}, {0xF09F1B, 0xE18A11}, {0xEFA612, 0xE77512},
        {0xF28B31, 0xE26314}, {0x55CA47, 0x27B434}, {0xF45255, 0xDF3955}, {0x32C0CE, 0x1D9CC6}, {0xC46EF4, 0x9F55DF}, {0x8699AA, 0x6E8397}, {0x2C2C30, 0x1C1C20}, {0xCDB8F5, 0xB59DEB}
    };
    *top = table[tone][0];
    *bottom = table[tone][1];
}

static UIColor *NoshiMix(UIColor *color, CGFloat white, CGFloat amount) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:r + (white - r) * amount green:g + (white - g) * amount blue:b + (white - b) * amount alpha:1];
}

UIImage *NoshiSettingsTileImage(NoshiSymbol symbol, NoshiSettingsTone tone, CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    BOOL dark = NoshiThemeIsDark();
    NSString *key = [NSString stringWithFormat:@"%d/%d/%g/%d", (int)symbol, (int)tone, (double)side, dark];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    uint32_t top, bottom;
    NoshiToneEnds(tone, &top, &bottom);
    UIColor *middle = NoshiMix(NoshiToneRGB(top), 0, 0);
    CGFloat r1 = 0, g1 = 0, b1 = 0, r2 = 0, g2 = 0, b2 = 0, a = 0;
    [NoshiToneRGB(top) getRed:&r1 green:&g1 blue:&b1 alpha:&a];
    [NoshiToneRGB(bottom) getRed:&r2 green:&g2 blue:&b2 alpha:&a];
    middle = [UIColor colorWithRed:(r1 + r2) / 2 green:(g1 + g2) / 2 blue:(b1 + b2) / 2 alpha:1];
    /* a pale disc with a deep glyph: the tonal pair the M3 list takes from the two colors of the tone */
    UIColor *disc = dark ? NoshiMix(middle, 1, 0.56) : NoshiMix(middle, 1, 0.80);
    UIColor *ink = dark ? NoshiMix(middle, 0, 0.42) : NoshiMix(middle, 0, 0.12);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [disc setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    UIImage *glyph = NoshiSymbolImage(symbol, floor(side * 0.62), ink);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

/* the outline of the mark, in the units of the vector: absolute M, L, C and Z commands */
static const char NoshiMarkPath[] =
    "M122.661 123.5L261.364 67.4608C279.286 60.2198 287.945 39.8198 280.704 21.8978C273.463 3.97575 253.064 -4.68325 235.141 2.55775L21.8888 88.7168"
    "C15.0532 91.4785 9.26419 96.3283 5.34756 102.574C1.43092 108.82 -0.413356 116.144 0.0777699 123.5C-0.413356 130.856 1.43092 138.179 5.34756 144.425"
    "C9.26419 150.671 15.0532 155.521 21.8888 158.283L235.141 244.442C253.064 251.683 273.463 243.024 280.704 225.102C287.945 207.179 279.286 186.78 261.364 179.539Z";

/* reads the numbers after a command letter; the path above is fixed text, so a malformed one is a build mistake and ends the walk */
static void NoshiWalkMarkPath(CGMutablePathRef path, CGAffineTransform place) {
    const char *at = NoshiMarkPath;
    char command = 0;
    double v[6];
    while (*at) {
        if (*at == 'M' || *at == 'L' || *at == 'C' || *at == 'Z') command = *at++;
        else break;
        int need = command == 'C' ? 6 : (command == 'Z' ? 0 : 2);
        do {
            for (int i = 0; i < need; ++i) {
                char *end = NULL;
                v[i] = strtod(at, &end);
                if (end == at) return;
                at = end;
            }
            if (command == 'M') CGPathMoveToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1]);
            else if (command == 'L') CGPathAddLineToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1]);
            else if (command == 'C') CGPathAddCurveToPoint(path, &place, (CGFloat)v[0], (CGFloat)v[1], (CGFloat)v[2], (CGFloat)v[3], (CGFloat)v[4], (CGFloat)v[5]);
            else CGPathCloseSubpath(path);
        } while (need && (*at == '-' || *at == '.' || (*at >= '0' && *at <= '9')));
    }
}

UIImage *NoshiSettingsMarkTile(CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSString *key = [NSString stringWithFormat:@"%g", (double)side];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIColor colorWithRed:0x99 / 255.0 green:0x3C / 255.0 blue:0x38 / 255.0 alpha:1] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    /* the vector is 24 units wide, and its group moves the mark by 4.5 and 5.477 and shrinks it by 0.052817 */
    CGFloat unit = side / 24.0;
    CGMutablePathRef path = CGPathCreateMutable();
    NoshiWalkMarkPath(path, CGAffineTransformMake(0.052817 * unit, 0, 0, 0.052817 * unit, 4.5 * unit, 5.477 * unit));
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextAddPath(context, path);
    CGPathRelease(path);
    [[UIColor whiteColor] setFill];
    CGContextFillPath(context);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

#pragma mark devices

/* the avatar colors theme, top and bottom */
static void NoshiDeviceEnds(noshi_session_kind kind, uint32_t *top, uint32_t *bottom) {
    switch (kind) {
    case NOSHI_SESSION_IPHONE:
    case NOSHI_SESSION_IPAD:
    case NOSHI_SESSION_LINUX:
    case NOSHI_SESSION_UBUNTU:
        *top = 0x5CAFFA; *bottom = 0x408ACF; return;
    case NOSHI_SESSION_MAC:
    case NOSHI_SESSION_WINDOWS:
    case NOSHI_SESSION_DESKTOP:
        *top = 0x5BCBE3; *bottom = 0x359AD4; return;
    case NOSHI_SESSION_ANDROID:
    case NOSHI_SESSION_ANDROID_TABLET:
        *top = 0x9AD164; *bottom = 0x46BA43; return;
    default:
        *top = 0xFF8AAC; *bottom = 0xD95574; return;
    }
}

static NoshiSymbol NoshiDeviceGlyph(noshi_session_kind kind) {
    switch (kind) {
    case NOSHI_SESSION_IPHONE: return NoshiSymbolDeviceIphone;
    case NOSHI_SESSION_IPAD: return NoshiSymbolDeviceIpad;
    case NOSHI_SESSION_MAC: return NoshiSymbolDeviceMac;
    case NOSHI_SESSION_WINDOWS: return NoshiSymbolDeviceWindows;
    case NOSHI_SESSION_LINUX:
    case NOSHI_SESSION_UBUNTU:
    case NOSHI_SESSION_DESKTOP: return NoshiSymbolDeviceDesktop;
    case NOSHI_SESSION_ANDROID: return NoshiSymbolDeviceAndroid;
    case NOSHI_SESSION_ANDROID_TABLET: return NoshiSymbolDeviceAndroidTablet;
    case NOSHI_SESSION_CHROME: return NoshiSymbolDeviceChrome;
    case NOSHI_SESSION_SAFARI: return NoshiSymbolDeviceSafari;
    case NOSHI_SESSION_EDGE: return NoshiSymbolDeviceEdge;
    case NOSHI_SESSION_FIREFOX: return NoshiSymbolDeviceFirefox;
    case NOSHI_SESSION_OPERA: return NoshiSymbolDeviceOpera;
    default: return NoshiSymbolDeviceWeb;
    }
}

UIImage *NoshiDeviceIconImage(noshi_session_kind kind, CGFloat side) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    NSString *key = [NSString stringWithFormat:@"%d/%g", (int)kind, (double)side];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    uint32_t top, bottom;
    NoshiDeviceEnds(kind, &top, &bottom);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, side, side));
    CGContextClip(context);
    CGFloat r1 = 0, g1 = 0, b1 = 0, r2 = 0, g2 = 0, b2 = 0, a = 0;
    [NoshiToneRGB(top) getRed:&r1 green:&g1 blue:&b1 alpha:&a];
    [NoshiToneRGB(bottom) getRed:&r2 green:&g2 blue:&b2 alpha:&a];
    CGFloat colors[] = {r1, g1, b1, 1, r2, g2, b2, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, side), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);
    UIImage *glyph = NoshiSymbolImage(NoshiDeviceGlyph(kind), floor(side * 0.62), [UIColor whiteColor]);
    [glyph drawAtPoint:CGPointMake((side - glyph.size.width) / 2, (side - glyph.size.height) / 2)];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

UIColor *NoshiDeviceColor(noshi_session_kind kind) {
    switch (kind) {
    case NOSHI_SESSION_FIREFOX: return NoshiToneRGB(0xFF845E);
    case NOSHI_SESSION_IPHONE:
    case NOSHI_SESSION_IPAD:
    case NOSHI_SESSION_LINUX:
    case NOSHI_SESSION_UBUNTU: return NoshiToneRGB(0x5CAFFA);
    case NOSHI_SESSION_MAC:
    case NOSHI_SESSION_WINDOWS:
    case NOSHI_SESSION_DESKTOP: return NoshiToneRGB(0x5BCBE3);
    case NOSHI_SESSION_ANDROID:
    case NOSHI_SESSION_ANDROID_TABLET: return NoshiToneRGB(0x9AD164);
    default: return NoshiToneRGB(0xFF8AAC);
    }
}

NSString *NoshiDeviceAnimationName(noshi_session_kind kind) {
    switch (kind) {
    case NOSHI_SESSION_IPHONE: return @"device_iphone";
    case NOSHI_SESSION_IPAD: return @"device_ipad";
    case NOSHI_SESSION_MAC: return @"device_mac";
    case NOSHI_SESSION_WINDOWS:
    case NOSHI_SESSION_DESKTOP: return @"device_windows";
    case NOSHI_SESSION_LINUX: return @"device_linux";
    case NOSHI_SESSION_UBUNTU: return @"device_ubuntu";
    case NOSHI_SESSION_ANDROID:
    case NOSHI_SESSION_ANDROID_TABLET: return @"device_android";
    case NOSHI_SESSION_CHROME:
    case NOSHI_SESSION_OTHER: return @"device_chrome";
    case NOSHI_SESSION_SAFARI: return @"device_safari";
    case NOSHI_SESSION_EDGE: return @"device_edge";
    case NOSHI_SESSION_FIREFOX: return @"device_firefox";
    default: return nil;
    }
}

#pragma mark models

@implementation NoshiSettingsRow

@synthesize hasSymbol = _hasSymbol;
@synthesize symbol = _symbol;
@synthesize tone = _tone;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize value = _value;
@synthesize valueIsEmoji = _valueIsEmoji;
@synthesize valueEmojiDocument = _valueEmojiDocument;
@synthesize line3 = _line3;
@synthesize picture = _picture;
@synthesize tileImage = _tileImage;
@synthesize trailingImage = _trailingImage;
@synthesize trailingImageUnclipped = _trailingImageUnclipped;
@synthesize customView = _customView;
@synthesize customHeight = _customHeight;
@synthesize bold = _bold;
@synthesize destructive = _destructive;
@synthesize hasSwitch = _hasSwitch;
@synthesize on = _on;
@synthesize accentLine3 = _accentLine3;
@synthesize checked = _checked;
@synthesize disabled = _disabled;
@synthesize hasLevel = _hasLevel;
@synthesize leftCaption = _leftCaption;
@synthesize rightCaption = _rightCaption;
@synthesize describe = _describe;
@synthesize hasSlider = _hasSlider;
@synthesize sliderValue = _sliderValue;
@synthesize sliderMinimum = _sliderMinimum;
@synthesize sliderMaximum = _sliderMaximum;
@synthesize sliderFormat = _sliderFormat;
@synthesize tap = _tap;
@synthesize remove = _remove;
@synthesize removed = _removed;
@synthesize removesSection = _removesSection;
@synthesize toggle = _toggle;
@synthesize slide = _slide;
@synthesize slideEnded = _slideEnded;

- (void)dealloc {
    [_describe release];
    [_leftCaption release];
    [_rightCaption release];
    [_sliderFormat release];
    [_slide release];
    [_slideEnded release];
    [_title release];
    [_subtitle release];
    [_value release];
    [_line3 release];
    [_picture release];
    [_tileImage release];
    [_trailingImage release];
    [_customView release];
    [_customHeight release];
    [_tap release];
    [_remove release];
    [_removed release];
    [_toggle release];
    [super dealloc];
}

- (BOOL)isSession { return _picture != nil; }

+ (NoshiSettingsRow *)rowWithSymbol:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle
                                value:(NSString *)value tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_tone = tone;
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_value = [value copy];
    row->_tap = [tap copy];
    return row;
}

+ (NoshiSettingsRow *)rowWithTileImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_tileImage = [image retain];
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_tap = [tap copy];
    return row;
}

+ (NoshiSettingsRow *)rowWithTitle:(NSString *)title value:(NSString *)value tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_value = [value copy];
    row->_tap = [tap copy];
    return row;
}

+ (NoshiSettingsRow *)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(NSString *)value tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTitle:title value:value tap:tap];
    row->_subtitle = [subtitle copy];
    return row;
}

+ (NoshiSettingsRow *)checkRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle checked:(BOOL)checked tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTitle:title subtitle:subtitle value:nil tap:tap];
    row->_checked = checked;
    return row;
}

+ (NoshiSettingsRow *)sliderRowWithTitle:(NSString *)title format:(NSString *)format value:(float)value minimum:(float)minimum maximum:(float)maximum
                                    change:(void (^)(float))change {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_sliderFormat = [format copy];
    row->_value = [[NSString stringWithFormat:format, (double)value] copy];
    row->_hasSlider = YES;
    row->_sliderValue = value;
    row->_sliderMinimum = minimum;
    row->_sliderMaximum = maximum;
    row->_slide = [change copy];
    return row;
}

+ (NoshiSettingsRow *)viewRowWithView:(UIView *)view height:(CGFloat (^)(CGFloat))height {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_customView = [view retain];
    row->_customHeight = [height copy];
    return row;
}

+ (NoshiSettingsRow *)levelRowWithTitle:(NSString *)title leftCaption:(NSString *)left rightCaption:(NSString *)right percent:(int)percent
                                  describe:(NSDictionary *(^)(int))describe change:(void (^)(int))change {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_leftCaption = [left copy];
    row->_rightCaption = [right copy];
    row->_hasLevel = YES;
    row->_hasSlider = YES;
    row->_sliderValue = (float)percent;
    row->_sliderMinimum = 0;
    row->_sliderMaximum = 100;
    row->_describe = [describe copy];
    void (^report)(int) = [change copy];
    row->_slide = [^(float value) { report((int)(value + 0.5f)); } copy];
    [report release];
    return row;
}

+ (NoshiSettingsRow *)switchRowWithSymbol:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone title:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on
                                     toggle:(void (^)(BOOL))toggle {
    NoshiSettingsRow *row = [NoshiSettingsRow switchRowWithTitle:title subtitle:subtitle on:on toggle:toggle];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_tone = tone;
    return row;
}

+ (NoshiSettingsRow *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on toggle:(void (^)(BOOL))toggle {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_title = [title copy];
    row->_subtitle = [subtitle copy];
    row->_hasSwitch = YES;
    row->_on = on;
    row->_toggle = [toggle copy];
    return row;
}

+ (NoshiSettingsRow *)actionRowWithSymbol:(NoshiSymbol)symbol title:(NSString *)title destructive:(BOOL)destructive tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_hasSymbol = YES;
    row->_symbol = symbol;
    row->_title = [title copy];
    row->_destructive = destructive;
    row->_tap = [tap copy];
    return row;
}

+ (NoshiSettingsRow *)sessionRowWithPicture:(UIImage *)picture title:(NSString *)title line2:(NSString *)line2 line3:(NSString *)line3 accentLine3:(BOOL)accent
                                          tap:(void (^)(void))tap {
    NoshiSettingsRow *row = [[[NoshiSettingsRow alloc] init] autorelease];
    row->_picture = [picture retain];
    row->_title = [title copy];
    row->_subtitle = [line2 copy];
    row->_line3 = [line3 copy];
    row->_accentLine3 = accent;
    row->_bold = YES;
    row->_tap = [tap copy];
    return row;
}

@end

@implementation NoshiSettingsSection

@synthesize header = _header;
@synthesize footer = _footer;
@synthesize rows = _rows;
@synthesize centerFooter = _centerFooter;

+ (NoshiSettingsSection *)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray *)rows {
    NoshiSettingsSection *section = [[[NoshiSettingsSection alloc] init] autorelease];
    section->_header = [header copy];
    section->_footer = [footer copy];
    section->_rows = [rows retain];
    return section;
}

- (void)dealloc {
    [_header release];
    [_footer release];
    [_rows release];
    [super dealloc];
}

@end

#pragma mark cell

typedef enum { NoshiRowPlaceOnly, NoshiRowPlaceFirst, NoshiRowPlaceMiddle, NoshiRowPlaceLast } NoshiRowPlace;

static UIFont *NoshiRowTitleFont(NoshiSettingsRow *row) {
    return row.bold ? NoshiFontBold(15) : NoshiFontRegular(16);
}

/* the width of the system switch, which the cell lays the text out beside; 94 points before ios 7 and 51 from it,
   so a measure that took one number cut every title on the other system to "Запятая после упо…" */
static CGFloat NoshiSwitchWidth(void) {
    static CGFloat width;
    if (width == 0) {
        UISwitch *probe = [[UISwitch alloc] init];
        width = probe.frame.size.width;
        [probe release];
    }
    return width;
}

/* the width the text of a row may take: what is left of the card beside the tile, the value and the switch or check */
static CGFloat NoshiRowTextWidth(NoshiSettingsRow *row, CGFloat width) {
    CGFloat left = ICON_PAD;
    if (row.hasSymbol || row.tileImage) left += row.destructive ? 26 + 14 : TILE + 18;
    CGFloat right = ICON_PAD;
    if (row.hasSwitch) right = 16 + NoshiSwitchWidth() + 8;
    else if (row.checked) right = ICON_PAD + 22 + 8;
    else if (row.value.length) right = ICON_PAD + (row.valueIsEmoji ? MIN(34, width * 0.45) : MIN(ceil(NoshiStringSize(row.value, NoshiFontRegular(16)).width) + 4, width * 0.45)) + 8;
    else if (row.trailingImage) right = ICON_PAD + TRAILING_SIDE + 10;
    return MAX(0, width - left - right);
}

/* the height of a text wrapped at a width; the table asks for the height of every row at each reload and a cell
   asks again at each layout of a scroll, so the same few hundred measures repeat */
static CGFloat NoshiWrappedHeight(NSString *text, UIFont *font, CGFloat width) {
    if (!text.length) return 0;
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 600;
    }
    NSString *key = [NSString stringWithFormat:@"%.1f|%@ %.1f|%@", (double)width, font.fontName, (double)font.pointSize, text];
    NSNumber *known = [cache objectForKey:key];
    if (known) return (CGFloat)[known doubleValue];
    CGFloat height = ceil(NoshiStringSizeIn(text, font, CGSizeMake(width, 2000)).height);
    [cache setObject:[NSNumber numberWithDouble:(double)height] forKey:key];
    return height;
}

/* a row lets its title and the line under it wrap for as many lines as they need, since a text cut to "Подписи авт…" says nothing */
static void NoshiRowTextHeights(NoshiSettingsRow *row, CGFloat width, CGFloat *title, CGFloat *subtitle) {
    CGFloat room = NoshiRowTextWidth(row, width);
    *title = NoshiWrappedHeight(row.title, NoshiRowTitleFont(row), room);
    *subtitle = NoshiWrappedHeight(row.subtitle, NoshiFontRegular(13), room);
}

/* a rectangle with one radius on its two upper corners and another on its two lower ones */
static UIBezierPath *NoshiCardPath(CGRect rect, CGFloat top, CGFloat bottom) {
    CGFloat l = CGRectGetMinX(rect), r = CGRectGetMaxX(rect), t = CGRectGetMinY(rect), b = CGRectGetMaxY(rect);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(l + top, t)];
    [path addLineToPoint:CGPointMake(r - top, t)];
    [path addArcWithCenter:CGPointMake(r - top, t + top) radius:top startAngle:(CGFloat)(-M_PI_2) endAngle:0 clockwise:YES];
    [path addLineToPoint:CGPointMake(r, b - bottom)];
    [path addArcWithCenter:CGPointMake(r - bottom, b - bottom) radius:bottom startAngle:0 endAngle:(CGFloat)M_PI_2 clockwise:YES];
    [path addLineToPoint:CGPointMake(l + bottom, b)];
    [path addArcWithCenter:CGPointMake(l + bottom, b - bottom) radius:bottom startAngle:(CGFloat)M_PI_2 endAngle:(CGFloat)M_PI clockwise:YES];
    [path addLineToPoint:CGPointMake(l, t + top)];
    [path addArcWithCenter:CGPointMake(l + top, t + top) radius:top startAngle:(CGFloat)M_PI endAngle:(CGFloat)(M_PI + M_PI_2) clockwise:YES];
    [path closePath];
    return path;
}

/* the card is stretched by CALayer.contentsCenter: ios 6 crashes in _UIImageViewPretiledImageWrapper dealloc when resized UIImageView cards are reused */
static UIImage *NoshiCardImage(CGFloat top, CGFloat bottom) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    UIColor *color = NoshiColorCard();
    NSString *key = [NSString stringWithFormat:@"%g/%g/%@", (double)top, (double)bottom, color];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    CGFloat side = 2 * CARD_RADIUS + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [color setFill];
    [NoshiCardPath(CGRectMake(0, 0, side, side), top, bottom) fill];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

/* the big corners sit on the ends of the card and the small ones on the inner joints, so each row reads as a pill cut from the card */
static void NoshiCardRadii(NoshiRowPlace place, CGFloat *top, CGFloat *bottom) {
    *top = (place == NoshiRowPlaceOnly || place == NoshiRowPlaceFirst) ? CARD_RADIUS : INNER_RADIUS;
    *bottom = (place == NoshiRowPlaceOnly || place == NoshiRowPlaceLast) ? CARD_RADIUS : INNER_RADIUS;
}

@interface NoshiClassicSettingsTable : UITableView
@end

@implementation NoshiClassicSettingsTable
- (void)setContentSize:(CGSize)size {
    /* a wide table header can make grouped settings scroll sideways after an ipad resize */
    if (self.bounds.size.width > 0 && size.width > self.bounds.size.width) size.width = self.bounds.size.width;
    [super setContentSize:size];
}
@end

/* the cell of a row that holds a view of its own (a preview, a list of cards) */
@interface NoshiSettingsViewCell : UITableViewCell {
    NoshiSettingsRow *_row;
}
@property (nonatomic, retain) NoshiSettingsRow *row;
@end

@implementation NoshiSettingsViewCell

@synthesize row = _row;

- (void)dealloc {
    [_row release];
    [super dealloc];
}

- (void)setRow:(NoshiSettingsRow *)row {
    if (row == _row) return;
    for (UIView *old in [[self.contentView.subviews copy] autorelease]) [old removeFromSuperview];
    [_row release];
    _row = [row retain];
    if (_row.customView) [self.contentView addSubview:_row.customView];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - 2 * CARD_INSET;
    /* never taller than the row the table gave it, so a view that measures more than the table did stays inside its own row */
    CGFloat height = MIN(_row.customHeight(width), self.contentView.bounds.size.height);
    _row.customView.frame = CGRectMake(CARD_INSET, 0, width, height);
}

@end

@interface NoshiClassicSelectionView : UIView {
    UIRectCorner _corners;
}
@property (nonatomic, assign) UIRectCorner corners;
@end

@implementation NoshiClassicSelectionView
@synthesize corners = _corners;
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [NoshiClassicSelectionColor() setFill];
    [[UIBezierPath bezierPathWithRoundedRect:self.bounds byRoundingCorners:_corners cornerRadii:CGSizeMake(10, 10)] fill];
}
@end

/* the cell of a row with a slider in the classic grouped table */
@interface NoshiClassicSliderCell : UITableViewCell {
    UIView *_slider;
}
@property (nonatomic, assign) UIView *slider;
@end

@implementation NoshiClassicSliderCell

@synthesize slider = _slider;

/* the title and the value on the first line, and the slider under them from the left edge of the title to the right edge of the value, with room above and
   below it */
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGRect title = self.textLabel.frame;
    title.origin.y = 10;
    self.textLabel.frame = title;
    CGRect value = self.detailTextLabel.frame;
    value.origin.y = title.origin.y + floor((title.size.height - value.size.height) / 2);
    self.detailTextLabel.frame = value;
    CGFloat left = title.origin.x;
    _slider.frame = CGRectMake(left, CGRectGetMaxY(title) + 10, MAX(0, width - 2 * left), 30);
}

@end

/* the cell of a row with a view of its own in the classic grouped table */
@interface NoshiSettingsClassicViewCell : UITableViewCell {
    NoshiSettingsRow *_row;
    UIRectCorner _corners;
    CAShapeLayer *_cut;
}
@property (nonatomic, retain) NoshiSettingsRow *row;
@property (nonatomic, assign) UIRectCorner corners;
@end

@implementation NoshiSettingsClassicViewCell

@synthesize row = _row;
@synthesize corners = _corners;

- (void)dealloc {
    [_row release];
    [_cut release];
    [super dealloc];
}

- (void)setRow:(NoshiSettingsRow *)row {
    if (row == _row) return;
    for (UIView *old in [[self.contentView.subviews copy] autorelease]) [old removeFromSuperview];
    [_row release];
    _row = [row retain];
    if (_row.customView) [self.contentView addSubview:_row.customView];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIView *view = _row.customView;
    view.frame = self.contentView.bounds;
    view.layer.cornerRadius = 0;
    BOOL systemRounds = [UIViewController instancesRespondToSelector:NSSelectorFromString(@"preferredStatusBarStyle")];
    if (systemRounds || !_corners) {
        self.contentView.layer.mask = nil;
        [CATransaction commit];
        return;
    }
    if (!_cut) _cut = [[CAShapeLayer alloc] init];
    _cut.frame = self.contentView.bounds;
    _cut.path = [UIBezierPath bezierPathWithRoundedRect:self.contentView.bounds byRoundingCorners:_corners cornerRadii:CGSizeMake(10, 10)].CGPath;
    self.contentView.layer.mask = _cut;
    [CATransaction commit];
}

@end

@interface NoshiSettingsCell : UITableViewCell {
    UIView *_card;
    CALayer *_shape;
    UIImageView *_tile;
    UIImageView *_trailing;
    UILabel *_title;
    NoshiEmojiLabel *_nameTitle;
    UILabel *_subtitle;
    UILabel *_line3;
    UILabel *_value;
    NoshiEmojiLabel *_emojiValue;
    UISwitch *_switch;
    UIImageView *_check;
    NoshiExpressiveSlider *_slider;
    UILabel *_levelBadge;
    UILabel *_leftLabel;
    UILabel *_rightLabel;
    UILabel *_middle;
    UIImageView *_battery;
    int _lastPercent;
    NoshiSettingsRow *_row;
    NoshiRowPlace _place;
}
- (void)configureWithRow:(NoshiSettingsRow *)row place:(NoshiRowPlace)place;
/* how much of the plate behind the row is taken away: 0 as drawn, 1 only the row on what lies under the page */
- (void)setCardFade:(CGFloat)fade;
@end

@implementation NoshiSettingsCell

- (void)setCardFade:(CGFloat)fade {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.opacity = (float)(1 - fade);
    [CATransaction commit];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.clipsToBounds = YES;
    _card = [[UIView alloc] init];
    [self.contentView addSubview:_card];
    _shape = [[CALayer alloc] init];
    CGFloat side = 2 * CARD_RADIUS + 2;
    _shape.contentsCenter = CGRectMake(CARD_RADIUS / side, CARD_RADIUS / side, 2 / side, 2 / side);
    [_card.layer addSublayer:_shape];
    _tile = [[UIImageView alloc] init];
    [_card addSubview:_tile];
    _trailing = [[UIImageView alloc] init];
    _trailing.layer.masksToBounds = YES;
    _trailing.layer.cornerRadius = TRAILING_SIDE * 0.225;
    [_card addSubview:_trailing];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.numberOfLines = 1;
    [_card addSubview:_title];
    _nameTitle = [[NoshiEmojiLabel alloc] init];
    _nameTitle.dropsUndrawable = YES;
    [_card addSubview:_nameTitle];
    _subtitle = [[UILabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.numberOfLines = 1;
    [_card addSubview:_subtitle];
    _line3 = [[UILabel alloc] init];
    _line3.backgroundColor = [UIColor clearColor];
    [_card addSubview:_line3];
    _value = [[UILabel alloc] init];
    _value.backgroundColor = [UIColor clearColor];
    _value.textAlignment = NoshiTextAlignmentRight;
    [_card addSubview:_value];
    _emojiValue = [[NoshiEmojiLabel alloc] init];
    _emojiValue.textAlignment = NoshiTextAlignmentRight;
    [_card addSubview:_emojiValue];
    _switch = [[UISwitch alloc] init];
    [_switch addTarget:self action:@selector(switched) forControlEvents:UIControlEventValueChanged];
    [_card addSubview:_switch];
    _check = [[UIImageView alloc] init];
    [_card addSubview:_check];
    _slider = [[NoshiExpressiveSlider alloc] init];
    [_slider addTarget:self action:@selector(slid) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(slideLetGo) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_card addSubview:_slider];
    _levelBadge = [[UILabel alloc] init];
    _levelBadge.textAlignment = NoshiTextAlignmentCenter;
    _levelBadge.layer.cornerRadius = 4;
    _levelBadge.layer.masksToBounds = YES;
    [_card addSubview:_levelBadge];
    _leftLabel = [[UILabel alloc] init];
    _leftLabel.backgroundColor = [UIColor clearColor];
    [_card addSubview:_leftLabel];
    _rightLabel = [[UILabel alloc] init];
    _rightLabel.backgroundColor = [UIColor clearColor];
    _rightLabel.textAlignment = NoshiTextAlignmentRight;
    [_card addSubview:_rightLabel];
    _middle = [[UILabel alloc] init];
    _middle.backgroundColor = [UIColor clearColor];
    [_card addSubview:_middle];
    _battery = [[UIImageView alloc] init];
    [_card addSubview:_battery];
    return self;
}

- (void)dealloc {
    [_card release];
    [_shape release];
    [_tile release];
    [_trailing release];
    [_title release];
    [_nameTitle release];
    [_subtitle release];
    [_line3 release];
    [_value release];
    [_emojiValue release];
    [_switch release];
    [_check release];
    [_slider release];
    [_levelBadge release];
    [_leftLabel release];
    [_rightLabel release];
    [_middle release];
    [_battery release];
    [_row release];
    [super dealloc];
}

/* a small battery, outlined, with its charge filled in from the left; it stands after the words that name a level */
static UIImage *NoshiBatteryImage(float fill, UIColor *color) {
    CGSize size = CGSizeMake(22, 12);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGRect body = CGRectMake(0.75, 0.75, 18.5, 10.5);
    [color setStroke];
    UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:2.5];
    outline.lineWidth = 1.5;
    [outline stroke];
    [color setFill];
    CGFloat charge = MAX(0, MIN(1, fill));
    if (charge > 0) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.5, 2.5, 15 * charge, 7) cornerRadius:1] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(19.8, 3.8, 2, 4.4) cornerRadius:1] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the texts of a level: its words in the middle, the badge at the title, the two ends lit when one of them is the level */
- (void)showLevel:(int)percent {
    NSDictionary *info = _row.describe ? _row.describe(percent) : nil;
    _middle.text = [info objectForKey:@"line"];
    NSString *badge = [info objectForKey:@"badge"];
    _levelBadge.hidden = badge.length == 0;
    _levelBadge.text = badge;
    NSNumber *fill = [info objectForKey:@"fill"];
    _battery.hidden = fill == nil;
    _battery.image = fill ? NoshiBatteryImage([fill floatValue], NoshiColorAccent()) : nil;
    _leftLabel.textColor = [[info objectForKey:@"left"] boolValue] ? NoshiColorAccent() : NoshiColorSecondary();
    _rightLabel.textColor = [[info objectForKey:@"right"] boolValue] ? NoshiColorAccent() : NoshiColorSecondary();
    [self setNeedsLayout];
}

- (void)slideLetGo {
    if (_row.slideEnded) _row.slideEnded();
}

- (void)slid {
    if (_row.hasLevel) {
        int percent = (int)(_slider.value + 0.5f);
        if (percent == _lastPercent) return;
        _lastPercent = percent;
        /* the row keeps the value, because the table builds the cell again from it when the row scrolls back into view */
        _row.sliderValue = (float)percent;
        [self showLevel:percent];
        if (_row.slide) _row.slide((float)percent);
        return;
    }
    _row.sliderValue = _slider.value;
    _value.text = [NSString stringWithFormat:_row.sliderFormat, (double)_slider.value];
    if (_row.slide) _row.slide(_slider.value);
}

- (void)switched {
    _row.on = _switch.on;
    if (_row.toggle) _row.toggle(_switch.on);
}

- (void)configureWithRow:(NoshiSettingsRow *)row place:(NoshiRowPlace)place {
    /* the new row is kept before the old one goes, since a cell configured again with its own row would free it first */
    [row retain];
    [_row release];
    _row = row;
    _place = place;
    /* the picture of the card depends on the place and the colors only, so a scroll that lays the cell out again does not look it up again */
    CGFloat top, bottom;
    NoshiCardRadii(place, &top, &bottom);
    UIImage *shape = NoshiCardImage(top, bottom);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.contents = (id)shape.CGImage;
    _shape.contentsScale = shape.scale;
    [CATransaction commit];
    BOOL tappable = row.tap != nil;
    _card.backgroundColor = [UIColor clearColor];
    UIColor *textColor = row.destructive ? (NoshiColorBadgeRed()) : NoshiColorTitle();
    _title.text = row.title;
    _title.textColor = textColor;
    _title.font = NoshiRowTitleFont(row);
    /* a title and the line under it wrap for as many lines as they need, so "Terminate All Other Sessions" reads whole (the session rows keep one line each,
       their height is fixed) */
    _title.numberOfLines = row.isSession ? 1 : 0;
    /* a row with a picture is a person, a chat or a pack: the system label draws a styled nick as boxes with a code in them, so the name goes through the emoji label that leaves them out */
    _nameTitle.hidden = row.tileImage == nil;
    _title.hidden = row.tileImage != nil;
    _nameTitle.text = row.title;
    _nameTitle.textColor = textColor;
    _nameTitle.font = _title.font;
    _nameTitle.numberOfLines = _title.numberOfLines;
    _subtitle.numberOfLines = row.isSession ? 1 : 0;
    _subtitle.text = row.subtitle;
    _subtitle.font = NoshiFontRegular(row.isSession ? 14 : 13);
    _subtitle.textColor = row.isSession ? NoshiColorTitle() : NoshiColorSecondary();
    _subtitle.hidden = row.subtitle.length == 0;
    _line3.text = row.line3;
    _line3.font = NoshiFontRegular(13);
    _line3.textColor = row.accentLine3 ? NoshiColorAccent() : NoshiColorSecondary();
    _line3.hidden = row.line3.length == 0;
    _value.text = row.value;
    _value.font = NoshiFontRegular(16);
    _value.textColor = NoshiColorAccent();
    _value.hidden = row.value.length == 0 || row.valueIsEmoji;
    _emojiValue.hidden = !row.valueIsEmoji || row.value.length == 0;
    _emojiValue.text = row.value;
    _emojiValue.font = NoshiFontRegular(16);
    _emojiValue.textColor = NoshiColorAccent();
    if (row.valueEmojiDocument && row.value.length) {
        NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji range:NSMakeRange(0, row.value.length) url:nil] autorelease];
        entity.documentId = row.valueEmojiDocument;
        _emojiValue.entities = [NSArray arrayWithObject:entity];
    } else _emojiValue.entities = nil;
    _switch.hidden = !row.hasSwitch;
    _switch.on = row.on;
    _check.hidden = !row.checked;
    _check.image = row.checked ? NoshiSymbolImage(NoshiSymbolCheckMark(), 22, NoshiColorAccent()) : nil;
    _slider.hidden = !row.hasSlider;
    BOOL level = row.hasLevel;
    _levelBadge.hidden = _leftLabel.hidden = _rightLabel.hidden = _middle.hidden = _battery.hidden = !level;
    if (level) {
        _lastPercent = (int)(row.sliderValue + 0.5f);
        _title.font = NoshiFontSemibold(15);
        _title.textColor = NoshiColorAccent();
        _leftLabel.font = NoshiFontRegular(13);
        _leftLabel.text = row.leftCaption;
        _rightLabel.font = NoshiFontRegular(13);
        _rightLabel.text = row.rightCaption;
        _middle.font = NoshiFontMedium(13);
        _middle.textColor = NoshiColorAccent();
        _levelBadge.font = NoshiFontBold(12);
        _levelBadge.textColor = NoshiColorAccent();
        _levelBadge.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.15];
        [self showLevel:_lastPercent];
    }
    if (row.hasSlider) {
        _slider.minimumValue = row.sliderMinimum;
        _slider.maximumValue = row.sliderMaximum;
        _slider.value = row.sliderValue;
        /* the number follows the position, whatever text the row was made with */
        if (!level && row.sliderFormat) {
            _value.text = [NSString stringWithFormat:row.sliderFormat, (double)row.sliderValue];
            _value.hidden = NO;
        }
    }
    UIImage *tile = nil;
    if (row.isSession) {
        tile = row.picture;
    } else if (row.tileImage) {
        tile = row.tileImage;
    } else if (row.hasSymbol && row.destructive) {
        tile = NoshiSymbolImage(row.symbol, 26, textColor);
    } else if (row.hasSymbol) {
        tile = NoshiSettingsTileImage(row.symbol, row.tone, TILE);
    }
    if (_tile.image != tile) _tile.image = tile;
    _tile.hidden = _tile.image == nil;
    if (_trailing.image != row.trailingImage) _trailing.image = row.trailingImage;
    _trailing.layer.masksToBounds = !row.trailingImageUnclipped;
    _trailing.hidden = row.trailingImage == nil;
    CGFloat dim = row.disabled ? 0.5 : 1;
    _tile.alpha = _title.alpha = _nameTitle.alpha = _subtitle.alpha = _switch.alpha = dim;
    _switch.userInteractionEnabled = !row.disabled;
    self.accessibilityLabel = row.title;
    self.accessibilityTraits = tappable ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (_row.tap) _card.alpha = highlighted ? 0.7 : 1;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - 2 * CARD_INSET;
    /* the plate takes the height the table gave the row (minus the gap under a joint), so it cannot run into the row below when the two measures differ */
    BOOL last = _place == NoshiRowPlaceOnly || _place == NoshiRowPlaceLast;
    CGFloat height = MAX(0, self.contentView.bounds.size.height - (last ? 0 : ROW_GAP));
    _card.frame = CGRectMake(CARD_INSET, 0, width, height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.frame = _card.bounds;
    [CATransaction commit];
    BOOL session = _row.isSession;
    CGFloat iconSide = session ? SESSION_ICON : TILE;
    CGFloat left = ICON_PAD;
    if (!_tile.hidden) {
        _tile.frame = CGRectMake(ICON_PAD, session ? 9 : (height - iconSide) / 2, iconSide, iconSide);
        left = CGRectGetMaxX(_tile.frame) + (session ? 14 : 18);
        /* the glyph of an action row has no circle around it, so its text sits closer */
        if (_row.destructive) {
            _tile.frame = CGRectMake(ICON_PAD, (height - 26) / 2, 26, 26);
            left = CGRectGetMaxX(_tile.frame) + 14;
        }
    }
    CGFloat right = ICON_PAD;
    if (!_switch.hidden) {
        CGSize size = _switch.frame.size;
        _switch.frame = CGRectMake(width - 16 - size.width, (height - size.height) / 2, size.width, size.height);
        right = 16 + size.width + 8;
    }
    if (!_trailing.hidden) {
        _trailing.frame = CGRectMake(width - ICON_PAD - TRAILING_SIDE, (height - TRAILING_SIDE) / 2, TRAILING_SIDE, TRAILING_SIDE);
        right = ICON_PAD + TRAILING_SIDE + 10;
    }
    if (!_check.hidden) {
        _check.frame = CGRectMake(width - ICON_PAD - 22, (height - 22) / 2, 22, 22);
        right = ICON_PAD + 22 + 8;
    }
    if (_row.hasLevel) {
        _title.frame = CGRectMake(ICON_PAD, 16, MAX(0, width - 2 * ICON_PAD), 20);
        if (!_levelBadge.hidden) {
            CGFloat titleWidth = ceil(NoshiStringSize(_title.text, _title.font).width);
            CGFloat badgeWidth = ceil(NoshiStringSize(_levelBadge.text, _levelBadge.font).width) + 11;
            _levelBadge.frame = CGRectMake(ICON_PAD + titleWidth + 6, 17, badgeWidth, 18);
        }
        _leftLabel.frame = CGRectMake(ICON_PAD, 46, 80, 20);
        _rightLabel.frame = CGRectMake(width - ICON_PAD - 80, 46, 80, 20);
        CGFloat room = MAX(0, width - 2 * ICON_PAD - 170);
        CGFloat textWidth = MIN(room, ceil(NoshiStringSize(_middle.text, _middle.font).width));
        CGFloat group = textWidth + (_battery.hidden ? 0 : 28);
        CGFloat x = floor((width - group) / 2);
        _middle.frame = CGRectMake(x, 46, textWidth, 20);
        _battery.frame = CGRectMake(x + textWidth + 6, 50, 22, 12);
        _slider.frame = CGRectMake(ICON_PAD - 6, 72, width - 2 * ICON_PAD + 12, 30);
        return;
    }
    if (!_slider.hidden) {
        _title.frame = CGRectMake(left, 10, MAX(0, width - left - ICON_PAD - 90), 22);
        _value.frame = CGRectMake(width - ICON_PAD - 90, 10, 90, 22);
        _slider.frame = CGRectMake(left, 40, MAX(0, width - left - ICON_PAD), 28);
        return;
    }
    CGFloat valueWidth = 0;
    if (!_value.hidden || !_emojiValue.hidden) {
        valueWidth = !_emojiValue.hidden ? MIN(34, width * 0.45) : MIN(ceil(NoshiStringSize(_value.text, _value.font).width) + 4, width * 0.45);
        _value.frame = _emojiValue.frame = CGRectMake(width - ICON_PAD - valueWidth, 0, valueWidth, height);
        right = ICON_PAD + valueWidth + 8;
    }
    CGFloat textWidth = MAX(0, width - left - right);
    if (session) {
        _title.frame = CGRectMake(left, 6, textWidth, 20);
        _subtitle.frame = CGRectMake(left, 28, textWidth, 18);
        _line3.frame = CGRectMake(left, 46, textWidth, 18);
    } else if (!_subtitle.hidden) {
        CGFloat titleHeight, subtitleHeight;
        NoshiRowTextHeights(_row, width, &titleHeight, &subtitleHeight);
        CGFloat textTop = floor((height - (titleHeight + 4 + subtitleHeight)) / 2);
        _title.frame = CGRectMake(left, textTop, textWidth, titleHeight);
        _subtitle.frame = CGRectMake(left, textTop + titleHeight + 4, textWidth, subtitleHeight);
    } else {
        _title.frame = CGRectMake(left, 0, textWidth, height);
    }
    _nameTitle.frame = _title.frame;
}

@end

#pragma mark page

/* a field whose hint is drawn in the muted color of the bar; attributedPlaceholder, which would do it, came with ios 6 */
@interface NoshiSettingsSearchField : UITextField
@end

@implementation NoshiSettingsSearchField

- (void)drawPlaceholderInRect:(CGRect)rect {
    [NoshiColorMuted() setFill];
    NoshiDrawStringIn(self.placeholder, self.font, rect, NoshiStringTailTruncate, NoshiTextAlignmentLeft);
}

@end

/* a reused cell starts at its old width; laying out its label here avoids a second autoresize beyond the right margin */
@interface NoshiSettingsTextCell : UITableViewCell
@end

@implementation NoshiSettingsTextCell
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label = (UILabel *)[self.contentView viewWithTag:1];
    CGRect bounds = self.contentView.bounds;
    label.frame = CGRectMake(CARD_INSET + ICON_PAD, 10, MAX(0, bounds.size.width - 2 * (CARD_INSET + ICON_PAD)),
                             MAX(0, bounds.size.height - 20));
}
@end

/* what the back button with its word and the dots take of a phone's width on the wider side of the classic bar of a settings page */
#define SETTINGS_CLASSIC_SIDE 92.0

@interface NoshiSettingsPageController () {
    NSString *_pageTitle;
    NSArray *_sections;
    NSArray *_flat;
    UIView *_headerView;
    UITableView *_table;
    BOOL _showsBack;
    CGFloat _bottomInset;
    NSArray *_barViews;
    UIView *_leadingView;
    CGFloat _titleAlpha;
    BOOL _contentUnderBar;
    CGFloat _barFill;
    BOOL _searchable;
    BOOL _searching;
    NSString *_query;
    NSArray *_searchSections;
    UIView *_barBackground;
    NoshiWaveBackgroundView *_backdrop;
    UIView *_underlay;
    CGFloat _cardFade;
    UIButton *_back;
    UILabel *_titleLabel;
    UIButton *_searchButton;
    UITextField *_searchField;
    UILabel *_emptyLabel;
    NSString *_classicTitleText;
    NSArray *_classicTitleEntities;
    NoshiClassicSearchInput *_classicSearch;
    UIView *_classicHead;
    /* the classic search sits in the navigation bar while it is open, and what it replaced waits here */
    BOOL _classicSearchOpen;
    UIView *_savedTitleView;
    NSArray *_savedLeftItems;
    NSArray *_savedRightItems;
    NSMutableIndexSet *_footerDirty;
    BOOL _sliding;
    CGPoint _selectPoint;
}
@end

@implementation NoshiSettingsPageController

@synthesize table = _table;
@synthesize showsBack = _showsBack;
@synthesize bottomInset = _bottomInset;
@synthesize contentUnderBar = _contentUnderBar;

@synthesize searchable = _searchable;
@synthesize searching = _searching;

- (CGFloat)titleAlpha { return _titleAlpha; }
- (void)setTitleAlpha:(CGFloat)alpha {
    _titleAlpha = alpha;
    _titleLabel.alpha = alpha;
}

- (CGFloat)barFill { return _barFill; }
- (void)setBarFill:(CGFloat)fill {
    _barFill = fill;
    _barBackground.alpha = _searching ? 1 : fill;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _showsBack = YES;
    _titleAlpha = 1;
    _barFill = 1;
    _footerDirty = [[NSMutableIndexSet alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeNotified:) name:NoshiThemeDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyThemeInPlace) object:nil];
    _table.delegate = nil;
    _table.dataSource = nil;
    _searchField.delegate = nil;
    _classicSearch.changeHandler = nil;
    [_pageTitle release];
    [_classicTitleText release];
    [_classicTitleEntities release];
    [_sections release];
    [_flat release];
    [_headerView release];
    [_table release];
    [_barViews release];
    [_leadingView release];
    [_backdrop release];
    [_underlay release];
    [_back release];
    [_titleLabel release];
    [_barBackground release];
    [_searchButton release];
    [_searchField release];
    [_emptyLabel release];
    [_classicSearch release];
    [_classicHead release];
    [_savedTitleView release];
    [_savedLeftItems release];
    [_savedRightItems release];
    [_footerDirty release];
    [_query release];
    [_searchSections release];
    [super dealloc];
}

- (NSString *)pageTitle { return _pageTitle; }
- (void)setPageTitle:(NSString *)title {
    if (title == _pageTitle || [title isEqualToString:_pageTitle]) return;
    [_pageTitle release];
    _pageTitle = [title copy];
    _titleLabel.text = _pageTitle;
    self.title = _pageTitle;
    [self showClassicTitle];
}

/* the name of a person or a chat in the classic bar is drawn by the app's own label: the system title shows boxes for the letters of a styled nick that the system font lacks */
- (void)showClassicTitle {
    if (!self.isViewLoaded) return;
    /* the bar centers the view between its buttons, and the 190 points of the default ran under the back button and the dots of a phone 320 points wide: the width is what is left
       beside the wider side, as the system's own title had */
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat width = NoshiIsPad() ? 420 : MIN(190, MIN(screen.width, screen.height) - 2 * SETTINGS_CLASSIC_SIDE);
    NSString *text = _classicTitleText.length ? _classicTitleText : _pageTitle;
    UIView *title = text.length ? NoshiClassicTitleViewWithStatusWidth(text, nil, 0, width) : nil;
    if (title && _classicTitleText.length) {
        for (UIView *view in title.subviews) {
            if (![view isKindOfClass:[NoshiEmojiLabel class]]) continue;
            NoshiEmojiLabel *label = (NoshiEmojiLabel *)view;
            label.entities = _classicTitleEntities;
            /* the name in the body keeps every character it has a font for, so the title does not cut them either */
            label.dropsUndrawable = NO;
        }
    }
    self.navigationItem.titleView = title;
}

- (void)setClassicTitleText:(NSString *)text entities:(NSArray *)entities {
    [_classicTitleText release];
    _classicTitleText = [text copy];
    [_classicTitleEntities release];
    _classicTitleEntities = [entities copy];
    [self showClassicTitle];
}

- (void)refreshClassicTitle {
    for (UIView *view in self.navigationItem.titleView.subviews) [view setNeedsDisplay];
}

- (UIView *)underlay { return _underlay; }
- (void)setUnderlay:(UIView *)underlay {
    if (underlay == _underlay) return;
    [_underlay removeFromSuperview];
    [_underlay release];
    _underlay = [underlay retain];
    [self.view setNeedsLayout];
}

- (CGFloat)cardFade { return _cardFade; }
- (void)setCardFade:(CGFloat)fade {
    CGFloat clamped = fade < 0 ? 0 : (fade > 1 ? 1 : fade);
    if (clamped == _cardFade) return;
    _cardFade = clamped;
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[NoshiSettingsCell class]]) [(NoshiSettingsCell *)cell setCardFade:_cardFade];
    }
}

- (NSArray *)sections { return _sections; }
- (void)setSections:(NSArray *)sections {
    if (sections == _sections) return;
    [_sections release];
    _sections = [sections retain];
    [self rebuildFlat];
    [_table reloadData];
}

- (UIView *)headerView { return _headerView; }
- (void)setHeaderView:(UIView *)view {
    if (view != _headerView) {
        [_headerView release];
        _headerView = [view retain];
    }
    /* a table takes the height of its head when the head is handed over, so a head that grew in place is handed over again, or the rows stay where the short one ended */
    if ([self isViewLoaded]) {
        _table.tableHeaderView = [self classicTableHeader];
        [self.view setNeedsLayout];
    }
}

- (UIView *)leadingView { return _leadingView; }
- (void)setLeadingView:(UIView *)view {
    [_leadingView removeFromSuperview];
    [_leadingView release];
    _leadingView = [view retain];
    if ([self isViewLoaded] && _leadingView) [self.view addSubview:_leadingView];
    [self.view setNeedsLayout];
}

- (NSArray *)barViews { return _barViews; }
- (void)setBarViews:(NSArray *)views {
    for (UIView *old in _barViews) [old removeFromSuperview];
    [_barViews release];
    _barViews = [views retain];
    if ([self isViewLoaded]) for (UIView *view in _barViews) [self.view addSubview:view];
    [self.view setNeedsLayout];
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self.view setNeedsLayout];
}

- (void)goBack {
    if (_searching) {
        [self endSearch];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark search

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    (void)query;
    return nil;
}

- (void)searchDidChangeState {
}

- (void)setSearchable:(BOOL)searchable {
    _searchable = searchable;
    _searchButton.hidden = !searchable;
    if (_classicSearch) _table.tableHeaderView = [self classicTableHeader];
    if ([self isViewLoaded]) [self.view setNeedsLayout];
}

/* the classic style searches as the text is typed: there is no open and close, the text decides */
- (void)classicSearchChanged:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL was = _searching;
    _searching = query.length > 0;
    [_query release];
    _query = [query copy];
    [_searchSections release];
    _searchSections = _searching ? [[self sectionsForSearchQuery:query] retain] : nil;
    [self rebuildFlat];
    [_table reloadData];
    if (was != _searching) [self searchDidChangeState];
    [self refreshEmptyLabel];
}

- (void)focusSearch {
    if (!_searchable) return;
    [self beginClassicSearch];
}

/* old iOS can refuse keyboard focus for a table header during scrolling or before it enters the window */
- (void)beginClassicSearch {
    if (_classicSearchOpen || !_classicSearch) return;
    UINavigationItem *item = self.navigationItem;
    _classicSearchOpen = YES;
    [_savedTitleView release];
    _savedTitleView = [item.titleView retain];
    [_savedLeftItems release];
    _savedLeftItems = [item.leftBarButtonItems copy];
    [_savedRightItems release];
    _savedRightItems = [item.rightBarButtonItems copy];
    CGFloat width = self.navigationController.navigationBar.bounds.size.width;
    _classicSearch.frame = CGRectMake(0, 0, MAX(120, width - 24), 44);
    BOOL animate = !NoshiReduceMotionEnabled();
    [item setLeftBarButtonItems:nil animated:animate];
    [item setRightBarButtonItems:[NSArray arrayWithObject:[[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"picker.cancel", nil)
                                                                                           style:UIBarButtonItemStyleBordered target:self action:@selector(endClassicSearch)] autorelease]] animated:animate];
    item.titleView = _classicSearch;
    if (animate) {
        /* the field opens from the right edge, where the search was, and grows across the bar while it comes in */
        CGFloat shrunk = 0.3f, fullWidth = _classicSearch.bounds.size.width;
        _classicSearch.alpha = 0;
        _classicSearch.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(shrunk, 1), CGAffineTransformMakeTranslation(fullWidth * (1 - shrunk) / 2, 0));
        [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            _classicSearch.alpha = 1;
            _classicSearch.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    /* the bar is in the window after this pass of the run loop, which is when a keyboard can be asked for */
    [self performSelector:@selector(raiseClassicSearchKeyboard) withObject:nil afterDelay:0];
}

- (void)raiseClassicSearchKeyboard {
    if (!_classicSearchOpen) return;
    if (![_classicSearch becomeFirstResponder]) NSLog(@"noshigram: the search bar of the settings did not take the keyboard");
}

- (void)endClassicSearch {
    if (!_classicSearchOpen) return;
    _classicSearchOpen = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(raiseClassicSearchKeyboard) object:nil];
    _classicSearch.text = @"";
    [_classicSearch resignFirstResponder];
    UINavigationItem *item = self.navigationItem;
    BOOL animate = !NoshiReduceMotionEnabled();
    _classicSearch.alpha = 1;
    _classicSearch.transform = CGAffineTransformIdentity;
    item.titleView = _savedTitleView;
    [item setLeftBarButtonItems:_savedLeftItems animated:animate];
    [item setRightBarButtonItems:_savedRightItems animated:animate];
    if (animate && _savedTitleView) {
        /* what the bar showed before comes back with a fade, as the search went out with a grow */
        _savedTitleView.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{ _savedTitleView.alpha = 1; }];
    }
    [self classicSearchChanged:@""];
}

- (void)beginSearch {
    if (_searching || !_searchable) return;
    _searching = YES;
    _barBackground.hidden = NO;
    _barBackground.alpha = 1;
    _back.hidden = NO;
    _titleLabel.hidden = YES;
    _leadingView.hidden = YES;
    _searchButton.hidden = YES;
    for (UIView *view in _barViews) view.hidden = YES;
    _searchField.text = @"";
    _searchField.hidden = NO;
    [_query release];
    _query = [@"" retain];
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:@""] retain];
    _table.tableHeaderView = nil;
    [self rebuildFlat];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
    [self searchDidChangeState];
    [self.view setNeedsLayout];
    [_searchField becomeFirstResponder];
    [self refreshEmptyLabel];
}

- (void)endSearch {
    if (!_searching) return;
    [self endClassicSearch];
}

- (void)reloadSearchResults {
    if (!_searching) return;
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:_query ? _query : @""] retain];
    [self rebuildFlat];
    [_table reloadData];
    [self refreshEmptyLabel];
}

- (void)searchTextChanged {
    NSString *query = [_searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query isEqualToString:_query]) return;
    [_query release];
    _query = [query copy];
    [_searchSections release];
    _searchSections = [[self sectionsForSearchQuery:query] retain];
    [self rebuildFlat];
    [_table reloadData];
    [_table setContentOffset:CGPointZero animated:NO];
    [self refreshEmptyLabel];
}

/* a query that matched nothing says so in the middle of the empty table */
- (void)refreshEmptyLabel {
    BOOL empty = _searching && _query.length && _searchSections && _flat.count == 0;
    _emptyLabel.hidden = !empty;
}


- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

/* the waves under the rows hold still while the table moves; their animated masks are drawn again by the render
   server on every frame, which a long page of rows on an iPhone 4S cannot afford next to its own scroll */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = YES;
    if (_searching) [_searchField resignFirstResponder];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    (void)scrollView;
    if (!decelerate) _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

/* a row that changes height animates its cell, while a view of its own inside it (the preview) takes the new size
   at once and for a moment spills over the rows beside it */
- (void)updateRowHeights {
    BOOL animated = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    [_table beginUpdates];
    [_table endUpdates];
    [UIView setAnimationsEnabled:animated];
}

- (void)reloadSettings {
    [_table reloadData];
}

/* the head of the classic table: the block of a page that has one (the identity of the settings), and under it the
   search bar of a searchable page; with both they share one container */
- (UIView *)classicTableHeader {
    /* the search lives in the navigation bar now, so the head of the table is the page's own block alone */
    UIView *search = nil;
    if (!_headerView || !search) return _headerView ? _headerView : search;
    for (UIView *old in [[_classicHead.subviews copy] autorelease]) [old removeFromSuperview];
    [_classicHead release];
    CGFloat width = _table.bounds.size.width, head = _headerView.bounds.size.height;
    _classicHead = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, head + search.bounds.size.height)];
    _classicHead.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _headerView.frame = CGRectMake(0, 0, width, head);
    _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    search.frame = CGRectMake(0, head, width, search.bounds.size.height);
    search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_classicHead addSubview:_headerView];
    [_classicHead addSubview:search];
    return _classicHead;
}

/* the classic style: the system's grouped table under the navigation bar of its tab, with the search in a bar at the head of the table */
- (void)loadClassicView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _table = [[NoshiClassicSettingsTable alloc] initWithFrame:root.bounds style:UITableViewStyleGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.alwaysBounceHorizontal = NO;
    _table.directionalLockEnabled = YES;
    _table.showsHorizontalScrollIndicator = NO;
    _table.delegate = self;
    _table.dataSource = self;
    NoshiClassicStyleTable(_table);
    [root addSubview:_table];
    _classicSearch = [[NoshiClassicSearchInput alloc] initWithFrame:CGRectMake(0, 0, root.bounds.size.width, 44) placeholder:NSLocalizedString(@"settings.search", nil)];
    NoshiWeakReference *searchWeak = [NoshiWeakReference referenceTo:self];
    _classicSearch.changeHandler = ^(NSString *text) { [(NoshiSettingsPageController *)searchWeak.target classicSearchChanged:text]; };
    _table.tableHeaderView = [self classicTableHeader];
    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, root.bounds.size.width - 48, 24)];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.textColor = NoshiThemeIsDark() ? NoshiColorSecondary() : [UIColor grayColor];
    _emptyLabel.textAlignment = NoshiTextAlignmentCenter;
    _emptyLabel.text = NSLocalizedString(@"settings.search.empty", nil);
    _emptyLabel.hidden = YES;
    [root addSubview:_emptyLabel];
    self.title = _pageTitle;
    [self showClassicTitle];
}

/* everything the modern page draws around its rows; it is made again when the colors change */
- (void)buildModernChromeInRoot:(UIView *)root {
    _backdrop = [[NoshiWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.plain = YES;
    _backdrop.animated = YES;
    /* the table is made once and stays through every change of colors; only its rows are drawn again */
    if (_table) {
        [root insertSubview:_backdrop atIndex:0];
    } else {
        [root addSubview:_backdrop];
        _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
        NoshiScrollViewOwnsInsets(_table);
        _table.backgroundColor = [UIColor clearColor];
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.showsVerticalScrollIndicator = NO;
        _table.delegate = self;
        _table.dataSource = self;
        _table.tableHeaderView = _headerView;
        [root addSubview:_table];
        UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowPressed:)] autorelease];
        press.minimumPressDuration = 0.45;
        [_table addGestureRecognizer:press];
    }
    if (_underlay) {
        _underlay.frame = root.bounds;
        [root insertSubview:_underlay aboveSubview:_backdrop];
    }
    _barBackground = [[UIView alloc] init];
    _barBackground.backgroundColor = [NoshiColorScreen() colorWithAlphaComponent:0.94];
    _barBackground.alpha = _barFill;
    _barBackground.hidden = !_contentUnderBar;
    [root addSubview:_barBackground];
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.textColor = NoshiColorSecondary();
    _emptyLabel.textAlignment = NoshiTextAlignmentCenter;
    _emptyLabel.text = NSLocalizedString(@"settings.search.empty", nil);
    _emptyLabel.hidden = YES;
    [root addSubview:_emptyLabel];
    _back = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_back setImage:NoshiSymbolImage(NoshiSymbolBack, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    _back.accessibilityLabel = NSLocalizedString(@"story.close", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    _back.hidden = !_showsBack;
    [root addSubview:_back];
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = NoshiColorTitle();
    _titleLabel.text = _pageTitle;
    _titleLabel.alpha = _titleAlpha;
    [root addSubview:_titleLabel];
    for (UIView *view in _barViews) [root addSubview:view];
    if (_leadingView) [root addSubview:_leadingView];
    _searchButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_searchButton setImage:NoshiSymbolImage(NoshiSymbolMagnifier, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    _searchButton.accessibilityLabel = NSLocalizedString(@"settings.search", nil);
    [_searchButton addTarget:self action:@selector(beginSearch) forControlEvents:UIControlEventTouchUpInside];
    _searchButton.frame = CGRectMake(0, 0, 44, 44);
    _searchButton.hidden = !_searchable;
    [root addSubview:_searchButton];
    _searchField = [[NoshiSettingsSearchField alloc] init];
    _searchField.backgroundColor = [UIColor clearColor];
    _searchField.textColor = NoshiColorTitle();
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.delegate = self;
    _searchField.placeholder = NSLocalizedString(@"settings.search", nil);
    _searchField.hidden = YES;
    [_searchField addTarget:self action:@selector(searchTextChanged) forControlEvents:UIControlEventEditingChanged];
    [root addSubview:_searchField];
}

/* the views of the page go, except its table; the old views are kept for a moment before they are let go, since an
   animation that was running on one of them (the waves, a fade of the bar) still reports to it when it ends */
- (void)discardModernChrome {
    _searchField.delegate = nil;
    /* the underlay belongs to whoever set it and goes back under the new table */
    [_underlay removeFromSuperview];
    NSMutableArray *retired = [NSMutableArray array];
    for (UIView *view in [NSArray arrayWithObjects:_backdrop, _barBackground, _emptyLabel, _back, _titleLabel, _searchButton, _searchField, nil]) {
        [view removeFromSuperview];
        [retired addObject:view];
    }
    [_backdrop release];
    _backdrop = nil;
    [_barBackground release];
    _barBackground = nil;
    [_emptyLabel release];
    _emptyLabel = nil;
    [_back release];
    _back = nil;
    [_titleLabel release];
    _titleLabel = nil;
    [_searchButton release];
    _searchButton = nil;
    [_searchField release];
    _searchField = nil;
    [self performSelector:@selector(dropRetiredViews:) withObject:retired afterDelay:1.5];
}

- (void)dropRetiredViews:(NSArray *)views {
    (void)views;
}

/* the colors are read when a view is built, so a page that stays up across a change of the theme makes its own
   views again */
- (void)themeNotified:(NSNotification *)note {
    (void)note;
    [self performSelector:@selector(applyThemeInPlace) withObject:nil afterDelay:0];
}

- (void)applyThemeInPlace {
    NoshiThemeApplyStored();
}

- (void)themeDidChange {
}

- (CGPoint)selectPoint { return _selectPoint; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)loadView {
    [self loadClassicView];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate { return YES; }

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return NoshiOrientationMask(); }
#pragma clang diagnostic pop

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = _table.tableHeaderView;
    CGFloat width = _table.bounds.size.width;
    if (header && width > 0 && header.frame.size.width != width) {
        CGRect frame = header.frame;
        frame.size.width = width;
        header.frame = frame;
        _table.tableHeaderView = header;
    }
}

#pragma mark table

/* the headers and footers of the sections are rows of the one section of the table, so they scroll away with the
   cards */
enum { NoshiFlatHeader, NoshiFlatRow, NoshiFlatFooter, NoshiFlatSpace };

- (void)rebuildFlat {
    [_flat release];
    NSMutableArray *flat = [NSMutableArray array];
    NSUInteger sectionIndex = 0;
    BOOL afterView = NO;
    for (NoshiSettingsSection *section in [self shownSections]) {
        NSNumber *mine = [NSNumber numberWithUnsignedInteger:sectionIndex++];
        /* a header under a card that is a picture (a preview, a list of cards) sat too close to its corners, so it gets a gap of its own */
        if (afterView && section.header.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NoshiFlatSpace], @"kind", mine, @"section", nil]];
        afterView = [section.rows.lastObject customView] != nil;
        if (section.header.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NoshiFlatHeader], @"kind", section.header, @"text", mine, @"section", nil]];
        else [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NoshiFlatSpace], @"kind", mine, @"section", nil]];
        NSUInteger count = section.rows.count;
        for (NSUInteger i = 0; i < count; ++i) {
            NoshiRowPlace place = count == 1 ? NoshiRowPlaceOnly : (i == 0 ? NoshiRowPlaceFirst : (i == count - 1 ? NoshiRowPlaceLast : NoshiRowPlaceMiddle));
            [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NoshiFlatRow], @"kind", [section.rows objectAtIndex:i], @"row",
                             [NSNumber numberWithInt:place], @"place", mine, @"section", nil]];
        }
        if (section.footer.length) [flat addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NoshiFlatFooter], @"kind", section.footer, @"text",
                             [NSNumber numberWithBool:section.centerFooter], @"center", mine, @"section", nil]];
    }
    _flat = [flat retain];
}

/* the flat rows of one section, as index paths */
- (NSArray *)pathsOfSection:(NSUInteger)index inFlat:(NSArray *)flat footersOnly:(BOOL)footersOnly {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSUInteger i = 0; i < flat.count; ++i) {
        NSDictionary *item = [flat objectAtIndex:i];
        if ([[item objectForKey:@"section"] unsignedIntegerValue] != index) continue;
        if (footersOnly && [[item objectForKey:@"kind"] intValue] != NoshiFlatFooter) continue;
        [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    return paths;
}

- (void)replaceSectionAtIndex:(NSUInteger)index withSection:(NoshiSettingsSection *)section {
    if (index >= _sections.count) return;
    NSMutableArray *sections = [NSMutableArray arrayWithArray:_sections];
    [sections replaceObjectAtIndex:index withObject:section];
    [_sections release];
    _sections = [sections copy];
    if (!_searching) [_table reloadSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)setFooter:(NSString *)footer forSectionAtIndex:(NSUInteger)index {
    if (index >= _sections.count) return;
    NoshiSettingsSection *section = [_sections objectAtIndex:index];
    if ([footer isEqualToString:section.footer]) return;
    section.footer = footer;
    /* the system's own footer is part of the section, which is made again once the finger leaves the slider above it */
    [_footerDirty addIndex:index];
    if (!_sliding) [self flushFooters];
}

- (void)flushFooters {
    if (!_footerDirty.count) return;
    [_table reloadSections:_footerDirty withRowAnimation:UITableViewRowAnimationNone];
    [_footerDirty removeAllIndexes];
}

- (NSArray *)shownSections {
    return (_searching && _searchSections) ? _searchSections : _sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)[self shownSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[[[self shownSections] objectAtIndex:(NSUInteger)section] rows] count];
}

- (NSDictionary *)itemAt:(NSIndexPath *)indexPath {
    return [_flat objectAtIndex:(NSUInteger)indexPath.row];
}

- (CGFloat)sectionTextHeight:(NSString *)text width:(CGFloat)width font:(UIFont *)font minimum:(CGFloat)minimum {
    CGFloat room = MAX(0, width - 2 * (CARD_INSET + ICON_PAD));
    return MAX(minimum, NoshiWrappedHeight(text, font, room) + 20);
}

#pragma mark classic table

- (NoshiSettingsRow *)classicRowAt:(NSIndexPath *)indexPath {
    return [[[[self shownSections] objectAtIndex:(NSUInteger)indexPath.section] rows] objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[[self shownSections] objectAtIndex:(NSUInteger)section] header];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return [[[self shownSections] objectAtIndex:(NSUInteger)section] footer];
}

/* the system header text is dark grey, unreadable on the dark grouped background */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!NoshiThemeIsDark()) return nil;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] header];
    if (!text.length) return nil;
    return NoshiClassicGroupedHeader(text, tableView.bounds.size.width, 34, [UIColor whiteColor]);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (!NoshiThemeIsDark()) return nil;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] footer];
    if (!text.length) return nil;
    CGFloat edge = NoshiClassicGroupedTextInset(tableView.bounds.size.width);
    CGFloat width = MAX(0, tableView.bounds.size.width - 2 * edge);
    CGSize fit = NoshiStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(width, 600));
    return NoshiClassicGroupedFooter(text, tableView.bounds.size.width, fit.height + 12);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] header];
    return text.length ? (NoshiThemeIsDark() ? 34 : UITableViewAutomaticDimension) : 10;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [[[self shownSections] objectAtIndex:(NSUInteger)section] footer];
    if (!text.length) return 10;
    if (!NoshiThemeIsDark()) return UITableViewAutomaticDimension;
    CGFloat edge = NoshiClassicGroupedTextInset(tableView.bounds.size.width);
    CGSize fit = NoshiStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(MAX(0, tableView.bounds.size.width - 2 * edge), 600));
    return fit.height + 12;
}

- (void)classicSwitched:(UISwitch *)toggle {
    NSInteger tag = toggle.tag - 1;
    NSArray *shown = [self shownSections];
    NSUInteger section = (NSUInteger)(tag / 1000), index = (NSUInteger)(tag % 1000);
    if (section >= shown.count) return;
    NSArray *rows = [[shown objectAtIndex:section] rows];
    if (index >= rows.count) return;
    NoshiSettingsRow *row = [rows objectAtIndex:index];
    row.on = toggle.on;
    if (row.toggle) row.toggle(toggle.on);
}

- (void)classicSlid:(UISlider *)slider {
    NSInteger tag = slider.tag - 1;
    NSArray *shown = [self shownSections];
    NSUInteger section = (NSUInteger)(tag / 1000), index = (NSUInteger)(tag % 1000);
    if (section >= shown.count) return;
    NSArray *rows = [[shown objectAtIndex:section] rows];
    if (index >= rows.count) return;
    NoshiSettingsRow *row = [rows objectAtIndex:index];
    UIView *up = slider.superview;
    while (up && ![up isKindOfClass:[UITableViewCell class]]) up = up.superview;
    if (row.hasLevel) {
        int percent = (int)(slider.value + 0.5f);
        /* the long line does not fit beside the bold title of the cell, and ios drops the detail text then; the short one is the number or the end of the scale */
        NSDictionary *info = row.describe(percent);
        NSString *line = [info objectForKey:@"short"] ?: [info objectForKey:@"line"];
        row.sliderValue = (float)percent;
        UILabel *label = [(UITableViewCell *)up detailTextLabel];
        if ([label.text isEqualToString:line]) return;
        label.text = line;
        if (row.slide) row.slide((float)percent);
        return;
    }
    row.sliderValue = slider.value;
    [(UITableViewCell *)up detailTextLabel].text = [NSString stringWithFormat:row.sliderFormat, (double)slider.value];
    if (row.slide) row.slide(slider.value);
}

- (void)classicSlideBegan {
    _sliding = YES;
}

/* a footer that changed under the finger is swapped in now that the finger has left */
- (void)classicSlideEnded:(UISlider *)slider {
    _sliding = NO;
    [self flushFooters];
    NSInteger tag = slider.tag - 1;
    NSArray *shown = [self shownSections];
    NSUInteger section = (NSUInteger)(tag / 1000), index = (NSUInteger)(tag % 1000);
    if (section >= shown.count) return;
    NSArray *rows = [[shown objectAtIndex:section] rows];
    if (index < rows.count && [[rows objectAtIndex:index] slideEnded]) [[rows objectAtIndex:index] slideEnded]();
}

/* the classic cell has one line for its title, so "Pause music when recording a video" ended as "Pause music when" */
static CGFloat NoshiClassicTextWidth(NoshiSettingsRow *row, CGFloat tableWidth) {
    CGFloat left = 20 + (row.tileImage ? CLASSIC_FACE + 10 : (row.hasSymbol ? 29 + 10 : 0));
    CGFloat right = 14;
    if (row.hasSwitch) right = 20 + 79 + 8;
    else if (row.trailingImage) right = 20 + 29 + 8;
    else if (row.value.length) right = 20 + MIN(ceil(NoshiStringSize(row.value, [UIFont systemFontOfSize:17]).width), tableWidth * 0.4) + 8;
    else if (row.tap || row.tileImage) right = 40;
    return MAX(40, tableWidth - 20 - left - right);
}

static CGFloat NoshiClassicRowHeight(NoshiSettingsRow *row, CGFloat tableWidth) {
    if (row.hasSlider) return 84;
    CGFloat width = NoshiClassicTextWidth(row, tableWidth);
    CGFloat title = NoshiStringSizeIn(row.title, [UIFont boldSystemFontOfSize:17], CGSizeMake(width, 600)).height;
    CGFloat detail = row.subtitle.length ? NoshiStringSizeIn(row.subtitle, [UIFont systemFontOfSize:14], CGSizeMake(width, 600)).height : 0;
    /* ios 6 scales a cell's picture down to the row, so faces in rows of 44 and 59 points came out in two sizes; every row with a face is tall enough to show it whole */
    return MAX(row.tileImage ? CLASSIC_FACE + 16 : 44, ceil(title) + ceil(detail) + 22);
}

- (UITableViewCell *)classicCellForRow:(NoshiSettingsRow *)row at:(NSIndexPath *)indexPath {
    if (row.customView) {
        static NSString *viewIdentifier = @"settings.classic.view";
        NoshiSettingsClassicViewCell *host = (NoshiSettingsClassicViewCell *)[_table dequeueReusableCellWithIdentifier:viewIdentifier];
        if (!host) {
            host = [[[NoshiSettingsClassicViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:viewIdentifier] autorelease];
            host.selectionStyle = UITableViewCellSelectionStyleNone;
            NoshiClassicStyleCell(host);
        }
        NSUInteger count = [[[[self shownSections] objectAtIndex:(NSUInteger)indexPath.section] rows] count];
        UIRectCorner corners = 0;
        if (indexPath.row == 0) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
        if ((NSUInteger)indexPath.row + 1 == count) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
        host.corners = corners;
        host.row = row;
        return host;
    }
    /* a slider rides in the cell, so its cells are not shared with the others */
    BOOL subtitle = row.subtitle.length > 0;
    UITableViewCellStyle style = subtitle ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
    NSString *identifier = row.hasSlider ? nil : (subtitle ? @"settings.classic.subtitle" : @"settings.classic.value");
    UITableViewCell *cell = identifier ? [_table dequeueReusableCellWithIdentifier:identifier] : nil;
    if (!cell) {
        Class cellClass = row.hasSlider ? [NoshiClassicSliderCell class] : [UITableViewCell class];
        cell = [[[cellClass alloc] initWithStyle:style reuseIdentifier:identifier] autorelease];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.textLabel.textColor = NoshiThemeIsDark() ? NoshiColorTitle() : [UIColor blackColor];
    cell.detailTextLabel.textColor = NoshiThemeIsDark() ? NoshiColorSecondary() : (subtitle ? [UIColor grayColor] : [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1]);
    NoshiClassicStyleCell(cell);
    NoshiClassicSelectionView *selection = [[[NoshiClassicSelectionView alloc] initWithFrame:CGRectZero] autorelease];
    NSUInteger count = [[[[self shownSections] objectAtIndex:(NSUInteger)indexPath.section] rows] count];
    if (indexPath.row == 0) selection.corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if ((NSUInteger)indexPath.row + 1 == count) selection.corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    cell.selectedBackgroundView = selection;
    cell.textLabel.text = row.title;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = UILineBreakModeWordWrap;
    cell.detailTextLabel.numberOfLines = subtitle ? 0 : 1;
    if (row.destructive) cell.textLabel.textColor = [UIColor redColor];
    NSInteger tag = indexPath.section * 1000 + indexPath.row + 1;
    if (subtitle) {
        cell.detailTextLabel.text = row.subtitle;
        if (row.value.length) {
            UILabel *value = [[[UILabel alloc] init] autorelease];
            value.backgroundColor = [UIColor clearColor];
            value.font = [UIFont systemFontOfSize:16];
            value.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1];
            value.text = row.value;
            [value sizeToFit];
            cell.accessoryView = value;
        }
    } else {
        cell.detailTextLabel.text = row.value;
    }
    if (row.valueIsEmoji && row.value.length) {
        cell.detailTextLabel.text = subtitle ? row.subtitle : nil;
        NoshiEmojiLabel *value = [[[NoshiEmojiLabel alloc] initWithFrame:CGRectMake(0, 0, 34, 34)] autorelease];
        value.font = [UIFont systemFontOfSize:16]; value.text = row.value; value.textAlignment = NoshiTextAlignmentCenter;
        if (row.valueEmojiDocument) {
            NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleCustomEmoji range:NSMakeRange(0, row.value.length) url:nil] autorelease];
            entity.documentId = row.valueEmojiDocument; value.entities = [NSArray arrayWithObject:entity];
        }
        cell.accessoryView = value;
    }
    if (row.hasSymbol && !row.destructive) cell.imageView.image = NoshiSettingsTileImage(row.symbol, row.tone, 29);
    else if (row.tileImage) cell.imageView.image = row.tileImage;
    if (row.trailingImage && !row.hasSwitch && !row.value.length) {
        UIImageView *mark = [[[UIImageView alloc] initWithImage:row.trailingImage] autorelease];
        mark.frame = CGRectMake(0, 0, 29, 29);
        mark.layer.masksToBounds = !row.trailingImageUnclipped;
        mark.layer.cornerRadius = 29 * 0.225;
        cell.accessoryView = mark;
    }
    if (row.hasSwitch) {
        UISwitch *toggle = [[[UISwitch alloc] init] autorelease];
        toggle.on = row.on;
        toggle.enabled = !row.disabled;
        toggle.tag = tag;
        [toggle addTarget:self action:@selector(classicSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row.hasSlider) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (row.hasLevel) {
            NSDictionary *info = row.describe((int)(row.sliderValue + 0.5f));
            cell.detailTextLabel.text = [info objectForKey:@"short"] ?: [info objectForKey:@"line"];
            if (!NoshiThemeIsDark()) cell.textLabel.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1];
        } else {
            /* the row keeps where the slider stands, so a cell made again shows the value and not the one the row was made with */
            cell.detailTextLabel.text = [NSString stringWithFormat:row.sliderFormat, (double)row.sliderValue];
        }
        UISlider *slider = [[[UISlider alloc] initWithFrame:CGRectMake(20, 38, _table.bounds.size.width - 60, 28)] autorelease];
        slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        /* the filled part takes the accent of the style; the grey of the system slider is no part of it */
        slider.minimumTrackTintColor = NoshiColorAccent();
        slider.minimumValue = row.sliderMinimum;
        slider.maximumValue = row.sliderMaximum;
        slider.value = row.sliderValue;
        slider.tag = tag;
        [slider addTarget:self action:@selector(classicSlid:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(classicSlideBegan) forControlEvents:UIControlEventTouchDown];
        [slider addTarget:self action:@selector(classicSlideEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [cell.contentView addSubview:slider];
        [(NoshiClassicSliderCell *)cell setSlider:slider];
    } else if (row.checked) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else if (row.tap && !row.value.length && (!subtitle || row.tileImage)) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    if (!row.tap && !row.hasSwitch && !row.hasSlider) cell.selectionStyle = UITableViewCellSelectionStyleNone;
    else if (!row.hasSwitch && !row.hasSlider) cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NoshiSettingsRow *row = [self classicRowAt:indexPath];
    /* a grouped cell is narrower than the table by its margins before ios 7 */
    if (row.customView) return row.customHeight(tableView.bounds.size.width - ([UIViewController instancesRespondToSelector:NSSelectorFromString(@"preferredStatusBarStyle")] ? 0 : 20));
    return NoshiClassicRowHeight(row, tableView.bounds.size.width);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self classicCellForRow:[self classicRowAt:indexPath] at:indexPath];
}

#pragma mark removal

/* the tonal red of an M3 error container, light and dark */
static UIColor *NoshiErrorContainerColor(void) {
    return NoshiThemeIsDark() ? NoshiToneRGB(0x8C1D18) : NoshiToneRGB(0xF9DEDC);
}

- (void)rowPressed:(UILongPressGestureRecognizer *)press {
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [self classicRowAt:indexPath].remove != nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [self classicRowAt:indexPath].remove ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NSLocalizedString(@"settings.remove", nil);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (style != UITableViewCellEditingStyleDelete) return;
    [self removeRow:[self classicRowAt:indexPath]];
}

- (void)removeRow:(NoshiSettingsRow *)row {
    if (!row.remove) return;
    /* the block may drop the last reference to the row */
    [[row retain] autorelease];
    NSString *failure = row.remove();
    if (failure) {
        NoshiShowNotice(nil, failure);
        /* a swipe left the row open */
        [_table reloadData];
        return;
    }
    [self takeOutRow:row];
}

/* the sections without the row, and the section index it was in; a section left with no rows goes too */
- (void)takeOutRow:(NoshiSettingsRow *)row {
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < _sections.count; ++i) if ([[[_sections objectAtIndex:i] rows] containsObject:row]) at = i;
    void (^done)(void) = [[row.removed retain] autorelease];
    if (at == NSNotFound) {
        if (done) done();
        return;
    }
    NoshiSettingsSection *old = [_sections objectAtIndex:at];
    NSMutableArray *rows = [NSMutableArray arrayWithArray:old.rows];
    NSUInteger rowIndex = [rows indexOfObject:row];
    [rows removeObjectAtIndex:rowIndex];
    BOOL vanishes = rows.count == 0 || row.removesSection;
    NoshiSettingsSection *rest = [NoshiSettingsSection sectionWithHeader:old.header footer:old.footer rows:rows];
    rest.centerFooter = old.centerFooter;
    NSMutableArray *next = [NSMutableArray arrayWithArray:_sections];
    if (vanishes) [next removeObjectAtIndex:at];
    else [next replaceObjectAtIndex:at withObject:rest];
    if (_searching || ![self isViewLoaded] || !_table.window) {
        self.sections = next;
        if (done) done();
        return;
    }
    [_sections release];
    _sections = [next copy];
    [_table beginUpdates];
    if (vanishes) [_table deleteSections:[NSIndexSet indexSetWithIndex:at] withRowAnimation:UITableViewRowAnimationLeft];
    else [_table deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)rowIndex inSection:(NSInteger)at]] withRowAnimation:UITableViewRowAnimationLeft];
    [_table endUpdates];
    if (done) done();
}

- (void)takeOutModernRow:(NoshiSettingsRow *)row section:(NSUInteger)at vanishes:(BOOL)vanishes next:(NSArray *)next done:(void (^)(void))done {
    NSArray *oldFlat = [[_flat retain] autorelease];
    NSUInteger target = NSNotFound;
    NSMutableArray *removed = [NSMutableArray array];
    for (NSUInteger i = 0; i < oldFlat.count; ++i) {
        NSDictionary *item = [oldFlat objectAtIndex:i];
        if ([item objectForKey:@"row"] == row) target = i;
        if (vanishes && [[item objectForKey:@"section"] unsignedIntegerValue] == at) [removed addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    if (target == NSNotFound) {
        self.sections = next;
        if (done) done();
        return;
    }
    if (!vanishes) [removed addObject:[NSIndexPath indexPathForRow:(NSInteger)target inSection:0]];
    NSArray *oldSections = [[_sections retain] autorelease];
    [_sections release];
    _sections = [next copy];
    [self rebuildFlat];
    NSArray *newFlat = [[_flat retain] autorelease];
    if (newFlat.count + removed.count != oldFlat.count) {
        /* the rows around it changed shape in a way the table cannot be told of, so it is drawn again */
        [_table reloadData];
        if (done) done();
        return;
    }
    /* the neighbours take their new corners first, while the table still holds the old count, so that the deletion below is the only thing that moves */
    NSMutableDictionary *places = [NSMutableDictionary dictionary];
    for (NSDictionary *item in newFlat) if ([item objectForKey:@"row"]) [places setObject:[item objectForKey:@"place"] forKey:[NSValue valueWithNonretainedObject:[item objectForKey:@"row"]]];
    NSMutableArray *patched = [NSMutableArray arrayWithArray:oldFlat];
    NSMutableArray *reload = [NSMutableArray array];
    for (NSUInteger i = 0; i < oldFlat.count; ++i) {
        NSDictionary *item = [oldFlat objectAtIndex:i];
        id shown = [item objectForKey:@"row"];
        NSNumber *place = shown && shown != row ? [places objectForKey:[NSValue valueWithNonretainedObject:shown]] : nil;
        if (!place || [place isEqual:[item objectForKey:@"place"]]) continue;
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:item];
        [copy setObject:place forKey:@"place"];
        [patched replaceObjectAtIndex:i withObject:copy];
        [reload addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
    }
    [_flat release];
    _flat = [patched retain];
    if (reload.count) {
        BOOL animated = [UIView areAnimationsEnabled];
        [UIView setAnimationsEnabled:NO];
        [_table reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
        [UIView setAnimationsEnabled:animated];
    }
    (void)oldSections;
    void (^finish)(void) = ^{
        [_flat release];
        _flat = [newFlat retain];
        [_table beginUpdates];
        [_table deleteRowsAtIndexPaths:removed withRowAnimation:UITableViewRowAnimationFade];
        [_table endUpdates];
        _table.userInteractionEnabled = YES;
        if (done) done();
    };
    /* the rows that leave with the animation: the one that was asked for, or every row of its section */
    NSMutableArray *leaving = [NSMutableArray array];
    for (NSUInteger i = 0; i < oldFlat.count; ++i) {
        NSDictionary *item = [oldFlat objectAtIndex:i];
        BOOL mine = row.removesSection ? ([[item objectForKey:@"section"] unsignedIntegerValue] == at && [item objectForKey:@"row"]) : i == target;
        UITableViewCell *shown = mine ? [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]] : nil;
        if (!shown) continue;
        NoshiRowPlace place = (NoshiRowPlace)[[item objectForKey:@"place"] intValue];
        BOOL last = place == NoshiRowPlaceLast || place == NoshiRowPlaceOnly;
        UIView *wash = [[[UIView alloc] initWithFrame:CGRectMake(CARD_INSET, 0, shown.contentView.bounds.size.width - 2 * CARD_INSET, shown.contentView.bounds.size.height - (last ? 0 : ROW_GAP))] autorelease];
        wash.backgroundColor = NoshiErrorContainerColor();
        wash.layer.cornerRadius = CARD_RADIUS;
        wash.alpha = 0;
        [leaving addObject:[NSArray arrayWithObjects:shown, wash, nil]];
    }
    if (!leaving.count || NoshiReduceMotionEnabled()) {
        finish();
        return;
    }
    _table.userInteractionEnabled = NO;
    for (NSArray *pair in leaving) [[[pair objectAtIndex:0] contentView] addSubview:[pair objectAtIndex:1]];
    /* the emphasized curves of Material 3: the wash comes in decelerating, the card leaves accelerating */
    CAMediaTimingFunction *accelerate = [CAMediaTimingFunction functionWithControlPoints:0.3f:0.0f:0.8f:0.15f];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (NSArray *pair in leaving) [[pair objectAtIndex:1] setAlpha:1];
    } completion:^(BOOL ignored) {
        (void)ignored;
        /* each card becomes a pill as it shrinks; the layer keeps the end value once the animation is over */
        for (NSArray *pair in leaving) {
            UIView *wash = [pair objectAtIndex:1];
            CGFloat pill = wash.bounds.size.height / 2;
            CABasicAnimation *round = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
            round.fromValue = [NSNumber numberWithDouble:CARD_RADIUS];
            round.toValue = [NSNumber numberWithDouble:pill];
            round.duration = 0.26;
            round.timingFunction = accelerate;
            wash.layer.cornerRadius = pill;
            [wash.layer addAnimation:round forKey:@"pill"];
        }
        [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            for (NSArray *pair in leaving) {
                UITableViewCell *shown = [pair objectAtIndex:0];
                shown.transform = CGAffineTransformMakeScale(0.8f, 0.8f);
                shown.alpha = 0;
            }
        } completion:^(BOOL over) {
            (void)over;
            finish();
            /* the cells are reused by the table, so they are made whole again after their fade out has run */
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                for (NSArray *pair in leaving) {
                    [[pair objectAtIndex:1] removeFromSuperview];
                    UITableViewCell *shown = [pair objectAtIndex:0];
                    shown.transform = CGAffineTransformIdentity;
                    shown.alpha = 1;
                }
            });
        }];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CGRect rowRect = [tableView rectForRowAtIndexPath:indexPath];
    _selectPoint = [tableView convertPoint:CGPointMake(CGRectGetMidX(rowRect), CGRectGetMidY(rowRect)) toView:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NoshiSettingsRow *row = [self classicRowAt:indexPath];
    if (row.tap) row.tap();
}

@end

void NoshiSettingsChoose(UIViewController *host, NSString *title, NSArray *options, void (^handler)(NSUInteger index)) {
    void (^pick)(NSUInteger) = [handler copy];
    NoshiChoose(title, options, -1, ^(NSInteger index) {
        if (index >= 0 && pick) pick((NSUInteger)index);
    });
    [pick release];
}

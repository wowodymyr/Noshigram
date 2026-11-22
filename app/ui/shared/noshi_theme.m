#import "noshi_theme.h"

#import <objc/message.h>

#import "noshi_font_choice.h"
#import "noshi_imported_theme.h"

#include <math.h>

/* the palette is the blue of Telegram, and a color of your own can turn every hue of it: the turn in degrees, zero for the blue of the app */
static CGFloat NoshiTintShift = 0;
static BOOL NoshiDark = NO;
/* grows with every change of the palette, so what was made in the colors of an earlier one can be told from what was made in these */
static NSUInteger NoshiRevision = 1;

NSUInteger NoshiThemeRevision(void) { return NoshiRevision; }
/* how many times the saturation of the palette is multiplied; a color of your own sets it */
static CGFloat NoshiTintScale = 1;
/* a color of your own is stored: palettes with a seed of their own follow it even when it lands on the hue of the app */
static BOOL NoshiCustomTint = NO;
/* how much of the value of the colors of your own a palette keeps: 1 is the palette, 0 is black. The accents, the screens, the bars, the cards and the bubbles take it (see NoshiDimRGB); the text colors never do, so the words stay readable */
static CGFloat NoshiTintBrightness = 1;
/* set while the cards of the built-in themes are drawn, which show the palette even when a .tgios-theme is on */
static BOOL NoshiImportedOff = NO;
/* the color the imported theme (the chosen one, or the one being previewed) gives this key, if it gives one; it stands before the palette */
#define NOSHI_IMPORTED(key) do { if (!NoshiImportedOff) { UIColor *imported_ = NoshiImportedThemeColor(key); if (imported_) return imported_; } } while (0)
/* the hue and the saturation of the light accent in the palette below, which a hue and a saturation of your own are measured from */
#define NOSHI_PALETTE_HUE 207.0
#define NOSHI_PALETTE_SATURATION 1.0

void NoshiRGBToHSV(CGFloat red, CGFloat green, CGFloat blue, CGFloat *hue, CGFloat *saturation, CGFloat *value) {
    CGFloat high = MAX(red, MAX(green, blue)), low = MIN(red, MIN(green, blue));
    CGFloat span = high - low;
    CGFloat h = 0;
    if (span > 0) {
        if (high == red) h = fmod((green - blue) / span, 6);
        else if (high == green) h = (blue - red) / span + 2;
        else h = (red - green) / span + 4;
        h *= 60;
        if (h < 0) h += 360;
    }
    if (hue) *hue = h;
    if (saturation) *saturation = high > 0 ? span / high : 0;
    if (value) *value = high;
}

void NoshiHSVToRGB(CGFloat hue, CGFloat saturation, CGFloat value, CGFloat *red, CGFloat *green, CGFloat *blue) {
    CGFloat chroma = value * saturation;
    CGFloat sector = fmod(hue, 360) / 60;
    CGFloat x = chroma * (1 - fabs(fmod(sector, 2) - 1));
    CGFloat r = 0, g = 0, b = 0;
    if (sector < 1) { r = chroma; g = x; }
    else if (sector < 2) { r = x; g = chroma; }
    else if (sector < 3) { g = chroma; b = x; }
    else if (sector < 4) { g = x; b = chroma; }
    else if (sector < 5) { r = x; b = chroma; }
    else { r = chroma; b = x; }
    CGFloat match = value - chroma;
    *red = r + match;
    *green = g + match;
    *blue = b + match;
}

/* the color with its hue turned to the color of your own; greys stay grey, since the turn leaves the saturation alone */
static UIColor *NoshiTurnedColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    if (NoshiTintShift != 0 || NoshiTintScale != 1) {
        CGFloat h, s, v;
        NoshiRGBToHSV(red, green, blue, &h, &s, &v);
        if (s > 0) {
            NoshiHSVToRGB(h + NoshiTintShift + 360, MIN(1, s * NoshiTintScale), v, &red, &green, &blue);
        }
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

/* the brightness of a color of your own taken by a surface. A dark color keeps its share of the value, and a light one is dimmed less, down to six tenths of itself, since the
   words on it are dark and a light screen turned dark would hide them. At full brightness it does nothing */
static void NoshiDimRGB(CGFloat *red, CGFloat *green, CGFloat *blue) {
    if (NoshiTintBrightness >= 1) return;
    CGFloat h, s, v;
    NoshiRGBToHSV(*red, *green, *blue, &h, &s, &v);
    CGFloat scale = v > 0.7 ? 0.6 + 0.4 * NoshiTintBrightness : NoshiTintBrightness;
    NoshiHSVToRGB(h, s, v * scale, red, green, blue);
}

/* a surface of the palette: turned to the color of your own, then dimmed by its brightness */
static UIColor *NoshiSurface(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    UIColor *turned = NoshiTurnedColor(red, green, blue, alpha);
    if (NoshiTintBrightness >= 1) return turned;
    const CGFloat *c = CGColorGetComponents(turned.CGColor);
    if (CGColorGetNumberOfComponents(turned.CGColor) != 4) return turned;
    CGFloat r = c[0], g = c[1], b = c[2];
    NoshiDimRGB(&r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:c[3]];
}

UIColor *NoshiThemeTinted(UIColor *color) {
    if (NoshiTintShift == 0 && NoshiTintScale == 1 && NoshiTintBrightness >= 1) return color;
    CGColorRef ref = color.CGColor;
    const CGFloat *c = CGColorGetComponents(ref);
    size_t count = CGColorGetNumberOfComponents(ref);
    if (count == 4) return NoshiSurface(c[0], c[1], c[2], c[3]);
    return color;
}

static UIColor *NoshiRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return NoshiTurnedColor(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

/* the same for a surface, which takes the brightness */
static UIColor *NoshiSurfaceRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return NoshiSurface(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

static NSString *const NoshiDarkThemeKey = @"NoshiDarkTheme";
static NSString *const NoshiCustomTintOnKey = @"NoshiThemeCustomTintOn";
static NSString *const NoshiCustomTintHueKey = @"NoshiThemeCustomTintHue";
static NSString *const NoshiCustomTintSaturationKey = @"NoshiThemeCustomTintSaturation";
static NSString *const NoshiCustomTintBrightnessKey = @"NoshiThemeCustomTintBrightness";
NSString *const NoshiThemeDidChangeNotification = @"NoshiThemeDidChangeNotification";
NSString *const NoshiThemeOriginKey = @"origin";

BOOL NoshiThemeStoredDark(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoshiDarkThemeKey];
}

void NoshiThemeStoreDark(BOOL dark) {
    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:NoshiDarkThemeKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: theme choice was not saved");
}

BOOL NoshiThemeIsDark(void) { return NoshiDark; }

BOOL NoshiThemeStoredCustomTint(float *hue, float *saturation, float *brightness) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:NoshiCustomTintOnKey]) return NO;
    if (hue) *hue = [defaults floatForKey:NoshiCustomTintHueKey];
    if (saturation) *saturation = [defaults floatForKey:NoshiCustomTintSaturationKey];
    if (brightness) *brightness = [defaults objectForKey:NoshiCustomTintBrightnessKey] ? MIN(1, MAX(0, [defaults floatForKey:NoshiCustomTintBrightnessKey])) : 1;
    return YES;
}

void NoshiThemeStoreCustomTint(float hue, float saturation, float brightness) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:NoshiCustomTintOnKey];
    [defaults setFloat:fmodf(fmodf(hue, 360) + 360, 360) forKey:NoshiCustomTintHueKey];
    [defaults setFloat:MIN(1, MAX(0, saturation)) forKey:NoshiCustomTintSaturationKey];
    [defaults setFloat:MIN(1, MAX(0, brightness)) forKey:NoshiCustomTintBrightnessKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the custom color was not saved");
}

UIColor *NoshiThemeCustomTintColor(float hue, float saturation, float brightness) {
    CGFloat red, green, blue;
    /* the light accent of the palette: value 0.745 */
    NoshiHSVToRGB(hue, saturation, 0.745 * MIN(1, MAX(0, brightness)), &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

/* ios 13 and later turn the default style into light content when the system is dark, and the app is not told; UIStatusBarStyleDarkContent (3) keeps the text
   black on the light theme. UIWindowScene marks the systems that know the value, older ones keep the default style */
UIStatusBarStyle NoshiStatusBarStyle(BOOL dark) {
    if (dark) return (UIStatusBarStyle)1;
    return NSClassFromString(@"UIWindowScene") ? (UIStatusBarStyle)3 : UIStatusBarStyleDefault;
}

/* ios 5 to 6 call style 1 black translucent, ios 7 on call it light content; both are light text on a dark bar */
void NoshiThemeApply(BOOL dark) {
    ++NoshiRevision;
    NoshiDark = dark;
    NoshiTintShift = 0;
    NoshiTintScale = 1;
    NoshiCustomTint = NO;
    NoshiTintBrightness = 1;
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:NoshiStatusBarStyle(dark) animated:NO];
    }
}

void NoshiThemeApplyStored(void) {
    ++NoshiRevision;
    NoshiThemeApply(NoshiThemeStoredDark());
    NoshiImportedThemeReload(NoshiThemeStoredDark());
    NoshiTintScale = 1;
    float customHue = 0, customSaturation = 0, customBrightness = 1;
    NoshiCustomTint = NoshiThemeStoredCustomTint(&customHue, &customSaturation, &customBrightness);
    if (NoshiCustomTint) {
        NoshiTintBrightness = customBrightness;
        NoshiTintShift = (CGFloat)customHue - NOSHI_PALETTE_HUE;
        NoshiTintScale = (CGFloat)customSaturation / NOSHI_PALETTE_SATURATION;
    }
    /* a theme of its own has its colors already, so a color of the person's own does not turn them again */
    if (NoshiImportedThemeSelected(NoshiDark)) {
        NoshiTintShift = 0;
        NoshiTintScale = 1;
        NoshiTintBrightness = 1;
    }
    /* the bars are light in the light theme, so the status bar over them is dark there */
    [[UIApplication sharedApplication] setStatusBarStyle:NoshiStatusBarStyle(NoshiDark) animated:NO];
}

/* an accent color of the palette: turned to the color of your own, then dimmed by its brightness */
static UIColor *NoshiAccentRGB(CGFloat red, CGFloat green, CGFloat blue) {
    UIColor *turned = NoshiRGB(red, green, blue);
    if (NoshiTintBrightness >= 1) return turned;
    const CGFloat *c = CGColorGetComponents(turned.CGColor);
    if (CGColorGetNumberOfComponents(turned.CGColor) != 4) return turned;
    CGFloat h, s, v, r, g, b;
    NoshiRGBToHSV(c[0], c[1], c[2], &h, &s, &v);
    NoshiHSVToRGB(h, s, v * NoshiTintBrightness, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:c[3]];
}

/* the colors of Telegram for iOS of the ios 6 and 7 years: the grouped grey of the system, white cells, the blue accent, and the green and white bubbles */
UIColor *NoshiColorBackdrop(void) { NOSHI_IMPORTED("list.blocksBg"); return NoshiColorScreen(); }
UIColor *NoshiColorScreen(void) { NOSHI_IMPORTED("list.plainBg"); return NoshiDark ? NoshiSurfaceRGB(18, 18, 20) : NoshiSurfaceRGB(239, 239, 244); }
UIColor *NoshiColorField(void) { NOSHI_IMPORTED("list.itemInputField.bg"); return NoshiDark ? NoshiSurfaceRGB(44, 44, 48) : NoshiSurfaceRGB(229, 229, 234); }
UIColor *NoshiColorCard(void) { NOSHI_IMPORTED("list.itemBlocksBg"); return NoshiDark ? NoshiSurfaceRGB(30, 30, 33) : NoshiSurfaceRGB(255, 255, 255); }
UIColor *NoshiColorBar(void) { NOSHI_IMPORTED("root.navBar.background"); return NoshiDark ? NoshiSurfaceRGB(26, 26, 29) : NoshiSurfaceRGB(247, 247, 247); }
UIColor *NoshiColorHairline(void) { NOSHI_IMPORTED("list.plainSeparator"); return NoshiDark ? [UIColor colorWithWhite:1 alpha:0.12] : NoshiRGB(200, 199, 204); }
UIColor *NoshiColorAccent(void) { NOSHI_IMPORTED("list.accent"); return NoshiDark ? NoshiAccentRGB(62, 152, 240) : NoshiAccentRGB(0, 126, 229); }
UIColor *NoshiColorAccentDark(void) { NOSHI_IMPORTED("root.navBar.button"); return NoshiAccentRGB(0, 94, 176); }
UIColor *NoshiColorTitle(void) { NOSHI_IMPORTED("list.primaryText"); return NoshiDark ? NoshiRGB(242, 242, 247) : [UIColor blackColor]; }
UIColor *NoshiColorMessage(void) { NOSHI_IMPORTED("chatList.messageText"); return NoshiDark ? NoshiRGB(152, 152, 158) : NoshiRGB(142, 142, 147); }
UIColor *NoshiColorDotOff(void) { NOSHI_IMPORTED("list.placeholderText"); return NoshiDark ? NoshiRGB(72, 72, 76) : NoshiRGB(199, 199, 204); }
UIColor *NoshiColorSecondary(void) { NOSHI_IMPORTED("list.secondaryText"); return NoshiDark ? NoshiRGB(152, 152, 158) : NoshiRGB(142, 142, 147); }
UIColor *NoshiColorMuted(void) { NOSHI_IMPORTED("chatList.muteIcon"); return NoshiDark ? NoshiRGB(100, 100, 106) : NoshiRGB(178, 178, 178); }
UIColor *NoshiColorBadgeRed(void) { NOSHI_IMPORTED("list.destructive"); return [UIColor colorWithRed:255 / 255.0 green:59 / 255.0 blue:48 / 255.0 alpha:1]; }
UIColor *NoshiColorQrPaper(void) { return NoshiRGB(234, 244, 253); }
UIColor *NoshiColorBubbleOut(void) { NOSHI_IMPORTED("chat.message.outgoing.bubble.withWp.bg"); return NoshiDark ? NoshiSurfaceRGB(43, 82, 120) : NoshiSurfaceRGB(225, 255, 199); }
UIColor *NoshiColorBubbleIn(void) { NOSHI_IMPORTED("chat.message.incoming.bubble.withWp.bg"); return NoshiDark ? NoshiSurfaceRGB(44, 44, 48) : NoshiSurfaceRGB(255, 255, 255); }
UIColor *NoshiColorBubbleCapsule(void) { return NoshiDark ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor colorWithRed:0.32 green:0.42 blue:0.52 alpha:0.42]; }

void NoshiThemePreviewColors(BOOL dark, UIColor **incoming, UIColor **outgoing, UIColor **incomingText, UIColor **outgoingText) {
    /* the cards of the day and the night theme show the palette of the app, not an imported theme that is on */
    BOOL wasDark = NoshiDark, wasOff = NoshiImportedOff;
    NoshiDark = dark;
    NoshiImportedOff = YES;
    if (incoming) *incoming = NoshiColorBubbleIn();
    if (outgoing) *outgoing = NoshiColorBubbleOut();
    if (incomingText) *incomingText = NoshiColorBubbleText(NO);
    if (outgoingText) *outgoingText = NoshiColorBubbleText(YES);
    NoshiDark = wasDark;
    NoshiImportedOff = wasOff;
}

UIColor *NoshiColorChatBackground(void) {
    NOSHI_IMPORTED("chat.defaultWallpaper");
    return NoshiDark ? NoshiRGB(16, 20, 26) : NoshiRGB(210, 222, 233);
}

UIColor *NoshiColorBubbleText(BOOL outgoing) {
    NOSHI_IMPORTED(outgoing ? "chat.message.outgoing.primaryText" : "chat.message.incoming.primaryText");
    return NoshiColorTitle();
}

UIColor *NoshiColorBubbleLink(BOOL outgoing) {
    NOSHI_IMPORTED(outgoing ? "chat.message.outgoing.linkText" : "chat.message.incoming.linkText");
    if (NoshiDark) return outgoing ? NoshiRGB(160, 206, 255) : NoshiColorAccent();
    return NoshiRGB(0, 75, 173);
}

UIColor *NoshiColorBubbleLinkText(BOOL outgoing) {
    return NoshiColorBubbleLink(outgoing);
}

/* the time and the checks: green on the outgoing bubble, grey on the other, as Telegram had them */
UIColor *NoshiColorBubbleMeta(BOOL outgoing) {
    NOSHI_IMPORTED(outgoing ? "chat.message.outgoing.secondaryText" : "chat.message.incoming.secondaryText");
    if (NoshiDark) return outgoing ? NoshiRGB(140, 180, 220) : NoshiColorSecondary();
    return outgoing ? NoshiRGB(89, 168, 55) : NoshiRGB(167, 167, 167);
}

/* the bubbles of Telegram, flat in one color with a faint rim. top and bottom are the fill, outline the rim */
void NoshiClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline) {
    UIColor *fill = outgoing ? NoshiColorBubbleOut() : NoshiColorBubbleIn();
    UIColor *black = [UIColor blackColor];
    /* the bubbles of an imported theme are lit and rimmed from their own fill, since the green and white ramps below belong to the palette */
    if (!NoshiImportedOff && NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.bubble.withWp.bg" : "chat.message.incoming.bubble.withWp.bg")) {
        *top = fill;
        *bottom = fill;
        *outline = NoshiMixedColor(fill, black, 0.3);
        return;
    }
    *top = fill;
    *bottom = fill;
    *outline = NoshiDark ? NoshiMixedColor(fill, black, 0.3) : (outgoing ? NoshiRGB(178, 222, 153) : NoshiRGB(206, 214, 222));
}

typedef enum { NoshiWeightRegular, NoshiWeightMedium, NoshiWeightSemibold, NoshiWeightBold } NoshiWeight;

/* Apple licenses San Francisco for mock-ups only and bars embedding it, so only the system can supply it */
static UIFont *NoshiSystemFont(NoshiWeight weight, CGFloat size) {
    static const CGFloat weights[] = {0.0, 0.23, 0.3, 0.4};
    if (![UIFont respondsToSelector:NSSelectorFromString(@"monospacedDigitSystemFontOfSize:weight:")]) return nil;
    UIFont *(*weighted)(id, SEL, CGFloat, CGFloat) = (UIFont *(*)(id, SEL, CGFloat, CGFloat))objc_msgSend;
    return weighted([UIFont class], NSSelectorFromString(@"systemFontOfSize:weight:"), size, weights[weight]);
}

/* fonts are asked for in every cell layout and every bubble draw, and each lookup resolved the family by name again */
static NSCache *NoshiFontCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

void NoshiFontsDidChange(void) {
    [NoshiFontCache() removeAllObjects];
}

static NSString *const NoshiInterfaceScaleKey = @"noshigram.interface.scale";

NSInteger NoshiInterfaceScaleStored(void) {
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:NoshiInterfaceScaleKey];
    if (![stored isKindOfClass:[NSNumber class]]) return 100;
    NSInteger percent = stored.integerValue;
    return percent < NOSHI_INTERFACE_SCALE_MIN ? NOSHI_INTERFACE_SCALE_MIN : (percent > NOSHI_INTERFACE_SCALE_MAX ? NOSHI_INTERFACE_SCALE_MAX : percent);
}

/* every font and row height asks for the scale, so it is kept in a variable and not read from the defaults each time; zero means not read yet */
static CGFloat NoshiScaleNow;

void NoshiInterfaceScaleStore(NSInteger percent) {
    percent = percent < NOSHI_INTERFACE_SCALE_MIN ? NOSHI_INTERFACE_SCALE_MIN : (percent > NOSHI_INTERFACE_SCALE_MAX ? NOSHI_INTERFACE_SCALE_MAX : percent);
    [[NSUserDefaults standardUserDefaults] setInteger:percent forKey:NoshiInterfaceScaleKey];
    NoshiScaleNow = (CGFloat)percent / 100.0f;
}

CGFloat NoshiInterfaceScale(void) {
    if (NoshiScaleNow <= 0) NoshiScaleNow = (CGFloat)NoshiInterfaceScaleStored() / 100.0f;
    return NoshiScaleNow;
}

static UIFont *NoshiFont(NoshiWeight weight, CGFloat size) {
    /* Helvetica Neue, the face of Telegram on ios 6 and 7; every system from ios 5 has these four */
    static NSString *const names[] = {@"HelveticaNeue", @"HelveticaNeue-Medium", @"HelveticaNeue-Medium", @"HelveticaNeue-Bold"};
    size *= NoshiInterfaceScale();
    NSCache *cache = NoshiFontCache();
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)(size * 100 + 0.5) * 4 + (unsigned long long)weight];
    UIFont *cached = [[[cache objectForKey:key] retain] autorelease];
    if (cached) return cached;
    UIFont *font = NoshiFontChoiceFont((int)weight, size);
    if (!font) font = NoshiSystemFont(weight, size);
    if (!font) font = [UIFont fontWithName:names[weight] size:size];
    if (!font) font = weight == NoshiWeightRegular ? [UIFont systemFontOfSize:size] : [UIFont boldSystemFontOfSize:size];
    if (font) [cache setObject:font forKey:key];
    return font;
}

UIFont *NoshiFontRegular(CGFloat size) { return NoshiFont(NoshiWeightRegular, size); }
UIFont *NoshiFontMedium(CGFloat size) { return NoshiFont(NoshiWeightMedium, size); }
UIFont *NoshiFontSemibold(CGFloat size) { return NoshiFont(NoshiWeightSemibold, size); }
UIFont *NoshiFontBold(CGFloat size) { return NoshiFont(NoshiWeightBold, size); }

UIColor *NoshiMixedColor(UIColor *base, UIColor *tint, CGFloat share) {
    CGFloat b[4] = {0, 0, 0, 1}, t[4] = {0, 0, 0, 1};
    if (![base getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]]) {
        CGFloat white;
        if (![base getWhite:&white alpha:&b[3]]) return base;
        b[0] = b[1] = b[2] = white;
    }
    if (![tint getRed:&t[0] green:&t[1] blue:&t[2] alpha:&t[3]]) {
        CGFloat white;
        if (![tint getWhite:&white alpha:&t[3]]) return base;
        t[0] = t[1] = t[2] = white;
    }
    return [UIColor colorWithRed:b[0] + (t[0] - b[0]) * share green:b[1] + (t[1] - b[1]) * share blue:b[2] + (t[2] - b[2]) * share alpha:1];
}

UIColor *NoshiColorOfRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f green:((rgb >> 8) & 0xFF) / 255.0f blue:(rgb & 0xFF) / 255.0f alpha:1];
}

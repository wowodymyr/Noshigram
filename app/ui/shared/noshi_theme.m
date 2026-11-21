#import "noshi_theme.h"

#import <objc/message.h>

#import "noshi_font_choice.h"
#import "noshi_imported_theme.h"

#include <math.h>

/* the palette is purple, and a color of your own can turn every hue of it: the turn in degrees, zero for the purple of the app */
static CGFloat NoshiTintShift = 0;
static BOOL NoshiDark = NO;
/* grows with every change of the palette, so what was made in the colors of an earlier one can be told from what was made in these */
static NSUInteger NoshiRevision = 1;

NSUInteger NoshiThemeRevision(void) { return NoshiRevision; }
static BOOL NoshiClassic = NO;
/* how many times the saturation of the palette is multiplied; a color of your own sets it */
static CGFloat NoshiTintScale = 1;
/* a color of your own is stored: palettes with a seed of their own follow it even when it lands on the hue of the app */
static BOOL NoshiCustomTint = NO;
/* how much of the value of the colors of your own a palette keeps: 1 is the palette, 0 is black. The accents, the screens, the bars, the cards and the bubbles take it (see NoshiDimRGB); the text colors never do, so the words stay readable */
static CGFloat NoshiTintBrightness = 1;
/* the hue and the saturation of the light accent in the palette below, which a hue and a saturation of your own are measured from */
#define NOSHI_PALETTE_HUE 286.0
#define NOSHI_PALETTE_SATURATION 0.6

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

/* a palette with a seed hue of its own (the Shiro screens) moved to the accent of the app: the seed hue goes to the hue the accent has now, saturation follows a color
   of your own, and a grey accent makes the palette grey. The palette keeps its own colors when no color of your own is stored */
UIColor *NoshiThemeFollowAccent(UIColor *color, CGFloat seedHue) {
    CGColorRef ref = color.CGColor;
    const CGFloat *c = CGColorGetComponents(ref);
    if (CGColorGetNumberOfComponents(ref) != 4) return color;
    CGFloat red = c[0], green = c[1], blue = c[2];
    CGFloat target = 0, scale = 1;
    BOOL grey = NO, follow = NO;
    UIColor *imported = !NoshiClassic ? NoshiImportedThemeColor("list.accent") : nil;
    if (imported) {
        const CGFloat *a = CGColorGetComponents(imported.CGColor);
        if (CGColorGetNumberOfComponents(imported.CGColor) == 4) {
            CGFloat s = 0;
            NoshiRGBToHSV(a[0], a[1], a[2], &target, &s, NULL);
            grey = s < 0.08;
            follow = YES;
        }
    } else if (NoshiCustomTint) {
        target = fmod(NOSHI_PALETTE_HUE + NoshiTintShift + 720, 360);
        scale = NoshiTintScale;
        follow = YES;
    }
    if (!follow) return color;
    if (grey) {
        CGFloat luma = 0.299f * red + 0.587f * green + 0.114f * blue;
        return [UIColor colorWithRed:luma green:luma blue:luma alpha:c[3]];
    }
    CGFloat h, s, v;
    NoshiRGBToHSV(red, green, blue, &h, &s, &v);
    if (s <= 0) return color;
    NoshiHSVToRGB(fmod(h + target - seedHue + 720, 360), MIN(1, s * scale), v, &red, &green, &blue);
    /* a palette that follows a color of your own follows its brightness as well, but not that of an imported theme, which has its own */
    if (!imported) NoshiDimRGB(&red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:c[3]];
}

static UIColor *NoshiRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return NoshiTurnedColor(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

/* the same for a surface, which takes the brightness */
static UIColor *NoshiSurfaceRGB(CGFloat red, CGFloat green, CGFloat blue) {
    return NoshiSurface(red / 255.0, green / 255.0, blue / 255.0, 1.0);
}

static NSString *const NoshiClassicThemeKey = @"NoshiClassicTheme";
static NSString *const NoshiDarkThemeKey = @"NoshiDarkTheme";
static NSString *const NoshiCustomTintOnKey = @"NoshiThemeCustomTintOn";
static NSString *const NoshiCustomTintHueKey = @"NoshiThemeCustomTintHue";
static NSString *const NoshiCustomTintSaturationKey = @"NoshiThemeCustomTintSaturation";
static NSString *const NoshiCustomTintBrightnessKey = @"NoshiThemeCustomTintBrightness";
NSString *const NoshiThemeDidChangeNotification = @"NoshiThemeDidChangeNotification";
NSString *const NoshiThemeOriginKey = @"origin";

NSString *const NoshiClassicAnywhereKey = @"noshigram.developer.classicAnywhere";

BOOL NoshiClassicThemeAvailable(void) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:NoshiClassicAnywhereKey]) return YES;
    return [[[UIDevice currentDevice] systemVersion] integerValue] <= 10;
}

/* ios 5 and 6 have no flat ui, so the modern style looks foreign there; until the person picks a style, 6 and older get the classic one */
BOOL NoshiThemeStoredClassic(void) {
    if (!NoshiClassicThemeAvailable()) return NO;
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:NoshiClassicThemeKey];
    if (!stored) return [[[UIDevice currentDevice] systemVersion] integerValue] <= 6;
    return [stored boolValue];
}

void NoshiThemeStoreClassic(BOOL classic) {
    [[NSUserDefaults standardUserDefaults] setBool:classic && NoshiClassicThemeAvailable() forKey:NoshiClassicThemeKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: theme style was not saved");
}

BOOL NoshiThemeIsClassic(void) { return NoshiClassic; }

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
    /* the login keeps its light waves, the signed in root restores the stored style */
    NoshiClassic = NO;
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:NoshiStatusBarStyle(dark) animated:NO];
    }
}

void NoshiThemeApplyStored(void) {
    ++NoshiRevision;
    NoshiThemeApply(NoshiThemeStoredDark());
    NoshiImportedThemeReload(NoshiThemeStoredDark());
    NoshiClassic = NoshiThemeStoredClassic();
    NoshiTintScale = 1;
    float customHue = 0, customSaturation = 0, customBrightness = 1;
    NoshiCustomTint = NoshiThemeStoredCustomTint(&customHue, &customSaturation, &customBrightness);
    if (NoshiCustomTint) {
        NoshiTintBrightness = customBrightness;
        NoshiTintShift = (CGFloat)customHue - NOSHI_PALETTE_HUE;
        NoshiTintScale = (CGFloat)customSaturation / NOSHI_PALETTE_SATURATION;
    }
    if (!NoshiClassic && NoshiImportedThemeSelected(NoshiDark)) {
        NoshiTintShift = 0;
        NoshiTintScale = 1;
        NoshiTintBrightness = 1;
    }
    /* the classic bars are dark purple whatever the theme, so the status bar over them is light */
    UIApplication *application = [UIApplication sharedApplication];
    if (NoshiClassic && [application respondsToSelector:@selector(setStatusBarStyle:animated:)]) [application setStatusBarStyle:(UIStatusBarStyle)1 animated:NO];
    else if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        NSString *status = NoshiImportedThemeStatusBar();
        if (status) [application setStatusBarStyle:NoshiStatusBarStyle([status isEqualToString:@"white"]) animated:NO];
    }
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

UIColor *NoshiColorBackdrop(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("list.blocksBg"); if (color) return color; } if (NoshiClassic || NoshiDark) return NoshiColorScreen(); return NoshiSurfaceRGB(242, 232, 249); }
UIColor *NoshiColorScreen(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("list.plainBg"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(24, 21, 32) : NoshiSurfaceRGB(247, 245, 251); return NoshiDark ? NoshiSurfaceRGB(21, 18, 31) : NoshiSurfaceRGB(251, 250, 254); }
UIColor *NoshiColorField(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("list.itemInputField.bg"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(46, 41, 59) : NoshiSurfaceRGB(236, 232, 245); return NoshiDark ? NoshiSurfaceRGB(43, 39, 62) : NoshiSurfaceRGB(237, 234, 248); }
UIColor *NoshiColorCard(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("list.itemBlocksBg"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(34, 30, 44) : NoshiSurfaceRGB(255, 255, 255); return NoshiDark ? NoshiSurfaceRGB(34, 30, 49) : NoshiSurfaceRGB(255, 255, 255); }
UIColor *NoshiColorBar(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("root.navBar.background"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(38, 32, 52) : NoshiSurfaceRGB(253, 252, 254); return NoshiDark ? NoshiSurfaceRGB(27, 23, 40) : NoshiSurfaceRGB(255, 255, 255); }
UIColor *NoshiColorHairline(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("list.plainSeparator") : nil; if (color) return color; return NoshiDark ? [UIColor colorWithWhite:1 alpha:0.09] : [UIColor colorWithWhite:0 alpha:0.1]; }
UIColor *NoshiColorAccent(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("list.accent") : nil; if (color) return color; return NoshiDark ? NoshiAccentRGB(172, 98, 222) : NoshiAccentRGB(164, 75, 190); }
UIColor *NoshiColorAccentDark(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("root.navBar.button") : nil; return color ? color : NoshiAccentRGB(132, 44, 160); }
UIColor *NoshiColorTitle(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("list.primaryText") : nil; if (color) return color; return NoshiDark ? NoshiRGB(240, 238, 248) : NoshiRGB(34, 34, 38); }
UIColor *NoshiColorMessage(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("chatList.messageText") : nil; if (color) return color; return NoshiDark ? NoshiRGB(176, 170, 196) : NoshiRGB(86, 86, 92); }
UIColor *NoshiColorDotOff(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("list.placeholderText") : nil; return color ? color : (NoshiDark ? NoshiRGB(84, 78, 104) : NoshiRGB(208, 204, 212)); }
UIColor *NoshiColorSecondary(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("list.secondaryText"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiRGB(172, 164, 190) : NoshiRGB(116, 108, 132); return NoshiDark ? NoshiRGB(151, 143, 178) : NoshiRGB(128, 112, 140); }
UIColor *NoshiColorMuted(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("chatList.muteIcon"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiRGB(130, 122, 150) : NoshiRGB(156, 148, 172); return NoshiDark ? NoshiRGB(108, 101, 134) : NoshiRGB(176, 166, 186); }
/* badgeBackground is the accent in most imported themes, so a red theme turned every destructive control yellow; list.destructive stays red. the fallback is not turned with the
   accent either, or a green accent made reset and delete buttons green-opposite */
UIColor *NoshiColorBadgeRed(void) { UIColor *color = !NoshiClassic ? NoshiImportedThemeColor("list.destructive") : nil; return color ? color : [UIColor colorWithRed:230 / 255.0 green:62 / 255.0 blue:72 / 255.0 alpha:1]; }
UIColor *NoshiColorQrPaper(void) { return NoshiRGB(244, 236, 251); }
UIColor *NoshiColorBubbleOut(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("chat.message.outgoing.bubble.withWp.bg"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(65, 51, 84) : NoshiSurfaceRGB(235, 225, 249); return NoshiDark ? NoshiAccentRGB(124, 70, 196) : NoshiAccentRGB(139, 80, 214); }
UIColor *NoshiColorBubbleIn(void) { if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor("chat.message.incoming.bubble.withWp.bg"); if (color) return color; } if (NoshiClassic) return NoshiDark ? NoshiSurfaceRGB(54, 47, 68) : NoshiSurfaceRGB(255, 255, 255); return NoshiDark ? NoshiSurface(0.14, 0.125, 0.2, 0.94) : NoshiSurface(1, 1, 1, 0.96); }
UIColor *NoshiColorBubbleCapsule(void) { return NoshiSurface(0.12, 0.1, 0.18, 0.5); }

void NoshiThemePreviewColors(BOOL classic, BOOL dark, UIColor **incoming, UIColor **outgoing, UIColor **incomingText, UIColor **outgoingText) {
    BOOL wasClassic = NoshiClassic, wasDark = NoshiDark;
    NoshiClassic = classic;
    NoshiDark = dark;
    if (incoming) *incoming = NoshiColorBubbleIn();
    if (outgoing) *outgoing = NoshiColorBubbleOut();
    if (incomingText) *incomingText = NoshiColorBubbleText(NO);
    if (outgoingText) *outgoingText = NoshiColorBubbleText(YES);
    NoshiClassic = wasClassic;
    NoshiDark = wasDark;
}

UIColor *NoshiColorChatBackground(void) {
    UIColor *imported = !NoshiClassic ? NoshiImportedThemeColor("chat.defaultWallpaper") : nil;
    if (imported) return imported;
    return NoshiDark ? NoshiRGB(25, 29, 36) : NoshiRGB(218, 225, 233);
}

UIColor *NoshiColorBubbleText(BOOL outgoing) {
    if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.primaryText" : "chat.message.incoming.primaryText"); if (color) return color; }
    return outgoing && !NoshiClassic ? [UIColor whiteColor] : NoshiColorTitle();
}

UIColor *NoshiColorBubbleLink(BOOL outgoing) {
    if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.linkText" : "chat.message.incoming.linkText"); if (color) return color; }
    return outgoing && !NoshiClassic ? [UIColor colorWithWhite:1 alpha:0.92] : NoshiColorAccent();
}

/* the links in the words of a message: the classic outgoing bubble is lit in the accent, so a link in the accent itself vanished into it. half way to white keeps the hue of the
   theme and reads on the bubble, where the quote bars and names above keep the plain accent */
UIColor *NoshiColorBubbleLinkText(BOOL outgoing) {
    if (outgoing && NoshiClassic) return NoshiMixedColor(NoshiColorAccent(), [UIColor whiteColor], 0.5);
    return NoshiColorBubbleLink(outgoing);
}

UIColor *NoshiColorBubbleMeta(BOOL outgoing) {
    if (!NoshiClassic) { UIColor *color = NoshiImportedThemeColor(outgoing ? "chat.message.outgoing.secondaryText" : "chat.message.incoming.secondaryText"); if (color) return color; }
    return outgoing && !NoshiClassic ? [UIColor colorWithWhite:1 alpha:0.78] : NoshiColorSecondary();
}

/* the bubbles are lit from above in the accent of the theme: top is the lit edge, bottom the color the picture is filled with and the light that bounces up from the lower
   edge, outline the dark rim. the colors follow the accent, so a color of the person's own reaches the bubbles */
void NoshiClassicBubbleColors(BOOL outgoing, UIColor **top, UIColor **bottom, UIColor **outline) {
    UIColor *accent = NoshiColorAccent();
    UIColor *white = [UIColor whiteColor], *black = [UIColor blackColor];
    if (NoshiDark) {
        if (outgoing) {
            *top = NoshiMixedColor(accent, black, 0.12);
            *bottom = NoshiMixedColor(accent, black, 0.34);
            *outline = NoshiMixedColor(accent, black, 0.68);
        } else {
            UIColor *grey = [UIColor colorWithWhite:0.3 alpha:1];
            *top = NoshiMixedColor(grey, accent, 0.16);
            *bottom = NoshiMixedColor([UIColor colorWithWhite:0.2 alpha:1], accent, 0.14);
            *outline = NoshiMixedColor([UIColor colorWithWhite:0.06 alpha:1], accent, 0.12);
        }
    } else if (outgoing) {
        *top = NoshiMixedColor(accent, white, 0.56);
        *bottom = NoshiMixedColor(accent, white, 0.36);
        *outline = NoshiMixedColor(accent, black, 0.45);
    } else {
        *top = white;
        *bottom = NoshiMixedColor([UIColor colorWithWhite:0.9 alpha:1], accent, 0.07);
        *outline = NoshiMixedColor([UIColor colorWithWhite:0.52 alpha:1], accent, 0.28);
    }
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
    static NSString *const names[] = {@"Inter-Regular", @"Inter-Medium", @"Inter-SemiBold", @"Inter-Bold"};
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

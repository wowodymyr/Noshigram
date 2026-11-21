#import "noshi_shiro_style.h"

#import "noshi_theme.h"

static UIColor *NoshiShiroFixedHex(unsigned int light, unsigned int dark) {
    unsigned int rgb = NoshiThemeIsDark() ? dark : light;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

/* the hue of the raspberry seed of the palette (the primary of the day, 0xBC0F52) */
#define SHIRO_SEED_HUE 337.0

/* the palette follows the accent of the app (color of your own, imported theme): its seed goes to the hue of the accent, and every
   tone turns the same way, so the primary of this screen is the accent of the rest */
static UIColor *NoshiShiroHex(unsigned int light, unsigned int dark) {
    return NoshiThemeFollowAccent(NoshiShiroFixedHex(light, dark), SHIRO_SEED_HUE);
}

UIColor *NoshiShiroColorSurface(void) { return NoshiShiroHex(0xFFF8F8, 0x1A1113); }
UIColor *NoshiShiroColorSurfaceContainer(void) { return NoshiShiroHex(0xFBEAEC, 0x271D1F); }
UIColor *NoshiShiroColorSurfaceHighest(void) { return NoshiShiroHex(0xF0DFE2, 0x3D3234); }
UIColor *NoshiShiroColorOnSurface(void) { return NoshiShiroHex(0x22191B, 0xF0DEE0); }
UIColor *NoshiShiroColorOnSurfaceVariant(void) { return NoshiShiroHex(0x524347, 0xD6C2C5); }
UIColor *NoshiShiroColorOutline(void) { return NoshiShiroHex(0x847376, 0x9F8C8F); }
UIColor *NoshiShiroColorPrimary(void) { return NoshiShiroHex(0xBC0F52, 0xFFB1C6); }
UIColor *NoshiShiroColorOnPrimary(void) { return NoshiShiroHex(0xFFFFFF, 0x660030); }
UIColor *NoshiShiroColorPrimaryContainer(void) { return NoshiShiroHex(0xFFD9E2, 0x8E0043); }
UIColor *NoshiShiroColorOnPrimaryContainer(void) { return NoshiShiroHex(0x3E001D, 0xFFD9E2); }
UIColor *NoshiShiroColorSecondaryContainer(void) { return NoshiShiroHex(0xFFD9E1, 0x5B3F46); }
UIColor *NoshiShiroColorOnSecondaryContainer(void) { return NoshiShiroHex(0x2B151B, 0xFFD9E1); }
UIColor *NoshiShiroColorError(void) { return NoshiShiroFixedHex(0xBA1A1A, 0xFFB4AB); }
UIColor *NoshiShiroColorErrorContainer(void) { return NoshiShiroFixedHex(0xFFDAD6, 0x93000A); }
UIColor *NoshiShiroColorOnErrorContainer(void) { return NoshiShiroFixedHex(0x410002, 0xFFDAD6); }

NSArray *NoshiShiroShimmerColors(void) {
    /* raspberry, then the peach and lilac tertiary and secondary tones of the same seed */
    return [NSArray arrayWithObjects:NoshiShiroHex(0xD81B60, 0xFF8FB1), NoshiShiroHex(0xF0743C, 0xFFB38A),
            NoshiShiroHex(0x8E4DD6, 0xCBA6FF), NoshiShiroHex(0x1E88E5, 0x8CC8FF), nil];
}

/* the faces of the bundle: Rubik-Regular, Rubik-Medium and Rubik-Bold are registered in Info.plist, and ios before 11 reads no variable font axes */
UIFont *NoshiShiroFontDisplay(CGFloat size) {
    size *= NoshiInterfaceScale();
    UIFont *font = [UIFont fontWithName:@"Rubik-Bold" size:size];
    return font ? font : [UIFont boldSystemFontOfSize:size];
}

UIFont *NoshiShiroFontBody(CGFloat size, BOOL medium) {
    size *= NoshiInterfaceScale();
    UIFont *font = [UIFont fontWithName:medium ? @"Rubik-Medium" : @"Rubik-Regular" size:size];
    if (font) return font;
    return medium ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

NSString *NoshiShiroByteText(unsigned long long bytes) {
    static const char *const units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = (double)bytes;
    size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < sizeof(units) / sizeof(units[0])) {
        value /= 1024.0;
        ++unit;
    }
    if (unit == 0) return [NSString stringWithFormat:@"%llu %s", bytes, units[0]];
    return [NSString stringWithFormat:@"%.1f %s", value, units[unit]];
}

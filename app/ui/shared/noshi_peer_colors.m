#import "noshi_peer_colors.h"

static NSString *const NoshiServerNameColorsKey = @"noshigram.namecolors";

/* red, orange, violet, green, cyan, blue, pink: the avatar_nameInMessage colors, for the light theme and for its
   night themes */
static const uint32_t NoshiLightNames[] = {0xCC5049, 0xD67722, 0x955CDB, 0x40A920, 0x309EBA, 0x368AD1, 0xC7508B};
static const uint32_t NoshiDarkNames[] = {0xE88878, 0xE8AB5A, 0x8C8DEA, 0x7DD071, 0x53CCC6, 0x5CADEA, 0xE8749A};
#define BUILT_IN (sizeof(NoshiLightNames) / sizeof(NoshiLightNames[0]))

static UIColor *NoshiNameRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

NSUInteger NoshiBuiltInNameColorCount(void) {
    return BUILT_IN;
}

NSInteger NoshiDefaultNameColorId(long long userId) {
    return (NSInteger)((NSUInteger)(userId < 0 ? -userId : userId) % BUILT_IN);
}

NSArray *NoshiServerNameColors(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:NoshiServerNameColorsKey];
    return [stored isKindOfClass:[NSArray class]] ? stored : [NSArray array];
}

void NoshiStoreServerNameColors(NSArray *colors) {
    [[NSUserDefaults standardUserDefaults] setObject:colors forKey:NoshiServerNameColorsKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the name colors of the server were not saved");
}

UIColor *NoshiNameColor(NSInteger colorId, long long userId, BOOL dark) {
    if (colorId >= 0 && (NSUInteger)colorId < BUILT_IN) return NoshiNameRGB(dark ? NoshiDarkNames[colorId] : NoshiLightNames[colorId]);
    if (colorId >= (NSInteger)BUILT_IN) {
        for (NSDictionary *option in NoshiServerNameColors()) {
            if ([[option objectForKey:@"id"] integerValue] != colorId) continue;
            return NoshiNameRGB((uint32_t)[[option objectForKey:dark ? @"dark" : @"light"] unsignedIntegerValue]);
        }
    }
    NSInteger fallback = NoshiDefaultNameColorId(userId);
    return NoshiNameRGB(dark ? NoshiDarkNames[fallback] : NoshiLightNames[fallback]);
}

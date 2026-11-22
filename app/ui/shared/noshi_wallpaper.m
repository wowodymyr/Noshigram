#import "noshi_wallpaper.h"
#import "noshi_imported_theme.h"

#include <math.h>
#include <string.h>

#import "noshi_platform.h"
#import "noshi_chat_settings.h"
#import "noshi_theme.h"
#import "noshi_wave.h"
#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>

NSString *const NoshiWallpaperDidChangeNotification = @"NoshiWallpaperDidChange";

static NSString *const NoshiWallpaperKindKey = @"noshigram.wallpaper.kind";
static NSString *const NoshiWallpaperTopKey = @"noshigram.wallpaper.top";
static NSString *const NoshiWallpaperBottomKey = @"noshigram.wallpaper.bottom";
static NSString *const NoshiWallpaperAngleKey = @"noshigram.wallpaper.angle";
static NSString *const NoshiWallpaperPatternKey = @"noshigram.wallpaper.pattern";
static NSString *const NoshiWallpaperIntensityKey = @"noshigram.wallpaper.intensity";
static NSString *const NoshiWallpaperBlurKey = @"noshigram.wallpaper.blur";
static NSString *const NoshiWallpaperDimKey = @"noshigram.wallpaper.dim";

/* the longest side of a stored photo, in pixels: the 4s shows a wallpaper at 960, and a bigger one would only cost memory */
#define PHOTO_SIDE_MAX 1280.0
/* the pattern is darkened or lightened up to this much at full intensity */
#define PATTERN_ALPHA_MAX 0.55
/* blur a quarter-size image to keep the temporary buffers small on ios 5 */
#define BLUR_DIVISOR 4.0
#define DIM_ALPHA_MAX 0.8

#pragma mark storage

static NSInteger NoshiStoredInteger(NSString *key, NSInteger fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : fallback;
}

static NSInteger NoshiClampInt(NSInteger value, NSInteger low, NSInteger high) {
    return value < low ? low : (value > high ? high : value);
}

/* the keys of the wallpaper of one chat carry the chat after the name, the keys of every chat are the ones the app always had */
static NSString *NoshiScopeSuffix(int32_t chatKind, long long chat) {
    return chat ? [NSString stringWithFormat:@".chat%d_%lld", (int)chatKind, chat] : @"";
}

/* each tone keeps its own wallpaper: the night keys carry a suffix, the day ones are the keys the app always had */
static NSString *NoshiToneKey(NSString *key, BOOL dark, int32_t chatKind, long long chat) {
    NSString *scoped = [key stringByAppendingString:NoshiScopeSuffix(chatKind, chat)];
    return dark ? [scoped stringByAppendingString:@".dark"] : scoped;
}

static BOOL NoshiToneHasKey(NSString *key, BOOL dark, int32_t chatKind, long long chat) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:NoshiToneKey(key, dark, chatKind, chat)] != nil;
}

static NSInteger NoshiToneInteger(NSString *key, BOOL dark, int32_t chatKind, long long chat, NSInteger fallback) {
    return NoshiStoredInteger(NoshiToneKey(key, dark, chatKind, chat), fallback);
}

/* how light a gradient is, 0 to 1, by the middle of its two colors */
static CGFloat NoshiColorsLightness(uint32_t top, uint32_t bottom) {
    CGFloat sum = 0;
    uint32_t colors[2] = {top, bottom};
    for (int i = 0; i < 2; ++i) {
        sum += (0.299 * ((colors[i] >> 16) & 0xFF) + 0.587 * ((colors[i] >> 8) & 0xFF) + 0.114 * (colors[i] & 0xFF)) / 255.0;
    }
    return sum / 2;
}

/* a gradient that does not belong to the tone, a dark one by day or a light one by night, is not the wallpaper of that tone */
static BOOL NoshiColorsFitTone(uint32_t top, uint32_t bottom, BOOL dark) {
    CGFloat lightness = NoshiColorsLightness(top, bottom);
    return dark ? lightness <= 0.45 : lightness >= 0.4;
}

static NoshiWallpaperSetting NoshiWallpaperStoredForTone(BOOL dark, int32_t chatKind, long long chat) {
    NoshiWallpaperSetting setting;
    memset(&setting, 0, sizeof(setting));
    setting.chatKind = chat ? chatKind : 0;
    setting.chatId = chat;
    /* the night had no keys of its own before: what the day keys hold stands for it when it is a dark gradient. a chat never had keys but its own */
    BOOL own = dark && !chat ? NoshiToneHasKey(NoshiWallpaperKindKey, YES, 0, 0) : YES;
    BOOL keysDark = dark && own;
    NSInteger kind = NoshiToneInteger(NoshiWallpaperKindKey, keysDark, setting.chatKind, chat, NoshiWallpaperStandard);
    if (!own) kind = NoshiStoredInteger(NoshiWallpaperKindKey, NoshiWallpaperStandard);
    setting.kind = kind == NoshiWallpaperColors || kind == NoshiWallpaperPhoto ? (NoshiWallpaperKind)kind : NoshiWallpaperStandard;
    BOOL source = keysDark;
    setting.top = (uint32_t)(NoshiToneInteger(NoshiWallpaperTopKey, source, setting.chatKind, chat, 0xD6E2EE) & 0xFFFFFF);
    setting.bottom = (uint32_t)(NoshiToneInteger(NoshiWallpaperBottomKey, source, setting.chatKind, chat, 0xC1D2E7) & 0xFFFFFF);
    setting.angle = (int)NoshiClampInt(NoshiToneInteger(NoshiWallpaperAngleKey, source, setting.chatKind, chat, 45), 0, 359);
    setting.pattern = NoshiToneInteger(NoshiWallpaperPatternKey, source, setting.chatKind, chat, 1) ? 1 : 0;
    setting.intensity = (int)NoshiClampInt(NoshiToneInteger(NoshiWallpaperIntensityKey, source, setting.chatKind, chat, 50), 0, 100);
    /* a wallpaper whose blur the person never chose takes the setting of the chats, which is on unless it was turned off */
    setting.blur = NoshiToneInteger(NoshiWallpaperBlurKey, source, setting.chatKind, chat, NoshiChatFlagGet(NoshiChatFlagBlurWallpaper) ? 1 : 0) ? 1 : 0;
    setting.dim = (int)NoshiClampInt(NoshiToneInteger(NoshiWallpaperDimKey, source, setting.chatKind, chat, 0), 0, 100);
    if (setting.kind == NoshiWallpaperColors && !NoshiColorsFitTone(setting.top, setting.bottom, dark)) setting.kind = NoshiWallpaperStandard;
    /* the photo of the day is the one the app always kept; the night has a file of its own, so legacy keys never lend a photo to it */
    if (setting.kind == NoshiWallpaperPhoto && dark && !own) setting.kind = NoshiWallpaperStandard;
    return setting;
}

NoshiWallpaperSetting NoshiWallpaperStored(void) {
    return NoshiWallpaperStoredForTone(NoshiThemeIsDark(), 0, 0);
}

BOOL NoshiWallpaperChatHasOwn(int32_t peerKind, long long peerId) {
    return peerId && NoshiWallpaperStoredForTone(NoshiThemeIsDark(), peerKind, peerId).kind != NoshiWallpaperStandard;
}

NoshiWallpaperSetting NoshiWallpaperStoredForChat(int32_t peerKind, long long peerId) {
    if (!peerId) return NoshiWallpaperStored();
    if (NoshiWallpaperChatHasOwn(peerKind, peerId)) return NoshiWallpaperStoredForTone(NoshiThemeIsDark(), peerKind, peerId);
    NoshiWallpaperSetting setting = NoshiWallpaperStored();
    setting.chatKind = peerKind;
    setting.chatId = peerId;
    return setting;
}

void NoshiWallpaperStore(NoshiWallpaperSetting setting) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL dark = NoshiThemeIsDark();
    int32_t chatKind = setting.chatId ? setting.chatKind : 0;
    long long chat = setting.chatId;
    [defaults setInteger:setting.kind forKey:NoshiToneKey(NoshiWallpaperKindKey, dark, chatKind, chat)];
    [defaults setInteger:setting.top & 0xFFFFFF forKey:NoshiToneKey(NoshiWallpaperTopKey, dark, chatKind, chat)];
    [defaults setInteger:setting.bottom & 0xFFFFFF forKey:NoshiToneKey(NoshiWallpaperBottomKey, dark, chatKind, chat)];
    [defaults setInteger:NoshiClampInt(setting.angle, 0, 359) forKey:NoshiToneKey(NoshiWallpaperAngleKey, dark, chatKind, chat)];
    [defaults setInteger:setting.pattern ? 1 : 0 forKey:NoshiToneKey(NoshiWallpaperPatternKey, dark, chatKind, chat)];
    [defaults setInteger:NoshiClampInt(setting.intensity, 0, 100) forKey:NoshiToneKey(NoshiWallpaperIntensityKey, dark, chatKind, chat)];
    [defaults setInteger:setting.blur ? 1 : 0 forKey:NoshiToneKey(NoshiWallpaperBlurKey, dark, chatKind, chat)];
    [defaults setInteger:NoshiClampInt(setting.dim, 0, 100) forKey:NoshiToneKey(NoshiWallpaperDimKey, dark, chatKind, chat)];
    NoshiDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiWallpaperDidChangeNotification object:nil];
}

static NSString *NoshiWallpaperPhotoPathForTone(BOOL dark, int32_t chatKind, long long chat) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *name = chat ? [NSString stringWithFormat:@"wallpaper-chat%d_%lld%@.jpg", (int)chatKind, chat, dark ? @"-dark" : @""] : (dark ? @"wallpaper-dark.jpg" : @"wallpaper.jpg");
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:name];
}

static BOOL NoshiWallpaperUsePhoto(NSString *path, int32_t chatKind, long long chat) {
    UIImage *photo = [UIImage imageWithContentsOfFile:path];
    if (!photo) return NO;
    /* a photo from the library is shrunk once, to what any screen shows, and kept as a jpeg */
    CGFloat longest = MAX(photo.size.width, photo.size.height);
    CGFloat factor = longest > PHOTO_SIDE_MAX ? PHOTO_SIDE_MAX / longest : 1;
    UIImage *kept = photo;
    if (factor < 1) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(floor(photo.size.width * factor), floor(photo.size.height * factor)), YES, 1);
        [photo drawInRect:CGRectMake(0, 0, floor(photo.size.width * factor), floor(photo.size.height * factor))];
        kept = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    NSData *data = UIImageJPEGRepresentation(kept, 0.85);
    NSString *target = NoshiWallpaperPhotoPathForTone(NoshiThemeIsDark(), chatKind, chat);
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[target stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!data || ![data writeToFile:target options:NSDataWritingAtomic error:&error]) {
        NSLog(@"noshigram: the wallpaper photo was not kept: %@", error);
        return NO;
    }
    NoshiWallpaperSetting setting = NoshiWallpaperStoredForChat(chatKind, chat);
    setting.kind = NoshiWallpaperPhoto;
    setting.blur = NoshiChatFlagGet(NoshiChatFlagBlurWallpaper) ? 1 : 0;
    setting.dim = 0;
    NoshiWallpaperStore(setting);
    return YES;
}

BOOL NoshiWallpaperUsePhotoAtPathForChat(NSString *path, int32_t peerKind, long long peerId) {
    return peerId ? NoshiWallpaperUsePhoto(path, peerKind, peerId) : NoshiWallpaperUsePhoto(path, 0, 0);
}

void NoshiWallpaperClearChat(int32_t peerKind, long long peerId) {
    if (!peerId) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *const keys[] = {NoshiWallpaperKindKey, NoshiWallpaperTopKey, NoshiWallpaperBottomKey, NoshiWallpaperAngleKey, NoshiWallpaperPatternKey,
                              NoshiWallpaperIntensityKey, NoshiWallpaperBlurKey, NoshiWallpaperDimKey};
    for (int tone = 0; tone < 2; ++tone) {
        for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) [defaults removeObjectForKey:NoshiToneKey(keys[i], tone == 1, peerKind, peerId)];
        NSError *error = nil;
        NSString *file = NoshiWallpaperPhotoPathForTone(tone == 1, peerKind, peerId);
        if ([[NSFileManager defaultManager] fileExistsAtPath:file] && ![[NSFileManager defaultManager] removeItemAtPath:file error:&error]) {
            NSLog(@"noshigram: the wallpaper photo of a chat was not removed: %@", error);
        }
    }
    NoshiDefaultsSaveSoon();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiWallpaperDidChangeNotification object:nil];
}

#pragma mark presets

typedef struct {
    uint32_t top, bottom;
    int angle;
} NoshiPreset;

/* the grounds the white theme offers: pale and soft ones, a plain white to close them */
static const NoshiPreset NoshiLightPresets[] = {
    {0xD6E2EE, 0xC1D2E7, 45}, {0xDBDDBB, 0x6BA587, 45}, {0xE6EBEE, 0xC8D4DA, 90}, {0xFFE0B2, 0xF8B195, 45},
    {0xE1BEE7, 0xB39DDB, 45}, {0xF8BBD0, 0xCE93D8, 45}, {0xB2EBF2, 0x80DEEA, 90}, {0xC5E1A5, 0x9CCC65, 45},
    {0xFFF59D, 0xFFCC80, 45}, {0x90A4AE, 0x546E7A, 90}, {0xFAD0C4, 0xFF9A9E, 45}, {0xA1C4FD, 0xC2E9FB, 90},
    {0xD4FC79, 0x96E6A1, 45}, {0xE0C3FC, 0x8EC5FC, 45}, {0xF5F7FA, 0xB8C6DB, 90}, {0xFFECD2, 0xFCB69F, 45},
    {0xFF9A9E, 0xFECFEF, 45}, {0xC1DFC4, 0xDEECDD, 90}, {0xFBC2EB, 0xA6C1EE, 45}, {0xD299C2, 0xFEF9D7, 45},
    {0xB5FFFC, 0xFFDEE9, 45}, {0xF6D365, 0xFDA085, 45}, {0xCFD9DF, 0xE2EBF0, 90}, {0xC9FFBF, 0xFFAFBD, 45},
    {0xA8EDEA, 0xFED6E3, 45}, {0xFFDDE1, 0xEE9CA7, 45}, {0xBDE0FE, 0xA2D2FF, 90}, {0xFFC8DD, 0xCDB4DB, 45},
    {0xCAF0F8, 0x90E0EF, 45}, {0xFFE5D9, 0xD8E2DC, 90}, {0xE9EDC9, 0xCCD5AE, 90}, {0xFEC89A, 0xF9DCC4, 45},
    {0xE7C6FF, 0xC8B6FF, 45}, {0xB9FBC0, 0x98F5E1, 45}, {0xFBF8CC, 0xFDE4CF, 45}, {0xFFFFFF, 0xFFFFFF, 90},
};

/* the grounds the dark theme offers: deep ones, a plain black to close them */
static const NoshiPreset NoshiDarkPresets[] = {
    {0x3E3A54, 0x1B1830, 45}, {0x0F2027, 0x2C5364, 45}, {0x232526, 0x414345, 90}, {0x1E2A44, 0x3B4F7A, 45},
    {0x41295A, 0x2F0743, 45}, {0x2C3E50, 0x4CA1AF, 45}, {0x141E30, 0x243B55, 45}, {0x0F0C29, 0x302B63, 45},
    {0x1F1C2C, 0x4B4668, 45}, {0x373B44, 0x4286F4, 45}, {0x200122, 0x6F0000, 45}, {0x2B5876, 0x4E4376, 45},
    {0x134E5E, 0x2F6B4F, 45}, {0x3A1C71, 0x8E3B6B, 45}, {0x16222A, 0x3A6073, 45}, {0x42275A, 0x734B6D, 45},
    {0x1E3C72, 0x2A5298, 45}, {0x3C3B3F, 0x605C3C, 45}, {0x1D4350, 0x2B2B3A, 45}, {0x4B1D3F, 0x1B1B2F, 45},
    {0x0B3D2E, 0x1B1B2F, 90}, {0x2D1B4E, 0x0F172A, 90}, {0x101820, 0x101820, 90}, {0x000000, 0x000000, 90},
};

#define LIGHT_PRESET_COUNT (sizeof(NoshiLightPresets) / sizeof(NoshiLightPresets[0]))
#define DARK_PRESET_COUNT (sizeof(NoshiDarkPresets) / sizeof(NoshiDarkPresets[0]))

/* the picker offers the grounds of the theme on screen: the light ones by day, the dark ones by night */
static const NoshiPreset *NoshiShownPresets(NSUInteger *count) {
    if (NoshiThemeIsDark()) {
        *count = DARK_PRESET_COUNT;
        return NoshiDarkPresets;
    }
    *count = LIGHT_PRESET_COUNT;
    return NoshiLightPresets;
}

NSUInteger NoshiWallpaperPresetCount(void) {
    NSUInteger count;
    NoshiShownPresets(&count);
    return count;
}

NoshiWallpaperSetting NoshiWallpaperPreset(NSUInteger index) {
    NoshiWallpaperSetting setting = NoshiWallpaperStored();
    NSUInteger count;
    const NoshiPreset *presets = NoshiShownPresets(&count);
    if (index >= count) index = 0;
    setting.kind = NoshiWallpaperColors;
    setting.top = presets[index].top;
    setting.bottom = presets[index].bottom;
    setting.angle = presets[index].angle;
    return setting;
}

#pragma mark drawing

static void NoshiWallpaperRGB(uint32_t rgb, CGFloat out[4]) {
    out[0] = ((rgb >> 16) & 0xFF) / 255.0;
    out[1] = ((rgb >> 8) & 0xFF) / 255.0;
    out[2] = (rgb & 0xFF) / 255.0;
    out[3] = 1;
}

static CGRect NoshiFillRect(CGSize source, CGSize target) {
    CGFloat scale = MAX(target.width / source.width, target.height / source.height);
    CGSize fitted = CGSizeMake(source.width * scale, source.height * scale);
    return CGRectMake((target.width - fitted.width) / 2, (target.height - fitted.height) / 2, fitted.width, fitted.height);
}

/* the doodle pattern in one color, as a picture with transparency: the color everywhere, kept only where the pattern has ink */
static UIImage *NoshiPatternInColor(UIColor *ink) {
    /* the pattern is a 720 by 1280 picture, and a slider that moves the intensity asked for it again at every step; the black and the white one are kept */
    static UIImage *kept[2];
    NSUInteger slot = [ink isEqual:[UIColor blackColor]] ? 0 : 1;
    static BOOL watching;
    if (!watching) {
        watching = YES;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            for (int i = 0; i < 2; ++i) {
                [kept[i] release];
                kept[i] = nil;
            }
        }];
    }
    if (kept[slot]) return kept[slot];
    UIImage *pattern = [UIImage imageNamed:@"chat_pattern.png"];
    if (!pattern) return nil;
    UIGraphicsBeginImageContextWithOptions(pattern.size, NO, 1);
    CGRect rect = CGRectMake(0, 0, pattern.size.width, pattern.size.height);
    [ink setFill];
    UIRectFill(rect);
    [pattern drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1];
    kept[slot] = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return kept[slot];
}

/* the pattern already scaled to the picture it is drawn into: a slider moves the intensity at every step, and scaling the 720 by 1280 file down again each time was what
   made it stutter on old phones. Only the alpha changes between steps, so the scaled one is kept per ink and size and the system drops it under memory pressure */
static UIImage *NoshiPatternScaled(UIColor *ink, CGSize size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 3;
    });
    UIImage *pattern = NoshiPatternInColor(ink);
    if (!pattern) return nil;
    CGRect target = NoshiFillRect(pattern.size, size);
    NSString *key = [NSString stringWithFormat:@"%d|%.1fx%.1f|%.1f", [ink isEqual:[UIColor blackColor]] ? 0 : 1, (double)size.width, (double)size.height, (double)NoshiScreenScale()];
    UIImage *scaled = [cache objectForKey:key];
    if (scaled) return scaled;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [pattern drawInRect:target];
    scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (scaled) [cache setObject:scaled forKey:key];
    return scaled;
}

static UIImage *NoshiColorsImage(NoshiWallpaperSetting setting, CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat colors[8];
    NoshiWallpaperRGB(setting.top, colors);
    NoshiWallpaperRGB(setting.bottom, colors + 4);
    /* the gradient runs along its angle through the middle of the picture, and reaches the corners */
    CGFloat radians = setting.angle * M_PI / 180.0;
    CGFloat reach = (fabs(cos(radians)) * size.width + fabs(sin(radians)) * size.height) / 2;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint from = CGPointMake(middle.x - cos(radians) * reach, middle.y - sin(radians) * reach);
    CGPoint to = CGPointMake(middle.x + cos(radians) * reach, middle.y + sin(radians) * reach);
    NoshiFillGradient(context, from, to, colors, 2);
    if (setting.pattern && setting.intensity > 0) {
        /* black ink on a light ground, white on a dark one, by the brightness of the middle of the gradient */
        CGFloat mid = ((colors[0] + colors[4]) * 0.299 + (colors[1] + colors[5]) * 0.587 + (colors[2] + colors[6]) * 0.114) / 2;
        UIColor *ink = mid > 0.5 ? [UIColor blackColor] : [UIColor whiteColor];
        UIImage *pattern = NoshiPatternScaled(ink, size);
        if (pattern) [pattern drawInRect:CGRectMake(0, 0, size.width, size.height) blendMode:kCGBlendModeNormal alpha:(CGFloat)(setting.intensity / 100.0 * PATTERN_ALPHA_MAX)];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *NoshiPhotoImage(NoshiWallpaperSetting setting, CGSize size) {
    UIImage *photo = [UIImage imageWithContentsOfFile:NoshiWallpaperPhotoPathForTone(NoshiThemeIsDark(), setting.chatId ? setting.chatKind : 0, setting.chatId)];
    if (!photo) return nil;
    UIImage *source = photo;
    if (setting.blur) {
        CGSize small = CGSizeMake(MAX(8, floor(size.width / BLUR_DIVISOR)), MAX(8, floor(size.height / BLUR_DIVISOR)));
        size_t width = (size_t)small.width, height = (size_t)small.height, row = width * 4;
        void *pixels = calloc(height, row), *scratch = calloc(height, row);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = pixels && colorSpace ? CGBitmapContextCreate(pixels, width, height, 8, row, colorSpace, kCGImageAlphaPremultipliedLast) : NULL;
        if (colorSpace) CGColorSpaceRelease(colorSpace);
        if (bitmap && scratch) {
            UIGraphicsPushContext(bitmap);
            CGContextTranslateCTM(bitmap, 0, small.height);
            CGContextScaleCTM(bitmap, 1, -1);
            CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
            [photo drawInRect:NoshiFillRect(photo.size, small)];
            UIGraphicsPopContext();
            vImage_Buffer a = {pixels, height, width, row}, b = {scratch, height, width, row};
            vImage_Error error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) error = vImageBoxConvolve_ARGB8888(&b, &a, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) error = vImageBoxConvolve_ARGB8888(&a, &b, NULL, 0, 0, 9, 9, NULL, kvImageEdgeExtend);
            if (error == kvImageNoError) {
                NSData *copy = [NSData dataWithBytes:scratch length:row * height];
                CGDataProviderRef provider = copy ? CGDataProviderCreateWithCFData((CFDataRef)copy) : NULL;
                CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
                CGImageRef blurred = provider && rgb ? CGImageCreate(width, height, 8, 32, row, rgb, (CGBitmapInfo)kCGImageAlphaPremultipliedLast,
                                                                     provider, NULL, true, kCGRenderingIntentDefault) : NULL;
                if (blurred) { source = [UIImage imageWithCGImage:blurred]; CGImageRelease(blurred); }
                else NSLog(@"noshigram: blurred wallpaper image could not be made");
                if (provider) CGDataProviderRelease(provider);
                if (rgb) CGColorSpaceRelease(rgb);
            } else NSLog(@"noshigram: wallpaper blur failed: %ld", (long)error);
        } else NSLog(@"noshigram: wallpaper blur buffers could not be allocated");
        if (bitmap) CGContextRelease(bitmap);
        free(pixels);
        free(scratch);
    }
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [source drawInRect:NoshiFillRect(source.size, size)];
    if (setting.dim > 0) {
        [[UIColor colorWithWhite:0 alpha:(CGFloat)(setting.dim / 100.0 * DIM_ALPHA_MAX)] setFill];
        UIRectFillUsingBlendMode(CGRectMake(0, 0, size.width, size.height), kCGBlendModeNormal);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIImage *NoshiWallpaperImage(NoshiWallpaperSetting setting, CGSize size) {
    if (size.width < 1 || size.height < 1) return nil;
    switch (setting.kind) {
    case NoshiWallpaperColors: return NoshiColorsImage(setting, size);
    case NoshiWallpaperPhoto: return NoshiPhotoImage(setting, size);
    case NoshiWallpaperStandard: break;
    }
    return nil;
}

/* the picture of the setting on screen is made once and kept until the setting changes, since a screen of a chat
   asks for it every time it opens */
static UIImage *NoshiShownWallpaper(void) {
    static UIImage *cached;
    static NoshiWallpaperSetting cachedSetting;
    /* the palette the picture was painted in: the same setting is painted in other colors in the other theme */
    static NSUInteger cachedRevision;
    static BOOL watching;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    @synchronized (lock) {
        if (!watching) {
            watching = YES;
            [[NSNotificationCenter defaultCenter] addObserverForName:NoshiWallpaperDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                (void)note;
                @synchronized (lock) {
                    [cached release];
                    cached = nil;
                }
            }];
        }
        NoshiWallpaperSetting setting = NoshiWallpaperStored();
        if (setting.kind == NoshiWallpaperStandard) return nil;
        if (!cached || cachedRevision != NoshiThemeRevision() || memcmp(&setting, &cachedSetting, sizeof(setting)) != 0) {
            [cached release];
            cached = [NoshiWallpaperImage(setting, [UIScreen mainScreen].bounds.size) retain];
            cachedSetting = setting;
            cachedRevision = NoshiThemeRevision();
        }
        return [[cached retain] autorelease];
    }
}

void NoshiWallpaperWarm(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool { (void)NoshiShownWallpaper(); }
    });
}

/* the preview of the settings asks for a small picture of the same setting at every layout and at every step of a slider, and a step back to a value
   already seen needs no new painting */
static UIImage *NoshiSizedWallpaper(NoshiWallpaperSetting setting, CGSize size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 4;
        [[NSNotificationCenter defaultCenter] addObserverForName:NoshiWallpaperDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            (void)note;
            [cache removeAllObjects];
        }];
    });
    /* a new photo for the same setting is a new picture, and the notification that empties this cache reaches it after the screens that ask for the picture have asked */
    NSString *stamp = @"";
    if (setting.kind == NoshiWallpaperPhoto) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:NoshiWallpaperPhotoPathForTone(NoshiThemeIsDark(), setting.chatId ? setting.chatKind : 0, setting.chatId) error:NULL];
        stamp = [[attributes fileModificationDate] description];
    }
    NSString *key = [NSString stringWithFormat:@"%@|%.1fx%.1f|t%lu|%@", [[NSData dataWithBytes:&setting length:sizeof(setting)] description], (double)size.width, (double)size.height,
                     (unsigned long)NoshiThemeRevision(), stamp];
    UIImage *image = [cache objectForKey:key];
    if (!image) {
        image = NoshiWallpaperImage(setting, size);
        if (image) [cache setObject:image forKey:key];
    }
    return image;
}

#pragma mark applying

void NoshiApplyChatWallpaper(UIImageView *view, BOOL dark) {
    NoshiApplyWallpaperStyle(view, dark);
    /* the picked wallpaper takes the place of the standard picture */
    UIImage *picked = NoshiShownWallpaper();
    if (picked) view.image = picked;
}

void NoshiApplyChatWallpaperForChat(UIImageView *view, BOOL dark, int32_t peerKind, long long peerId) {
    NoshiApplyChatWallpaper(view, dark);
    if (!peerId || !NoshiWallpaperChatHasOwn(peerKind, peerId)) return;
    /* the wallpaper picked for this chat alone takes the place of the one every chat wears */
    NoshiWallpaperSetting own = NoshiWallpaperStoredForChat(peerKind, peerId);
    UIImage *picture = NoshiSizedWallpaper(own, [UIScreen mainScreen].bounds.size);
    if (picture) view.image = picture;
}

void NoshiApplyChatWallpaperSizedForChat(UIImageView *view, BOOL dark, CGSize size, int32_t peerKind, long long peerId) {
    NoshiApplyWallpaperStyle(view, dark);
    NoshiWallpaperSetting setting = NoshiWallpaperStoredForChat(peerKind, peerId);
    /* a preview a few hundred points wide does not need the picture of the whole screen, which cost a full repaint of the pattern at every step of a slider */
    if (setting.kind != NoshiWallpaperStandard) view.image = NoshiSizedWallpaper(setting, size);
}

static UIImage *NoshiImportedWallpaperGradientImage(const uint32_t values[4], NSUInteger count, int angle, CGSize size) {
    if (size.width < 1 || size.height < 1 || count == 0 || count > 4) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 3;
        cache.totalCostLimit = 12 * 1024 * 1024;
    });
    NSString *key = [NSString stringWithFormat:@"%08x-%08x-%08x-%08x-%lu-%d-%.0fx%.0f", values[0], values[1], values[2], values[3], (unsigned long)count, angle, size.width, size.height];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    CGFloat colors[16] = {0};
    for (NSUInteger i = 0; i < count; ++i) {
        colors[i * 4] = ((values[i] >> 16) & 255) / 255.0;
        colors[i * 4 + 1] = ((values[i] >> 8) & 255) / 255.0;
        colors[i * 4 + 2] = (values[i] & 255) / 255.0;
        colors[i * 4 + 3] = ((values[i] >> 24) & 255) / 255.0;
    }
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat radians = angle * M_PI / 180.0;
    CGFloat reach = (fabs(cos(radians)) * size.width + fabs(sin(radians)) * size.height) / 2;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint from = CGPointMake(middle.x - cos(radians) * reach, middle.y - sin(radians) * reach);
    CGPoint to = CGPointMake(middle.x + cos(radians) * reach, middle.y + sin(radians) * reach);
    if (count == 1) {
        memcpy(colors + 4, colors, 4 * sizeof(CGFloat));
        count = 2;
    }
    NoshiFillGradient(context, from, to, colors, count);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key cost:(NSUInteger)(size.width * size.height * 4)];
    return image;
}

/* the hue the bundled pictures are drawn in, the purple of the palette */
#define STANDARD_SEED_HUE 286.0

/* a bundled picture with its hue turned: the hue blend keeps the lightness and saturation of the drawing and takes only the hue of the fill, so the paper and the black
   stay as they are and a grey accent turns the lines grey. ownHue below zero follows the accent of the app and returns the picture as shipped while the accent is the
   seed purple; zero and up is a hue the person chose. the turned picture is kept per name, hue and palette */
static UIImage *NoshiTurnedImage(UIImage *original, NSString *name, CGFloat seedHue, NSInteger ownHue) {
    UIColor *seed = [UIColor colorWithHue:(CGFloat)(seedHue / 360.0) saturation:1 brightness:1 alpha:1];
    UIColor *accent = ownHue >= 0 ? [UIColor colorWithHue:(CGFloat)(ownHue / 360.0) saturation:1 brightness:1 alpha:1] : NoshiColorAccent();
    CGFloat seedRed = 0, seedGreen = 0, seedBlue = 0, red = 0, green = 0, blue = 0;
    if (![seed getRed:&seedRed green:&seedGreen blue:&seedBlue alpha:NULL] || ![accent getRed:&red green:&green blue:&blue alpha:NULL]) return original;
    if (fabs(seedRed - red) + fabs(seedGreen - green) + fabs(seedBlue - blue) < 0.005) return original;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 6;
    });
    NSString *key = [NSString stringWithFormat:@"%@|%ld|%lu", name, (long)ownHue, (unsigned long)NoshiThemeRevision()];
    UIImage *turned = [[[cache objectForKey:key] retain] autorelease];
    if (turned) return turned;
    UIGraphicsBeginImageContextWithOptions(original.size, YES, original.scale);
    CGRect rect = CGRectMake(0, 0, original.size.width, original.size.height);
    [original drawInRect:rect];
    [accent setFill];
    UIRectFillUsingBlendMode(rect, kCGBlendModeHue);
    turned = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!turned) return original;
    [cache setObject:turned forKey:key];
    return turned;
}

static UIImage *NoshiStandardWallpaperImage(BOOL dark) {
    NSString *name = dark ? @"chat_bg_dark.jpg" : @"chat_bg_light.jpg";
    UIImage *original = [UIImage imageNamed:name];
    return original ? NoshiTurnedImage(original, name, STANDARD_SEED_HUE, -1) : nil;
}

void NoshiApplyWallpaperStyle(UIImageView *view, BOOL dark) {
    /* the doodles of the standard wallpaper, turned to the blue of the app; an imported theme lays its own gradient or color instead */
    uint32_t values[4] = {0};
    int angle = 90;
    (void)dark;
    NSUInteger importedColors = NoshiImportedThemeWallpaperGradient(values, &angle);
    BOOL importedBackground = NoshiImportedThemeColor("chat.defaultWallpaper") != nil;
    view.image = importedColors ? NoshiImportedWallpaperGradientImage(values, importedColors, angle, [UIScreen mainScreen].bounds.size)
                                : (importedBackground ? nil : NoshiStandardWallpaperImage(dark));
    view.backgroundColor = NoshiColorChatBackground();
    view.contentMode = UIViewContentModeScaleAspectFill;
    view.clipsToBounds = YES;
}


#pragma mark kept chat wallpapers

#define CHAT_WALLPAPER_FILES_MAX 40

static NSString *NoshiChatWallpaperDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return roots.count ? [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"chat-wallpapers"] : nil;
}

static NSString *NoshiChatWallpaperPath(int32_t peerKind, long long peerId) {
    NSString *directory = NoshiChatWallpaperDirectory();
    return directory ? [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d-%lld.plist", (int)peerKind, peerId]] : nil;
}

NSString *NoshiChatWallpaperSignature(const noshi_chat_wallpaper *paper, NSString *fileKey) {
    if (!paper || !paper->present) return nil;
    return [NSString stringWithFormat:@"%d,%d,%d,%d,%08x,%08x,%08x,%08x,%d,%d,%@", paper->pattern, paper->blur, paper->color_count, paper->has_file, paper->colors[0], paper->colors[1],
            paper->colors[2], paper->colors[3], (int)paper->rotation, (int)paper->intensity, fileKey ? fileKey : @""];
}

UIImage *NoshiCachedChatWallpaper(int32_t peerKind, long long peerId, CGSize size, NSString *signature, NSString **found) {
    if (found) *found = nil;
    NSString *path = NoshiChatWallpaperPath(peerKind, peerId);
    NSDictionary *kept = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    if (![kept isKindOfClass:[NSDictionary class]]) return nil;
    NSString *kept_signature = [kept objectForKey:@"signature"];
    NSData *data = [kept objectForKey:@"image"];
    if (![kept_signature isKindOfClass:[NSString class]] || ![data isKindOfClass:[NSData class]]) return nil;
    if (signature && ![signature isEqualToString:kept_signature]) return nil;
    /* a turned screen needs another size, and a picture stretched to it would be soft */
    if (fabs([[kept objectForKey:@"width"] doubleValue] - size.width) > 1 || fabs([[kept objectForKey:@"height"] doubleValue] - size.height) > 1) return nil;
    /* imageWithData:scale: came with ios 6, so the scale is given through the bitmap */
    UIImage *decoded = [UIImage imageWithData:data];
    UIImage *image = decoded.CGImage ? [UIImage imageWithCGImage:decoded.CGImage scale:NoshiScreenScale() orientation:UIImageOrientationUp] : nil;
    if (image && found) *found = kept_signature;
    return image;
}

void NoshiStoreChatWallpaper(int32_t peerKind, long long peerId, CGSize size, NSString *signature, UIImage *image) {
    NSString *path = NoshiChatWallpaperPath(peerKind, peerId);
    if (!path || !signature || !image) return;
    NSData *data = UIImageJPEGRepresentation(image, 0.85f);
    if (!data) return;
    NSDictionary *kept = [NSDictionary dictionaryWithObjectsAndKeys:signature, @"signature", data, @"image", [NSNumber numberWithDouble:size.width], @"width",
                          [NSNumber numberWithDouble:size.height], @"height", nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            NSFileManager *files = [NSFileManager defaultManager];
            NSString *directory = [path stringByDeletingLastPathComponent];
            NSError *error = nil;
            if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"noshigram: chat wallpaper folder was not made: %@", error);
                return;
            }
            if (![kept writeToFile:path atomically:YES]) {
                NSLog(@"noshigram: chat wallpaper %@ was not kept", path.lastPathComponent);
                return;
            }
            /* the oldest go first, so the kept pictures stay a few dozen */
            NSArray *names = [files contentsOfDirectoryAtPath:directory error:NULL];
            if (names.count <= CHAT_WALLPAPER_FILES_MAX) return;
            NSMutableArray *dated = [NSMutableArray array];
            for (NSString *name in names) {
                NSDate *date = [[files attributesOfItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL] fileModificationDate];
                [dated addObject:[NSArray arrayWithObjects:name, date ? date : [NSDate distantPast], nil]];
            }
            [dated sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [[a objectAtIndex:1] compare:[b objectAtIndex:1]]; }];
            for (NSUInteger i = 0; i + CHAT_WALLPAPER_FILES_MAX < dated.count; ++i) {
                NSError *removeError = nil;
                if (![files removeItemAtPath:[directory stringByAppendingPathComponent:[[dated objectAtIndex:i] objectAtIndex:0]] error:&removeError])
                    NSLog(@"noshigram: old chat wallpaper was not removed: %@", removeError);
            }
        }
    });
}

void NoshiDropChatWallpaper(int32_t peerKind, long long peerId) {
    NSString *path = NoshiChatWallpaperPath(peerKind, peerId);
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) NSLog(@"noshigram: chat wallpaper was not dropped: %@", error);
}

UIImage *NoshiChannelWallpaperImage(const noshi_chat_wallpaper *paper, UIImage *file, CGSize size) {
    if (!paper || !paper->present || size.width < 1 || size.height < 1) return nil;
    if (paper->has_file && !paper->pattern) {
        if (!file) return nil;
        UIGraphicsBeginImageContextWithOptions(size, YES, 0);
        CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
        [file drawInRect:NoshiFillRect(file.size, size)];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return image;
    }
    if (!paper->color_count) return nil;
    uint32_t values[4] = {0};
    for (NSUInteger i = 0; i < paper->color_count && i < 4; ++i) values[i] = 0xFF000000u | paper->colors[i];
    /* the server counts its rotation from the top edge turning clockwise, the gradient here from the left edge turning the same way */
    int angle = (int)(((paper->rotation % 360) + 360 + 90) % 360);
    UIImage *ground = NoshiImportedWallpaperGradientImage(values, paper->color_count, angle, size);
    if (!ground || !paper->pattern || paper->intensity <= 0) return ground;
    CGFloat red = 0, green = 0, blue = 0, shade = 0;
    for (NSUInteger i = 0; i < paper->color_count; ++i) {
        red += ((paper->colors[i] >> 16) & 255) / 255.0;
        green += ((paper->colors[i] >> 8) & 255) / 255.0;
        blue += (paper->colors[i] & 255) / 255.0;
    }
    shade = (red * 0.299 + green * 0.587 + blue * 0.114) / paper->color_count;
    UIImage *doodle = NoshiPatternInColor(shade > 0.5 ? [UIColor blackColor] : [UIColor whiteColor]);
    if (!doodle) return ground;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [ground drawInRect:CGRectMake(0, 0, size.width, size.height)];
    [doodle drawInRect:NoshiFillRect(doodle.size, size) blendMode:kCGBlendModeNormal alpha:(CGFloat)(paper->intensity / 100.0 * PATTERN_ALPHA_MAX)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}


#import "noshi_app_icon.h"
#import "noshi_theme.h"

#import <UIKit/UIKit.h>

#include <fcntl.h>
#include <unistd.h>

static NSString *const NoshiIconError = @"NoshiAppIcon";
/* the screen color the launch images in the bundle were drawn for ("|15121f"), kept in the Info.plist so that a new install, which brings
   its own launch images and plist, drops it */
static NSString *const NoshiLaunchIconKey = @"NoshiLaunchIcon";
/* the splash and the launch images draw the icon this wide, in points, on the color of the screen under them (the dark one is also SPLASH_BACKGROUND in tools/make_assets.py) */
#define LAUNCH_ICON_POINTS 96.0

static NSString *NoshiBundlePlistPath(void) {
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Info.plist"];
}

/* the plist is replaced by a new file, which needs the folder. access() does not see what the sandbox denies: a bundle installed by the system lets
   access() say yes while the write fails with permErr (-54) on ios 6, so the folder is tried with a real file once per run */
static BOOL NoshiBundleWritable(void) {
    static BOOL writable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *bundle = [[NSBundle mainBundle] bundlePath];
        if (access([bundle fileSystemRepresentation], W_OK) != 0 || access([NoshiBundlePlistPath() fileSystemRepresentation], W_OK) != 0) return;
        NSString *probe = [bundle stringByAppendingPathComponent:@".noshigram-write-probe"];
        int fd = open([probe fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0644);
        if (fd < 0) return;
        close(fd);
        writable = unlink([probe fileSystemRepresentation]) == 0;
    });
    return writable;
}

static dispatch_queue_t NoshiIconQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("noshigram.icon", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSError *NoshiIconFailure(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:NoshiIconError code:code userInfo:[NSDictionary dictionaryWithObject:reason forKey:NSLocalizedDescriptionKey]];
}

/* the splash picture of the icon, at the scale asked for */
static NSString *NoshiSplashPath(int scale) {
    NSString *suffix = scale >= 3 ? @"@3x" : (scale == 2 ? @"@2x" : @"");
    return [[NSBundle mainBundle] pathForResource:[@"splash_icon" stringByAppendingString:suffix] ofType:@"png"];
}

/* the size of a png from its header, without decoding it: a launch image of a big phone is some fourteen megabytes of pixels */
static BOOL NoshiPNGSize(NSString *path, uint32_t *width, uint32_t *height) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:24];
    [handle closeFile];
    static const uint8_t signature[8] = {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    if (head.length < 24 || memcmp(head.bytes, signature, 8) != 0) return NO;
    const uint8_t *b = head.bytes;
    *width = (uint32_t)b[16] << 24 | (uint32_t)b[17] << 16 | (uint32_t)b[18] << 8 | b[19];
    *height = (uint32_t)b[20] << 24 | (uint32_t)b[21] << 16 | (uint32_t)b[22] << 8 | b[23];
    return YES;
}

/* what the launch images carry: the color of the screen of the theme that is on now, as hex */
static NSString *NoshiLaunchSignature(UIColor *screen) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [screen getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"|%02x%02x%02x", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

/* the package's launch images: the app icon on the dark screen color of the modern theme */
static NSString *const NoshiPackageLaunchSignature = @"|15121f";

static NSString *NoshiMarkedLaunchSignature(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:NoshiBundlePlistPath()];
    NSString *marked = [plist objectForKey:NoshiLaunchIconKey];
    return marked.length ? marked : NoshiPackageLaunchSignature;
}

/* the system shows the launch image of the bundle until the app has a window */
static NSError *NoshiWriteLaunchImages(UIColor *screenColor) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat screenScale = [UIScreen mainScreen].scale;
    uint32_t screenWidth = (uint32_t)lround(screen.width * screenScale), screenHeight = (uint32_t)lround(screen.height * screenScale);
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:&error];
    if (!files) return error;
    for (NSString *file in files) {
        if (![file hasPrefix:@"Default"] || ![file hasSuffix:@".png"]) continue;
        NSString *path = [bundle stringByAppendingPathComponent:file];
        uint32_t width = 0, height = 0;
        if (!NoshiPNGSize(path, &width, &height)) continue;
        if (!((width == screenWidth && height == screenHeight) || (width == screenHeight && height == screenWidth))) continue;
        int scale = [file rangeOfString:@"@3x"].location != NSNotFound ? 3 : ([file rangeOfString:@"@2x"].location != NSNotFound ? 2 : 1);
        UIImage *icon = [UIImage imageWithContentsOfFile:NoshiSplashPath(scale)];
        if (!icon) return NoshiIconFailure(5, @"no splash picture for the icon");
        CGSize points = CGSizeMake(width / (CGFloat)scale, height / (CGFloat)scale);
        UIGraphicsBeginImageContextWithOptions(points, YES, (CGFloat)scale);
        [screenColor setFill];
        UIRectFill(CGRectMake(0, 0, points.width, points.height));
        [icon drawInRect:CGRectMake(floor((points.width - LAUNCH_ICON_POINTS) / 2), floor((points.height - LAUNCH_ICON_POINTS) / 2), LAUNCH_ICON_POINTS, LAUNCH_ICON_POINTS)];
        UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *png = made ? UIImagePNGRepresentation(made) : nil;
        if (!png) return NoshiIconFailure(6, [NSString stringWithFormat:@"the launch image %@ could not be drawn", file]);
        if (![png writeToFile:path options:NSDataWritingAtomic error:&error]) return error;
    }
    return nil;
}

/* the Info.plist remembers which icon and color the launch images carry: nothing for what the package brings */
static NSError *NoshiMarkLaunchSignature(NSString *signature) {
    NSString *path = NoshiBundlePlistPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError *error = nil;
    NSMutableDictionary *plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error] : nil;
    if (![plist isKindOfClass:[NSMutableDictionary class]]) return error ? error : NoshiIconFailure(1, @"the Info.plist could not be read");
    if ([signature isEqualToString:NoshiPackageLaunchSignature]) [plist removeObjectForKey:NoshiLaunchIconKey];
    else [plist setObject:signature forKey:NoshiLaunchIconKey];
    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out) return error ? error : NoshiIconFailure(2, @"the Info.plist could not be made");
    if (![out writeToFile:path options:NSDataWritingAtomic error:&error]) return error ? error : NoshiIconFailure(3, @"the Info.plist could not be written");
    return nil;
}

/* the launch images for the icon, and the mark that says so; a failure is logged and the next launch tries again */
static void NoshiSyncLaunchImages(UIColor *screenColor) {
    NSString *signature = NoshiLaunchSignature(screenColor);
    NSError *error = NoshiWriteLaunchImages(screenColor);
    if (!error) error = NoshiMarkLaunchSignature(signature);
    if (error) NSLog(@"noshigram: the launch images were not drawn for the chosen icon: %@", error);
}

/* the launch images carry the icon and the screen color of the theme, so a change of the theme draws them again
   for the next start */
void NoshiAppIconRefreshLaunchImages(void) {
    /* only a jailbreak install can write its own bundle */
    if (!NoshiBundleWritable()) return;
    UIColor *screen = NoshiColorScreen();
    if ([NoshiMarkedLaunchSignature() isEqualToString:NoshiLaunchSignature(screen)]) return;
    dispatch_async(NoshiIconQueue(), ^{
        @autoreleasepool { NoshiSyncLaunchImages(screen); }
    });
}

UIImage *NoshiSplashIconImage(void) {
    return [UIImage imageNamed:@"splash_icon"];
}

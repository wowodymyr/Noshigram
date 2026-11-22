#import "noshi_app_icon.h"
#import "noshi_theme.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

#include <errno.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include "noshi_icon_environment.h"

/* the app is an executable, so the environment is a symbol it links against; the headers of the sdk do not declare it */
extern char **environ;

static NSString *const NoshiIconError = @"NoshiAppIcon";
/* the name of the chosen icon, kept in the plist beside the files it chose, so the two cannot disagree */
static NSString *const NoshiIconNameKey = @"NoshiIconName";
/* the icon entries of the packaged plist, saved before the first rewrite so that the icon of the app can come back */
static NSString *const NoshiIconOriginalKey = @"NoshiOriginalIcons";
/* the icon and the screen color the launch images in the bundle were drawn for ("Telegram|15121f"), kept in the
   Info.plist so that a new install, which brings its own launch images and plist, drops it */
static NSString *const NoshiLaunchIconKey = @"NoshiLaunchIcon";
/* the splash and the launch images draw the icon this wide, in points, on the color of the screen under them (the dark one is also SPLASH_BACKGROUND in tools/make_assets.py) */
#define LAUNCH_ICON_POINTS 96.0

static BOOL NoshiNativeIconsSupported(void) {
    UIApplication *application = [UIApplication sharedApplication];
    SEL supports = NSSelectorFromString(@"supportsAlternateIcons");
    SEL set = NSSelectorFromString(@"setAlternateIconName:completionHandler:");
    if (![application respondsToSelector:supports] || ![application respondsToSelector:set]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(application, supports);
}

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

static const char *NoshiKillallPath(void) {
    if (access("/usr/bin/killall", X_OK) == 0) return "/usr/bin/killall";
    if (access("/bin/killall", X_OK) == 0) return "/bin/killall";
    return NULL;
}

BOOL NoshiAppIconCanRewrite(void) {
    return NoshiBundleWritable() && access("/usr/bin/uicache", X_OK) == 0 && NoshiKillallPath() != NULL;
}

static dispatch_queue_t NoshiIconQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("noshigram.icon", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

NoshiAppIconMode NoshiAppIconCurrentMode(void) {
    if (NoshiAlternateIconNames().count == 0) return NoshiAppIconUnavailable;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:NoshiBundlePlistPath()];
    if ([plist objectForKey:NoshiIconOriginalKey] && NoshiAppIconCanRewrite()) return NoshiAppIconRewrite;
    if (NoshiNativeIconsSupported()) return NoshiAppIconNative;
    return NoshiAppIconCanRewrite() ? NoshiAppIconRewrite : NoshiAppIconUnavailable;
}

static NSError *NoshiIconFailure(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:NoshiIconError code:code userInfo:[NSDictionary dictionaryWithObject:reason forKey:NSLocalizedDescriptionKey]];
}

/* runs a program with an argument vector and waits for it; nil when it exited with status 0 */
static NSError *NoshiRunProgram(const char *path, char *const argv[], BOOL mobileHome) {
    pid_t pid = 0;
    char **environment = environ;
    if (mobileHome) {
        size_t count = 0;
        while (count < 4096 && environ[count]) ++count;
        if (count == 4096) return NoshiIconFailure(8, @"the environment is too large for uicache");
        environment = calloc(count + 3, sizeof(*environment));
        if (!environment) return NoshiIconFailure(ENOMEM, @"the uicache environment could not be allocated");
        if (!noshi_icon_cache_environment(environ, environment, count + 3)) {
            free(environment);
            return NoshiIconFailure(8, @"the uicache environment could not be prepared");
        }
    }
    int started = posix_spawn(&pid, path, NULL, NULL, argv, environment);
    if (mobileHome) free(environment);
    if (started != 0) return NoshiIconFailure(started, [NSString stringWithFormat:@"%s did not start (%d)", path, started]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return NoshiIconFailure(errno, [NSString stringWithFormat:@"%s was not waited for (%d)", path, errno]);
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return nil;
    return NoshiIconFailure(status, [NSString stringWithFormat:@"%s ended with status %d", path, status]);
}

/* the home screen reads icons from its own cache of the app, which only uicache fills again, and SpringBoard shows
   the new icon after it starts again. uicache registers the app anew */
static NSError *NoshiRefreshHomeScreen(void) {
    char *cache[] = {"uicache", NULL};
    char *restart[] = {"killall", "SpringBoard", NULL};
    NSError *error = NoshiRunProgram("/usr/bin/uicache", cache, YES);
    if (error) return error;
    const char *killall = NoshiKillallPath();
    return killall ? NoshiRunProgram(killall, restart, NO) : NoshiIconFailure(4, @"SpringBoard cannot be restarted");
}

/* the icon entries a plist keeps: the iphone and ipad dictionaries and the flat list of the oldest systems */
static NSArray *NoshiIconEntryKeys(void) {
    return [NSArray arrayWithObjects:@"CFBundleIcons", @"CFBundleIcons~ipad", @"CFBundleIconFiles", @"CFBundleIconFiles~ipad", nil];
}

/* the plist with the primary icon of every entry swapped for the files of the named alternate icon, or put back as the package had it for nil */
static NSError *NoshiRewriteIconPlist(NSString *name) {
    NSString *path = NoshiBundlePlistPath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError *error = nil;
    NSMutableDictionary *plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error] : nil;
    if (![plist isKindOfClass:[NSMutableDictionary class]]) return error ? error : NoshiIconFailure(1, @"the Info.plist could not be read");

    if (![plist objectForKey:NoshiIconOriginalKey]) {
        NSMutableDictionary *original = [NSMutableDictionary dictionary];
        for (NSString *key in NoshiIconEntryKeys()) {
            id entry = [plist objectForKey:key];
            if (entry) [original setObject:[NSPropertyListSerialization propertyListWithData:[NSPropertyListSerialization dataWithPropertyList:entry format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]
                                                                                   options:NSPropertyListMutableContainers format:NULL error:NULL] forKey:key];
        }
        [plist setObject:original forKey:NoshiIconOriginalKey];
    }
    NSMutableDictionary *original = [plist objectForKey:NoshiIconOriginalKey];
    /* ios 5 reads the pre-rendered flag of the flat file list from the top of the plist, so it is kept with the rest and changes with the icon; a copy saved by an
       older version lacks it, and the plist still has the packaged value then */
    if (![original objectForKey:@"UIPrerenderedIcon"] && [plist objectForKey:@"UIPrerenderedIcon"]) [original setObject:[plist objectForKey:@"UIPrerenderedIcon"] forKey:@"UIPrerenderedIcon"];
    if (!name && [original objectForKey:@"UIPrerenderedIcon"]) [plist setObject:[original objectForKey:@"UIPrerenderedIcon"] forKey:@"UIPrerenderedIcon"];

    for (NSString *key in NoshiIconEntryKeys()) {
        id saved = [original objectForKey:key];
        if (!saved) continue;
        if (!name) {
            /* a copy of the saved entry, because the alternate icons of the dictionary entries must stay in the plist whole */
            id copy = [NSPropertyListSerialization propertyListWithData:[NSPropertyListSerialization dataWithPropertyList:saved format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]
                                                               options:NSPropertyListMutableContainers format:NULL error:NULL];
            [plist setObject:copy forKey:key];
            continue;
        }
        BOOL flat = [saved isKindOfClass:[NSArray class]];
        NSDictionary *source = flat ? [original objectForKey:[key hasSuffix:@"~ipad"] ? @"CFBundleIcons~ipad" : @"CFBundleIcons"] : saved;
        NSDictionary *alternates = [source isKindOfClass:[NSDictionary class]] ? [source objectForKey:@"CFBundleAlternateIcons"] : nil;
        NSDictionary *icon = [alternates objectForKey:name];
        NSArray *files = [icon objectForKey:@"CFBundleIconFiles"];
        if (!files.count) {
            /* a device without files for this alternate keeps its primary icon */
            continue;
        }
        if (flat) {
            [plist setObject:files forKey:key];
            id flatFlag = [icon objectForKey:@"UIPrerenderedIcon"];
            if (flatFlag) [plist setObject:flatFlag forKey:@"UIPrerenderedIcon"];
            continue;
        }
        NSMutableDictionary *entry = [plist objectForKey:key];
        NSMutableDictionary *primary = [entry objectForKey:@"CFBundlePrimaryIcon"];
        [primary setObject:files forKey:@"CFBundleIconFiles"];
        id prerendered = [icon objectForKey:@"UIPrerenderedIcon"];
        if (prerendered) [primary setObject:prerendered forKey:@"UIPrerenderedIcon"];
    }
    if (name) [plist setObject:name forKey:NoshiIconNameKey];
    else [plist removeObjectForKey:NoshiIconNameKey];

    NSData *out = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!out) return error ? error : NoshiIconFailure(2, @"the Info.plist could not be made");
    if (![out writeToFile:path options:NSDataWritingAtomic error:&error]) return error ? error : NoshiIconFailure(3, @"the Info.plist could not be written");
    return nil;
}

NSString *NoshiAlternateIconName(void) {
    if (NoshiAppIconCurrentMode() == NoshiAppIconNative) {
        SEL current = NSSelectorFromString(@"alternateIconName");
        UIApplication *application = [UIApplication sharedApplication];
        if (![application respondsToSelector:current]) return nil;
        return ((NSString *(*)(id, SEL))objc_msgSend)(application, current);
    }
    /* the file, not the dictionary the bundle loaded at launch, which does not change until the app starts again */
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:NoshiBundlePlistPath()];
    NSString *name = [plist objectForKey:NoshiIconNameKey];
    return [name isKindOfClass:[NSString class]] ? name : nil;
}

/* the choice, kept apart from the bundle: the name of the alternate icon, or an empty string for the icon of the app */
static NSString *const NoshiIconChoiceKey = @"noshigram.icon";

static void NoshiKeepIconChoice(NSString *name) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:name ? name : @"" forKey:NoshiIconChoiceKey];
    /* the app is closed by the restart of SpringBoard that follows, so the value is written out at once */
    [defaults synchronize];
}

/* the splash picture of an icon, at the scale asked for; the app's own picture where the icon has none */
static NSString *NoshiSplashPath(NSString *name, int scale) {
    NSString *stem = name.length ? [@"splash_" stringByAppendingString:name.lowercaseString] : @"splash_icon";
    NSString *suffix = scale >= 3 ? @"@3x" : (scale == 2 ? @"@2x" : @"");
    NSString *path = [[NSBundle mainBundle] pathForResource:[stem stringByAppendingString:suffix] ofType:@"png"];
    if (path || !name.length) return path;
    return NoshiSplashPath(nil, scale);
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

/* whether a png has an alpha channel, from its header: the packaged icons of the sizes ios 5 and 6 use carry their own rounded corners */
static BOOL NoshiPNGHasAlpha(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:26];
    [handle closeFile];
    if (head.length < 26) return NO;
    uint8_t colorType = ((const uint8_t *)head.bytes)[25];
    return colorType == 4 || colorType == 6;
}

/* old uicache rebuilds system app entries but leaves ipa icon names in the user installation cache */
static BOOL NoshiUsesCachedUserIcons(void) {
    NSString *bundle = [[[NSBundle mainBundle] bundlePath] stringByResolvingSymlinksInPath];
    return ([bundle hasPrefix:@"/private/var/mobile/Applications/"] || [bundle hasPrefix:@"/var/mobile/Applications/"]) &&
        [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Caches/com.apple.mobile.installation.plist"];
}

static NSError *NoshiWriteUserIconFiles(NSString *name) {
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSString *originals = [bundle stringByAppendingPathComponent:@"noshigram-original-icons"];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:originals error:&error];
    if (!files.count) return error ? error : NoshiIconFailure(9, @"the original app icons are missing");
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:NoshiBundlePlistPath()];
    NSDictionary *saved = [plist objectForKey:NoshiIconOriginalKey];
    NSDictionary *source = saved ? saved : plist;
    NSMutableArray *alternates = [NSMutableArray array];
    if (name) {
        for (NSString *key in [NSArray arrayWithObjects:@"CFBundleIcons", @"CFBundleIcons~ipad", nil]) {
            NSDictionary *icons = [source objectForKey:key];
            NSDictionary *icon = [[icons objectForKey:@"CFBundleAlternateIcons"] objectForKey:name];
            NSArray *paths = [icon objectForKey:@"CFBundleIconFiles"];
            if ([paths isKindOfClass:[NSArray class]]) [alternates addObjectsFromArray:paths];
        }
        if (!alternates.count) return NoshiIconFailure(9, @"the selected icon has no files");
    }
    for (NSString *file in files) {
        if (![file hasPrefix:@"Icon"] || ![file hasSuffix:@".png"] || ![[file lastPathComponent] isEqualToString:file])
            return NoshiIconFailure(9, @"the original icon list is invalid");
        NSString *original = [originals stringByAppendingPathComponent:file];
        NSData *data = nil;
        if (!name) {
            data = [NSData dataWithContentsOfFile:original];
        } else {
            uint32_t width = 0, height = 0;
            if (!NoshiPNGSize(original, &width, &height) || !width || width != height || width > 1024)
                return NoshiIconFailure(9, @"an original app icon is invalid");
            NSString *best = nil;
            uint32_t bestDistance = UINT32_MAX;
            for (id candidate in alternates) {
                if (![candidate isKindOfClass:[NSString class]] || ![[candidate lastPathComponent] isEqualToString:candidate]) continue;
                NSString *path = [bundle stringByAppendingPathComponent:candidate];
                uint32_t w = 0, h = 0;
                if (!NoshiPNGSize(path, &w, &h) || !w || w != h) continue;
                uint32_t distance = w > width ? w - width : width - w;
                if (distance < bestDistance) { best = path; bestDistance = distance; }
            }
            UIImage *image = best ? [UIImage imageWithContentsOfFile:best] : nil;
            if (!image) return NoshiIconFailure(9, @"the selected icon could not be read");
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 1);
            /* this install keeps the primary names and their pre-rendered flag, so nothing masks the picture: the corners the original file has are cut here, which
               covers an opaque alternate file of a size that is not one of the rounded ones. an alternate that already carries its rounded corners is drawn as it is: cutting it
               again at another radius edged it twice, which showed as a dark rim and uneven corners on the home screen */
            if (NoshiPNGHasAlpha(original) && !NoshiPNGHasAlpha(best)) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height) cornerRadius:width * 0.18] addClip];
            [image drawInRect:CGRectMake(0, 0, width, height)];
            UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
            data = resized ? UIImagePNGRepresentation(resized) : nil;
            UIGraphicsEndImageContext();
        }
        if (!data) return NoshiIconFailure(9, @"the app icon could not be prepared");
        if (![data writeToFile:[bundle stringByAppendingPathComponent:file] options:NSDataWritingAtomic error:&error])
            return error ? error : NoshiIconFailure(9, @"the app icon could not be written");
    }
    return nil;
}

static NSError *NoshiRewriteSelectedIcon(NSString *name) {
    if (!NoshiUsesCachedUserIcons()) return NoshiRewriteIconPlist(name);
    NSString *previous = [[NoshiAlternateIconName() copy] autorelease];
    NSString *path = NoshiBundlePlistPath();
    NSData *previousPlist = [NSData dataWithContentsOfFile:path];
    if (!previousPlist) return NoshiIconFailure(1, @"the Info.plist could not be read");
    NSError *error = NoshiWriteUserIconFiles(name);
    if (!error) {
        /* restore the packaged icon names for installs changed by older noshigram versions */
        error = NoshiRewriteIconPlist(nil);
        if (!error && name) {
            NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:path];
            if (!plist) error = NoshiIconFailure(1, @"the Info.plist could not be read");
            else {
                [plist setObject:name forKey:NoshiIconNameKey];
                if (![plist writeToFile:path atomically:YES]) error = NoshiIconFailure(3, @"the Info.plist could not be written");
            }
        }
    }
    if (error) {
        NSError *rollback = NoshiWriteUserIconFiles(previous);
        if (rollback) NSLog(@"noshigram: the previous app icon files could not be restored: %@", rollback);
        NSError *plistError = nil;
        if (![previousPlist writeToFile:path options:NSDataWritingAtomic error:&plistError])
            NSLog(@"noshigram: the previous app icon plist could not be restored: %@", plistError);
    }
    return error;
}

/* what the launch images carry: the icon and the color of the screen of the theme that is on now, as hex */
static NSString *NoshiLaunchSignature(NSString *name, UIColor *screen) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [screen getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%@|%02x%02x%02x", name ? name : @"", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

/* the package's launch images: the app icon on the dark screen color of the modern theme */
static NSString *const NoshiPackageLaunchSignature = @"|15121f";

static NSString *NoshiMarkedLaunchSignature(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:NoshiBundlePlistPath()];
    NSString *marked = [plist objectForKey:NoshiLaunchIconKey];
    return marked.length ? marked : NoshiPackageLaunchSignature;
}

/* the system shows the launch image of the bundle until the app has a window */
static NSError *NoshiWriteLaunchImages(NSString *name, UIColor *screenColor) {
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
        UIImage *icon = [UIImage imageWithContentsOfFile:NoshiSplashPath(name, scale)];
        if (!icon) return NoshiIconFailure(5, [NSString stringWithFormat:@"no splash picture for the icon %@", name]);
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
static void NoshiSyncLaunchImages(NSString *name, UIColor *screenColor) {
    NSString *signature = NoshiLaunchSignature(name, screenColor);
    NSError *error = NoshiWriteLaunchImages(name, screenColor);
    if (!error) error = NoshiMarkLaunchSignature(signature);
    if (error) NSLog(@"noshigram: the launch images were not drawn for the chosen icon: %@", error);
}

/* the launch images carry the icon and the screen color of the theme, so a change of the theme draws them again
   for the next start */
void NoshiAppIconRefreshLaunchImages(void) {
    if (NoshiAppIconCurrentMode() != NoshiAppIconRewrite) return;
    NSString *shown = NoshiAlternateIconName();
    UIColor *screen = NoshiColorScreen();
    if ([NoshiMarkedLaunchSignature() isEqualToString:NoshiLaunchSignature(shown, screen)]) return;
    NSString *chosen = [[shown copy] autorelease];
    dispatch_async(NoshiIconQueue(), ^{
        @autoreleasepool { NoshiSyncLaunchImages(chosen, screen); }
    });
}

void NoshiAppIconRestore(void) {
    if (NoshiAppIconCurrentMode() != NoshiAppIconRewrite) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *shown = NoshiAlternateIconName();
    id kept = [defaults objectForKey:NoshiIconChoiceKey];
    NSString *wanted = shown;
    if (![kept isKindOfClass:[NSString class]]) {
        if (shown) NoshiKeepIconChoice(shown);
    } else {
        wanted = [(NSString *)kept length] ? kept : nil;
        if (wanted && ![NoshiAlternateIconNames() containsObject:wanted]) {
            /* an icon this version no longer has */
            [defaults removeObjectForKey:NoshiIconChoiceKey];
            [defaults synchronize];
            wanted = shown;
        }
    }
    BOOL plistWrong = !(wanted == shown || [wanted isEqualToString:shown]);
    UIColor *screen = NoshiColorScreen();
    BOOL launchWrong = ![NoshiMarkedLaunchSignature() isEqualToString:NoshiLaunchSignature(wanted, screen)];
    if (!plistWrong && !launchWrong) return;
    dispatch_async(NoshiIconQueue(), ^{
        @autoreleasepool {
            if (plistWrong) {
                NSError *error = NoshiRewriteSelectedIcon(wanted);
                if (error) {
                    NSLog(@"noshigram: the chosen icon was not put back: %@", error);
                    return;
                }
            }
            NoshiSyncLaunchImages(wanted, screen);
            if (!plistWrong) return;
            NSError *error = NoshiRefreshHomeScreen();
            if (error) NSLog(@"noshigram: the home screen did not read the icon again: %@", error);
        }
    });
}

UIImage *NoshiSplashIconImage(void) {
    NSString *name = NoshiAlternateIconName();
    UIImage *image = name.length ? [UIImage imageNamed:[@"splash_" stringByAppendingString:name.lowercaseString]] : nil;
    return image ? image : [UIImage imageNamed:@"splash_icon"];
}

static void NoshiFinishIcon(void (^done)(NSError *), NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (done) done(error);
        [done release];
    });
}

void NoshiRewriteAppIcon(NSString *name, void (^completion)(NSError *)) {
    void (^done)(NSError *) = [completion copy];
    if (name && ![NoshiAlternateIconNames() containsObject:name]) {
        NoshiFinishIcon(done, NoshiIconFailure(7, @"the selected icon is absent from this app bundle"));
        return;
    }
    if (!NoshiAppIconCanRewrite()) {
        NoshiFinishIcon(done, NoshiIconFailure(4, @"the app bundle or the home screen cache cannot be updated"));
        return;
    }
    NSString *chosen = [[name copy] autorelease];
    NSString *previous = [[NoshiAlternateIconName() copy] autorelease];
    UIColor *screen = NoshiColorScreen();
    dispatch_async(NoshiIconQueue(), ^{
        @autoreleasepool {
            NSError *error = NoshiRewriteSelectedIcon(chosen);
            if (!error) NoshiKeepIconChoice(chosen);
            if (!error) NoshiSyncLaunchImages(chosen, screen);
            if (!error) {
                error = NoshiRefreshHomeScreen();
                if (error) {
                    NSError *rollback = NoshiRewriteSelectedIcon(previous);
                    if (rollback) NSLog(@"noshigram: the previous icon could not be restored: %@", rollback);
                    else {
                        NoshiKeepIconChoice(previous);
                        NoshiSyncLaunchImages(previous, screen);
                        char *cache[] = {"uicache", NULL};
                        NSError *refresh = NoshiRunProgram("/usr/bin/uicache", cache, YES);
                        if (refresh) NSLog(@"noshigram: the restored icon cache was not refreshed: %@", refresh);
                    }
                }
            }
            NoshiFinishIcon(done, error);
        }
    });
}

void NoshiSetAlternateIcon(NSString *name, void (^completion)(NSError *)) {
    void (^done)(NSError *) = [completion copy];
    NoshiAppIconMode mode = NoshiAppIconCurrentMode();
    if (mode == NoshiAppIconRewrite) {
        [done release];
        NoshiRewriteAppIcon(name, completion);
        return;
    }
    if (mode != NoshiAppIconNative) {
        NoshiFinishIcon(done, NoshiIconFailure(4, @"this system cannot change the icon"));
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    SEL set = NSSelectorFromString(@"setAlternateIconName:completionHandler:");
    ((void (*)(id, SEL, NSString *, void (^)(NSError *)))objc_msgSend)(application, set, name, ^(NSError *error) {
        if (!error) NoshiKeepIconChoice(name);
        NoshiFinishIcon(done, error);
    });
}

NSArray *NoshiAlternateIconNames(void) {
    NSDictionary *icons = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIcons"];
    NSDictionary *alternates = [icons objectForKey:@"CFBundleAlternateIcons"];
    /* the plist is a dictionary, so the order is made here, by name */
    return [[alternates allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

#import "noshi_font_choice.h"

#import <CoreText/CoreText.h>
#include <pthread.h>
#import "noshi_theme.h"

static NSString *const NoshiRubikKey = @"NoshiRubikEverywhere";
static NSString *const NoshiCustomFontPostScriptKey = @"NoshiCustomFontPostScript";
static NSString *const NoshiCustomFontTitleKey = @"NoshiCustomFontTitle";
static NSString *const NoshiCustomFontFileKey = @"NoshiCustomFontFile";
/* a font file is read whole to check it, and a picked file of this size is not a font */
static const unsigned long long NoshiCustomFontMaxBytes = 20ull * 1024 * 1024;

static pthread_mutex_t NoshiFontLock = PTHREAD_MUTEX_INITIALIZER;
/* the file registered with the font manager in this process, so a replaced or removed one is unregistered first */
static NSURL *NoshiRegisteredFont;
static BOOL NoshiRegistrationTried;

static NSString *NoshiCustomFontDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"];
}

/* the lock is held by the caller */
static void NoshiUnregisterLocked(void) {
    if (!NoshiRegisteredFont) return;
    CFErrorRef error = NULL;
    if (!CTFontManagerUnregisterFontsForURL((CFURLRef)NoshiRegisteredFont, kCTFontManagerScopeProcess, &error))
        NSLog(@"noshigram: the custom font was not unregistered: %@", error ? [(NSError *)error localizedDescription] : @"unknown");
    if (error) CFRelease(error);
    [NoshiRegisteredFont release];
    NoshiRegisteredFont = nil;
}

/* the lock is held by the caller. a font the system already knows by this name counts as registered, since the font manager refuses a duplicate name */
static BOOL NoshiRegisterLocked(NSURL *url, NSString *postScript) {
    CFErrorRef error = NULL;
    BOOL registered = CTFontManagerRegisterFontsForURL((CFURLRef)url, kCTFontManagerScopeProcess, &error);
    if (registered) {
        NoshiRegisteredFont = [url retain];
    } else {
        NSLog(@"noshigram: the custom font did not register: %@", error ? [(NSError *)error localizedDescription] : @"unknown");
    }
    if (error) CFRelease(error);
    return [UIFont fontWithName:postScript size:12] != nil;
}

/* the file kept by an earlier run is registered on first use, because the font manager forgets it at every launch */
static void NoshiRestoreLocked(void) {
    if (NoshiRegistrationTried) return;
    NoshiRegistrationTried = YES;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *file = [defaults stringForKey:NoshiCustomFontFileKey];
    NSString *postScript = [defaults stringForKey:NoshiCustomFontPostScriptKey];
    if (!file.length || !postScript.length) return;
    NSString *path = [NoshiCustomFontDirectory() stringByAppendingPathComponent:file];
    if (!NoshiRegisterLocked([NSURL fileURLWithPath:path], postScript))
        NSLog(@"noshigram: the custom font %@ is not available, the default face stays", postScript);
}

UIFont *NoshiFontChoiceFont(int weight, CGFloat size) {
    static NSString *const rubik[] = {@"Rubik-Regular", @"Rubik-Medium", @"Rubik-Bold", @"Rubik-Bold"};
    if (weight < 0 || weight > 3) return nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *custom = [defaults stringForKey:NoshiCustomFontPostScriptKey];
    if (custom.length) {
        pthread_mutex_lock(&NoshiFontLock);
        NoshiRestoreLocked();
        pthread_mutex_unlock(&NoshiFontLock);
        UIFont *font = [UIFont fontWithName:custom size:size];
        if (font) return font;
    }
    if ([defaults boolForKey:NoshiRubikKey]) return [UIFont fontWithName:rubik[weight] size:size];
    return nil;
}

BOOL NoshiFontRubikEverywhere(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoshiRubikKey];
}

void NoshiFontStoreRubikEverywhere(BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:NoshiRubikKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the font choice was not saved");
    NoshiFontsDidChange();
}

NSString *NoshiFontCustomName(void) {
    NSString *title = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiCustomFontTitleKey];
    return title.length ? title : nil;
}

NSString *NoshiFontImportCustom(NSString *path) {
    NSString *extension = [[path pathExtension] lowercaseString];
    if (![extension isEqualToString:@"ttf"] && ![extension isEqualToString:@"otf"]) return NSLocalizedString(@"font.error.type", nil);
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!attributes) return NSLocalizedString(@"font.error.read", nil);
    if ([attributes fileSize] == 0 || [attributes fileSize] > NoshiCustomFontMaxBytes) return NSLocalizedString(@"font.error.size", nil);
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return NSLocalizedString(@"font.error.read", nil);
    /* a file the graphics layer cannot parse would register as nothing and leave every label in the fallback face */
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef font = provider ? CGFontCreateWithDataProvider(provider) : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (!font) return NSLocalizedString(@"font.error.invalid", nil);
    NSString *postScript = [(NSString *)CGFontCopyPostScriptName(font) autorelease];
    NSString *title = [(NSString *)CGFontCopyFullName(font) autorelease];
    CGFontRelease(font);
    if (!postScript.length) return NSLocalizedString(@"font.error.invalid", nil);

    NSString *directory = NoshiCustomFontDirectory();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: the font folder was not made: %@", error);
        return NSLocalizedString(@"font.error.save", nil);
    }
    /* a new name per import: a registered file is not replaced in place */
    NSString *file = [NSString stringWithFormat:@"custom-font-%lu.%@", (unsigned long)[[NSDate date] timeIntervalSince1970], extension];
    NSString *target = [directory stringByAppendingPathComponent:file];
    if (![data writeToFile:target options:NSDataWritingAtomic error:&error]) {
        NSLog(@"noshigram: the font was not copied: %@", error);
        return NSLocalizedString(@"font.error.save", nil);
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *previousFile = [defaults stringForKey:NoshiCustomFontFileKey];
    pthread_mutex_lock(&NoshiFontLock);
    NoshiRegistrationTried = YES;
    NoshiUnregisterLocked();
    BOOL usable = NoshiRegisterLocked([NSURL fileURLWithPath:target], postScript);
    pthread_mutex_unlock(&NoshiFontLock);
    if (!usable) {
        [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
        return NSLocalizedString(@"font.error.invalid", nil);
    }
    [defaults setObject:postScript forKey:NoshiCustomFontPostScriptKey];
    [defaults setObject:title.length ? title : postScript forKey:NoshiCustomFontTitleKey];
    [defaults setObject:file forKey:NoshiCustomFontFileKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the font choice was not saved");
    if (previousFile.length) [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:previousFile] error:NULL];
    NoshiFontsDidChange();
    return nil;
}

void NoshiFontRemoveCustom(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *file = [defaults stringForKey:NoshiCustomFontFileKey];
    pthread_mutex_lock(&NoshiFontLock);
    NoshiRegistrationTried = YES;
    NoshiUnregisterLocked();
    pthread_mutex_unlock(&NoshiFontLock);
    [defaults removeObjectForKey:NoshiCustomFontPostScriptKey];
    [defaults removeObjectForKey:NoshiCustomFontTitleKey];
    [defaults removeObjectForKey:NoshiCustomFontFileKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the font choice was not saved");
    if (file.length) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:[NoshiCustomFontDirectory() stringByAppendingPathComponent:file] error:&error])
            NSLog(@"noshigram: the font file was not removed: %@", error);
    }
    NoshiFontsDidChange();
}

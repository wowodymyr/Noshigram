#import "noshi_imported_theme.h"
#import "noshi_theme.h"

#include "noshi_tgios_theme.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>

static noshi_tgios_theme *NoshiImportedActive;
static pthread_mutex_t NoshiImportedLock = PTHREAD_MUTEX_INITIALIZER;
static NSString *const NoshiImportedSuspendKey = @"noshigram.imported-theme.suspended";

void NoshiImportedThemeSuspend(BOOL suspended) {
    NSMutableDictionary *values = [[NSThread currentThread] threadDictionary];
    if (suspended) [values setObject:[NSNumber numberWithBool:YES] forKey:NoshiImportedSuspendKey];
    else [values removeObjectForKey:NoshiImportedSuspendKey];
}

static BOOL NoshiImportedThemeIsSuspended(void) {
    return [[[[NSThread currentThread] threadDictionary] objectForKey:NoshiImportedSuspendKey] boolValue];
}

static NSString *NoshiImportedKey(BOOL dark) {
    return dark ? @"noshigram.imported-theme.dark" : @"noshigram.imported-theme.day";
}

static NSString *NoshiImportedPath(BOOL dark) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"];
    return [directory stringByAppendingPathComponent:dark ? @"imported-night.tgios-theme" : @"imported-day.tgios-theme"];
}

static NSString *NoshiImportedRead(NSURL *url, noshi_tgios_theme *theme, NSData **validatedData) {
    if (!url || ![url isFileURL] || [[[url path] pathExtension] caseInsensitiveCompare:@"tgios-theme"] != NSOrderedSame)
        return NSLocalizedString(@"theme.import.type", nil);
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
    NSNumber *size = [attributes objectForKey:NSFileSize];
    if (!size) return NSLocalizedString(@"theme.import.read", nil);
    if ([size unsignedLongLongValue] > NOSHI_TGIOS_MAX_BYTES) return NSLocalizedString(@"theme.import.size", nil);
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:[url path]];
    NSData *data = nil;
    @try { data = [handle readDataOfLength:NOSHI_TGIOS_MAX_BYTES + 1]; }
    @catch (NSException *exception) { NSLog(@"noshigram: theme read: %@", exception); }
    @finally { [handle closeFile]; }
    if (!data) return NSLocalizedString(@"theme.import.read", nil);
    noshi_tgios_status status = noshi_tgios_parse([data bytes], [data length], theme);
    if (status != NOSHI_TGIOS_OK) return NSLocalizedString(status == NOSHI_TGIOS_TOO_LARGE ? @"theme.import.size" : @"theme.import.format", nil);
    const noshi_tgios_field *badField = NULL;
    status = noshi_tgios_validate_applicable_at(theme, &badField);
    if (status == NOSHI_TGIOS_INVALID_COLOR) {
        /* the line names the key and its value, since a theme has hundreds of colors and the file is read on a phone */
        return [NSString stringWithFormat:NSLocalizedString(@"theme.import.color", nil), [NSString stringWithUTF8String:badField->key], [NSString stringWithUTF8String:badField->value]];
    }
    if (status != NOSHI_TGIOS_OK) return NSLocalizedString(status == NOSHI_TGIOS_INVALID_WALLPAPER ? @"theme.import.wallpaper" : @"theme.import.format", nil);
    if (validatedData) *validatedData = data;
    return nil;
}

NSString *NoshiImportedThemeCheck(NSURL *url, BOOL *dark, NSString **name) {
    noshi_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSString *error = NoshiImportedRead(url, theme, NULL);
    if (!error) {
        const char *tone = noshi_tgios_get(theme, "dark");
        const char *title = noshi_tgios_get(theme, "name");
        if (dark) *dark = strcmp(tone, "true") == 0;
        if (name) *name = title ? [NSString stringWithUTF8String:title] : [[url lastPathComponent] stringByDeletingPathExtension];
    }
    free(theme);
    return error;
}

NSString *NoshiImportedThemeInstall(NSURL *url, BOOL dark) {
    noshi_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSData *data = nil;
    NSString *error = NoshiImportedRead(url, theme, &data);
    if (!error && (strcmp(noshi_tgios_get(theme, "dark"), "true") == 0) != dark)
        error = NSLocalizedString(@"theme.import.format", nil);
    free(theme);
    if (error) return error;
    NSString *path = NoshiImportedPath(dark);
    NSError *fileError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&fileError]) {
        NSLog(@"noshigram: theme directory: %@", fileError);
        return NSLocalizedString(@"theme.import.save", nil);
    }
    NSData *previous = [NSData dataWithContentsOfFile:path];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&fileError]) {
        NSLog(@"noshigram: theme save: %@", fileError);
        return NSLocalizedString(@"theme.import.save", nil);
    }
    BOOL wasSelected = NoshiImportedThemeSelected(dark);
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:NoshiImportedKey(dark)];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) {
        [[NSUserDefaults standardUserDefaults] setBool:wasSelected forKey:NoshiImportedKey(dark)];
        NSError *restoreError = nil;
        BOOL restored = previous ? [previous writeToFile:path options:NSDataWritingAtomic error:&restoreError] : [[NSFileManager defaultManager] removeItemAtPath:path error:&restoreError];
        if (!restored) NSLog(@"noshigram: previous theme could not be restored: %@", restoreError);
        NSLog(@"noshigram: theme selection was not saved");
        return NSLocalizedString(@"theme.import.save", nil);
    }
    return nil;
}

NSString *NoshiImportedThemeBeginPreview(NSURL *url) {
    noshi_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) return NSLocalizedString(@"theme.import.memory", nil);
    NSString *error = NoshiImportedRead(url, theme, NULL);
    if (error) { free(theme); return error; }
    pthread_mutex_lock(&NoshiImportedLock);
    free(NoshiImportedActive);
    NoshiImportedActive = theme;
    pthread_mutex_unlock(&NoshiImportedLock);
    return nil;
}

void NoshiImportedThemeUseBuiltin(BOOL dark) {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:NoshiImportedKey(dark)];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: built-in theme choice was not saved");
}

BOOL NoshiImportedThemeSelected(BOOL dark) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoshiImportedKey(dark)];
}

void NoshiImportedThemeReload(BOOL dark) {
    pthread_mutex_lock(&NoshiImportedLock);
    free(NoshiImportedActive);
    NoshiImportedActive = NULL;
    pthread_mutex_unlock(&NoshiImportedLock);
    if (!NoshiImportedThemeSelected(dark)) return;
    noshi_tgios_theme *theme = malloc(sizeof(*theme));
    if (!theme) { NSLog(@"noshigram: imported theme memory unavailable"); return; }
    NSString *error = NoshiImportedRead([NSURL fileURLWithPath:NoshiImportedPath(dark)], theme, NULL);
    if (error) { NSLog(@"noshigram: imported theme unavailable: %@", error); free(theme); NoshiImportedThemeUseBuiltin(dark); return; }
    pthread_mutex_lock(&NoshiImportedLock);
    NoshiImportedActive = theme;
    pthread_mutex_unlock(&NoshiImportedLock);
}

UIColor *NoshiImportedThemeColor(const char *key) {
    if (NoshiImportedThemeIsSuspended()) return nil;
    pthread_mutex_lock(&NoshiImportedLock);
    const char *value = noshi_tgios_get(NoshiImportedActive, key);
    uint32_t argb;
    if (!value || !noshi_tgios_color(value, &argb)) { pthread_mutex_unlock(&NoshiImportedLock); return nil; }
    pthread_mutex_unlock(&NoshiImportedLock);
    return [UIColor colorWithRed:((argb >> 16) & 255) / 255.0 green:((argb >> 8) & 255) / 255.0 blue:(argb & 255) / 255.0 alpha:((argb >> 24) & 255) / 255.0];
}

NSString *NoshiImportedThemeWallpaper(void) {
    if (NoshiImportedThemeIsSuspended()) return nil;
    pthread_mutex_lock(&NoshiImportedLock);
    const char *wallpaper = noshi_tgios_get(NoshiImportedActive, "wallpaper");
    NSString *value = wallpaper ? [NSString stringWithUTF8String:wallpaper] : nil;
    pthread_mutex_unlock(&NoshiImportedLock);
    return value;
}

NSString *NoshiImportedThemeStatusBar(void) {
    pthread_mutex_lock(&NoshiImportedLock);
    const char *value = noshi_tgios_get(NoshiImportedActive, "root.statusBar");
    NSString *style = value ? [NSString stringWithUTF8String:value] : nil;
    pthread_mutex_unlock(&NoshiImportedLock);
    return style;
}

NSUInteger NoshiImportedThemeWallpaperGradient(uint32_t colors[4], int *angle) {
    NSString *wallpaper = NoshiImportedThemeWallpaper();
    if (!wallpaper || !colors || !angle) return 0;
    noshi_tgios_wallpaper parsed;
    if (!noshi_tgios_parse_wallpaper([wallpaper UTF8String], &parsed)) return 0;
    if (parsed.kind != NOSHI_TGIOS_WALLPAPER_COLOR && parsed.kind != NOSHI_TGIOS_WALLPAPER_GRADIENT) return 0;
    for (unsigned i = 0; i < parsed.color_count; ++i) colors[i] = parsed.colors[i];
    *angle = parsed.rotation;
    return parsed.color_count;
}

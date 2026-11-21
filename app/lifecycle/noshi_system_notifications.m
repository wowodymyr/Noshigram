#import "noshi_system_notifications.h"

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#import <CoreFoundation/CoreFoundation.h>

#define INTERNAL_TAG @"SBInternalAppTag"
#define TAGS_KEY @"SBAppTags"
#define SHOW_INTERNAL_KEY @"SBShowInternalApps"
#define SPRINGBOARD_PREFS @"/var/mobile/Library/Preferences/com.apple.springboard.plist"
/* kept next to the preferences, so a removal of the package knows the switch was set here and not by the person */
#define SWITCH_MARKER @"/var/mobile/Library/Preferences/.noshigram-show-internal-apps"
/* kCFCoreFoundationVersionNumber of ios 7.0; the settings of a system app are read this way up to ios 6 only */
#define FIRST_UNSUPPORTED_CF 847.20

static void NoshiSysNotifyFail(NSString *what, NSString *path) {
    fprintf(stderr, "noshigram: %s: %s\n", what.UTF8String, path.UTF8String);
}

/* the plist at path with the changes of mutate, in the format it had and with its owner and mode, written beside it and renamed so a stop in the middle cannot leave half a file;
   mutate returns NO when nothing changed, and then the file is not touched */
static BOOL NoshiSysNotifyEdit(NSString *path, BOOL (^mutate)(NSMutableDictionary *dictionary)) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) {
        NoshiSysNotifyFail(@"cannot stat", path);
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        NoshiSysNotifyFail(@"cannot read", path);
        return NO;
    }
    CFPropertyListFormat format = 0;
    CFErrorRef error = NULL;
    id parsed = (id)CFPropertyListCreateWithData(kCFAllocatorDefault, (CFDataRef)data, kCFPropertyListMutableContainers, &format, &error);
    if (!parsed || ![parsed isKindOfClass:[NSMutableDictionary class]]) {
        if (error) CFRelease(error);
        if (parsed) CFRelease((CFTypeRef)parsed);
        NoshiSysNotifyFail(@"not a property list dictionary", path);
        return NO;
    }
    NSMutableDictionary *dictionary = [(NSMutableDictionary *)parsed autorelease];
    if (!mutate(dictionary)) return YES;
    CFErrorRef writeError = NULL;
    NSData *out = [(NSData *)CFPropertyListCreateData(kCFAllocatorDefault, (CFPropertyListRef)dictionary, format, 0, &writeError) autorelease];
    if (!out.length) {
        if (writeError) CFRelease(writeError);
        NoshiSysNotifyFail(@"cannot serialize", path);
        return NO;
    }
    NSString *temporary = [path stringByAppendingString:@".noshigram-new"];
    if (![out writeToFile:temporary atomically:NO]) {
        NoshiSysNotifyFail(@"cannot write", temporary);
        return NO;
    }
    if (chown(temporary.fileSystemRepresentation, info.st_uid, info.st_gid) != 0 || chmod(temporary.fileSystemRepresentation, info.st_mode & 07777) != 0 ||
        rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        NoshiSysNotifyFail(@"cannot replace", path);
        return NO;
    }
    return YES;
}

static BOOL NoshiSysNotifyTagBundle(NSString *infoPath) {
    return NoshiSysNotifyEdit(infoPath, ^BOOL(NSMutableDictionary *info) {
        id tags = [info objectForKey:TAGS_KEY];
        if ([tags isKindOfClass:[NSArray class]]) {
            if ([tags containsObject:INTERNAL_TAG]) return NO;
            [info setObject:[tags arrayByAddingObject:INTERNAL_TAG] forKey:TAGS_KEY];
        } else {
            [info setObject:[NSArray arrayWithObject:INTERNAL_TAG] forKey:TAGS_KEY];
        }
        return YES;
    });
}

static BOOL NoshiSysNotifySetSwitch(NSString *prefs, NSString *marker) {
    __block BOOL changed = NO;
    BOOL ok = NoshiSysNotifyEdit(prefs, ^BOOL(NSMutableDictionary *dictionary) {
        id current = [dictionary objectForKey:SHOW_INTERNAL_KEY];
        if ([current respondsToSelector:@selector(boolValue)] && [current boolValue]) return NO;
        [dictionary setObject:[NSNumber numberWithBool:YES] forKey:SHOW_INTERNAL_KEY];
        changed = YES;
        return YES;
    });
    if (ok && changed && ![[NSData data] writeToFile:marker atomically:NO]) {
        NoshiSysNotifyFail(@"cannot write", marker);
        return NO;
    }
    return ok;
}

static BOOL NoshiSysNotifyClearSwitch(NSString *prefs, NSString *marker) {
    if (access(marker.fileSystemRepresentation, F_OK) != 0) return YES;
    BOOL ok = NoshiSysNotifyEdit(prefs, ^BOOL(NSMutableDictionary *dictionary) {
        if (![dictionary objectForKey:SHOW_INTERNAL_KEY]) return NO;
        [dictionary removeObjectForKey:SHOW_INTERNAL_KEY];
        return YES;
    });
    if (ok && unlink(marker.fileSystemRepresentation) != 0) {
        NoshiSysNotifyFail(@"cannot remove", marker);
        return NO;
    }
    return ok;
}

int NoshiSystemNotificationsRun(const char *command) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int status = 2;
    if (kCFCoreFoundationVersionNumber >= FIRST_UNSUPPORTED_CF) {
        fprintf(stderr, "noshigram: the system notification setup is for ios 5 and 6, nothing to do\n");
        status = 0;
    } else {
        /* the paths of a test run may come from the environment; a run without them uses the real ones */
        const char *infoOverride = getenv("NOSHI_SYSNOTIFY_INFO"), *prefsOverride = getenv("NOSHI_SYSNOTIFY_PREFS"), *markerOverride = getenv("NOSHI_SYSNOTIFY_MARKER");
        NSString *info = infoOverride ? [NSString stringWithUTF8String:infoOverride] : [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Info.plist"];
        NSString *prefs = prefsOverride ? [NSString stringWithUTF8String:prefsOverride] : SPRINGBOARD_PREFS;
        NSString *marker = markerOverride ? [NSString stringWithUTF8String:markerOverride] : SWITCH_MARKER;
        if (command && !strcmp(command, "on")) status = NoshiSysNotifyTagBundle(info) && NoshiSysNotifySetSwitch(prefs, marker) ? 0 : 1;
        else if (command && !strcmp(command, "off")) status = NoshiSysNotifyClearSwitch(prefs, marker) ? 0 : 1;
        else fprintf(stderr, "usage: Noshigram --system-notifications on|off\n");
    }
    [pool release];
    return status;
}

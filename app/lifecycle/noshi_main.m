#import <UIKit/UIKit.h>

#include <stdio.h>
#include <string.h>

#import "noshi_app_delegate.h"
#import "noshi_system_notifications.h"

#define LOG_BYTES_MAX (512 * 1024)

/* NSLog reaches the system log only, and the jailbroken phones keep none, so stderr goes to a file that can be pulled
   from Library/Logs; a file past the limit starts over */
static void NoshiRedirectLog(void) {
    NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *directory = [library stringByAppendingPathComponent:@"Logs"];
    NSString *path = [directory stringByAppendingPathComponent:@"noshigram.log"];
    NSFileManager *files = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: no log directory: %@", error);
        return;
    }
    if ([[files attributesOfItemAtPath:path error:NULL] fileSize] > LOG_BYTES_MAX) [files removeItemAtPath:path error:NULL];
    if (!freopen(path.fileSystemRepresentation, "a", stderr)) NSLog(@"noshigram: cannot open the log file");
}

/* the interface follows the first language of the system, and bundle lookup would otherwise fall through to the
   second one: a phone set to French first and Russian second would show Russian */
static void NoshiChooseLanguage(void) {
    NSArray *system = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain] objectForKey:@"AppleLanguages"];
    NSString *first = system.count ? [system objectAtIndex:0] : @"en";
    NSRange dash = [first rangeOfString:@"-"];
    NSString *base = dash.location == NSNotFound ? first : [first substringToIndex:dash.location];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([base isEqualToString:@"en"] || [base isEqualToString:@"ru"]) [defaults removeObjectForKey:@"AppleLanguages"];
    else [defaults setObject:[NSArray arrayWithObject:@"en"] forKey:@"AppleLanguages"];
}

int main(int argc, char *argv[]) {
    /* the package scripts run the executable like a tool, before any screen exists */
    if (argc >= 2 && !strcmp(argv[1], "--system-notifications")) return NoshiSystemNotificationsRun(argc >= 3 ? argv[2] : NULL);
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NoshiRedirectLog();
    NoshiChooseLanguage();
    int status = UIApplicationMain(argc, argv, nil, NSStringFromClass([NoshiAppDelegate class]));
    [pool release];
    return status;
}

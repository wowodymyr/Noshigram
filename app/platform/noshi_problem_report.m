#import "noshi_problem_report.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <sys/sysctl.h>
#include <string.h>

/* the identifier of the binary that ran, to look the addresses of a crash up in the symbols of the very build */
static NSString *NoshiBuildIdentifier(void) {
#if defined(__LP64__)
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    const uint8_t *command = (const uint8_t *)(header + 1);
    uint32_t count = header->ncmds;
#else
    const struct mach_header *header = _dyld_get_image_header(0);
    const uint8_t *command = (const uint8_t *)(header + 1);
    uint32_t count = header->ncmds;
#endif
    for (uint32_t i = 0; i < count; ++i) {
        const struct load_command *load = (const struct load_command *)command;
        if (load->cmd == LC_UUID) {
            const struct uuid_command *uuid = (const struct uuid_command *)load;
            NSMutableString *text = [NSMutableString string];
            for (int j = 0; j < 16; ++j) [text appendFormat:@"%02x", uuid->uuid[j]];
            return text;
        }
        command += load->cmdsize;
    }
    return @"unknown";
}

static NSString *NoshiMachine(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0 || size > 64) return @"?";
    char buffer[64];
    if (sysctlbyname("hw.machine", buffer, &size, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buffer];
}

NSString *NoshiProblemReportHeader(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
#if defined(__arm64__)
    NSString *architecture = @"arm64";
#else
    NSString *architecture = @"armv7";
#endif
    UIDevice *device = [UIDevice currentDevice];
    return [NSString stringWithFormat:@"noshigram %@ (%@) %@ build %@\n%@ %@, %@", [info objectForKey:@"CFBundleShortVersionString"],
            [info objectForKey:@"CFBundleVersion"], architecture, NoshiBuildIdentifier(), device.systemName, device.systemVersion, NoshiMachine()];
}

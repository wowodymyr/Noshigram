#import "noshi_devices_sticker.h"

#import "noshi_image_decoder.h"
#import "noshi_lottie_view.h"

/* the key names the animation in the log and in the file of its first frame */
static NSString *const NoshiDevicesStickerKey = @"devices.laptop";

static NSString *NoshiDevicesStickerPath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if (!roots.count) return nil;
    return [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram/devices-sticker.tgs"];
}

@implementation NoshiDevicesSticker

+ (NSData *)storedData {
    NSString *path = NoshiDevicesStickerPath();
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    return data && NoshiFileFormatOfData(data) == NoshiFileFormatGzip ? data : nil;
}

+ (void)storeData:(NSData *)data {
    NSString *path = NoshiDevicesStickerPath();
    if (!path || !data) return;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"noshigram: the sticker of the devices screen was not kept: %@", error);
    }
}

+ (NoshiLottieView *)animationWithData:(NSData *)data {
    NoshiLottieView *view = [[[NoshiLottieView alloc] initWithPackedData:data key:NoshiDevicesStickerKey] autorelease];
    view.cachesPoster = YES;
    view.userInteractionEnabled = NO;
    return view;
}

@end

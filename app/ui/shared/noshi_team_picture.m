#import "noshi_team_picture.h"

/* the pictures of the people of the credits are kept: in memory for the next time the page opens, and on disk for the next launch, so the page shows them at once and
   the server only corrects them; a picture was drawn into its wavy outline again at every arrival of a name or a photo, a dozen times for a page */
static NSMutableDictionary *NoshiTeamImageMemory(void) {
    static NSMutableDictionary *images;
    if (!images) images = [[NSMutableDictionary alloc] init];
    return images;
}

static NSString *NoshiTeamImageDirectory(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:@"noshigram-team"];
}

UIImage *NoshiStoredTeamImage(NSNumber *identifier) {
    UIImage *image = [NoshiTeamImageMemory() objectForKey:identifier];
    if (image) return image;
    NSString *path = [NoshiTeamImageDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%lld.png", identifier.longLongValue]];
    image = [UIImage imageWithContentsOfFile:path];
    if (image) [NoshiTeamImageMemory() setObject:image forKey:identifier];
    return image;
}

void NoshiKeepTeamImage(NSNumber *identifier, UIImage *image) {
    if (!image) return;
    [NoshiTeamImageMemory() setObject:image forKey:identifier];
    NSString *directory = NoshiTeamImageDirectory();
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%lld.png", identifier.longLongValue]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            NSData *data = UIImagePNGRepresentation(image);
            if (data) [data writeToFile:path atomically:YES];
        }
    });
}


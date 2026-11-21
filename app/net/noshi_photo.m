#import "noshi_photo.h"

@implementation NoshiPhoto

@synthesize ref = _ref;
@synthesize key = _key;

+ (NoshiPhoto *)photoWithRef:(const noshi_photo_ref *)ref {
    if (!ref || ref->photo_id <= 0) return nil;
    NoshiPhoto *photo = [[[NoshiPhoto alloc] init] autorelease];
    photo->_ref = *ref;
    photo->_key = [[NSString stringWithFormat:@"%lld", (long long)ref->photo_id] copy];
    return photo;
}

- (void)dealloc {
    [_key release];
    [super dealloc];
}

@end

#import <Foundation/Foundation.h>

#include "noshi_photos.h"

/* where a profile photo lives; the file itself comes from NoshiSession downloadFile:completion */
@interface NoshiPhoto : NSObject {
    noshi_photo_ref _ref;
    NSString *_key;
}

/* nil when the ref carries no photo */
+ (NoshiPhoto *)photoWithRef:(const noshi_photo_ref *)ref;

@property (nonatomic, readonly) noshi_photo_ref ref;
/* one photo, one key: the id alone, because a photo id is unique across telegram */
@property (nonatomic, readonly, copy) NSString *key;

@end

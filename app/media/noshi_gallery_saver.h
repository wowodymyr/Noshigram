#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_message.h"

/* puts the photo or video of a message into the photo library of the phone, without opening it */
@interface NoshiGallerySaver : NSObject

/* completion runs on the main thread, with nil once the library has the file and the localization key of the reason otherwise (the person
   refused access, the file did not load, or the format is not one the library takes) */
+ (void)saveMedia:(NoshiMedia *)media cache:(NoshiMediaCache *)cache completion:(void (^)(NSString *failureKey))completion;

/* the picture of a photo to the pasteboard, decoded at most 2048 points on a side. completion is the same as above */
+ (void)copyPhotoOfMedia:(NoshiMedia *)media cache:(NoshiMediaCache *)cache completion:(void (^)(NSString *failureKey))completion;

@end

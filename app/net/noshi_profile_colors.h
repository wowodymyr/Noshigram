#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* the backgrounds of the profile colors the server lists, asked for once in a run and kept by the id a user's profile color names */
@interface NoshiProfileColors : NSObject
/* asks the server for the list when it has not been asked in this run; done runs on the main thread, with the list or without it when the ask failed */
+ (void)loadWithSession:(NoshiSession *)session completion:(void (^)(void))done;
/* the two ends of the blend of a color as 0xRRGGBB, for the dark theme when asked and the list has one; NO when the id is not in the list */
+ (BOOL)blendForColorId:(int32_t)colorId dark:(BOOL)dark center:(uint32_t *)center edge:(uint32_t *)edge;
@end

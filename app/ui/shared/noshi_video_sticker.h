#import "noshi_lottie.h"

/* the same frame interface as tgs, with a bounded 15 fps vp9 decode */
@interface NoshiVideoSticker : NSObject <NoshiFrameAnimation>
+ (NoshiVideoSticker *)animationWithPackedData:(NSData *)packed key:(NSString *)key;
@end

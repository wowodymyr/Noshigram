#import <UIKit/UIKit.h>
#include "noshi_geo.h"

@interface NoshiMapTileTicket : NSObject
- (void)cancel;
@end

/* shared by message previews and the full map, so one visible tile has one request */
@interface NoshiMapTiles : NSObject
+ (NoshiMapTiles *)sharedTiles;
- (NoshiMapTileTicket *)loadTile:(noshi_map_tile)tile completion:(void (^)(UIImage *image, NSString *failure))completion;
@end

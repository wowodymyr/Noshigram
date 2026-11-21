#import <UIKit/UIKit.h>
#include "noshi_geo.h"
@class NoshiSession, NoshiDialog;

@interface NoshiLocationController : UIViewController
@property (nonatomic, copy) void (^closeHandler)(void);
/* a bot query only needs the chosen point, not a search for nearby venues */
@property (nonatomic, assign) BOOL locationOnly;
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog location:(noshi_geo_point)location
             selection:(void (^)(noshi_geo_point point))selection;
- (void)cancel;
@end

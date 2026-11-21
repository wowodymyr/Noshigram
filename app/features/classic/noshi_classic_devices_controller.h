#import <UIKit/UIKit.h>

#import "noshi_session.h"

@class NoshiMediaCache;

/* the devices of the account in the classic style: a grouped system table with the link button, This device, the
   glossy button that ends the others, the active sessions and the self destruct time */
@interface NoshiClassicDevicesController : UITableViewController <UIActionSheetDelegate>

/* the media cache loads the laptop sticker over the table, the one the modern screen shows in its card */
- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media;

@end

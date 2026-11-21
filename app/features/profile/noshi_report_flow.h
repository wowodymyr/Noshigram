#import <UIKit/UIKit.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

/* the report of a user, group or channel: a list of reasons, a line of words when the reason is "other" */
@interface NoshiReportFlow : NSObject

/* host is the screen the list rises over; done runs on the main thread after a report was sent, and not on a cancel or a failure */
+ (void)startForDialog:(NoshiDialog *)dialog session:(NoshiSession *)session host:(UIViewController *)host done:(void (^)(void))done;

@end

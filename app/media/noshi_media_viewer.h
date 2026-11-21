#import <UIKit/UIKit.h>
#import "noshi_media_cache.h"

@interface NoshiMediaViewer : UIViewController
- (id)initWithMessages:(NSArray *)messages selected:(NoshiMessage *)message media:(NoshiMediaCache *)media;
- (id)initWithMessages:(NSArray *)messages selected:(NoshiMessage *)message media:(NoshiMediaCache *)media
           senderNames:(NSDictionary *)senderNames chatTitle:(NSString *)chatTitle;
- (id)initWithImage:(UIImage *)image send:(void (^)(UIImage *image, NSString *caption))send;
- (id)initWithVideoURL:(NSURL *)url send:(void (^)(NSString *caption))send;
/* a one-time photo, video or round video of a chat: the viewer has no menu, no forward and no save, tells the owner when the file is on the screen (the moment the
   server must hear that it was opened), and burns away when it is closed after that. closed runs once the viewer is gone, opened or not */
- (id)initWithOneTimeMessage:(NoshiMessage *)message media:(NoshiMediaCache *)media opened:(void (^)(void))opened closed:(void (^)(void))closed;
/* the sender looks at their own one-time file before the other side has: the same viewer, but nothing is reported to the server and nothing burns. A file that is
   still going up is read from the copy on this phone */
- (id)initWithOneTimePreviewOfMessage:(NoshiMessage *)message media:(NoshiMediaCache *)media;
@property (nonatomic, copy) void (^cancelHandler)(void);
/* when set, the menu gets "show in chat"; it runs after the viewer is gone, with the message that was on the screen */
@property (nonatomic, copy) void (^showInChatHandler)(NoshiMessage *message);
@end

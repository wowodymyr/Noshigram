#import <UIKit/UIKit.h>

#import "noshi_attach_options.h"
#import "noshi_message.h"
@class NoshiSession, NoshiDialog;

/* the type of a file by its extension, application/octet-stream for one the system does not know */
NSString *NoshiMimeOfPath(NSString *path);

/* what the paperclip opens: the photo library, the file browser or the place the person is at */
@interface NoshiAttachFlow : NSObject

- (id)initWithHost:(UIViewController *)host handler:(void (^)(NoshiOutgoing *outgoing))handler;
@property (nonatomic, readonly) BOOL cancelled;
@property (nonatomic, retain) NoshiSession *session;
@property (nonatomic, retain) NoshiDialog *dialog;
/* a selection of several photos or videos from the gallery ends here, in one call with all of them, instead of in the handler one by one; without it they go one by one */
@property (nonatomic, copy) void (^albumHandler)(NSArray *outgoings);
- (void)chooseGallery;
- (void)chooseCamera;
/* the selection of the gallery sheet; without options.preview the pictures are made and sent at once, the words of
   the sheet on the first of them; with it, they go through the editor first */
- (void)chooseAssets:(NSArray *)urls options:(NoshiAttachOptions *)options;
- (void)chooseContact;
- (void)chooseFile;
- (void)chooseLocation;
/* the screen goes away: a picker or a location fix still running is dropped */
- (void)cancel;

@end

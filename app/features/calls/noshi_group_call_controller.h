#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_group_call_state.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"

/* the full screen of a group call (a voice chat): the chat and how many are in, the members with who speaks marked, and the buttons for the microphone, the
   speaker and leaving, with the menu that invites and ends */
@interface NoshiGroupCallController : UIViewController

- (id)initWithSession:(NoshiSession *)session;

@property (nonatomic, retain) NoshiAvatarCache *avatars;
/* where the picture of an emoji status after a name comes from */
@property (nonatomic, retain) NoshiMediaCache *media;

/* main thread only */
- (void)updateWithCall:(NoshiGroupCall *)call;

/* the call the screen shows, 0 before its first snapshot */
@property (nonatomic, readonly) long long callId;
/* the call has ended and the screen is on its way out */
@property (nonatomic, readonly) BOOL finishing;

/* the person pressed the arrow that folds the screen away: the call goes on and the owner shows the way back */
@property (nonatomic, copy) void (^onMinimize)(void);
/* called once the screen is off the window, to let the owner drop it */
@property (nonatomic, copy) void (^onFinish)(void);

@end

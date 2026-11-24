#import <Foundation/Foundation.h>

/* keeps a sleeping app awake on the systems that no longer keep a VoIP socket for it (ios 7 and later, where the
   keep-alive handler and the VoIP service type went, and ios 10 and later, where they are gone) */
@interface NoshiBackgroundKeeper : NSObject

/* this system keeps no VoIP socket, so only playing keeps the app alive */
+ (BOOL)needed;
/* begins to play, unless a call or a recording has the audio session, which is theirs to keep; NO when it did not begin, with the reason logged */
- (BOOL)start;
- (void)stop;
/* a song that let go of the audio session: with the silence playing the session stays on and goes back to mixing with other apps,
   since closing it would stop the silence too and the app would fall asleep; YES when the silence took it, NO when it should be closed */
+ (BOOL)takeSessionFromSong;
@property (nonatomic, readonly) BOOL running;

@end

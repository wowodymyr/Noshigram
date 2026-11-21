#import "noshi_settings_kit.h"

@class NoshiSession, NoshiPerson;

/* the Change Name Color screen, for the name of the person themselves */
@interface NoshiNameColorController : NoshiSettingsPageController

/* person is the signed in account, as the settings screen loaded it */
- (id)initWithSession:(NoshiSession *)session person:(NoshiPerson *)person;

/* runs on the main thread with the id that was set, so the screen behind can show it */
@property (nonatomic, copy) void (^changedHandler)(NSInteger colorId);

@end

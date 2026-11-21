#import "noshi_session.h"
#import "noshi_settings_kit.h"

/* what Noshigram adds to the chat screens beyond the settings of the original client; playback, how messages look
   and answer a tap, the entries of the menu of a message, the questions asked before an action, and how times,
   numbers and names are written */
@interface NoshiChatExtrasController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session;
@end

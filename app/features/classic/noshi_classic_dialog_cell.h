#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_person.h"
#import "noshi_session_calllog.h"
#import "noshi_story.h"

/* a chat row in the classic style: the system cell with its own highlight, separators and swipe, and the system
   fonts; the avatar and the texts are views */
@class NoshiDraft;

@interface NoshiClassicDialogCell : UITableViewCell

/* where the picture of a photo or video preview comes from; without it the row shows the text alone */
@property (nonatomic, assign) NoshiMediaCache *media;
/* runs when the arrow on the avatar of a chat that belongs to a community is tapped; set after configureWithDialog */
@property (nonatomic, copy) void (^communityHandler)(void);

/* the stories of the user the row is with: a ring round the avatar, coloured while one is unseen; nil takes it away. Set after configureWithDialog, which clears it */
- (void)setStoryPeer:(NoshiStoryPeer *)peer;

+ (CGFloat)rowHeight;
/* a forum whose topics were read stands taller: the name, the topic of its last message in a plate and the message in another */
+ (CGFloat)rowHeightForDialog:(NoshiDialog *)dialog;
- (void)configureWithDialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars;
/* replaces the preview with what the chat is doing right now, in the accent color; nil leaves the last message */
- (void)showTypingText:(NSString *)text;
/* the unsent message of the chat stands in the place of the last one, after a red "Draft:" and with the time of the draft. Set after configureWithDialog; nil leaves
   the last message */
- (void)showDraft:(NoshiDraft *)draft;
/* a contact: the name and when they were last seen, with no time or count on the right */
- (void)configureWithPerson:(NoshiPerson *)person avatars:(NoshiAvatarCache *)avatars;

/* a call of the log: the name, how it went in the line under it (red for a missed one) and when */
- (void)configureWithCall:(NoshiCallLogEntry *)call avatars:(NoshiAvatarCache *)avatars;

@end

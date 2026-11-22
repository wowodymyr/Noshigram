#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_message.h"

/* the row of the song a profile shows: the cover, the title over the artist, on the white of the group it stands in; a tap on it is the owner's
   to handle, and it hides itself when it has nothing to show, so ask hasContent before laying it out */
@interface NoshiMusicPill : UIControl

/* the song the profile shows first, nil when it has none */
@property (nonatomic, retain) NoshiMedia *savedTrack;
/* whether the pill has anything to show: a saved song */
@property (nonatomic, readonly) BOOL hasContent;
/* runs when the pill changes between having content and not, so the owner can lay the head out again */
@property (nonatomic, copy) void (^contentHandler)(void);
+ (CGFloat)height;
/* where the cover comes from; without it the card shows the note in place of the cover */
@property (nonatomic, retain) NoshiMediaCache *media;
/* the emoji of the profile's Premium pattern and its color: a few of them run onto the right end of the card, fading out toward the left */
@property (nonatomic, retain) UIImage *patternImage;
@property (nonatomic, retain) UIColor *patternColor;

@end

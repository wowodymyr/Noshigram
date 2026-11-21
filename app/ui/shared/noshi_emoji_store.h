#import <UIKit/UIKit.h>

#include "noshi_emoji.h"

/* whether the app has a picture for the emoji, which the layout needs to reserve room for it */
BOOL NoshiEmojiHasPicture(size_t entry);

/* the decoded picture when it is in memory */
UIImage *NoshiEmojiImage(size_t entry);

/* the picture, decoded here when it is not in memory; for rendering into a bitmap that is kept, where a missing
   picture cannot be filled in later */
UIImage *NoshiEmojiImageNow(size_t entry);

/* a system emoji rendered at chat size, or nil when this ios cannot draw the complete sequence */
void NoshiLargeEmojiImage(size_t entry, void (^completion)(UIImage *image));

/* how many times a picture was asked for and not yet in memory; a view reads it before and after drawing, and when
   it changed calls NoshiEmojiRedrawWhenLoaded */
NSUInteger NoshiEmojiMissCount(void);

/* sets the view to redraw once the pictures that are being decoded are in memory; asking twice before the redraw
   is the same as once */
void NoshiEmojiRedrawWhenLoaded(UIView *view);

/* the emoji as a string, to type it into a message */
NSString *NoshiEmojiString(size_t entry);

/* draws the emoji in rect when its picture is in memory, and leaves the rect empty while it is being decoded */
void NoshiDrawEmoji(size_t entry, CGRect rect);

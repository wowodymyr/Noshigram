#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_emoji_label.h"
#import "noshi_media_cache.h"

/* the profile photos of a person, a group or a channel on the whole screen, newest first: the name and the day of the shown photo under the arrow that goes
   back to the profile, "n of m" under them, one page for each photo, and a strip of small pictures along the foot to jump by. While the list is on its
   way the photo the profile already has is shown, so the screen is never empty */
@interface NoshiAvatarViewer : UIViewController <UIScrollViewDelegate> {
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NSArray *_photos;
    NoshiMedia *_publicPhoto;
    UIScrollView *_pager;
    UILabel *_counter;
    UIButton *_back;
    UIButton *_more;
    NoshiEmojiLabel *_titleLabel;
    UILabel *_dateLabel;
    UILabel *_toast;
    UIScrollView *_strip;
    NSMutableArray *_thumbs;
    /* the thumbs whose picture was asked for, so a long list loads only the ones near the strip's window */
    NSMutableIndexSet *_thumbsAsked;
    NSDateFormatter *_dateFormat;
    UIActivityIndicatorView *_spinner;
    NSMutableArray *_pages;
    NSInteger _index;
    BOOL _thumbScrolling;
    BOOL _requested;
    BOOL _statusWasHidden;
}

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;

/* the photo that those who may not see the main one get, in the profile of the signed in person: the page after the last profile photo, as the wide photo of the profile has it, unless
   the list of photos holds it already; set before the screen is shown */
@property (nonatomic, retain) NoshiMedia *publicPhoto;

@end

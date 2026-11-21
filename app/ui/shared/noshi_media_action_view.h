#import <UIKit/UIKit.h>

/* the glyphs of the round button on a picture, a video, a voice note and a round message */
typedef enum {
    NoshiMediaIconPlay,
    NoshiMediaIconPause,
    NoshiMediaIconDownload,
    /* a cross inside a ring that turns while the file arrives and fills up as it does */
    NoshiMediaIconCancel,
    /* a page with a folded corner, for a file that is here */
    NoshiMediaIconFile,
    NoshiMediaIconNone
} NoshiMediaIcon;

/* the button of the media in a chat, drawn it */
@interface NoshiMediaActionView : UIView

/* the disc behind the glyph; nil leaves the glyph on what is under it */
@property (nonatomic, retain) UIColor *discColor;
/* the color of the glyph and of the ring */
@property (nonatomic, retain) UIColor *inkColor;
@property (nonatomic, readonly) NoshiMediaIcon icon;

- (void)setIcon:(NoshiMediaIcon)icon animated:(BOOL)animated;
/* how much of the file has come, 0 to 1; the ring shows a small arc while it is 0 */
- (void)setProgress:(float)progress;

@end

#import <UIKit/UIKit.h>

#import "noshi_typing_board.h"

typedef enum {
    NoshiStatusPlain = 0,     /* last seen, a kind of chat, a count: the quiet color */
    NoshiStatusOnline,        /* the person is on line: the same words in the accent color */
    NoshiStatusTyping         /* the person is typing or sending something; the accent color and three dots before the words */
} NoshiStatusKind;

/* the line under a name in a chat or a profile; it colors itself by what it says, and while someone is typing it
   shows three dots that light one after the other before the text, as the status of the original does */
@interface NoshiStatusLabel : UILabel {
    NoshiStatusKind _kind;
    UIColor *_plainColor;
    UIColor *_activeColor;
    NSArray *_dots;
}

/* the colors of the quiet and the active states; the defaults are the secondary text color and the accent of the app */
@property (nonatomic, retain) UIColor *plainColor;
@property (nonatomic, retain) UIColor *activeColor;
@property (nonatomic, readonly) NoshiStatusKind kind;

/* text and kind together, so the color and the dots never lag behind the words */
- (void)setStatus:(NSString *)text kind:(NoshiStatusKind)kind;

@end

/* the words for what someone is doing in a chat, without the dots (the label draws those) */
NSString *NoshiTypingStatusText(int action, NSUInteger count);
/* the same with who acts: in a group a single person is named before the words ("Ann is typing"), two are joined
   ("Ann and Bob are typing") */
NSString *NoshiTypingStatusTextNamed(int action, NSUInteger count, NSArray *names);
/* the same for a row of the chat list; nil when nobody acts in that chat */
NSString *NoshiTypingTextForDialog(NoshiTypingBoard *board, NoshiDialog *dialog);

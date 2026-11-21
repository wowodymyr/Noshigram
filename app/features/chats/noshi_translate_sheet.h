#import <UIKit/UIKit.h>

#import "noshi_session.h"

/* the translation of a message, in a card that rises from the bottom over the chat */
@interface NoshiTranslateSheet : UIView

/* context holds the lines of the chat before the message for the AI translator, or nil */
+ (void)presentInView:(UIView *)host text:(NSString *)text entities:(NSArray *)entities session:(NoshiSession *)session context:(NSString *)context;
/* closed runs once, when the card has left; a story waits for it before it runs on */
+ (void)presentInView:(UIView *)host text:(NSString *)text entities:(NSArray *)entities session:(NoshiSession *)session context:(NSString *)context closed:(void (^)(void))closed;

@end

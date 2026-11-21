#import <UIKit/UIKit.h>

@class NoshiEmojiPicker;

@protocol NoshiEmojiPickerDelegate <NSObject>
/* entry is an index into the emoji table; its string is what goes into the message */
- (void)emojiPicker:(NoshiEmojiPicker *)picker didPickEntry:(size_t)entry;
/* the question of the search is off the screen, answered or turned down; it took the keyboard focus of the message field, which the owner gives back */
- (void)emojiPickerDidCloseSearch:(NoshiEmojiPicker *)picker;
@end

/* the emoji grid: the ones used lately, then the nine groups, with a strip that jumps between them. the magnifier at the head of the strip asks for a word, and the grid shows the
   emoji that the keywords of the server name for it */
@class NoshiSession;

@interface NoshiEmojiPicker : UIView <UITableViewDataSource, UITableViewDelegate> {
    id<NoshiEmojiPickerDelegate> _delegate;
}
@property (nonatomic, assign) id<NoshiEmojiPickerDelegate> delegate;
/* the account the keywords of the search are asked from; without one the search uses what an earlier launch kept */
@property (nonatomic, assign) NoshiSession *session;
@end

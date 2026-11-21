#import <UIKit/UIKit.h>
#import "noshi_session_folders.h"
@class NoshiMediaCache;

@interface NoshiFolderTabs : UIView
- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media changed:(void (^)(void))changed;
@property(nonatomic, readonly) CGFloat height;
/* which way the last change of folder went: 1 to a folder further along the bar (a swipe to the left), -1 to one before it; the list slides the same way */
@property(nonatomic, readonly) NSInteger slideDirection;
@property(nonatomic, readonly) NoshiChatFolder *selectedFolder;
- (void)refresh;
/* the unread chats of every folder as a number on its tab, counted from the chats of the main list; a muted chat, a left channel and the archive row are not counted */
- (void)updateCountsFromDialogs:(NSArray *)dialogs;
- (void)installPagingInView:(UIView *)view;
@property(nonatomic, readonly) NSArray *pagingRecognizers;
@end

#import "noshi_list_controller.h"
#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"

@class NoshiChatsController;

/* the unread messages of the main list, those of muted chats left out: the count a chat shows by its way back; posted on the main thread when it changes */
extern NSString *const NoshiUnreadTotalDidChangeNotification;
NSInteger NoshiUnreadTotal(void);
/* the rows of the main chat list as the screen last loaded it, nil before the first load; what the icon badge is counted from when the server cannot be asked */
NSArray *NoshiMainDialogsSnapshot(void);
void NoshiSetMainDialogsSnapshot(NSArray *dialogs);

@protocol NoshiChatsControllerDelegate <NSObject>
/* the unread messages of the chats that are not muted, for the badge on the tab */
- (void)chatsController:(NoshiChatsController *)controller didChangeUnreadTotal:(NSInteger)total;
@end

/* the chat list: search, filter pills, and a row per chat */
@interface NoshiChatsController : NoshiListController <UITextFieldDelegate> {
    id<NoshiChatsControllerDelegate> _chatsDelegate;
}

@property (nonatomic, assign) id<NoshiChatsControllerDelegate> chatsDelegate;
/* 0 lists the chats, 1 the archive; set before the view loads */
@property (nonatomic, assign) int32_t folderId;
/* the list goes back to its first row, as the chats tab does when it is pressed while it is shown */
- (void)scrollToTopAnimated;
/* what a chat opened from the list needs for its pictures and its sticker panel; set before the first tap */
@property (nonatomic, retain) NoshiMediaCache *media;
@property (nonatomic, retain) NoshiStickerLibrary *stickerLibrary;

@end

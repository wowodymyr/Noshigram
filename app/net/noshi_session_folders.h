#import "noshi_session.h"
#import "noshi_chat_folder.h"

extern NSString *const NoshiChatFoldersDidChangeNotification;

@protocol NoshiFolderDialogRequest <NSObject>
- (void)cancel;
@end

/* a folder the server recommends: the folder as it would be made, and the line that says what it is for */
@interface NoshiSuggestedFolder : NSObject {
    NoshiChatFolder *_folder;
    NSString *_info;
}
@property(nonatomic, readonly, retain) NoshiChatFolder *folder;
@property(nonatomic, readonly, copy) NSString *info;
@end

@interface NoshiSession (Folders)
@property(nonatomic, readonly) NSArray *chatFolders;
- (void)refreshChangedChatFolders;
- (void)loadChatFoldersWithCompletion:(NoshiListCompletion)completion;
/* messages.getSuggestedDialogFilters: NoshiSuggestedFolder items; the folders of the account are not among them */
- (void)loadSuggestedChatFoldersWithCompletion:(NoshiListCompletion)completion;
- (void)saveChatFolder:(NoshiChatFolder *)folder completion:(void (^)(NSString *errorName))completion;
- (void)setDialogs:(NSArray *)dialogs pinned:(BOOL)pinned inChatFolder:(NoshiChatFolder *)folder completion:(void (^)(NSString *errorName))completion;
- (void)deleteChatFolder:(int32_t)folderId completion:(void (^)(NSString *errorName))completion;
- (void)orderChatFolders:(NSArray *)folders completion:(void (^)(NSString *errorName))completion;
/* the main list and archive are both inputs to custom folder rules */
/* the chats a custom folder had when it was last scanned, kept on disk: a scan reads up to two hundred pages of the chat list and meets a flood wait on a long list, so the
   screen shows these at once and scans again only when they are old. nil when nothing is kept, or the rules of the folder changed since */
- (void)loadKeptDialogsForChatFolder:(NoshiChatFolder *)folder completion:(NoshiListCompletion)completion;
/* how long ago the kept chats of this folder were scanned, in seconds; a negative number when nothing usable is kept */
- (NSTimeInterval)keptAgeOfChatFolder:(NoshiChatFolder *)folder;
- (id<NoshiFolderDialogRequest>)loadDialogsForChatFolder:(NoshiChatFolder *)folder completion:(NoshiListCompletion)completion;
- (id<NoshiFolderDialogRequest>)loadDialogsForChatFolder:(NoshiChatFolder *)folder progress:(void (^)(NSArray *items))progress completion:(NoshiListCompletion)completion;
@end

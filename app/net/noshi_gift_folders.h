#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_session.h"
#import "noshi_star_gift.h"

/* a folder of the gifts on a profile, as the server keeps it */
@interface NoshiGiftFolder : NSObject {
    int32_t _folderId;
    int32_t _count;
    NSString *_title;
}
@property (nonatomic, readonly) int32_t folderId;
@property (nonatomic, readonly) int32_t count;
@property (nonatomic, readonly, copy) NSString *title;
@end

/* the folders of a profile: reading them, and the changes the owner makes */
@interface NoshiSession (GiftFolders)

/* the folders of the profile of a user or a channel, in the order the server keeps them */
- (void)loadGiftFoldersOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *folders, NSString *errorName))completion;
/* one page of the gifts in a folder; folderId zero is the same as loadSavedGiftsOfDialog:offset:completion */
- (void)loadSavedGiftsOfDialog:(NoshiDialog *)dialog folder:(int32_t)folderId offset:(NSString *)offset completion:(NoshiSavedGiftsCompletion)completion;

/* for the own profile only: gifts are named by their messages */
- (void)createGiftFolderTitled:(NSString *)title withGifts:(NSArray *)gifts dialog:(NoshiDialog *)dialog
                    completion:(void (^)(NoshiGiftFolder *folder, NSString *errorName))completion;
- (void)renameGiftFolder:(NoshiGiftFolder *)folder to:(NSString *)title dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)addGifts:(NSArray *)gifts toFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)removeGifts:(NSArray *)gifts fromFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)deleteGiftFolder:(NoshiGiftFolder *)folder dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;

@end

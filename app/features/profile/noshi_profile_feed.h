#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

typedef enum {
    NoshiFeedPinnedStories,
    NoshiFeedArchivedStories,
    NoshiFeedGifts
} NoshiProfileFeedKind;

/* one list under the profile, loaded in pages: our pinned stories, our archive of stories, or the gifts on our
   profile; main thread only */
@interface NoshiProfileFeed : NSObject {
    NoshiProfileFeedKind _kind;
}

- (id)initWithSession:(NoshiSession *)session kind:(NoshiProfileFeedKind)kind owner:(NoshiDialog *)owner;

@property (nonatomic, readonly) NoshiProfileFeedKind kind;
/* NoshiStory or NoshiSavedGift items in the order the server gave them */
@property (nonatomic, readonly) NSArray *items;
/* one NoshiGiftTileInfo per item */
@property (nonatomic, readonly) NSArray *tiles;
@property (nonatomic, readonly) BOOL loading;
/* the first page has arrived */
@property (nonatomic, readonly) BOOL loaded;
/* the last page has arrived */
@property (nonatomic, readonly) BOOL finished;
/* the rpc error name of the last failed page, nil after a good one */
@property (nonatomic, readonly, copy) NSString *errorName;

/* the folder of the gifts the feed lists, zero for all of them; a change takes effect with the next reload */
@property (nonatomic, assign) int32_t folderId;

/* starts again from the first page; the changed block runs on the main thread each time items, tiles or the state changed */
- (void)reload:(void (^)(void))changed;
/* the next page unless one is loading or the last has come */
- (void)loadMore:(void (^)(void))changed;

@end

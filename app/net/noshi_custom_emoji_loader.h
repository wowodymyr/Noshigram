#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_session.h"

/* fetches custom emoji documents and the pictures that draw them into NoshiCustomEmoji; a document already in
   memory, on its way or failed before is not asked for again, so a screen can call this on every rebuild */
@interface NoshiCustomEmojiLoader : NSObject

/* documentIds are NSNumbers. documents runs once on the main thread with the answered documents, for the ordinary
   emoji each stands for */
+ (void)loadDocuments:(NSArray *)documentIds session:(NoshiSession *)session media:(NoshiMediaCache *)media
            documents:(void (^)(NSArray *documents))documents picture:(void (^)(void))picture;

/* the pictures of documents already in hand, such as the emoji of a set: the same rules, without asking the server about the documents */
+ (void)loadPicturesOfDocuments:(NSArray *)documents media:(NoshiMediaCache *)media picture:(void (^)(void))picture;

@end

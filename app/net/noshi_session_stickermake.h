#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* the document the server made of an uploaded sticker file, ready to go into a set */
@interface NoshiStickerDocument : NSObject {
    long long _documentId;
    long long _accessHash;
    NSData *_fileReference;
}
@property (nonatomic, readonly) long long documentId;
@property (nonatomic, readonly) long long accessHash;
@property (nonatomic, readonly, retain) NSData *fileReference;
- (id)initWithId:(long long)documentId accessHash:(long long)accessHash fileReference:(NSData *)fileReference;
@end

/* making stickers of the account's own */
@interface NoshiSession (StickerMake)

/* nil once the name is free, NAME_OCCUPIED when it is taken, otherwise the rpc error name */
- (void)checkStickerShortName:(NSString *)name completion:(void (^)(NSString *errorName))completion;
/* a new set with this sticker; the completion gets the public name of the set the server made */
- (void)createStickerSetTitle:(NSString *)title shortName:(NSString *)name document:(NoshiStickerDocument *)document emoji:(NSString *)emoji
                   completion:(void (^)(NSString *shortName, NSString *errorName))completion;
- (void)addStickerDocument:(NoshiStickerDocument *)document emoji:(NSString *)emoji toSetNamed:(NSString *)name
                completion:(void (^)(NSString *shortName, NSString *errorName))completion;

@end

#import <Foundation/Foundation.h>

#include "noshi_messages.h"
#include "noshi_photos.h"

@class NoshiPhoto;

/* photos, stickers and thumbnails are well under this; a file that fills the part is longer than the part and fails
   with FILE_TOO_BIG instead of arriving cut */
#define NOSHI_REMOTE_FILE_PART (256 * 1024)

/* where a file lives on the servers: a profile photo, a document or photo size of a message */
@interface NoshiRemoteFile : NSObject {
    int32_t _dc;
    NSString *_key;
    int _kind;
    noshi_photo_ref _photo;
    noshi_media_ref _media;
    noshi_sticker_set_row _set;
}

/* nil when the ref carries nothing to fetch */
+ (NoshiRemoteFile *)fileForPhoto:(NoshiPhoto *)photo;
+ (NoshiRemoteFile *)fileForMedia:(const noshi_media_ref *)ref;
+ (NoshiRemoteFile *)fileForStickerSet:(const noshi_sticker_set_row *)set;

@property (nonatomic, readonly) int32_t dc;
/* one file, one key, usable as a file name: the same bytes always get the same key, and different bytes never share one */
@property (nonatomic, readonly, copy) NSString *key;

/* takes the file reference of another handle on the same file (a message read again after the server let the old reference expire); NO when it is not the
   same file */
- (BOOL)adoptReferenceOf:(NoshiRemoteFile *)fresh;

/* the InputFileLocation of the file, built in arena */
- (noshi_status)buildLocation:(noshi_arena *)arena into:(noshi_tl_value **)out;

@end

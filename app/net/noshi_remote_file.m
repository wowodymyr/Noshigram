#import "noshi_remote_file.h"

#import "noshi_photo.h"

enum { NoshiRemoteProfilePhoto = 1, NoshiRemoteMedia, NoshiRemoteStickerSet };

@implementation NoshiRemoteFile

@synthesize dc = _dc;
@synthesize key = _key;

+ (NoshiRemoteFile *)fileForPhoto:(NoshiPhoto *)photo {
    if (!photo) return nil;
    NoshiRemoteFile *file = [[[NoshiRemoteFile alloc] init] autorelease];
    file->_kind = NoshiRemoteProfilePhoto;
    file->_photo = photo.ref;
    file->_dc = photo.ref.dc;
    /* the photo id is unique across telegram, so it alone names the file */
    file->_key = [[NSString stringWithFormat:@"u%lld", (long long)photo.ref.photo_id] copy];
    return file;
}

+ (NoshiRemoteFile *)fileForMedia:(const noshi_media_ref *)ref {
    if (!ref || ref->source == NOSHI_MEDIA_SOURCE_NONE) return nil;
    NoshiRemoteFile *file = [[[NoshiRemoteFile alloc] init] autorelease];
    file->_kind = NoshiRemoteMedia;
    file->_media = *ref;
    file->_dc = ref->dc;
    /* a document and a photo can share an id, and one id has many sizes */
    file->_key = [[NSString stringWithFormat:@"%c%llx_%s", ref->source == NOSHI_MEDIA_SOURCE_PHOTO ? 'p' : 'd',
                   (unsigned long long)ref->id, ref->thumb] copy];
    return file;
}

+ (NoshiRemoteFile *)fileForStickerSet:(const noshi_sticker_set_row *)set {
    if (!set || set->id == 0 || set->thumb_dc <= 0) return nil;
    NoshiRemoteFile *file = [[[NoshiRemoteFile alloc] init] autorelease];
    file->_kind = NoshiRemoteStickerSet;
    file->_set = *set;
    file->_dc = set->thumb_dc;
    file->_key = [[NSString stringWithFormat:@"s%llx_%d", (unsigned long long)set->id, (int)set->thumb_version] copy];
    return file;
}

- (void)dealloc {
    [_key release];
    [super dealloc];
}

- (BOOL)adoptReferenceOf:(NoshiRemoteFile *)fresh {
    if (_kind != NoshiRemoteMedia || fresh->_kind != NoshiRemoteMedia || _media.source != fresh->_media.source || _media.id != fresh->_media.id ||
        strncmp(_media.thumb, fresh->_media.thumb, sizeof(_media.thumb)) != 0 || !fresh->_media.ref_len) return NO;
    memcpy(_media.file_ref, fresh->_media.file_ref, sizeof(_media.file_ref));
    _media.ref_len = fresh->_media.ref_len;
    return YES;
}

- (noshi_status)buildLocation:(noshi_arena *)arena into:(noshi_tl_value **)out {
    switch (_kind) {
    case NoshiRemoteProfilePhoto: return noshi_photo_location(arena, &_photo, out);
    case NoshiRemoteMedia: return noshi_media_location(arena, &_media, out);
    case NoshiRemoteStickerSet: return noshi_sticker_set_thumb_location(arena, &_set, out);
    }
    return NOSHI_E_ARG;
}

@end

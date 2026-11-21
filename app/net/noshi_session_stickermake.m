#import "noshi_session_stickermake.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_sticker_make.h"

@implementation NoshiStickerDocument
@synthesize documentId = _documentId;
@synthesize accessHash = _accessHash;
@synthesize fileReference = _fileReference;

- (id)initWithId:(long long)documentId accessHash:(long long)accessHash fileReference:(NSData *)fileReference {
    self = [super init];
    if (!self) return nil;
    _documentId = documentId;
    _accessHash = accessHash;
    _fileReference = [fileReference copy];
    return self;
}

- (void)dealloc {
    [_fileReference release];
    [super dealloc];
}
@end

/* the document as the core wants it; a reference longer than the core keeps cannot have come from the core */
static noshi_input_document NoshiInputDocument(NoshiStickerDocument *document) {
    noshi_input_document value;
    memset(&value, 0, sizeof(value));
    value.id = document.documentId;
    value.access_hash = document.accessHash;
    value.file_reference_len = MIN(document.fileReference.length, (NSUInteger)NOSHI_STICKER_REF_MAX);
    memcpy(value.file_reference, document.fileReference.bytes, value.file_reference_len);
    return value;
}

@implementation NoshiSession (StickerMake)

- (void)checkStickerShortName:(NSString *)name completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *text = [name copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_check_request(arena, text.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status parsed = noshi_sticker_check_parse(result->value);
            if (parsed == NOSHI_E_STATE) error = @"NAME_OCCUPIED";
            else if (parsed != NOSHI_OK) error = @"MALFORMED";
        }
        [text release];
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

/* the set the server answers with: only its public name is kept */
- (void)finishSetResult:(const noshi_mt_rpc_result *)result completion:(void (^)(NSString *, NSString *))done {
    NSString *name = nil, *error = nil;
    char buffer[NOSHI_STICKER_SHORT_NAME_MAX + 1];
    if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
    else if (noshi_sticker_set_name_parse(result->value, buffer, sizeof(buffer)) == NOSHI_OK) name = [NSString stringWithUTF8String:buffer];
    else error = @"MALFORMED";
    [self noteRpcError:error];
    NSString *deliveredName = [[name copy] autorelease], *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(deliveredName, deliveredError); [done release]; }];
}

- (void)createStickerSetTitle:(NSString *)title shortName:(NSString *)name document:(NoshiStickerDocument *)document emoji:(NSString *)emoji
                   completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *setTitle = [title copy], *setName = [name copy], *setEmoji = [emoji copy];
    noshi_input_document value = NoshiInputDocument(document);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_create_request(arena, setTitle.UTF8String, setName.UTF8String, &value, setEmoji.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [setTitle release];
        [setName release];
        [setEmoji release];
        [self finishSetResult:result completion:done];
    }];
}

- (void)addStickerDocument:(NoshiStickerDocument *)document emoji:(NSString *)emoji toSetNamed:(NSString *)name completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    NSString *setName = [name copy], *setEmoji = [emoji copy];
    noshi_input_document value = NoshiInputDocument(document);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_add_request(arena, setName.UTF8String, &value, setEmoji.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [setName release];
        [setEmoji release];
        [self finishSetResult:result completion:done];
    }];
}

@end

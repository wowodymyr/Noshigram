#include "noshi_tl_ids.h"
#include "noshi_typing.h"
#import "noshi_session_drafts.h"
#import "noshi_session_internal.h"
#import "noshi_session_sendas.h"
#import "noshi_session_stickermake.h"
#import "noshi_chat_settings.h"
#import "noshi_reaction_artwork.h"
#include "noshi_reaction_art.h"

#include "noshi_sticker_make.h"
#include "noshi_message_actions.h"
#include "noshi_sticker_manage.h"
#include <fcntl.h>
#include <unistd.h>

#include "noshi_mt_files.h"

#import "noshi_community.h"
#import "noshi_forum_summaries.h"
#import "noshi_person.h"
#import "noshi_photo.h"
#include "noshi_channel.h"
#include "noshi_profile.h"
#include "noshi_stories.h"
#include "noshi_bots.h"
#include "noshi_effects.h"
#import "noshi_rpc.h"

/* the newest page of a chat the store is asked for on every change */
#define WATCH_PAGE 60

noshi_peer_ref NoshiPeerRefOfDialog(NoshiDialog *dialog) {
    noshi_peer_ref ref;
    memset(&ref, 0, sizeof(ref));
    ref.kind = dialog.peerKind;
    ref.id = dialog.peerId;
    ref.access_hash = dialog.peerHash;
    ref.self = dialog.saved;
    ref.topic_id = dialog.topicId;
    return ref;
}

/* one file on its way to the server: the transfer state, and what the message that names it needs once it is there */
typedef struct { char caption[NOSHI_STORY_CAPTION_MAX]; noshi_story_audience audience; } NoshiStoryPostOptions;

@interface NoshiUploadJob : NSObject {
@public
    noshi_file_transfer transfer;
    BOOL open;
    noshi_peer_ref peer;
    /* the file becomes the profile photo of the signed in user instead of a message */
    BOOL profilePhoto;
    /* ... and the file is an mp4 that moves, not a picture */
    BOOL profileVideo;
    /* ... and it is the public photo, which those who may not see the main one get to see, not the main photo */
    BOOL profilePublic;
    /* ... and it is the photo of the contact in peer, set on this account's side, or suggested to them */
    BOOL contactPhoto;
    BOOL contactSuggest;
    /* the file becomes a story of the signed in user */
    BOOL storyPhoto;
    /* ... with this text and for this audience */
    char storyCaption[NOSHI_STORY_CAPTION_MAX];
    noshi_story_audience storyAudience;
    /* the file is a sticker, which becomes a document of the signed in user for a set to take */
    void (^stickerDone)(NoshiStickerDocument *document, NSString *errorName);
    /* the file is one item of an album: its media, as an NSData of noshi_album_media, or the error */
    void (^albumDone)(NSData *media, NSString *errorName);
    noshi_upload_spec spec;
    uint8_t waveform[NOSHI_WAVEFORM_BYTES];
    long long randomId;
    NoshiSendCompletion completion;
}
@end

@implementation NoshiUploadJob
- (void)dealloc {
    if (open) noshi_file_close(&transfer);
    [completion release];
    [stickerDone release];
    [albumDone release];
    [super dealloc];
}
@end

/* the upload goes in parts of this size; it divides the largest part the server takes */
#define UPLOAD_PART (128 * 1024)
#define UPLOAD_PARTS_MAX 3000

static noshi_upload_spec NoshiSpec(noshi_upload_kind kind, int32_t durationMs, int32_t width, int32_t height);

static uint64_t NoshiMonotonicMs(void) {
    return noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
}

@implementation NoshiCustomEmojiDocument

@synthesize documentId = _documentId;
@synthesize alt = _alt;
@synthesize format = _format;
@synthesize file = _file;
@synthesize preview = _preview;

- (id)initWithRow:(const noshi_custom_emoji *)row {
    self = [super init];
    if (!self) return nil;
    _documentId = row->id;
    _alt = [[NSString stringWithUTF8String:row->alt] copy];
    _format = row->format;
    _file = [[NoshiRemoteFile fileForMedia:&row->ref] retain];
    _preview = [[NoshiRemoteFile fileForMedia:&row->preview] retain];
    return self;
}

- (void)dealloc {
    [_alt release];
    [_file release];
    [_preview release];
    [super dealloc];
}

@end

/* the people a messages answer names: its users by id, and the channels it carries, which messages written as a channel point at, by
   the negative of their id */
/* the photo and the hash of the whole object, for a row that came as a stub */
static void NoshiFillFromStore(NoshiSession *session, noshi_person_row *row, int64_t key) {
    if (row->photo.photo_id > 0) return;
    NoshiPerson *held = [session storedPersonWithKey:key];
    if (!held || !held.photo.ref.photo_id) return;
    row->photo = held.photo.ref;
    if (!row->access_hash) row->access_hash = held.accessHash;
}

NSMutableDictionary *NoshiPeopleOfAnswer(NoshiSession *session, const noshi_tl_value *answer) {
    NSMutableDictionary *people = [NSMutableDictionary dictionary];
    const noshi_tl_value *users = noshi_tl_get(answer, "users");
    for (uint32_t i = 0; users && users->kind == NOSHI_TL_V_VEC && i < users->u.vec.count; ++i) {
        noshi_person_row person;
        if (noshi_person_parse(users->u.vec.items[i], &person) != NOSHI_OK) continue;
        if (noshi_tl_has(users->u.vec.items[i], "min")) NoshiFillFromStore(session, &person, person.id);
        [people setObject:[[[NoshiPerson alloc] initWithRow:&person] autorelease] forKey:[NSNumber numberWithLongLong:person.id]];
    }
    const noshi_tl_value *chats = noshi_tl_get(answer, "chats");
    for (uint32_t i = 0; chats && chats->kind == NOSHI_TL_V_VEC && i < chats->u.vec.count; ++i) {
        noshi_person_row channel;
        if (noshi_channel_person_parse(chats->u.vec.items[i], &channel) != NOSHI_OK) continue;
        if (noshi_tl_has(chats->u.vec.items[i], "min")) NoshiFillFromStore(session, &channel, -channel.id);
        [people setObject:[[[NoshiPerson alloc] initWithRow:&channel] autorelease] forKey:[NSNumber numberWithLongLong:-channel.id]];
    }
    return people;
}

/* the buttons or keyboard of the messages an answer carries; a row only says that markup exists; the buttons are
   read from the message itself, and only for the messages that have some */
static void NoshiApplyMarkups(NSArray *messages, const noshi_tl_value *answer) {
    const noshi_tl_value *list = noshi_tl_get(answer, "messages");
    if (!list || list->kind != NOSHI_TL_V_VEC) return;
    for (uint32_t i = 0; i < list->u.vec.count; ++i) {
        const noshi_tl_value *value = list->u.vec.items[i];
        int32_t id = 0;
        if (!noshi_tl_has(value, "reply_markup") || noshi_tl_get_i32(value, "id", &id) != NOSHI_OK) continue;
        for (NoshiMessage *message in messages) {
            if (message.messageId == id) {
                message.markup = [NoshiMarkup markupWithValue:noshi_tl_get(value, "reply_markup")];
                break;
            }
        }
    }
}

/* the items of an album go up one after the other: each becomes media the server knows, and the last step sends them together */
@interface NoshiAlbumJob : NSObject {
@public
    NSArray *outgoings;
    NSArray *randomIds;
    noshi_peer_ref peer;
    NSUInteger next;
    NSMutableArray *medias;
    void (^completion)(NSArray *messageIds, NSString *errorName);
}
@end

@implementation NoshiAlbumJob
- (void)dealloc {
    [outgoings release];
    [randomIds release];
    [medias release];
    [completion release];
    [super dealloc];
}
@end

/* the name of a file as it goes in the upload and in the attribute of the document. a file system allows 255 characters, which is up to 510 bytes of utf-8 and more than the 256 the buffers
   of a transfer hold, so a long name sent from another application (the share sheet hands the file over with its own name) failed as FILE_NAME_TOO_LONG; the base of the name
   is cut short at a character and the extension stays */
static NSString *NoshiFittedFileName(NSString *name) {
    const char *utf8 = name.UTF8String;
    char fitted[NOSHI_UPLOAD_NAME_MAX];
    if (!utf8 || noshi_upload_fit_name(utf8, fitted, sizeof(fitted)) != NOSHI_OK) return name ? name : @"";
    NSString *result = [NSString stringWithUTF8String:fitted];
    return result ? result : name;
}

static NSString *NoshiSetDocumentFields(noshi_upload_spec *spec, NSString *name, NSString *mime) {
    int nameLength = snprintf(spec->name, sizeof(spec->name), "%s", NoshiFittedFileName(name).UTF8String);
    int mimeLength = snprintf(spec->mime, sizeof(spec->mime), "%s", mime.length ? mime.UTF8String : "application/octet-stream");
    if (nameLength < 0 || (size_t)nameLength >= sizeof(spec->name)) return @"FILE_NAME_TOO_LONG";
    if (mimeLength < 0 || (size_t)mimeLength >= sizeof(spec->mime)) {
        NSLog(@"noshigram: document MIME type is too long");
        return @"UPLOAD_FAILED";
    }
    return nil;
}

@implementation NoshiMessageEffect
@synthesize effectId = _effectId, emoticon = _emoticon, premium = _premium, animation = _animation, sticker = _sticker;
- (void)dealloc {
    [_emoticon release];
    [_animation release];
    [_sticker release];
    [super dealloc];
}

static NSArray *NoshiKeptEffects;
static NSMutableDictionary *NoshiEffectsById;

+ (NoshiMessageEffect *)effectWithId:(long long)effectId {
    @synchronized ([NoshiSession class]) {
        return [[[NoshiEffectsById objectForKey:[NSNumber numberWithLongLong:effectId]] retain] autorelease];
    }
}
@end

@implementation NoshiSession (Chat)

- (void)deliverMain:(void (^)(void))block {
    void (^copy)(void) = [block copy];
    dispatch_async(dispatch_get_main_queue(), ^{ copy(); [copy release]; });
}

/* the next unread chat of the list, from the index on; a chat that is only marked unread has the mark taken off instead of a history read */
- (void)readDialogs:(NSArray *)dialogs from:(NSUInteger)index completion:(void (^)(NSString *errorName))done {
    while (index < dialogs.count && !((NoshiDialog *)[dialogs objectAtIndex:index]).unread) ++index;
    if (index >= dialogs.count) {
        done(nil);
        return;
    }
    NoshiDialog *dialog = [dialogs objectAtIndex:index];
    [self performAction:dialog.unreadCount > 0 ? NoshiChatCommandMarkRead : NoshiChatCommandClearUnreadMark onDialog:dialog completion:^(NSString *errorName) {
        if (errorName) {
            done(errorName);
            return;
        }
        [self readDialogs:dialogs from:index + 1 completion:done];
    }];
}

- (void)markAllReadInFolder:(int32_t)folderId completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self loadDialogsInFolder:folderId > 0 ? folderId : 1 completion:^(NSArray *items, NSString *errorName) {
        if (errorName) {
            done(errorName);
            [done release];
            return;
        }
        [self readDialogs:items from:0 completion:^(NSString *readError) {
            done(readError);
            [done release];
        }];
    }];
}

#pragma mark chat list actions

#define MUTE_FOREVER 2147483647

- (void)performAction:(NoshiChatCommand)action onDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *input = NULL;
        noshi_status status = noshi_input_peer(arena, &peer, &input);
        if (status != NOSHI_OK) return status;
        switch (action) {
        case NoshiChatCommandPin:
        case NoshiChatCommandUnpin: {
            noshi_tl_value *target = noshi_tl_new_obj(arena, "inputDialogPeer");
            *request = noshi_tl_new_obj(arena, "messages.toggleDialogPin");
            if (!target || !*request) return NOSHI_E_NOMEM;
            status = noshi_tl_set(target, "peer", input);
            if (status == NOSHI_OK && action == NoshiChatCommandPin) status = noshi_tl_set_flag(*request, "pinned");
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "peer", target);
            return status;
        }
        case NoshiChatCommandMute:
        case NoshiChatCommandUnmute: {
            noshi_tl_value *target = noshi_tl_new_obj(arena, "inputNotifyPeer");
            noshi_tl_value *settings = noshi_tl_new_obj(arena, "inputPeerNotifySettings");
            *request = noshi_tl_new_obj(arena, "account.updateNotifySettings");
            if (!target || !settings || !*request) return NOSHI_E_NOMEM;
            status = noshi_tl_set(target, "peer", input);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, settings, "mute_until", action == NoshiChatCommandMute ? MUTE_FOREVER : 0);
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "peer", target);
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "settings", settings);
            return status;
        }
        case NoshiChatCommandDelete:
            if (peer.kind == 3) {
                noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
                *request = noshi_tl_new_obj(arena, "channels.leaveChannel");
                if (!channel || !*request) return NOSHI_E_NOMEM;
                status = noshi_tl_set_i64(arena, channel, "channel_id", peer.id);
                if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
                if (status == NOSHI_OK) status = noshi_tl_set(*request, "channel", channel);
                return status;
            }
            *request = noshi_tl_new_obj(arena, "messages.deleteHistory");
            if (!*request) return NOSHI_E_NOMEM;
            status = noshi_tl_set(*request, "peer", input);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *request, "max_id", 0);
            return status;
        case NoshiChatCommandMarkRead:
            /* a max id of INT32_MAX reads everything the chat holds; a positive one is what the call asks for */
            return noshi_read_history_request(arena, &peer, INT32_MAX, request);
        case NoshiChatCommandMarkUnread:
        case NoshiChatCommandClearUnreadMark: {
            noshi_tl_value *target = noshi_tl_new_obj(arena, "inputDialogPeer");
            *request = noshi_tl_new_obj(arena, "messages.markDialogUnread");
            if (!target || !*request) return NOSHI_E_NOMEM;
            status = noshi_tl_set(target, "peer", input);
            if (status == NOSHI_OK && action == NoshiChatCommandMarkUnread) status = noshi_tl_set_flag(*request, "unread");
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "peer", target);
            return status;
        }
        case NoshiChatCommandClear:
            /* the messages go for this account only, and the chat stays in the list */
            if (peer.kind == 3) return NOSHI_E_ARG;
            *request = noshi_tl_new_obj(arena, "messages.deleteHistory");
            if (!*request) return NOSHI_E_NOMEM;
            status = noshi_tl_set_flag(*request, "just_clear");
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "peer", input);
            if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *request, "max_id", 0);
            return status;
        }
        return NOSHI_E_ARG;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (action == NoshiChatCommandDelete && noshi_channel_already_left(peer.kind, error.UTF8String)) {
            NSLog(@"noshigram: channel %lld was already left", peer.id);
            error = nil;
        }
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

#pragma mark uploads

/* worker only: sends the next part, or the message once every part is there */
- (void)pumpUpload:(NoshiUploadJob *)job {
    noshi_file_state state = job->transfer.state;
    if ([self sendIsCancelled:job]) {
        noshi_status cancelled = noshi_file_cancel(&job->transfer);
        if (cancelled != NOSHI_OK) NSLog(@"noshigram: the stopped upload did not close cleanly: %s", noshi_status_name(cancelled));
        [self failUpload:job error:@"CANCELLED"];
        return;
    }
    if (state == NOSHI_FILE_DONE && job->albumDone) {
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *file = NULL;
            noshi_status status = noshi_file_uploaded(&job->transfer, arena, &file);
            if (status == NOSHI_OK) status = noshi_album_upload_request(arena, &job->peer, file, &job->spec, request);
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            NSData *blob = nil;
            NSString *error = nil;
            noshi_album_media media;
            if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
            else if (noshi_album_media_parse(result->value, &media) == NOSHI_OK) {
                media.spoiler = job->spec.spoiler;
                blob = [NSData dataWithBytes:&media length:sizeof(media)];
            }
            else error = @"MALFORMED";
            [self noteRpcError:error];
            void (^done)(NSData *, NSString *) = [job->albumDone retain];
            done(blob, error);
            [done release];
            [job release];
        }];
        return;
    }
    if (state == NOSHI_FILE_DONE && job->stickerDone) {
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *file = NULL;
            noshi_status status = noshi_file_uploaded(&job->transfer, arena, &file);
            if (status == NOSHI_OK) status = noshi_sticker_upload_request(arena, file, "sticker.png", request);
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            NoshiStickerDocument *document = nil;
            NSString *error = nil;
            noshi_input_document value;
            if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
            else if (noshi_sticker_upload_parse(result->value, &value) == NOSHI_OK)
                document = [[[NoshiStickerDocument alloc] initWithId:value.id accessHash:value.access_hash
                                                         fileReference:[NSData dataWithBytes:value.file_reference length:value.file_reference_len]] autorelease];
            else error = @"MALFORMED";
            [self noteRpcError:error];
            void (^done)(NoshiStickerDocument *, NSString *) = [job->stickerDone retain];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(document, delivered); [done release]; }];
            [job release];
        }];
        return;
    }
    if (state == NOSHI_FILE_DONE && (job->profilePhoto || job->storyPhoto)) {
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *file = NULL;
            noshi_status status = noshi_file_uploaded(&job->transfer, arena, &file);
            if (status == NOSHI_OK && job->storyPhoto) status = noshi_story_publish_photo_audience_request(arena, file, job->randomId, job->storyCaption, &job->storyAudience, request);
            else if (status == NOSHI_OK && job->profileVideo) status = noshi_profile_video_request(arena, file, 0, request);
            else if (status == NOSHI_OK && job->contactPhoto) status = noshi_contact_photo_request(arena, &job->peer, file, job->contactSuggest, request);
            else if (status == NOSHI_OK && job->profilePublic) status = noshi_profile_public_photo_request(arena, file, request);
            else if (status == NOSHI_OK) status = noshi_profile_photo_request(arena, file, request);
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NoshiSendCompletion done = [job->completion retain];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(0, delivered); [done release]; }];
            [job release];
        }];
        return;
    }
    if (state == NOSHI_FILE_DONE) {
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *file = NULL;
            noshi_status status = noshi_file_uploaded(&job->transfer, arena, &file);
            if (status == NOSHI_OK) status = noshi_send_upload_request(arena, &job->peer, file, &job->spec, job->randomId, request);
            if (status == NOSHI_OK) status = NoshiApplySendAs(self, &job->peer, arena, *request);
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            NSLog(@"noshigram: upload of the file is complete, sending the message");
            /* finishSend gives its completion up after delivering, so it gets a reference of its own */
            [self finishSend:result randomId:job->randomId completion:[job->completion retain]];
            [job release];
        }];
        return;
    }
    if (state == NOSHI_FILE_FAILED || state == NOSHI_FILE_CANCELLED) {
        [self failUpload:job error:@"UPLOAD_FAILED"];
        return;
    }
    __block uint64_t requestId = 0;
    __block int32_t dc = 0;
    __block int cdn = 0;
    __block noshi_status built = NOSHI_OK;
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        built = noshi_file_next(&job->transfer, NoshiMonotonicMs(), arena, request, &requestId, &dc, &cdn);
        return built;
    } handler:^(const noshi_mt_rpc_result *result) {
        if (built != NOSHI_OK) {
            /* a flood wait parks the transfer; the next part goes after the server's pause */
            if (built == NOSHI_E_RETRY && job->transfer.state == NOSHI_FILE_WAIT) {
                uint64_t now = NoshiMonotonicMs();
                uint64_t pause = job->transfer.wait_until > now ? job->transfer.wait_until - now : 0;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                    [self post:^{ [self pumpUpload:job]; }];
                });
                return;
            }
            NSLog(@"noshigram: upload part not built: %s", noshi_status_name(built));
            [self failUpload:job error:@"UPLOAD_FAILED"];
            return;
        }
        noshi_status status = noshi_file_result(&job->transfer, requestId, dc, cdn, NoshiMonotonicMs(), result);
        if (status != NOSHI_OK && status != NOSHI_E_RETRY) {
            NSString *error = result->status == NOSHI_OK ? @"UPLOAD_FAILED" : NoshiRpcErrorName(result);
            NSLog(@"noshigram: upload stopped: %@ (%s)", error, noshi_status_name(status));
            [self noteRpcError:error];
            [self failUpload:job error:error];
            return;
        }
        [self reportProgressOfUpload:job];
        [self post:^{ [self pumpUpload:job]; }];
    }];
}

/* worker only: only a file that goes out in a message of the chat has a pending message to cancel or to show progress on */
- (BOOL)isMessageUpload:(NoshiUploadJob *)job {
    return job->randomId != 0 && job->completion && !job->albumDone && !job->stickerDone && !job->profilePhoto && !job->storyPhoto;
}

- (BOOL)sendIsCancelled:(NoshiUploadJob *)job {
    return [self isMessageUpload:job] && [self workerSendIsCancelled:job->randomId];
}

- (void)reportProgressOfUpload:(NoshiUploadJob *)job {
    if (![self isMessageUpload:job] || job->transfer.size == 0) return;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:job->randomId], @"randomId",
                          [NSNumber numberWithFloat:(float)((double)job->transfer.offset / (double)job->transfer.size)], @"fraction", nil];
    [self deliverMain:^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiUploadProgressNotification object:self userInfo:info]; }];
}

- (void)cancelSendWithRandomId:(long long)randomId {
    [self post:^{
        [self workerCancelSend:randomId];
    }];
}

- (void)failUpload:(NoshiUploadJob *)job error:(NSString *)error {
    if (job->albumDone) {
        void (^albumDone)(NSData *, NSString *) = [job->albumDone retain];
        albumDone(nil, error);
        [albumDone release];
        [job release];
        return;
    }
    if (job->stickerDone) {
        void (^stickerDone)(NoshiStickerDocument *, NSString *) = [job->stickerDone retain];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ stickerDone(nil, failure); [stickerDone release]; }];
        [job release];
        return;
    }
    NoshiSendCompletion done = [job->completion retain];
    NSString *delivered = [[error copy] autorelease];
    [self workerForgetSend:job->randomId];
    [self deliverMain:^{ done(0, delivered); [done release]; }];
    [job release];
}

- (void)sendUploadAtPath:(NSString *)path spec:(noshi_upload_spec)spec waveform:(NSData *)waveform toDialog:(NoshiDialog *)dialog
               randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    NoshiUploadJob *job = [[NoshiUploadJob alloc] init];
    job->peer = NoshiPeerRefOfDialog(dialog);
    job->spec = spec;
    job->randomId = randomId;
    job->completion = [completion copy];
    if (waveform) {
        if (waveform.length != NOSHI_WAVEFORM_BYTES) {
            [self failUpload:job error:@"INTERNAL"];
            return;
        }
        memcpy(job->waveform, waveform.bytes, waveform.length);
        job->spec.waveform = job->waveform;
        job->spec.waveform_len = waveform.length;
    }
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        noshi_status status = fd < 0 ? NOSHI_E_IO : noshi_file_upload(&job->transfer, fd, NoshiFittedFileName(file.lastPathComponent).UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: cannot start the upload of %@: %s", file.lastPathComponent, noshi_status_name(status));
            [self failUpload:job error:status == NOSHI_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            NSLog(@"noshigram: upload of %@ starts, %llu bytes, data center %d", file.lastPathComponent, (unsigned long long)job->transfer.size, (int)[self workerDc]);
            [self pumpUpload:job];
        }
        [file release];
    }];
}

- (void)failAlbum:(NoshiAlbumJob *)job error:(NSString *)error {
    void (^done)(NSArray *, NSString *) = [job->completion retain];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{ done(nil, delivered); [done release]; }];
    [job release];
}

- (void)albumUploadNext:(NoshiAlbumJob *)job {
    if (job->next >= job->outgoings.count) {
        [self albumSend:job];
        return;
    }
    NoshiOutgoing *item = [job->outgoings objectAtIndex:job->next];
    NoshiUploadJob *upload = [[NoshiUploadJob alloc] init];
    upload->peer = job->peer;
    NSString *fieldError = nil;
    if (item->kind == NoshiOutgoingVideo) {
        upload->spec = NoshiSpec(NOSHI_UPLOAD_VIDEO, item->durationMs, item->width, item->height);
    } else if (item->kind == NoshiOutgoingFile) {
        /* files sent without compression go out as a group of documents, which the server shows as one album */
        upload->spec = NoshiSpec(NOSHI_UPLOAD_FILE, 0, 0, 0);
        fieldError = NoshiSetDocumentFields(&upload->spec, item->name, item->mime);
    } else {
        upload->spec = NoshiSpec(NOSHI_UPLOAD_PHOTO, 0, 0, 0);
    }
    upload->spec.spoiler = item->spoiler ? 1 : 0;
    upload->albumDone = [^(NSData *media, NSString *errorName) {
        if (!media) {
            [self failAlbum:job error:errorName];
            return;
        }
        [job->medias addObject:media];
        ++job->next;
        [self post:^{ [self albumUploadNext:job]; }];
    } copy];
    if (fieldError) {
        [self failUpload:upload error:fieldError];
        return;
    }
    NSString *file = [item->path copy];
    int fd = open(file.fileSystemRepresentation, O_RDONLY);
    noshi_status status = fd < 0 ? NOSHI_E_IO : noshi_file_upload(&upload->transfer, fd, NoshiFittedFileName(file.lastPathComponent).UTF8String, [self workerDc], UPLOAD_PART, UPLOAD_PARTS_MAX);
    if (fd >= 0) close(fd);
    [file release];
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: cannot start the upload of an album item: %s", noshi_status_name(status));
        [self failUpload:upload error:status == NOSHI_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        return;
    }
    upload->open = YES;
    [self pumpUpload:upload];
}

- (void)albumSend:(NoshiAlbumJob *)job {
    NSUInteger count = job->medias.count;
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_album_media items[NOSHI_ALBUM_ITEMS_MAX];
        int64_t ids[NOSHI_ALBUM_ITEMS_MAX];
        const char *captions[NOSHI_ALBUM_ITEMS_MAX];
        if (count > NOSHI_ALBUM_ITEMS_MAX) return NOSHI_E_ARG;
        for (NSUInteger i = 0; i < count; ++i) {
            NSData *blob = [job->medias objectAtIndex:i];
            if (blob.length != sizeof(items[i])) return NOSHI_E_ARG;
            memcpy(&items[i], blob.bytes, sizeof(items[i]));
            ids[i] = [[job->randomIds objectAtIndex:i] longLongValue];
            NSString *caption = ((NoshiOutgoing *)[job->outgoings objectAtIndex:i])->caption;
            captions[i] = caption.length ? caption.UTF8String : NULL;
        }
        noshi_status status = noshi_album_send_request(arena, &job->peer, items, ids, captions, count, request);
        int32_t reply = ((NoshiOutgoing *)[job->outgoings objectAtIndex:0])->replyTo;
        if (status == NOSHI_OK) status = noshi_set_reply(arena, *request, &job->peer, reply);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *messageIds = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            messageIds = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger i = 0; i < count; ++i) {
                int32_t serverId = 0;
                noshi_status status = noshi_sent_parse(result->value, [[job->randomIds objectAtIndex:i] longLongValue], &serverId);
                /* an answer that names no id still delivered the album, a reload brings the messages back */
                [messageIds addObject:[NSNumber numberWithInt:status == NOSHI_OK ? serverId : 0]];
            }
        }
        [self noteRpcError:error];
        void (^done)(NSArray *, NSString *) = [job->completion retain];
        NSArray *deliveredIds = [[messageIds copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredIds, deliveredError); [done release]; }];
        [job release];
    }];
}

- (void)sendAlbumOfOutgoings:(NSArray *)outgoings toDialog:(NoshiDialog *)dialog randomIds:(NSArray *)randomIds completion:(void (^)(NSArray *, NSString *))completion {
    NoshiAlbumJob *job = [[NoshiAlbumJob alloc] init];
    job->outgoings = [outgoings copy];
    job->randomIds = [randomIds copy];
    job->peer = NoshiPeerRefOfDialog(dialog);
    job->medias = [[NSMutableArray alloc] init];
    job->completion = [completion copy];
    if (outgoings.count < 2 || outgoings.count > NOSHI_ALBUM_ITEMS_MAX || randomIds.count != outgoings.count) {
        [self failAlbum:job error:@"ALBUM_INVALID"];
        return;
    }
    [self post:^{ [self albumUploadNext:job]; }];
}

- (void)uploadStickerAtPath:(NSString *)path completion:(void (^)(NoshiStickerDocument *, NSString *))completion {
    NoshiUploadJob *job = [[NoshiUploadJob alloc] init];
    job->stickerDone = [completion copy];
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        noshi_status status = fd < 0 ? NOSHI_E_IO : noshi_file_upload(&job->transfer, fd, NoshiFittedFileName(file.lastPathComponent).UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: cannot start the upload of %@: %s", file.lastPathComponent, noshi_status_name(status));
            [self failUpload:job error:status == NOSHI_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            [self pumpUpload:job];
        }
        [file release];
    }];
}

/* the completion of a change to the profile of this account: a success tells the screens that wear the photo */
- (void (^)(NSString *))announcingOwnProfile:(void (^)(NSString *))completion {
    void (^inner)(NSString *) = [[completion copy] autorelease];
    return [[^(NSString *errorName) {
        if (!errorName) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOwnProfileDidChangeNotification object:nil];
        if (inner) inner(errorName);
    } copy] autorelease];
}

- (void)uploadProfilePhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:NO video:NO completion:[self announcingOwnProfile:completion]];
}

- (void)uploadPublicPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:NO video:NO public:YES options:NULL completion:completion];
}

- (void)uploadContactPhotoAtPath:(NSString *)path ofPerson:(NoshiPerson *)person suggest:(BOOL)suggest completion:(void (^)(NSString *errorName))completion {
    noshi_peer_ref contact;
    memset(&contact, 0, sizeof(contact));
    contact.kind = 1;
    contact.id = person.userId;
    contact.access_hash = person.accessHash;
    [self uploadJobAtPath:path story:NO video:NO public:NO contact:&contact suggest:suggest options:NULL completion:completion];
}

- (void)uploadProfileVideoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:NO video:YES completion:[self announcingOwnProfile:completion]];
}

- (void)postStoryPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion {
    [self postStoryPhotoAtPath:path caption:nil privacy:NOSHI_STORY_EVERYONE completion:completion];
}

- (void)postStoryPhotoAtPath:(NSString *)path caption:(NSString *)caption privacy:(noshi_story_privacy)privacy completion:(void (^)(NSString *errorName))completion {
    [self postStoryPhotoAtPath:path caption:caption audience:[NoshiStoryAudience audienceWithBase:privacy] completion:completion];
}

- (void)postStoryPhotoAtPath:(NSString *)path caption:(NSString *)caption audience:(NoshiStoryAudience *)audience completion:(void (^)(NSString *errorName))completion {
    /* the options hold the whole list of people, which is large: they live on the heap while the job is made */
    NoshiStoryPostOptions *options = calloc(1, sizeof(*options));
    if (!options) { if (completion) completion(@"NO_MEMORY"); return; }
    if (audience) [audience fillAudience:&options->audience];
    if (caption.length) snprintf(options->caption, sizeof(options->caption), "%s", caption.UTF8String);
    [self uploadJobAtPath:path story:YES video:NO public:NO options:options completion:completion];
    free(options);
}

/* both end in a call that takes the file: the profile photo or the story of the signed in user */
- (void)uploadJobAtPath:(NSString *)path story:(BOOL)story video:(BOOL)video completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:story video:video public:NO options:NULL completion:completion];
}

- (void)uploadJobAtPath:(NSString *)path story:(BOOL)story video:(BOOL)video public:(BOOL)publicPhoto options:(const NoshiStoryPostOptions *)options completion:(void (^)(NSString *errorName))completion {
    [self uploadJobAtPath:path story:story video:video public:publicPhoto contact:NULL suggest:NO options:options completion:completion];
}

- (void)uploadJobAtPath:(NSString *)path story:(BOOL)story video:(BOOL)video public:(BOOL)publicPhoto contact:(const noshi_peer_ref *)contact suggest:(BOOL)suggest
                options:(const NoshiStoryPostOptions *)options completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    NoshiUploadJob *job = [[NoshiUploadJob alloc] init];
    job->profilePhoto = !story;
    if (contact && !story && !video) {
        job->contactPhoto = YES;
        job->contactSuggest = suggest;
        job->peer = *contact;
    }
    job->profileVideo = video && !story;
    job->profilePublic = publicPhoto && !story && !video;
    job->storyPhoto = story;
    if (story && options) {
        memcpy(job->storyCaption, options->caption, sizeof(job->storyCaption));
        job->storyAudience = options->audience;
    }
    job->randomId = story ? (((long long)arc4random() << 32) | arc4random()) | 1 : 0;
    job->completion = [^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        done(errorName);
        [done release];
    } copy];
    NSString *file = [path copy];
    [self post:^{
        int fd = open(file.fileSystemRepresentation, O_RDONLY);
        noshi_status status = fd < 0 ? NOSHI_E_IO : noshi_file_upload(&job->transfer, fd, NoshiFittedFileName(file.lastPathComponent).UTF8String, [self workerDc],
                                                                           UPLOAD_PART, UPLOAD_PARTS_MAX);
        if (fd >= 0) close(fd);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: cannot start the upload of %@: %s", file.lastPathComponent, noshi_status_name(status));
            [self failUpload:job error:status == NOSHI_E_LIMIT ? @"FILE_TOO_BIG" : @"UPLOAD_FAILED"];
        } else {
            job->open = YES;
            [self pumpUpload:job];
        }
        [file release];
    }];
}

static noshi_upload_spec NoshiSpec(noshi_upload_kind kind, int32_t durationMs, int32_t width, int32_t height) {
    noshi_upload_spec spec;
    memset(&spec, 0, sizeof(spec));
    spec.kind = kind;
    spec.duration_ms = durationMs;
    spec.width = width;
    spec.height = height;
    return spec;
}

- (void)sendVoiceAtPath:(NSString *)path durationMs:(int32_t)durationMs waveform:(NSData *)waveform toDialog:(NoshiDialog *)dialog
               randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    [self sendUploadAtPath:path spec:NoshiSpec(NOSHI_UPLOAD_VOICE, durationMs, 0, 0) waveform:waveform toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendRoundVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side toDialog:(NoshiDialog *)dialog
                    randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    [self sendUploadAtPath:path spec:NoshiSpec(NOSHI_UPLOAD_ROUND, durationMs, side, side) waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

static BOOL NoshiUploadCaption(noshi_upload_spec *spec, NSString *caption) {
    NSData *bytes = [caption dataUsingEncoding:NSUTF8StringEncoding];
    if (caption.length > 1024 || bytes.length > NOSHI_UPLOAD_CAPTION_MAX || (caption.length && !bytes)) return NO;
    if (bytes.length) memcpy(spec->caption, bytes.bytes, bytes.length);
    spec->caption[bytes.length] = 0;
    return YES;
}

- (void)sendOutgoing:(NoshiOutgoing *)outgoing toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion {
    if (replyTo < 0) { completion(0, @"INTERNAL"); return; }
    if (outgoing->kind == NoshiOutgoingLocation || outgoing->kind == NoshiOutgoingContact) {
        NoshiSendCompletion done = [completion copy];
        noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_status status;
            if (outgoing->kind == NoshiOutgoingLocation) {
                status = outgoing->location.valid ? noshi_send_location_request(arena, &peer, &outgoing->location, randomId, request) :
                    noshi_send_geo_request(arena, &peer, outgoing->latitude, outgoing->longitude, randomId, request);
            }
            else status = noshi_send_contact_request(arena, &peer, outgoing->phone.UTF8String, outgoing->name.UTF8String, "", randomId, request);
            if (status == NOSHI_OK) status = noshi_set_reply(arena, *request, &peer, replyTo);
            return status == NOSHI_OK ? NoshiApplySendAs(self, &peer, arena, *request) : status;
        } handler:^(const noshi_mt_rpc_result *result) { [self finishSend:result randomId:randomId completion:done]; }];
        return;
    }
    noshi_upload_kind kind;
    switch (outgoing->kind) {
    case NoshiOutgoingVoice: kind = NOSHI_UPLOAD_VOICE; break;
    case NoshiOutgoingRound: kind = NOSHI_UPLOAD_ROUND; break;
    case NoshiOutgoingPhoto: kind = NOSHI_UPLOAD_PHOTO; break;
    case NoshiOutgoingVideo: kind = NOSHI_UPLOAD_VIDEO; break;
    case NoshiOutgoingFile: kind = NOSHI_UPLOAD_FILE; break;
    default: completion(0, @"INTERNAL"); return;
    }
    noshi_upload_spec spec = NoshiSpec(kind, outgoing->durationMs, outgoing->width, outgoing->height);
    spec.reply_to = replyTo;
    spec.spoiler = outgoing->spoiler ? 1 : 0;
    spec.view_once = outgoing->viewOnce && kind != NOSHI_UPLOAD_FILE ? 1 : 0;
    spec.animated = outgoing->animated && kind == NOSHI_UPLOAD_FILE ? 1 : 0;
    if (!NoshiUploadCaption(&spec, outgoing->caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    if (kind == NOSHI_UPLOAD_FILE) {
        NSString *fieldError = NoshiSetDocumentFields(&spec, outgoing->name, outgoing->mime);
        if (fieldError) { completion(0, fieldError); return; }
        if (outgoing->music) {
            int titleLength = snprintf(spec.title, sizeof(spec.title), "%s", outgoing->title.UTF8String ? outgoing->title.UTF8String : "");
            int performerLength = snprintf(spec.performer, sizeof(spec.performer), "%s", outgoing->performer.UTF8String ? outgoing->performer.UTF8String : "");
            if (titleLength < 0 || (size_t)titleLength >= sizeof(spec.title) || performerLength < 0 || (size_t)performerLength >= sizeof(spec.performer)) { completion(0, @"SONG_TAGS_TOO_LONG"); return; }
            spec.music = 1;
        }
    }
    [self sendUploadAtPath:outgoing->path spec:spec waveform:outgoing->waveform toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendPhotoAtPath:(NSString *)path caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    noshi_upload_spec spec = NoshiSpec(NOSHI_UPLOAD_PHOTO, 0, 0, 0);
    spec.spoiler = spoiler ? 1 : 0;
    if (!NoshiUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs width:(int32_t)width height:(int32_t)height caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(NoshiDialog *)dialog
               randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    noshi_upload_spec spec = NoshiSpec(NOSHI_UPLOAD_VIDEO, durationMs, width, height);
    spec.spoiler = spoiler ? 1 : 0;
    if (!NoshiUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendDocumentAtPath:(NSString *)path name:(NSString *)name mime:(NSString *)mime caption:(NSString *)caption toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
                completion:(NoshiSendCompletion)completion {
    noshi_upload_spec spec = NoshiSpec(NOSHI_UPLOAD_FILE, 0, 0, 0);
    if (!NoshiUploadCaption(&spec, caption)) { completion(0, @"CAPTION_TOO_LONG"); return; }
    NSString *fieldError = NoshiSetDocumentFields(&spec, name, mime);
    if (fieldError) { completion(0, fieldError); return; }
    [self sendUploadAtPath:path spec:spec waveform:nil toDialog:dialog randomId:randomId completion:completion];
}

- (void)sendLocationLatitude:(double)latitude longitude:(double)longitude toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
                  completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_status status = noshi_send_geo_request(arena, &peer, latitude, longitude, randomId, request);
        return status == NOSHI_OK ? NoshiApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
}

#pragma mark history

static void NoshiKeepTopic(NSMutableArray *messages, int32_t topic, BOOL discussion);

- (void)loadHistoryOfDialog:(NoshiDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion {
    [self loadHistoryOfDialog:dialog offsetId:beforeId addOffset:0 limit:limit completion:completion];
}

- (void)loadHistoryOfDialog:(NoshiDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [[completion copy] autorelease];
    [self loadHistoryOfDialog:dialog offsetId:offsetId addOffset:addOffset limit:limit pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
        (void)page;
        if (done) done(messages, people, errorName);
    }];
}

- (void)loadHistoryOfDialog:(NoshiDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit pageCompletion:(NoshiHistoryPageCompletion)completion {
    NoshiHistoryPageCompletion final = [[completion copy] autorelease];
    [self loadHistoryOfDialog:dialog offsetId:offsetId addOffset:addOffset limit:limit viaChannel:dialog.discussionViaChannel
                   pageCompletion:^(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName) {
        /* the comments of a post are asked of its group with the group's copy of it; a server that answers MSG_ID_INVALID to that pair (seen for the discussion of
           a channel the account is not in the group of) takes the post itself on its own channel, which is how the comments are read without joining */
        if (!messages && !dialog.discussionViaChannel && dialog.discussion && dialog.discussionPost > 0 && [errorName isEqualToString:@"MSG_ID_INVALID"]) {
            NSLog(@"noshigram: thread %d of group %lld was refused, asking post %d of channel %lld", (int)dialog.topicId, dialog.peerId, (int)dialog.discussionPost, dialog.discussionChannel);
            dialog.discussionViaChannel = YES;
            [self loadHistoryOfDialog:dialog offsetId:offsetId addOffset:addOffset limit:limit viaChannel:YES pageCompletion:final];
            return;
        }
        if (final) final(messages, people, page, errorName);
    }];
}

- (void)loadHistoryOfDialog:(NoshiDialog *)dialog offsetId:(int32_t)beforeId addOffset:(int32_t)addOffset limit:(int32_t)limit viaChannel:(BOOL)viaChannel
             pageCompletion:(NoshiHistoryPageCompletion)completion {
    NoshiHistoryPageCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    if (viaChannel && dialog.discussionPost > 0) {
        peer.kind = 3;
        peer.id = dialog.discussionChannel;
        peer.access_hash = dialog.discussionChannelHash;
        peer.topic_id = dialog.discussionPost;
    }
    NoshiDialog *source = dialog.savedSource;
    noshi_peer_ref sourcePeer = source ? NoshiPeerRefOfDialog(source) : peer;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        /* channel history includes the boundary message, so a deleted boundary cannot hide the next post */
        int32_t serverOffset = beforeId > 0 && addOffset == 0 && peer.kind == 3 && limit > 1 ? -1 : addOffset;
        return source ? noshi_saved_history_window_request(arena, &sourcePeer, beforeId, serverOffset, limit, request) : noshi_history_window_request(arena, &peer, beforeId, serverOffset, limit, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSMutableDictionary *people = nil;
        NSString *error = nil;
        noshi_history_page page;
        memset(&page, 0, sizeof(page));
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
            NSLog(@"noshigram: history failed for peer %d:%lld topic %d offset %d: %@", peer.kind, (long long)peer.id, peer.topic_id, beforeId, error);
        } else {
            noshi_message_row *rows = calloc(NOSHI_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_messages_dropped dropped;
            if (rows && noshi_history_page_read(result->value, &page) == NOSHI_OK && noshi_messages_parse_counted(result->value, rows, NOSHI_MESSAGES_MAX, &count, &dropped) == NOSHI_OK) {
                if (dropped.count) NSLog(@"noshigram: history of peer %d:%lld dropped %lu messages that did not read, the first is %d (%s)", peer.kind, (long long)peer.id,
                                         (unsigned long)dropped.count, dropped.first_id, noshi_status_name(dropped.first_status));
                messages = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    if (rows[i].reactions.min) {
                        /* the cached copy preserves our selection when history carries only min counts */
                        noshi_arena storedArena;
                        noshi_tl_value *stored = NULL;
                        noshi_peer storedPeer = {dialog.peerKind, dialog.peerId};
                        noshi_arena_init(&storedArena, 8u * 1024u * 1024u);
                        noshi_status status = noshi_store_get([self workerStore], NOSHI_RECORD_MESSAGE,
                            storedPeer, rows[i].id, &storedArena, &stored);
                        noshi_reactions preserved;
                        if (status == NOSHI_OK) status = noshi_reactions_read(noshi_tl_get(stored, "reactions"), &preserved);
                        if (status == NOSHI_OK) rows[i].reactions = preserved;
                        if (status != NOSHI_OK) NSLog(@"noshigram: cached reaction selection unavailable: %s", noshi_status_name(status));
                        noshi_arena_free(&storedArena);
                    }
                    NoshiMessage *message = [NoshiMessage messageWithRow:&rows[i]];
                    if (message) [messages addObject:message];
                }
                NoshiApplyMarkups(messages, result->value);
                people = NoshiPeopleOfAnswer(self, result->value);
            } else {
                NSLog(@"noshigram: messages.getHistory answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredMessages = [[messages copy] autorelease];
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ if (done) done(deliveredMessages, deliveredPeople, page, deliveredError); [done release]; }];
    }];
}

/* a messages.search answer read into messages and the people they name, handed to done on the main thread */
- (void)deliverMessagesOfResult:(const noshi_mt_rpc_result *)result what:(const char *)what completion:(NoshiHistoryCompletion)done {
    NSMutableArray *messages = nil;
    NSMutableDictionary *people = nil;
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_message_row *rows = calloc(NOSHI_MESSAGES_MAX, sizeof(*rows));
        size_t count = 0;
        if (rows && noshi_messages_parse(result->value, rows, NOSHI_MESSAGES_MAX, &count) == NOSHI_OK) {
            messages = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) {
                NoshiMessage *message = [NoshiMessage messageWithRow:&rows[i]];
                if (message) [messages addObject:message];
            }
            NoshiApplyMarkups(messages, result->value);
            people = NoshiPeopleOfAnswer(self, result->value);
        } else {
            NSLog(@"noshigram: messages.search for %s answer rejected", what);
            error = @"INTERNAL";
        }
        free(rows);
    }
    [self noteRpcError:error];
    NSArray *deliveredMessages = [[messages copy] autorelease];
    NSDictionary *deliveredPeople = [[people copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(deliveredMessages, deliveredPeople, deliveredError); [done release]; }];
}

- (void)loadPinnedMessagesOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_pinned_request(arena, &peer, NOSHI_MESSAGES_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"pinned messages" completion:done];
    }];
}

- (void)loadUnreadReactionsOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_unread_reactions_request(arena, &peer, NOSHI_MESSAGES_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"unread reactions" completion:done];
    }];
}

- (BOOL)markReactionsReadOfDialog:(NoshiDialog *)dialog explicit:(BOOL)explicit {
    noshi_read_action action = explicit ? NOSHI_READ_EXPLICIT : NOSHI_READ_AUTOMATIC;
    if (!noshi_read_action_allowed(0, action)) return NO;
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        if (!noshi_read_action_allowed(0, action)) return NOSHI_E_RETRY;
        return noshi_read_reactions_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status == NOSHI_OK) return;
        NSString *error = NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSLog(@"noshigram: marking reactions of chat %lld seen failed: %@", peer.id, error);
    }];
    return YES;
}

- (void)searchMessagesOfDialog:(NoshiDialog *)dialog query:(NSString *)query completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *text = [query copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_chat_search_request(arena, &peer, text.UTF8String, NOSHI_MESSAGES_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"a text" completion:done];
    }];
    [text release];
}

- (void)searchMessagesOfDialog:(NoshiDialog *)dialog fromUserId:(long long)userId accessHash:(long long)accessHash completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    noshi_peer_ref from = {1, userId, accessHash, 0, 0};
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_chat_from_request(arena, &peer, &from, NOSHI_MESSAGES_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the messages of a person" completion:done];
    }];
}

- (void)loadSharedOfDialog:(NoshiDialog *)dialog kind:(noshi_shared_kind)kind beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_shared_request(arena, &peer, kind, beforeId, limit, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the shared media" completion:done];
    }];
}

- (void)loadOwnMessagesOfDialog:(NoshiDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_own_messages_request(arena, &peer, beforeId, limit, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the messages of the account" completion:done];
    }];
}

- (void)loadOldestSharedOfDialog:(NoshiDialog *)dialog kind:(noshi_shared_kind)kind completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_shared_oldest_request(arena, &peer, kind, 1, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverMessagesOfResult:result what:"the oldest shared media" completion:done];
    }];
}

static noshi_status NoshiCollectMessage(void *ctx, int64_t id, const noshi_tl_value *value);

/* the store keeps a forum as one chat, so a topic takes its own messages out of the newest page of the whole forum */
static void NoshiKeepTopic(NSMutableArray *messages, int32_t topic, BOOL discussion) {
    if (topic <= 0) return;
    NSIndexSet *others = [messages indexesOfObjectsPassingTest:^BOOL(id message, NSUInteger index, BOOL *stop) {
        (void)index;
        (void)stop;
        NoshiMessage *item = message;
        return discussion ? (item.messageId != topic && item.threadId != topic) : item.topicId != topic;
    }];
    [messages removeObjectsAtIndexes:others];
}

/* worker only: a stored user, or a stored channel for a negative key, for the sender names of a chat opened offline */
- (NoshiPerson *)storedPersonWithKey:(int64_t)key {
    noshi_arena arena;
    noshi_tl_value *entity = NULL;
    noshi_person_row row;
    noshi_peer none = {0, 0};
    NoshiPerson *person = nil;
    noshi_arena_init(&arena, 1024u * 1024u);
    if (key > 0) {
        if (noshi_store_get([self workerStore], NOSHI_RECORD_USER, none, key, &arena, &entity) == NOSHI_OK &&
            noshi_person_parse(entity, &row) == NOSHI_OK) person = [[[NoshiPerson alloc] initWithRow:&row] autorelease];
    } else {
        noshi_peer channel = {3, -key};
        noshi_status status = noshi_store_get([self workerStore], NOSHI_RECORD_CHAT, channel, -key, &arena, &entity);
        if (status == NOSHI_E_NOTFOUND) {
            /* older caches placed community objects under basic-chat keys */
            noshi_peer old = {2, -key};
            status = noshi_store_get([self workerStore], NOSHI_RECORD_CHAT, old, -key, &arena, &entity);
            if (status == NOSHI_OK && !noshi_tl_is(entity, NOSHI_TL_ID_community) &&
                !noshi_tl_is(entity, NOSHI_TL_ID_communityForbidden)) status = NOSHI_E_NOTFOUND;
        }
        if (status == NOSHI_OK && noshi_channel_person_parse(entity, &row) == NOSHI_OK)
            person = [[[NoshiPerson alloc] initWithRow:&row] autorelease];
    }
    noshi_arena_free(&arena);
    return person;
}

- (void)loadCachedPeopleWithIds:(NSArray *)ids completion:(void (^)(NSDictionary *))completion {
    NSArray *requested = [ids copy];
    void (^done)(NSDictionary *) = [completion copy];
    [self post:^{
        NSMutableDictionary *people = [NSMutableDictionary dictionary];
        for (NSNumber *key in requested) {
            NoshiPerson *person = [self storedPersonWithKey:key.longLongValue];
            if (person) [people setObject:person forKey:key];
        }
        [self deliverMain:^{ done(people); [done release]; }];
        [requested release];
    }];
}

- (NSDictionary *)storedPeopleForMessages:(NSArray *)messages {
    NSMutableDictionary *people = [NSMutableDictionary dictionary];
    for (NoshiMessage *message in messages) {
        NSNumber *key = [NSNumber numberWithLongLong:message.senderKey];
        if (!message.senderKey || [people objectForKey:key]) continue;
        NoshiPerson *person = [self storedPersonWithKey:message.senderKey];
        if (person) [people setObject:person forKey:key];
    }
    /* whoever wrote a forwarded message names it ("forwarded from ..."), so the people of the originals come with the senders */
    for (NoshiMessage *message in messages) {
        NSNumber *key = [NSNumber numberWithLongLong:message.forwardKey];
        if (!message.forwardKey || [people objectForKey:key]) continue;
        NoshiPerson *person = [self storedPersonWithKey:message.forwardKey];
        if (person) [people setObject:person forKey:key];
    }
    return people;
}

- (void)loadCachedHistoryOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    int32_t topic = dialog.topicId;
    BOOL discussion = dialog.discussion;
    [self post:^{
        NSMutableArray *messages = [NSMutableArray array];
        NSMutableDictionary *people = [NSMutableDictionary dictionary];
        noshi_status status = noshi_store_page([self workerStore], NOSHI_RECORD_MESSAGE, peer, INT64_MAX, WATCH_PAGE,
                                                  NoshiCollectMessage, messages);
        if (status != NOSHI_OK) NSLog(@"noshigram: cannot read the kept chat %lld: %s", (long long)peer.id, noshi_status_name(status));
        NoshiKeepTopic(messages, topic, discussion);
        [people addEntriesFromDictionary:[self storedPeopleForMessages:messages]];
        NSArray *deliveredMessages = status == NOSHI_OK && messages.count ? [[messages copy] autorelease] : nil;
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        [self deliverMain:^{ done(deliveredMessages, deliveredPeople, nil); [done release]; }];
    }];
}

#pragma mark topics

- (void)setTyping:(BOOL)typing inDialog:(NoshiDialog *)dialog {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_typing_request(arena, &peer, !typing, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) NSLog(@"noshigram: typing status of chat %lld was not sent: %@", dialog.peerId, NoshiRpcErrorName(result));
    }];
}

- (void)loadTopicsOfDialog:(NoshiDialog *)forum completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    NSUInteger draftRevision = self.drafts.revision;
    noshi_peer_ref peer = NoshiPeerRefOfDialog(forum);
    noshi_dialog_row base;
    memset(&base, 0, sizeof(base));
    base.peer_kind = peer.kind;
    base.peer_id = peer.id;
    base.peer_hash = peer.access_hash;
    base.kind = NOSHI_DIALOG_GROUP;
    snprintf(base.title, sizeof(base.title), "%s", forum.title.UTF8String);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_topics_request(arena, peer.kind, peer.id, peer.access_hash, 0, 0, 0, NOSHI_DIALOGS_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *topics = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_topics_parse(result->value, &base, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                             rows, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
                topics = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [topics addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
                [self noteDraftsOfTopicsAnswer:result->value forum:forum since:draftRevision];
                [self keepSummaryOfTopicRows:rows count:count forum:forum];
            } else {
                NSLog(@"noshigram: messages.getForumTopics answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredTopics = [[topics copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredTopics, deliveredError); [done release]; }];
    }];
}

/* worker only: the rows of a forum's topics, as the list names the topic of the last message and counts the unread ones from them */
- (void)keepSummaryOfTopicRows:(const noshi_dialog_row *)rows count:(size_t)count forum:(NoshiDialog *)forum {
    if (forum.saved || !forum.forum) return;
    noshi_forum_summary summary;
    if (noshi_forum_summarize(rows, count, forum.topMessage, &summary) != NOSHI_OK) return;
    [[self forumSummaries] setSummary:&summary forForum:forum.peerId topMessage:forum.topMessage];
    [self deliverMain:^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiForumSummariesDidChangeNotification object:self]; }];
}

/* the forums that a screen can show at a time are few, and each read is one request */
#define FORUM_SUMMARY_READS_MAX 12

- (void)refreshForumSummariesOfDialogs:(NSArray *)dialogs {
    NSUInteger started = 0;
    BOOL capped = NO;
    for (NoshiDialog *dialog in dialogs) {
        if (!dialog.forum || dialog.saved) continue;
        if (started >= FORUM_SUMMARY_READS_MAX) { capped = YES; continue; }
        if (![[self forumSummaries] beginReadingForum:dialog.peerId topMessage:dialog.topMessage]) continue;
        ++started;
        int64_t peerId = dialog.peerId;
        noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
        noshi_dialog_row base;
        memset(&base, 0, sizeof(base));
        base.peer_kind = peer.kind;
        base.peer_id = peer.id;
        base.peer_hash = peer.access_hash;
        base.kind = NOSHI_DIALOG_GROUP;
        int32_t last = dialog.topMessage;
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_topics_request(arena, peer.kind, peer.id, peer.access_hash, 0, 0, 0, NOSHI_DIALOGS_MAX, request);
        } handler:^(const noshi_mt_rpc_result *result) {
            noshi_dialog_row *rows = result->status == NOSHI_OK ? calloc(NOSHI_DIALOGS_MAX, sizeof(*rows)) : NULL;
            size_t count = 0;
            if (rows && noshi_topics_parse(result->value, &base, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                             rows, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
                noshi_forum_summary summary;
                if (noshi_forum_summarize(rows, count, last, &summary) == NOSHI_OK) {
                    [[self forumSummaries] setSummary:&summary forForum:peerId topMessage:last];
                    [self deliverMain:^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiForumSummariesDidChangeNotification object:self]; }];
                    /* the forums past the cap of one pass were left plain; each answer that comes frees the way for the next ones, and an error does not, so a failing server is not asked in a loop */
                    if (capped) [self refreshForumSummariesOfDialogs:dialogs];
                }
            } else {
                NSLog(@"noshigram: the topics of forum %lld did not load for the list: %@", (long long)peerId, result->status == NOSHI_OK ? @"answer rejected" : NoshiRpcErrorName(result));
            }
            free(rows);
            [[self forumSummaries] endReadingForum:peerId];
        }];
    }
}

- (void)applyForumSummariesToDialogs:(NSArray *)dialogs {
    [[self forumSummaries] applyToDialogs:dialogs];
}

- (void)loadMessageCountOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSInteger, NSString *))completion {
    void (^done)(NSInteger, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_history_request(arena, &peer, 0, 1, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSInteger count = -1;
        NSString *error = nil;
        int32_t total = 0;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_tl_get_i32(result->value, "count", &total) == NOSHI_OK && total >= 0) count = total;
        else {
            /* messages.messages is the whole list and carries no count of its own */
            const noshi_tl_value *all = NULL;
            if (noshi_tl_is(result->value, NOSHI_TL_ID_messages_messages) && noshi_tl_get_vec(result->value, "messages", &all) == NOSHI_OK) count = all->u.vec.count;
            else error = @"INTERNAL";
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(count, deliveredError); [done release]; }];
    }];
}

- (void)loadSavedDialogs:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_saved_dialogs_request(arena, 0, 0, 0, 0, 0, NOSHI_DIALOGS_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_dialogs_parse(result->value, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                              rows, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: messages.getSavedDialogs answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDialogs = [[dialogs copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDialogs, deliveredError); [done release]; }];
    }];
}

#pragma mark communities

- (void)loadCommunityPreviews:(NSMutableData *)data info:(NoshiCommunity *)info known:(NSArray *)known at:(NSUInteger)offset
                    completion:(void (^)(NoshiCommunity *, NSString *))completion {
    NSUInteger count = data.length / sizeof(noshi_dialog_row);
    if (offset >= count) {
        const noshi_dialog_row *rows = data.bytes;
        NSMutableArray *joined = [NSMutableArray array], *viewable = [NSMutableArray array];
        for (NSUInteger i = 0; i < count; ++i) {
            NoshiDialog *chat = nil;
            if (!rows[i].date) {
                for (NoshiDialog *candidate in known) {
                    if (!candidate.folder && candidate.peerKind == rows[i].peer_kind && candidate.peerId == rows[i].peer_id) {
                        chat = candidate;
                        break;
                    }
                }
            }
            if (!chat) chat = [[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease];
            [(rows[i].left ? viewable : joined) addObject:chat];
        }
        NoshiCommunity *loaded = [[[NoshiCommunity alloc] initWithTitle:info.title about:info.about collapsed:info.collapsed
                                                                  joined:joined viewable:viewable] autorelease];
        [self deliverMain:^{ completion(loaded, nil); }];
        return;
    }
    NSUInteger end = MIN(count, offset + 100);
    NSMutableData *peers = [NSMutableData data];
    const noshi_dialog_row *rows = data.bytes;
    for (NSUInteger i = offset; i < end; ++i) {
        noshi_peer_ref peer = {0};
        peer.kind = rows[i].peer_kind;
        peer.id = rows[i].peer_id;
        peer.access_hash = rows[i].peer_hash;
        if (peer.kind != 2 && !peer.access_hash) {
            NSLog(@"noshigram: community peer %lld has no access hash", peer.id);
            continue;
        }
        [peers appendBytes:&peer length:sizeof(peer)];
    }
    if (!peers.length) {
        [self loadCommunityPreviews:data info:info known:known at:end completion:completion];
        return;
    }
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_peer_dialogs_request(arena, peers.bytes, peers.length / sizeof(noshi_peer_ref), request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error && noshi_community_previews_apply(result->value, [self workerAccount], (int32_t)[[NSDate date] timeIntervalSince1970],
                                                       data.mutableBytes, count) != NOSHI_OK) error = @"MALFORMED";
        if (error) {
            [self noteRpcError:error];
            NSLog(@"noshigram: community message previews did not load: %@", error);
        }
        [self loadCommunityPreviews:data info:info known:known at:end completion:completion];
    }];
}

- (void)loadCommunity:(NoshiDialog *)community knownDialogs:(NSArray *)known completion:(void (^)(NoshiCommunity *, NSString *))completion {
    void (^done)(NoshiCommunity *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(community);
    NSArray *kept = [known copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_full_channel_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error) {
            noshi_community_info info;
            NSMutableData *data = [NSMutableData dataWithLength:NOSHI_DIALOGS_MAX * sizeof(noshi_dialog_row)];
            size_t count = 0;
            if (noshi_community_parse(result->value, &info, data.mutableBytes, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
                data.length = count * sizeof(noshi_dialog_row);
                NSString *title = [NSString stringWithUTF8String:info.title];
                NSString *about = [NSString stringWithUTF8String:info.about];
                NoshiCommunity *loaded = [[[NoshiCommunity alloc] initWithTitle:title.length ? title : community.title about:about ? about : @""
                    collapsed:info.collapsed joined:nil viewable:nil] autorelease];
                [self loadCommunityPreviews:data info:loaded known:kept at:0 completion:done];
            } else {
                NSLog(@"noshigram: community answer rejected");
                error = @"MALFORMED";
            }
        }
        if (error) {
            [self noteRpcError:error];
            [self deliverMain:^{ done(nil, error); }];
        }
        [done release];
    }];
    [kept release];
}

- (void)setCommunity:(NoshiDialog *)community collapsed:(BOOL)collapsed completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(community);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_community_collapse_request(arena, peer.id, peer.access_hash, collapsed, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

#pragma mark search

- (void)searchGlobal:(NSString *)query kind:(noshi_search_kind)kind offsetRate:(int32_t)offsetRate completion:(NoshiSearchCompletion)completion {
    NoshiSearchCompletion done = [completion copy];
    NSString *text = [query copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_search_request(arena, text.UTF8String, kind, offsetRate, 30, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        int32_t next = 0;
        int64_t account = [self workerAccount];
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_MESSAGES_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_search_parse(result->value, account, rows, NOSHI_MESSAGES_MAX, &count, &next) == NOSHI_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: messages.searchGlobal answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDialogs = [[dialogs copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDialogs, next, deliveredError); [done release]; }];
    }];
    [text release];
}

#pragma mark sending

- (void)finishSend:(const noshi_mt_rpc_result *)result randomId:(long long)randomId completion:(NoshiSendCompletion)done {
    [self workerForgetSend:randomId];
    int32_t serverId = 0;
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_status status = noshi_sent_parse(result->value, randomId, &serverId);
        /* an answer that names no id still delivered the message, the store or a reload brings it back */
        if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) {
            NSLog(@"noshigram: send answer rejected: %s", noshi_status_name(status));
            serverId = 0;
        }
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(serverId, deliveredError); [done release]; }];
}

/* the kinds a message can carry from here; the rest (addresses, hashtags, commands) the server finds in the text itself */
static uint8_t NoshiSendKindOfStyle(NoshiTextStyle style) {
    switch (style) {
    case NoshiTextStyleBold: return NOSHI_ENTITY_BOLD;
    case NoshiTextStyleItalic: return NOSHI_ENTITY_ITALIC;
    case NoshiTextStyleUnderline: return NOSHI_ENTITY_UNDERLINE;
    case NoshiTextStyleStrike: return NOSHI_ENTITY_STRIKE;
    case NoshiTextStyleCode: return NOSHI_ENTITY_CODE;
    case NoshiTextStylePre: return NOSHI_ENTITY_PRE;
    case NoshiTextStyleSpoiler: return NOSHI_ENTITY_SPOILER;
    case NoshiTextStyleQuote: return NOSHI_ENTITY_BLOCKQUOTE;
    case NoshiTextStyleLink: return NOSHI_ENTITY_TEXT_URL;
    case NoshiTextStyleMentionName: return NOSHI_ENTITY_MENTION_NAME;
    case NoshiTextStyleDate: return NOSHI_ENTITY_FORMATTED_DATE;
    case NoshiTextStyleCustomEmoji: return NOSHI_ENTITY_CUSTOM_EMOJI;
    default: return 0;
    }
}

/* pack entities and their strings together so the worker does not depend on Objective-C objects */
NSMutableData *NoshiPackSendEntities(NSArray *entities, NSMutableData **strings, size_t *count) {
    NSMutableData *packed = [NSMutableData dataWithLength:(entities.count ? entities.count : 1) * sizeof(noshi_send_entity)];
    NSMutableData *pool = [NSMutableData dataWithLength:1];
    noshi_send_entity *rows = packed.mutableBytes;
    size_t used = 0;
    for (NoshiTextEntity *entity in entities) {
        if (used >= NOSHI_MESSAGE_ENTITIES_MAX) break;
        uint8_t kind = NoshiSendKindOfStyle(entity.style);
        if (!kind) continue;
        rows[used].kind = kind;
        rows[used].flags = entity.flags;
        rows[used].offset = (int32_t)entity.range.location;
        rows[used].length = (int32_t)entity.range.length;
        rows[used].id = kind == NOSHI_ENTITY_MENTION_NAME ? entity.userId : entity.documentId;
        rows[used].access_hash = entity.accessHash;
        rows[used].date = entity.date;
        /* the offset into the buffer is turned into a pointer once the buffer has stopped growing */
        rows[used].text = entity.url.length ? (const char *)(uintptr_t)pool.length : NULL;
        if (entity.url.length) {
            NSData *utf8 = [entity.url dataUsingEncoding:NSUTF8StringEncoding];
            [pool appendData:utf8];
            [pool appendBytes:"\0" length:1];
        }
        ++used;
    }
    for (size_t i = 0; i < used; ++i) {
        if (rows[i].text) rows[i].text = (const char *)pool.bytes + (uintptr_t)rows[i].text;
    }
    *strings = pool;
    *count = used;
    return packed;
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    [self sendText:text entities:entities toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo
      completion:(NoshiSendCompletion)completion {
    [self sendText:text entities:entities toDialog:dialog randomId:randomId replyTo:replyTo quote:nil quoteOffset:-1 completion:completion];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo
           quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset completion:(NoshiSendCompletion)completion {
    [self sendText:text entities:entities toDialog:dialog randomId:randomId replyTo:replyTo quote:quote quoteOffset:quoteOffset silent:NO completion:completion];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo
           quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset silent:(BOOL)silent completion:(NoshiSendCompletion)completion {
    [self sendText:text entities:entities toDialog:dialog randomId:randomId replyTo:replyTo quote:quote quoteOffset:quoteOffset silent:silent effect:0 completion:completion];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo
           quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset silent:(BOOL)silent effect:(long long)effect completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    NSString *quoted = [quote copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    BOOL noPreview = NoshiChatFlagGet(NoshiChatFlagNoLinkPreview);
    NSMutableData *strings = nil;
    size_t count = 0;
    NSMutableData *packed = NoshiPackSendEntities(entities, &strings, &count);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        /* the block keeps the data object, not only the pointer into it */
        /* a game emoji alone is thrown by the server, as the other clients send it; with words, entities or a quote it stays text */
        BOOL thrown = !count && !quoted.length && noshi_dice_emoticon(body.UTF8String);
        noshi_status status = thrown ? noshi_send_dice_request(arena, &peer, body.UTF8String, randomId, request)
                                       : noshi_send_text_reply_request(arena, &peer, body.UTF8String, packed.bytes, count, randomId, replyTo, request);
        (void)strings;
        if (thrown && status == NOSHI_OK) status = noshi_set_reply(arena, *request, &peer, replyTo);
        if (status == NOSHI_OK && quoted.length && replyTo > 0) status = noshi_set_reply_quote(arena, *request, &peer, replyTo, quoted.UTF8String, quoteOffset);
        if (status == NOSHI_OK && noPreview && !thrown) status = noshi_tl_set_flag(*request, "no_webpage");
        if (status == NOSHI_OK && silent) status = noshi_tl_set_flag(*request, "silent");
        /* a dice thrown by messages.sendMedia has no effect field */
        if (status == NOSHI_OK && effect && !thrown) status = noshi_set_effect(arena, *request, effect);
        return status == NOSHI_OK ? NoshiApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [body release];
    [quoted release];
}

/* the list comes once per run: the effects of Telegram change rarely, and the hold on the send button must not wait for the network every time */
- (void)loadMessageEffects:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    if (NoshiKeptEffects) {
        NSArray *kept = NoshiKeptEffects;
        [self deliverMain:^{ done(kept, nil); [done release]; }];
        return;
    }
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_effects_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSArray *effects = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_effect rows[NOSHI_EFFECTS_MAX];
            size_t count = 0;
            if (noshi_effects_parse(result->value, rows, NOSHI_EFFECTS_MAX, &count) != NOSHI_OK) {
                error = @"MALFORMED";
            } else {
                NSMutableArray *list = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    NoshiMessageEffect *effect = [[[NoshiMessageEffect alloc] init] autorelease];
                    effect.effectId = rows[i].id;
                    effect.emoticon = [NSString stringWithUTF8String:rows[i].emoticon];
                    effect.premium = rows[i].premium != 0;
                    if (rows[i].animation.id) effect.animation = [[[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].animation] autorelease];
                    if (rows[i].sticker.id) effect.sticker = [[[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].sticker] autorelease];
                    [list addObject:effect];
                }
                effects = list;
            }
        }
        [self noteRpcError:error];
        NSArray *delivered = [[effects copy] autorelease];
        NSString *problem = [[error copy] autorelease];
        @synchronized ([NoshiSession class]) {
            if (delivered && !NoshiKeptEffects) {
                NoshiKeptEffects = [delivered retain];
                NoshiEffectsById = [[NSMutableDictionary alloc] init];
                for (NoshiMessageEffect *item in delivered) [NoshiEffectsById setObject:item forKey:[NSNumber numberWithLongLong:item.effectId]];
            }
        }
        [self deliverMain:^{ done(delivered, problem); [done release]; }];
    }];
}

- (void)sendSticker:(NoshiMedia *)sticker toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion {
    [self sendSticker:sticker toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendSticker:(NoshiMedia *)sticker toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    noshi_media_ref ref = sticker.ref;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_status status = noshi_send_sticker_request(arena, &peer, &ref, randomId, request);
        if (status == NOSHI_OK) status = noshi_set_reply(arena, *request, &peer, replyTo);
        return status == NOSHI_OK ? NoshiApplySendAs(self, &peer, arena, *request) : status;
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
}

- (void)markDialogRead:(NoshiDialog *)dialog upTo:(int32_t)maxId toEnd:(BOOL)toEnd completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    if (maxId <= 0 || !noshi_read_action_allowed(0, NOSHI_READ_AUTOMATIC)) {
        if (done) done(@"NOT_SENT");
        [done release];
        return;
    }
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:dialog.peerKind], @"kind", [NSNumber numberWithLongLong:dialog.peerId], @"peer",
                          [NSNumber numberWithInt:dialog.topicId], @"topic", [NSNumber numberWithInt:maxId], @"maxId", [NSNumber numberWithBool:toEnd], @"toEnd", nil];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        if (!noshi_read_action_allowed(0, NOSHI_READ_AUTOMATIC)) return NOSHI_E_RETRY;
        return noshi_read_history_request(arena, &peer, maxId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSLog(@"noshigram: marking chat %lld read failed: %@", peer.id, error);
        } else if (!noshi_read_history_answer_valid(&peer, result->value)) {
            error = @"MALFORMED";
            [self noteRpcError:error];
            NSLog(@"noshigram: marking chat %lld read returned an invalid answer", peer.id);
        }
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{
            /* the lists draw their counts from the rows they hold, and the server's own news of the read comes through a reload that can lag or wait out a flood limit */
            if (!delivered) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogReadNotification object:self userInfo:info];
            if (done) done(delivered);
            [done release];
        }];
    }];
}

- (void)markMentionsRead:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    if (!noshi_read_action_allowed(0, NOSHI_READ_AUTOMATIC)) { if (completion) completion(@"NOT_SENT"); return; }
    [self markContentsRead:ids dialog:dialog completion:completion];
}

/* one-time media cannot be consumed without telling the server, so ghost mode refuses the acknowledgement */
- (void)markContentsRead:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    if (!noshi_read_action_allowed(0, NOSHI_READ_ONCE)) { if (completion) completion(@"NOT_SENT"); return; }
    if (!ids.count || ids.count > NOSHI_MESSAGES_MAX) { if (completion) completion(@"NOT_SENT"); return; }
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSArray *messages = [ids copy];
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        if (!noshi_read_action_allowed(0, NOSHI_READ_ONCE)) return NOSHI_E_RETRY;
        noshi_tl_value *list = noshi_tl_new_vec(arena, (uint32_t)messages.count);
        *request = noshi_tl_new_obj(arena, peer.kind == 3 ? "channels.readMessageContents" : "messages.readMessageContents");
        if (!list || !*request) return NOSHI_E_NOMEM;
        for (NSUInteger i = 0; i < messages.count; ++i) {
            int32_t value = [[messages objectAtIndex:i] intValue];
            if (value <= 0) return NOSHI_E_ARG;
            noshi_tl_value *item = noshi_tl_new_i32(arena, value);
            if (!item) return NOSHI_E_NOMEM;
            noshi_status status = noshi_tl_vec_set(list, (uint32_t)i, item);
            if (status != NOSHI_OK) return status;
        }
        noshi_status status = noshi_tl_set(*request, "id", list);
        if (status == NOSHI_OK && peer.kind == 3) {
            noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
            if (!channel || !peer.access_hash) return NOSHI_E_ARG;
            status = noshi_tl_set_i64(arena, channel, "channel_id", peer.id);
            if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
            if (status == NOSHI_OK) status = noshi_tl_set(*request, "channel", channel);
        }
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error && !(peer.kind == 3 ? noshi_tl_is(result->value, NOSHI_TL_ID_boolTrue) : noshi_tl_is(result->value, NOSHI_TL_ID_messages_affectedMessages))) error = @"MALFORMED";
        if (error) { [self noteRpcError:error]; NSLog(@"noshigram: marking contents read failed: %@", error); }
        [self deliverMain:^{ if (done) done(error); [done release]; [messages release]; }];
    }];
}

#pragma mark watching

/* worker only: the visit callback of the store page; a message that cannot be shown is skipped */
static noshi_status NoshiCollectMessage(void *ctx, int64_t id, const noshi_tl_value *value) {
    (void)id;
    NSMutableArray *messages = ctx;
    noshi_message_row *row = calloc(1, sizeof(*row));
    if (!row) return NOSHI_E_NOMEM;
    if (noshi_message_read(value, row) == NOSHI_OK) {
        NoshiMessage *message = [NoshiMessage messageWithRow:row];
        if (message && row->has_markup) message.markup = [NoshiMarkup markupWithValue:noshi_tl_get(value, "reply_markup")];
        if (message) [messages addObject:message];
    }
    free(row);
    return NOSHI_OK;
}

- (void)loadChannelSender:(long long)channelId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiPerson *, NSString *))completion {
    void (^done)(NoshiPerson *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_channel_from_message_request(arena, &peer, messageId, channelId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NoshiPerson *person = nil;
        if (!error) {
            person = [NoshiPeopleOfAnswer(self, result->value) objectForKey:[NSNumber numberWithLongLong:-channelId]];
            if (!person.accessHash) error = @"CHANNEL_INVALID";
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(person, deliveredError); [done release]; }];
    }];
}

- (void)loadSenderRolesOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSDictionary *, NSDictionary *, NSString *))completion {
    void (^done)(NSDictionary *, NSDictionary *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_group_roles_request(arena, peer.kind, peer.id, peer.access_hash, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableDictionary *roles = [NSMutableDictionary dictionary];
        NSDictionary *people = nil;
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error) {
            noshi_group_role rows[NOSHI_GROUP_ROLES_MAX];
            size_t count = 0;
            noshi_status status = noshi_group_roles_parse(result->value, peer.id, rows, NOSHI_GROUP_ROLES_MAX, &count);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: group roles could not be read: %s", noshi_status_name(status));
                error = @"INTERNAL";
            } else {
                people = NoshiPeopleOfAnswer(self, result->value);
                for (size_t i = 0; i < count; ++i) {
                    NSString *role = rows[i].rank[0] ? [NSString stringWithUTF8String:rows[i].rank]
                        : NSLocalizedString(rows[i].owner ? @"chat.role.owner" : @"chat.role.admin", nil);
                    [roles setObject:role forKey:[NSNumber numberWithLongLong:rows[i].user_id]];
                }
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(roles, people, deliveredError); [done release]; }];
    }];
}

- (void)watchDialog:(NoshiDialog *)dialog handler:(void (^)(NSArray *messages))handler {
    if (!handler) { [self watchDialog:dialog peopleHandler:nil]; return; }
    [self watchDialog:dialog peopleHandler:^(NSArray *messages, NSDictionary *people) {
        (void)people;
        handler(messages);
    }];
}

- (void)watchDialog:(NoshiDialog *)dialog peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler {
    [self watchDialog:dialog owner:nil peopleHandler:handler];
}

- (void)stopWatchingForOwner:(id)owner {
    void *key = owner;
    [self post:^{ [self clearStoreObserverOwnedBy:key]; }];
}

- (void)watchDialog:(NoshiDialog *)dialog owner:(id)owner peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler {
    if (!dialog || !handler) {
        [self post:^{ [self setStoreObserver:nil]; }];
        return;
    }
    void *key = owner;
    void (^deliver)(NSArray *, NSDictionary *) = [handler copy];
    noshi_peer peer = {dialog.peerKind, dialog.peerId};
    int32_t topic = dialog.topicId;
    BOOL discussion = dialog.discussion;
    /* the same page twice in a row is not worth a trip to the main thread: what each message of the last page looked like, by id */
    NSMutableDictionary *seen = [[NSMutableDictionary alloc] init];
    /* the store counts the writes that touch this chat, so a change elsewhere (every update of every other chat
       reaches this observer) costs one compare and no page read */
    __block const noshi_store *seenStore = NULL;
    __block uint64_t seenVersion = 0;
    [self post:^{
        [self setStoreObserver:^{
            noshi_store *store = [self workerStore];
            uint64_t version = noshi_store_peer_version(store, peer);
            if (store == seenStore && version == seenVersion) return;
            NSMutableArray *messages = [NSMutableArray array];
            noshi_status status = noshi_store_page(store, NOSHI_RECORD_MESSAGE, peer, INT64_MAX, WATCH_PAGE,
                                                      NoshiCollectMessage, messages);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: reading chat %lld from the store failed: %s", (long long)peer.id, noshi_status_name(status));
                return;
            }
            NoshiKeepTopic(messages, topic, discussion);
            NSMutableDictionary *now = [NSMutableDictionary dictionaryWithCapacity:messages.count];
            NSDictionary *people = [self storedPeopleForMessages:messages];
            int32_t pageLowest = INT32_MAX;
            for (NoshiMessage *message in messages) {
                NoshiPerson *sender = [people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
                NSString *one = [NSString stringWithFormat:@"%d:%lu:%@:%@:%lld:%lu:%@:%@:%@:%d", message.edited, (unsigned long)message.text.length,
                    message.reactionKey, message.markupKey, message.senderKey, (unsigned long)sender.name.length, sender.name, sender.photo.key,
                    message.senderRank, sender.bot];
                [now setObject:one forKey:[NSNumber numberWithInt:message.messageId]];
                pageLowest = MIN(pageLowest, message.messageId);
            }
            seenStore = store;
            seenVersion = version;
            /* a message is news when it is new or changed, or when one at or above the oldest of the page is gone. an oldest message that only fell out of the window of the
               newest 60 is not: in a topic every message of any other topic of the forum pushes one of its own out, and each of those was a rebuild of the whole list */
            BOOL changed = NO;
            for (NSNumber *key in now) {
                if (![[seen objectForKey:key] isEqualToString:[now objectForKey:key]]) { changed = YES; break; }
            }
            if (!changed) {
                for (NSNumber *key in seen) {
                    if ([key intValue] >= pageLowest && ![now objectForKey:key]) { changed = YES; break; }
                }
            }
            [seen setDictionary:now];
            if (!changed) return;
            NSArray *page = [[messages copy] autorelease];
            [self deliverMain:^{ deliver(page, people); }];
        } owner:key];
        /* what is already stored shows at once */
        [self storeChanged];
    }];
    [deliver release];
    [seen release];
}

#pragma mark reactions

- (void)loadCustomEmojiDocuments:(NSArray *)documentIds completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    NSUInteger count = MIN(documentIds.count, (NSUInteger)NOSHI_CUSTOM_EMOJI_MAX);
    /* the request is built later on the worker, so the ids travel in an object the block keeps */
    NSMutableData *packed = [NSMutableData dataWithLength:(count ? count : 1) * sizeof(int64_t)];
    int64_t *ids = packed.mutableBytes;
    for (NSUInteger i = 0; i < count; ++i) ids[i] = [[documentIds objectAtIndex:i] longLongValue];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_custom_emoji_request(arena, packed.bytes, count, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *documents = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            /* the rows hold two file references each, so they live on the heap rather than on the worker's stack */
            noshi_custom_emoji *rows = calloc(NOSHI_CUSTOM_EMOJI_MAX, sizeof(*rows));
            size_t found = 0;
            if (rows && noshi_custom_emoji_parse(result->value, rows, NOSHI_CUSTOM_EMOJI_MAX, &found) == NOSHI_OK) {
                documents = [NSMutableArray arrayWithCapacity:found];
                for (size_t i = 0; i < found; ++i) {
                    NoshiCustomEmojiDocument *document = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i]];
                    if (document.alt.length) [documents addObject:document];
                    [document release];
                }
            } else {
                NSLog(@"noshigram: custom emoji answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredDocuments = [[documents copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredDocuments, deliveredError); [done release]; }];
    }];
}

/* the custom emoji a Premium account uses most or lately, from the two lists the server keeps; a list that fails
   is skipped and the other still counts */
- (void)loadFrequentCustomReactions:(void (^)(NSArray *reactions))then {
    void (^finish)(NSArray *) = [then copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_reaction_list_request(arena, 0, 24, request);
    } handler:^(const noshi_mt_rpc_result *top) {
        NSMutableArray *found = [NSMutableArray array];
        noshi_reaction rows[NOSHI_REACTION_CATALOG_MAX];
        size_t count = 0;
        if (top->status == NOSHI_OK && noshi_reaction_list_read(top->value, rows, NOSHI_REACTION_CATALOG_MAX, &count) == NOSHI_OK) {
            for (size_t i = 0; i < count; ++i) [found addObject:[NoshiReaction reactionWithRow:&rows[i]]];
        } else {
            NSLog(@"noshigram: top reactions not taken: %@", top->status == NOSHI_OK ? @"rejected" : NoshiRpcErrorName(top));
        }
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_reaction_list_request(arena, 1, 24, request);
        } handler:^(const noshi_mt_rpc_result *recent) {
            noshi_reaction more[NOSHI_REACTION_CATALOG_MAX];
            size_t added = 0;
            if (recent->status == NOSHI_OK && noshi_reaction_list_read(recent->value, more, NOSHI_REACTION_CATALOG_MAX, &added) == NOSHI_OK) {
                for (size_t i = 0; i < added; ++i) {
                    NoshiReaction *reaction = [NoshiReaction reactionWithRow:&more[i]];
                    BOOL seen = NO;
                    for (NoshiReaction *known in found) seen = seen || [known.key isEqualToString:reaction.key];
                    if (!seen) [found addObject:reaction];
                }
            } else {
                NSLog(@"noshigram: recent reactions not taken: %@", recent->status == NOSHI_OK ? @"rejected" : NoshiRpcErrorName(recent));
            }
            finish(found);
            [finish release];
        }];
    }];
}

- (void)loadReactionCatalogWithPolicy:(noshi_reactions)allowed all:(BOOL)all custom:(BOOL)allowCustom premium:(BOOL)premium
                           completion:(NoshiReactionChoicesCompletion)completion {
    NoshiReactionChoicesCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.getAvailableReactions");
        return *request ? noshi_tl_set_i32(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *items = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else {
            noshi_reaction rows[NOSHI_REACTION_CATALOG_MAX];
            size_t count = 0;
            noshi_status status = noshi_reaction_catalog_read(result->value, rows, NOSHI_REACTION_CATALOG_MAX, &count, premium);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: reaction catalog rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            } else {
                items = [NSMutableArray array];
                for (size_t i = 0; i < count; ++i) {
                    BOOL permitted = all;
                    for (uint8_t j = 0; !permitted && j < allowed.count; ++j)
                        permitted = noshi_reaction_equal(&rows[i], &allowed.items[j]);
                    if (permitted) [items addObject:[NoshiReaction reactionWithRow:&rows[i]]];
                }
                /* only a Premium account may react with a custom emoji, those the chat lists and, where the chat allows any, its own favorites */
                if (premium) {
                    for (uint8_t j = 0; j < allowed.count; ++j) {
                        if (allowed.items[j].kind == NOSHI_REACTION_CUSTOM) [items addObject:[NoshiReaction reactionWithRow:&allowed.items[j]]];
                    }
                }
            }
        }
        if (error || !premium || !all || !allowCustom) {
            [self finishReactionChoices:items custom:all && allowCustom error:error completion:done];
            [done release];
            return;
        }
        NSMutableArray *standard = items;
        [self loadFrequentCustomReactions:^(NSArray *favorites) {
            for (NoshiReaction *reaction in favorites) {
                BOOL seen = NO;
                for (NoshiReaction *known in standard) seen = seen || [known.key isEqualToString:reaction.key];
                if (!seen) [standard addObject:reaction];
            }
            [self finishReactionChoices:standard custom:YES error:nil completion:done];
            [done release];
        }];
    }];
}

/* the custom flag says whether the chat takes any custom emoji, which decides if the picker offers its emoji panel */
- (void)finishReactionChoices:(NSArray *)items custom:(BOOL)custom error:(NSString *)error completion:(NoshiReactionChoicesCompletion)done {
    [self finishLoad:items error:error completion:^(NSArray *delivered, NSString *deliveredError) { done(delivered, custom, deliveredError); }];
}

- (void)loadAvailableReactionsForDialog:(NoshiDialog *)dialog premium:(BOOL)premium completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self loadReactionChoicesForDialog:dialog premium:premium completion:^(NSArray *choices, BOOL custom, NSString *errorName) {
        (void)custom;
        done(choices, errorName);
    }];
    [done release];
}

- (void)loadReactionChoicesForDialog:(NoshiDialog *)dialog premium:(BOOL)premium completion:(NoshiReactionChoicesCompletion)completion {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    if (peer.kind == 1) {
        noshi_reactions allowed;
        memset(&allowed, 0, sizeof(allowed));
        [self loadReactionCatalogWithPolicy:allowed all:YES custom:YES premium:premium completion:completion];
        return;
    }
    NoshiReactionChoicesCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        if (peer.kind == 2) {
            *request = noshi_tl_new_obj(arena, "messages.getFullChat");
            return *request ? noshi_tl_set_i64(arena, *request, "chat_id", peer.id) : NOSHI_E_NOMEM;
        }
        noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
        *request = noshi_tl_new_obj(arena, "channels.getFullChannel");
        if (!channel || !*request) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_set_i64(arena, channel, "channel_id", peer.id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set(*request, "channel", channel);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        noshi_reactions allowed;
        int all = 0, custom = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else {
            noshi_status status = noshi_reaction_policy_read(result->value, &allowed, &all);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: chat reaction policy rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            custom = noshi_reaction_policy_custom(result->value);
        }
        if (error) [self finishReactionChoices:nil custom:NO error:error completion:done];
        else [self loadReactionCatalogWithPolicy:allowed all:all custom:custom premium:premium completion:done];
        [done release];
    }];
}

- (void)refreshReactionsForMessages:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion {
    NSArray *requested = [ids copy];
    NoshiListCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        int32_t values[NOSHI_MESSAGES_MAX];
        if (!requested.count || requested.count > NOSHI_MESSAGES_MAX) return NOSHI_E_ARG;
        for (NSUInteger i = 0; i < requested.count; ++i) values[i] = [[requested objectAtIndex:i] intValue];
        return noshi_get_reactions_request(arena, &peer, values, requested.count, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else {
            messages = [NSMutableArray array];
            noshi_peer storedPeer = {peer.kind, peer.id};
            for (NSNumber *key in requested) {
                noshi_arena arena;
                noshi_tl_value *value = NULL;
                noshi_message_row *row = calloc(1, sizeof(*row));
                noshi_arena_init(&arena, 8u * 1024u * 1024u);
                noshi_status status = row ? noshi_store_get([self workerStore], NOSHI_RECORD_MESSAGE,
                    storedPeer, key.intValue, &arena, &value) : NOSHI_E_NOMEM;
                if (status == NOSHI_OK) status = noshi_message_read(value, row);
                noshi_reactions fresh;
                if (status == NOSHI_OK) status = noshi_reaction_update_read(result->value, peer.kind, peer.id, key.intValue, &fresh);
                if (status == NOSHI_OK && !fresh.min) {
                    row->reactions = fresh;
                    row->has_reactions = 1;
                }
                if (status == NOSHI_OK) {
                    NoshiMessage *refreshed = [NoshiMessage messageWithRow:row];
                    if (row->has_markup) refreshed.markup = [NoshiMarkup markupWithValue:noshi_tl_get(value, "reply_markup")];
                    [messages addObject:refreshed];
                }
                else {
                    NSLog(@"noshigram: refreshed reactions for %d unavailable: %s", key.intValue, noshi_status_name(status));
                    error = @"INTERNAL";
                }
                free(row);
                noshi_arena_free(&arena);
            }
        }
        [self finishLoad:error ? nil : messages error:error completion:done];
        [done release];
    }];
    [requested release];
}

- (void)sendPaidReactionOfStars:(int32_t)stars messageId:(int32_t)messageId dialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    /* one id for the call, kept by the block, so a send that is repeated by the transport is not paid for twice */
    long long randomId = (((long long)arc4random() << 32) | arc4random()) | 1;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_paid_reaction_request(arena, &peer, messageId, stars, randomId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) [self finishLoad:nil error:NoshiRpcErrorName(result) completion:done];
        else [self refreshReactionsForMessages:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:dialog completion:done];
        [done release];
    }];
}

- (void)sendReactions:(NSArray *)reactions messageId:(int32_t)messageId dialog:(NoshiDialog *)dialog
           completion:(NoshiListCompletion)completion {
    NSArray *choices = [reactions copy];
    NoshiListCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_reaction rows[NOSHI_REACTIONS_MAX];
        if (choices.count > NOSHI_REACTIONS_MAX) return NOSHI_E_ARG;
        for (NSUInteger i = 0; i < choices.count; ++i) rows[i] = [(NoshiReaction *)[choices objectAtIndex:i] row];
        return noshi_send_reactions_request(arena, &peer, messageId, rows, choices.count, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) [self finishLoad:nil error:NoshiRpcErrorName(result) completion:done];
        else [self refreshReactionsForMessages:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:dialog completion:done];
        [done release];
    }];
    [choices release];
}

- (void)loadReactionArt:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.getAvailableReactions");
        return *request ? noshi_tl_set_i32(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *art = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else {
            /* six documents with a file reference each per reaction, so the rows live on the heap */
            noshi_reaction_art *rows = calloc(NOSHI_REACTION_CATALOG_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_reaction_art_read(result->value, rows, NOSHI_REACTION_CATALOG_MAX, &count) : NOSHI_E_NOMEM;
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: reaction art rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            } else {
                art = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    /* the catalog is keyed by this emoji, and stringWithUTF8String: answers nil for bytes that are not utf-8, which threw on the nil key in setCatalog: */
                    NSString *emoji = [NSString stringWithUTF8String:rows[i].emoji];
                    if (!emoji.length) {
                        NSLog(@"noshigram: reaction art row %lu has no readable emoji and is skipped", (unsigned long)i);
                        continue;
                    }
                    NoshiCustomEmojiDocument *icon = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].icon];
                    NoshiCustomEmojiDocument *appear = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].appear];
                    NoshiCustomEmojiDocument *select = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].select];
                    NoshiCustomEmojiDocument *activate = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].activate];
                    NoshiCustomEmojiDocument *effect = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].effect];
                    NoshiCustomEmojiDocument *around = rows[i].around.id ? [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i].around] : nil;
                    NoshiReactionArtwork *item = [[NoshiReactionArtwork alloc] initWithEmoji:emoji icon:icon appear:appear
                                                                                  select:select activate:activate effect:effect around:around];
                    [art addObject:item];
                    [item release];
                    [icon release];
                    [appear release];
                    [select release];
                    [activate release];
                    [effect release];
                    [around release];
                }
            }
            free(rows);
        }
        [self finishLoad:art error:error completion:done];
        [done release];
    }];
}

- (void)loadReactionLimits:(void (^)(int32_t, int32_t, NSString *))completion {
    void (^done)(int32_t, int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "help.getAppConfig");
        return *request ? noshi_tl_set_i32(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        int32_t standard = 1, premium = 3;
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_reaction_limits_read(result->value, &standard, &premium) != NOSHI_OK) {
            standard = 1;
            premium = 3;
            error = @"CONFIG_INVALID";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(standard, premium, delivered); [done release]; }];
    }];
}

#pragma mark stickers

- (void)loadStickerSets:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.getAllStickers");
        return *request ? noshi_tl_set_i64(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_set_row *rows = calloc(NOSHI_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_sticker_sets_parse(result->value, rows, NOSHI_STICKER_SETS_MAX, &count) == NOSHI_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[NoshiStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getAllStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadAnimatedEmojiStickers:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_animated_emoji_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_ANIMATED_EMOJI_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_animated_emoji_parse(result->value, rows, NOSHI_ANIMATED_EMOJI_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: animated emoji pack rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadDiceStickersForEmoji:(NSString *)emoji completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    NSString *asked = [emoji copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_dice_set_request(arena, asked.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_DICE_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_dice_set_parse(result->value, rows, NOSHI_DICE_STICKERS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK && count > 0) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: dice set of %@ rejected: %s", asked, noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
        [asked release];
    }];
}

- (void)loadStickersOfSet:(NoshiStickerSet *)set completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    noshi_sticker_set_row row = set.row;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_set_request(arena, &row, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            noshi_sticker_set_row header;
            size_t count = 0;
            if (rows && noshi_sticker_set_parse(result->value, &header, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getStickerSet answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadStickersOfSetNamed:(NSString *)shortName completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    NSString *name = [shortName copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_set_by_name_request(arena, name.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            noshi_sticker_set_row header;
            size_t count = 0;
            if (rows && noshi_sticker_set_parse(result->value, &header, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getStickerSet answer for %@ rejected", name);
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
    [name release];
}

- (void)loadEmojiSets:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_emoji_sets_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *sets = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_set_row *rows = calloc(NOSHI_STICKER_SETS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_emoji_sets_parse(result->value, rows, NOSHI_STICKER_SETS_MAX, &count) == NOSHI_OK) {
                sets = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [sets addObject:[NoshiStickerSet setWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getEmojiStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:sets error:error completion:done];
        [done release];
    }];
}

- (void)loadEmojiOfSet:(NoshiStickerSet *)set completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    noshi_sticker_set_row row = set.row;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sticker_set_request(arena, &row, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *emoji = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_custom_emoji *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            noshi_sticker_set_row header;
            size_t count = 0;
            if (rows && noshi_emoji_set_parse(result->value, &header, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                emoji = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    NoshiCustomEmojiDocument *document = [[NoshiCustomEmojiDocument alloc] initWithRow:&rows[i]];
                    [emoji addObject:document];
                    [document release];
                }
            } else {
                NSLog(@"noshigram: messages.getStickerSet answer for emoji rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:emoji error:error completion:done];
        [done release];
    }];
}

- (void)loadRecentStickers:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "messages.getRecentStickers");
        return *request ? noshi_tl_set_i64(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_recent_stickers_parse(result->value, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getRecentStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

/* the stickers of a list the server answered in full, read with the parser of its kind */
- (void)loadStickerList:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build
                  parse:(noshi_status (*)(const noshi_tl_value *, noshi_sticker_row *, size_t, size_t *))parse
                   what:(const char *)what completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? parse(result->value, rows, NOSHI_STICKERS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else if (status == NOSHI_E_NOTFOUND) {
                stickers = [NSMutableArray array];
            } else {
                NSLog(@"noshigram: the answer for %s was rejected: %s", what, noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

- (void)loadFavedStickers:(NoshiListCompletion)completion {
    [self loadStickerList:^noshi_status(noshi_arena *arena, noshi_tl_value **request) { return noshi_faved_stickers_request(arena, request); }
                    parse:noshi_faved_stickers_parse what:"the favorite stickers" completion:completion];
}

- (void)loadSavedGifs:(NoshiListCompletion)completion {
    [self loadStickerList:^noshi_status(noshi_arena *arena, noshi_tl_value **request) { return noshi_saved_gifs_request(arena, request); }
                    parse:noshi_saved_gifs_parse what:"the saved animations" completion:completion];
}

- (void)faveSticker:(NoshiSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_media_ref ref = sticker.media.ref;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_fave_sticker_request(arena, &ref, unfave ? 1 : 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_sticker_manage_parse(result->value) != NOSHI_OK) error = @"NOT_DONE";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)clearRecentStickers:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_clear_recent_stickers_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_sticker_manage_parse(result->value) != NOSHI_OK) error = @"NOT_DONE";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)loadGreetingStickers:(NoshiListCompletion)completion {
    [self loadStickersWithEmoticon:"\xf0\x9f\x91\x8b" completion:completion];
}

- (void)loadStickersWithEmoticon:(const char *)emoticon completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_stickers_request(arena, emoticon, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *stickers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_sticker_row *rows = calloc(NOSHI_STICKERS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_stickers_parse(result->value, rows, NOSHI_STICKERS_MAX, &count) == NOSHI_OK) {
                stickers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [stickers addObject:[NoshiSticker stickerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: messages.getStickers answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:stickers error:error completion:done];
        [done release];
    }];
}

@end

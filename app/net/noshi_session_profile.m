#import "noshi_session_internal.h"

#include "noshi_avatars.h"
#include "noshi_profile.h"

#import "noshi_rpc.h"
#import "noshi_session_profile.h"
#import "noshi_message.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *NoshiProfileUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiPersonalChannel
@synthesize dialog = _dialog;
@synthesize subscribers = _subscribers;
@synthesize lastText = _lastText;
@synthesize lastDate = _lastDate;
- (id)initWithDialog:(NoshiDialog *)dialog subscribers:(NSInteger)subscribers lastText:(NSString *)text lastDate:(int32_t)date {
    self = [super init];
    if (!self) return nil;
    _dialog = [dialog retain];
    _subscribers = subscribers;
    _lastText = [(text ? text : @"") copy];
    _lastDate = date;
    return self;
}
- (void)dealloc {
    [_dialog release];
    [_lastText release];
    [super dealloc];
}
@end

@implementation NoshiFullUser
@synthesize about = _about;
@synthesize note = _note, hasPersonalPhoto = _hasPersonalPhoto, publicPhoto = _publicPhoto;
@synthesize person = _person;
@synthesize requiresPremium = _requiresPremium;
@synthesize sharingRestricted = _sharingRestricted;
@synthesize blocked = _blocked;
@synthesize hasBirthday = _hasBirthday;
@synthesize birthdayDay = _birthdayDay;
@synthesize birthdayMonth = _birthdayMonth;
@synthesize birthdayYear = _birthdayYear;
@synthesize channel = _channel;
@synthesize music = _music;
@synthesize hasIntro = _hasIntro, introTitle = _introTitle, introText = _introText, introSticker = _introSticker;
@synthesize commonChats = _commonChats;
@synthesize hasRating = _hasRating, hasPendingRating = _hasPendingRating, pendingRatingDate = _pendingRatingDate;
@synthesize rating = _rating, pendingRating = _pendingRating;
- (id)initWithRow:(const noshi_full_user *)row channel:(NoshiPersonalChannel *)channel {
    self = [super init];
    if (!self) return nil;
    _about = [NoshiProfileUtf8(row->about) copy];
    _note = [NoshiProfileUtf8(row->note) copy];
    _hasPersonalPhoto = row->has_personal_photo != 0;
    if (row->has_public_photo) _publicPhoto = [[NoshiMedia mediaWithInfo:&row->public_photo] retain];
    if (row->has_person) _person = [[NoshiPerson alloc] initWithRow:&row->person];
    _requiresPremium = row->require_premium != 0;
    _sharingRestricted = row->sharing_restricted != 0;
    _blocked = row->blocked != 0;
    _hasBirthday = row->has_birthday;
    _birthdayDay = row->birthday_day;
    _birthdayMonth = row->birthday_month;
    _birthdayYear = row->birthday_year;
    _channel = [channel retain];
    if (row->has_music) _music = [[NoshiMedia mediaWithInfo:&row->music] retain];
    _hasIntro = row->has_intro != 0;
    _introTitle = [NoshiProfileUtf8(row->intro_title) copy];
    _introText = [NoshiProfileUtf8(row->intro_text) copy];
    if (row->has_intro_sticker) _introSticker = [[NoshiSticker stickerWithRow:&row->intro_sticker] retain];
    _hasRating = row->has_rating;
    _hasPendingRating = row->has_pending_rating;
    _pendingRatingDate = row->pending_rating_date;
    _rating = row->rating;
    _pendingRating = row->pending_rating;
    _commonChats = row->common_chats;
    return self;
}
- (void)dealloc {
    [_about release];
    [_note release];
    [_publicPhoto release];
    [_person release];
    [_channel release];
    [_music release];
    [_introTitle release];
    [_introText release];
    [_introSticker release];
    [super dealloc];
}
@end

/* the words that stand for a message that is not text, as the chat list says them */
NSString *NoshiPreviewWord(noshi_preview_kind kind) {
    switch (kind) {
    case NOSHI_PREVIEW_PHOTO: return NSLocalizedString(@"preview.photo", nil);
    case NOSHI_PREVIEW_VIDEO: return NSLocalizedString(@"preview.video", nil);
    case NOSHI_PREVIEW_VIDEO_MESSAGE: return NSLocalizedString(@"preview.videomessage", nil);
    case NOSHI_PREVIEW_VOICE: return NSLocalizedString(@"preview.voice", nil);
    case NOSHI_PREVIEW_AUDIO: return NSLocalizedString(@"preview.audio", nil);
    case NOSHI_PREVIEW_STICKER: return NSLocalizedString(@"preview.sticker", nil);
    case NOSHI_PREVIEW_GIF: return NSLocalizedString(@"preview.gif", nil);
    case NOSHI_PREVIEW_FILE: return NSLocalizedString(@"preview.file", nil);
    case NOSHI_PREVIEW_LOCATION: return NSLocalizedString(@"preview.location", nil);
    case NOSHI_PREVIEW_CONTACT: return NSLocalizedString(@"preview.contact", nil);
    case NOSHI_PREVIEW_POLL: return NSLocalizedString(@"preview.poll", nil);
    default: return @"";
    }
}

@implementation NoshiSession (Profile)

- (void)loadFullUserOfDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiFullUser *, NSString *))completion {
    void (^done)(NoshiFullUser *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_full_user_peer_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        noshi_full_user *full = calloc(1, sizeof(*full));
        noshi_status status = full ? noshi_full_user_parse(result->value, full) : NOSHI_E_NOMEM;
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: users.getFullUser answer rejected: %s", noshi_status_name(status));
            free(full);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        NoshiDialog *channelDialog = nil;
        if (full->has_channel) {
            noshi_dialog_row row = full->channel;
            channelDialog = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
        }
        NSInteger subscribers = full->channel_participants;
        int32_t messageId = full->channel_message;
        void (^finish)(NSString *, int32_t) = ^(NSString *text, int32_t date) {
            NoshiPersonalChannel *channel = channelDialog ? [[[NoshiPersonalChannel alloc] initWithDialog:channelDialog subscribers:subscribers
                                                                                                    lastText:text lastDate:date] autorelease] : nil;
            NoshiFullUser *user = [[[NoshiFullUser alloc] initWithRow:full channel:channel] autorelease];
            free(full);
            [self deliverMain:^{ done(user, nil); [done release]; }];
        };
        if (!channelDialog || messageId <= 0) {
            finish(nil, 0);
            return;
        }
        noshi_peer_ref channelPeer = NoshiPeerRefOfDialog(channelDialog);
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_channel_message_request(arena, &channelPeer, messageId, request);
        } handler:^(const noshi_mt_rpc_result *messageResult) {
            NSString *text = nil;
            int32_t date = 0;
            if (messageResult->status == NOSHI_OK) {
                noshi_message_row *rows = calloc(2, sizeof(*rows));
                size_t count = 0;
                if (rows && noshi_messages_parse(messageResult->value, rows, 2, &count) == NOSHI_OK && count > 0) {
                    text = rows[0].text[0] ? NoshiProfileUtf8(rows[0].text) : NoshiPreviewWord(rows[0].media.kind);
                    date = rows[0].date;
                }
                free(rows);
            } else {
                /* the profile is still worth showing without the line of text */
                NSLog(@"noshigram: personal channel message not loaded: %@", NoshiRpcErrorName(messageResult));
            }
            finish(text, date);
        }];
    }];
}

/* the Premium state of the signed in person is the same for every chat, so it is asked once */
static NSNumber *NoshiSelfPremium;

- (void)loadPremiumGateOfDialog:(NoshiDialog *)dialog completion:(void (^)(BOOL blocked))completion {
    void (^done)(BOOL) = [completion copy];
    if (dialog.kind != NOSHI_DIALOG_USER || dialog.saved) { done(NO); [done release]; return; }
    [self loadFullUserOfDialog:dialog completion:^(NoshiFullUser *user, NSString *errorName) {
        if (errorName || !user.requiresPremium) {
            if (errorName) NSLog(@"noshigram: premium gate not known, full profile failed: %@", errorName);
            done(NO);
            [done release];
            return;
        }
        if (NoshiSelfPremium) { done(!NoshiSelfPremium.boolValue); [done release]; return; }
        [self loadSelf:^(NSArray *items, NSString *selfError) {
            NoshiPerson *me = items.count ? [items objectAtIndex:0] : nil;
            if (!me) {
                NSLog(@"noshigram: premium gate not known, own profile failed: %@", selfError);
                done(NO);
            } else {
                [NoshiSelfPremium release];
                NoshiSelfPremium = [[NSNumber numberWithBool:me.premium] retain];
                done(!me.premium);
            }
            [done release];
        }];
    }];
}

- (void)loadSavedMusicOfDialog:(NoshiDialog *)dialog offset:(NSInteger)offset completion:(void (^)(NSArray *, NSInteger, NSString *))completion {
    void (^done)(NSArray *, NSInteger, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_saved_music_request(arena, &peer, (int32_t)offset, NOSHI_MUSIC_PAGE, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, 0, delivered); [done release]; }];
            return;
        }
        noshi_media_info *rows = calloc(NOSHI_MUSIC_PAGE, sizeof(*rows));
        size_t count = 0;
        int32_t total = 0;
        noshi_status status = rows ? noshi_saved_music_parse(result->value, rows, NOSHI_MUSIC_PAGE, &count, &total) : NOSHI_E_NOMEM;
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: users.getSavedMusic answer rejected: %s", noshi_status_name(status));
            free(rows);
            [self deliverMain:^{ done(nil, 0, @"INTERNAL"); [done release]; }];
            return;
        }
        NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [tracks addObject:[NoshiMedia mediaWithInfo:&rows[i]]];
        free(rows);
        [self deliverMain:^{ done(tracks, total, nil); [done release]; }];
    }];
}

- (void)loadAvatarsOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    BOOL user = peer.kind == 1 || peer.self;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return user ? noshi_user_photos_request(arena, &peer, NOSHI_AVATARS_MAX, request)
                    : noshi_chat_photos_request(arena, &peer, NOSHI_AVATARS_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, delivered); [done release]; }];
            return;
        }
        noshi_media_info *rows = calloc(NOSHI_AVATARS_MAX, sizeof(*rows));
        size_t count = 0;
        int32_t total = 0;
        noshi_status status = NOSHI_E_NOMEM;
        if (rows) status = user ? noshi_user_avatars_parse(result->value, rows, NOSHI_AVATARS_MAX, &count, &total)
                                : noshi_chat_avatars_parse(result->value, rows, NOSHI_AVATARS_MAX, &count);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: profile photos answer rejected: %s", noshi_status_name(status));
            free(rows);
            [self deliverMain:^{ done(nil, @"INTERNAL"); [done release]; }];
            return;
        }
        NSMutableArray *photos = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [photos addObject:[NoshiMedia mediaWithInfo:&rows[i]]];
        free(rows);
        [self deliverMain:^{ done(photos, nil); [done release]; }];
    }];
}

- (void)deleteProfilePhoto:(NoshiMedia *)photo completion:(void (^)(NSString *))completion {
    noshi_media_ref ref = photo.ref;
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_profile_photo_delete_request(arena, &ref, request);
    } completion:[self announcingOwnProfile:completion]];
}

- (void)saveMusic:(NoshiMedia *)song unsave:(BOOL)unsave completion:(void (^)(NSString *))completion {
    noshi_media_ref ref = song.ref;
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_save_music_request(arena, &ref, unsave ? 1 : 0, request);
    } completion:completion];
}

- (void)runBoolRequest:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)setBirthdayDay:(int32_t)day month:(int32_t)month year:(int32_t)year completion:(void (^)(NSString *))completion {
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_birthday_request(arena, day, month, year, request);
    } completion:completion];
}

- (void)clearBirthday:(void (^)(NSString *))completion {
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_birthday_clear_request(arena, request);
    } completion:completion];
}

- (void)loadCommonChatsOfDialog:(NoshiDialog *)dialog beforeId:(long long)beforeId
                     completion:(void (^)(NSArray *, long long, BOOL, NSString *))completion {
    void (^done)(NSArray *, long long, BOOL, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_common_chats_request(arena, &peer, beforeId, NOSHI_COMMON_CHATS_PAGE, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *chats = nil;
        long long last = 0;
        BOOL finished = NO;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_COMMON_CHATS_PAGE, sizeof(*rows));
            size_t count = 0, raw = 0;
            int64_t lastId = 0;
            noshi_status status = rows ? noshi_common_chats_parse(result->value, rows, NOSHI_COMMON_CHATS_PAGE, &count, &lastId, &raw) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                chats = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [chats addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
                last = lastId;
                finished = raw < NOSHI_COMMON_CHATS_PAGE;
            } else {
                NSLog(@"noshigram: messages.getCommonChats answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(chats, last, finished, deliveredError); [done release]; }];
    }];
}

- (void)loadChannelsForProfile:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_admined_channels_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *channels = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_admined_channels_parse(result->value, rows, NOSHI_DIALOGS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                channels = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [channels addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: channels.getAdminedPublicChannels answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:channels error:error completion:done];
        [done release];
    }];
}

- (void)setPersonalChannel:(NoshiDialog *)channel completion:(void (^)(NSString *))completion {
    BOOL has = channel != nil;
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    if (has) peer = NoshiPeerRefOfDialog(channel);
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_personal_channel_request(arena, has ? &peer : NULL, request);
    } completion:completion];
}


- (void)loadAbout:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_full_user_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *about = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_full_user full;
            noshi_status status = noshi_full_user_parse(result->value, &full);
            if (status == NOSHI_OK) {
                about = [NSString stringWithUTF8String:full.about];
                if (!about) about = @"";
            } else {
                NSLog(@"noshigram: users.getFullUser answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredAbout = [[about copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredAbout, deliveredError); [done release]; }];
    }];
}

/* the answer of a profile change is the user as the server now has them */
- (void)finishPersonResult:(const noshi_mt_rpc_result *)result completion:(void (^)(NoshiPerson *, NSString *))done {
    NoshiPerson *person = nil;
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_person_row row;
        noshi_status status = noshi_person_parse(result->value, &row);
        if (status == NOSHI_OK) {
            person = [[[NoshiPerson alloc] initWithRow:&row] autorelease];
        } else {
            NSLog(@"noshigram: profile change answer rejected: %s", noshi_status_name(status));
            error = @"INTERNAL";
        }
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(person, deliveredError); [done release]; }];
}

- (void)updateFirstName:(NSString *)firstName lastName:(NSString *)lastName about:(NSString *)about
             completion:(void (^)(NoshiPerson *, NSString *))completion {
    void (^done)(NoshiPerson *, NSString *) = [completion copy];
    NSString *first = [firstName copy], *last = [lastName copy], *bio = [about copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_profile_update_request(arena, first.UTF8String, last.UTF8String, bio.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishPersonResult:result completion:done];
    }];
    [first release];
    [last release];
    [bio release];
}

- (void)updateUsername:(NSString *)username completion:(void (^)(NoshiPerson *, NSString *))completion {
    void (^done)(NoshiPerson *, NSString *) = [completion copy];
    NSString *name = [username copy];
    if (noshi_username_check(name.UTF8String) != NOSHI_OK) {
        [name release];
        [self deliverMain:^{ done(nil, @"USERNAME_INVALID"); [done release]; }];
        return;
    }
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_username_request(arena, name.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishPersonResult:result completion:done];
    }];
    [name release];
}

@end

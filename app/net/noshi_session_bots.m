#import "noshi_session_bots.h"
#import "noshi_session_internal.h"

#import "noshi_rpc.h"
#import "noshi_remote_file.h"
#include "noshi_gifts.h"
#include "noshi_profile.h"

#define WEB_FILE_LIMIT (256 * 1024)

static noshi_peer_ref NoshiPeerRefOfPerson(NoshiPerson *person) {
    noshi_peer_ref ref;
    memset(&ref, 0, sizeof(ref));
    ref.kind = 1;
    ref.id = person.userId;
    ref.access_hash = person.accessHash;
    return ref;
}

/* the name a failed parse is reported under, so a screen shows one text for "the server sent something odd" */
static NSString *NoshiParseFailure(const char *method, noshi_status status) {
    NSLog(@"noshigram: %s answer rejected: %s", method, noshi_status_name(status));
    return @"INTERNAL";
}

@implementation NoshiSession (Bots)

#pragma mark names and info

- (void)resolveUsername:(NSString *)name completion:(NoshiResolveCompletion)completion {
    NoshiResolveCompletion done = [completion copy];
    NSString *username = [name copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_resolve_request(arena, username.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiDialog *dialog = nil;
        NoshiPerson *person = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
            if ([error isEqualToString:@"USERNAME_NOT_OCCUPIED"] || [error isEqualToString:@"USERNAME_INVALID"]) error = @"USERNAME_NOT_FOUND";
        } else {
            noshi_resolved resolved;
            noshi_status status = noshi_resolve_parse(result->value, [self workerAccount], &resolved);
            if (status == NOSHI_OK) {
                dialog = [[[NoshiDialog alloc] initWithRow:&resolved.dialog] autorelease];
                if (resolved.is_user) person = [[[NoshiPerson alloc] initWithRow:&resolved.person] autorelease];
            } else {
                error = status == NOSHI_E_NOTFOUND ? @"USERNAME_NOT_FOUND" : NoshiParseFailure("contacts.resolveUsername", status);
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(dialog, person, deliveredError); [done release]; }];
    }];
    [username release];
}

- (void)loadRecentInlineBots:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_top_inline_bots_request(arena, NOSHI_TOP_BOTS_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *bots = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_person_row rows[NOSHI_TOP_BOTS_MAX];
            size_t count = 0;
            noshi_status status = noshi_top_inline_bots_parse(result->value, rows, NOSHI_TOP_BOTS_MAX, &count);
            if (status == NOSHI_OK) {
                bots = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [bots addObject:[[[NoshiPerson alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                error = NoshiParseFailure("contacts.getTopPeers", status);
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSArray *deliveredBots = [[bots copy] autorelease];
        [self deliverMain:^{ done(deliveredBots, deliveredError); [done release]; }];
    }];
}

- (void)loadStoredPersonOfUserId:(long long)userId completion:(void (^)(NoshiPerson *))completion {
    void (^done)(NoshiPerson *) = [completion copy];
    [self post:^{
        NoshiPerson *held = userId > 0 ? [self storedPersonWithKey:(int64_t)userId] : nil;
        [self deliverMain:^{ done(held); [done release]; }];
    }];
}

- (void)checkInviteHash:(NSString *)hash completion:(NoshiInviteCheckCompletion)completion {
    NoshiInviteCheckCompletion done = [completion copy];
    NSString *value = [hash copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_check_request(arena, value.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiDialog *member = nil;
        NSString *title = nil, *about = nil, *error = nil;
        noshi_invite invite;
        memset(&invite, 0, sizeof(invite));
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = noshi_invite_parse(result->value, [self workerAccount], &invite);
            if (status != NOSHI_OK) {
                error = NoshiParseFailure("messages.checkChatInvite", status);
            } else {
                title = [NSString stringWithUTF8String:invite.title];
                about = [NSString stringWithUTF8String:invite.about];
                if (invite.member) member = [[[NoshiDialog alloc] initWithRow:&invite.dialog] autorelease];
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSInteger count = invite.participants;
        BOOL broadcast = invite.broadcast, request = invite.request_needed;
        long long subscription = invite.subscription_stars;
        NoshiRemoteFile *photo = [NoshiRemoteFile fileForMedia:&invite.photo];
        [self deliverMain:^{ done(member, title, about, photo, count, broadcast, request, subscription, deliveredError); [done release]; }];
    }];
    [value release];
}

- (void)joinInviteHash:(NSString *)hash completion:(void (^)(NoshiDialog *, NSString *))completion {
    void (^done)(NoshiDialog *, NSString *) = [completion copy];
    NSString *value = [hash copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_invite_import_request(arena, value.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiDialog *dialog = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row row;
            noshi_status status = noshi_invite_joined_parse(result->value, [self workerAccount], &row);
            if (status == NOSHI_OK) dialog = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
            else error = status == NOSHI_E_UNSUPPORTED ? @"JOIN_WEBVIEW" : NoshiParseFailure("messages.importChatInvite", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(dialog, deliveredError); [done release]; }];
    }];
    [value release];
}

- (void)addContactPhone:(NSString *)phone firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(BOOL, NSString *))completion {
    void (^done)(BOOL, NSString *) = [completion copy];
    NSString *number = [phone copy], *given = [first copy], *family = [last copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_contact_import_request(arena, number.UTF8String, given.UTF8String, family.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        BOOL found = NO;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            size_t imported = 0;
            if (noshi_contact_import_parse(result->value, &imported) == NOSHI_OK) found = imported > 0;
            else error = @"INTERNAL";
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(found, delivered); [done release]; }];
    }];
    [number release];
    [given release];
    [family release];
}

- (void)editContact:(NoshiPerson *)person firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref user = NoshiPeerRefOfPerson(person);
    NSString *given = [first copy], *family = [last copy], *phone = [person.phone copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_contact_edit_request(arena, &user, given.UTF8String, family.length ? family.UTF8String : "", phone.length ? phone.UTF8String : "", request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
    [given release];
    [family release];
    [phone release];
}

- (void)setContactNote:(NSString *)note ofPerson:(NoshiPerson *)person completion:(void (^)(NSString *))completion {
    noshi_peer_ref user = NoshiPeerRefOfPerson(person);
    NSString *text = [note copy];
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_contact_note_request(arena, &user, text.UTF8String, request);
    } completion:completion];
    [text release];
}

- (void)resetContactPhotoOfPerson:(NoshiPerson *)person completion:(void (^)(NSString *))completion {
    noshi_peer_ref user = NoshiPeerRefOfPerson(person);
    [self runBoolRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_contact_photo_reset_request(arena, &user, request);
    } completion:completion];
}

- (void)loadBotInfoOfPerson:(NoshiPerson *)bot completion:(void (^)(NoshiBotInfo *, NSString *))completion {
    void (^done)(NoshiBotInfo *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfPerson(bot);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_full_user_peer_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiBotInfo *info = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_bot_info *row = calloc(1, sizeof(*row));
            noshi_status status = row ? noshi_bot_info_parse(result->value, row) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) info = [NoshiBotInfo infoWithRow:row];
            else error = NoshiParseFailure("users.getFullUser", status);
            free(row);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(info, deliveredError); [done release]; }];
    }];
}

- (void)startBot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog param:(NSString *)param randomId:(long long)randomId
      completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref botRef = NoshiPeerRefOfPerson(bot), peer = NoshiPeerRefOfDialog(dialog);
    NSString *text = [param copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_start_bot_request(arena, &botRef, &peer, randomId, text.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [text release];
}

#pragma mark buttons

- (void)pressButton:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog password:(NSString *)password
         completion:(NoshiCallbackCompletion)completion {
    NoshiCallbackCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    BOOL game = button.kind == NOSHI_BUTTON_GAME;
    NSData *data = [button.data retain];
    BOOL needsPassword = button.row.password;
    NSString *secret = [password copy];
    if (needsPassword && !secret.length) {
        [self deliverMain:^{ done(nil, @"PASSWORD_REQUIRED"); [done release]; }];
        [data release];
        [secret release];
        return;
    }
    void (^finish)(const noshi_mt_rpc_result *) = ^(const noshi_mt_rpc_result *result) {
        NoshiCallbackAnswer *answer = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_callback_answer *row = calloc(1, sizeof(*row));
            noshi_status status = row ? noshi_callback_parse(result->value, row) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) answer = [NoshiCallbackAnswer answerWithRow:row];
            else error = NoshiParseFailure("messages.getBotCallbackAnswer", status);
            free(row);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(answer, deliveredError); [done release]; }];
    };
    void (^finishCopy)(const noshi_mt_rpc_result *) = [finish copy];
    if (!needsPassword) {
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_callback_request(arena, &peer, messageId, data.bytes, data.length, game, NULL, request);
        } handler:finishCopy];
    } else {
        /* the proof is computed from the server's challenge, so the password goes first and the press second */
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_password_request(arena, request);
        } handler:^(const noshi_mt_rpc_result *challenge) {
            if (challenge->status != NOSHI_OK) {
                finishCopy(challenge);
                return;
            }
            [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
                noshi_tl_value *check = NULL;
                noshi_status status = noshi_password_input(arena, challenge->value, secret.UTF8String, &check);
                if (status == NOSHI_OK) status = noshi_callback_request(arena, &peer, messageId, data.bytes, data.length, game, check, request);
                return status;
            } handler:finishCopy];
        }];
    }
    [finishCopy release];
    [data release];
    [secret release];
}

#pragma mark inline mode

- (void)loadVenueSearchBot:(void (^)(NoshiPerson *, NSString *))completion {
    void (^done)(NoshiPerson *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena,"help.getConfig");
        return *request ? NOSHI_OK : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        const uint8_t *bytes = NULL;
        size_t length = 0;
        NSString *name = nil;
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error && noshi_tl_get_bytes(result->value,"venue_search_username",&bytes,&length) == NOSHI_OK && length > 0 && length <= 64) {
            BOOL valid = YES;
            for (size_t i=0;i<length;++i) if (!((bytes[i]>='a' && bytes[i]<='z') || (bytes[i]>='A' && bytes[i]<='Z') ||
                (bytes[i]>='0' && bytes[i]<='9') || bytes[i]=='_')) valid = NO;
            if (valid) name = [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
        }
        [self deliverMain:^{
            if (!name) { done(nil,error ? error : @"VENUE_SEARCH_UNAVAILABLE"); [done release]; return; }
            [self resolveUsername:name completion:^(NoshiDialog *dialog,NoshiPerson *person,NSString *failure) {
                (void)dialog;
                done(person.bot ? person : nil,failure ? failure : (person.bot ? nil : @"VENUE_SEARCH_UNAVAILABLE"));
                [done release];
            }];
        }];
    }];
}

- (void)searchInline:(NSString *)query bot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog offset:(NSString *)offset
          completion:(void (^)(NoshiInlinePage *, NSString *))completion {
    noshi_geo_point point;
    memset(&point,0,sizeof(point));
    [self searchInline:query bot:bot inDialog:dialog offset:offset location:point completion:completion];
}

- (void)searchVenues:(NSString *)query latitude:(double)latitude longitude:(double)longitude bot:(NoshiPerson *)bot
           inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiInlinePage *, NSString *))completion {
    noshi_geo_point point;
    memset(&point,0,sizeof(point));
    point.valid=1; point.latitude=latitude; point.longitude=longitude;
    [self searchInline:query bot:bot inDialog:dialog offset:@"" location:point completion:completion];
}

- (void)searchInline:(NSString *)query bot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog offset:(NSString *)offset
           location:(noshi_geo_point)point completion:(void (^)(NoshiInlinePage *, NSString *))completion {
    void (^done)(NoshiInlinePage *, NSString *) = [completion copy];
    noshi_peer_ref botRef = NoshiPeerRefOfPerson(bot), peer = NoshiPeerRefOfDialog(dialog);
    NSString *text = [query copy], *start = [(offset ? offset : @"") copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_status status = noshi_inline_query_request(arena, &botRef, &peer, text.UTF8String, start.UTF8String, request);
        if (status == NOSHI_OK) status = noshi_inline_query_set_location(arena, *request, &point);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiInlinePage *page = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_inline_result *rows = calloc(NOSHI_INLINE_RESULTS_MAX, sizeof(*rows));
            noshi_inline_page row;
            size_t count = 0;
            noshi_status status = rows ? noshi_inline_results_parse(result->value, &row, rows, NOSHI_INLINE_RESULTS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [results addObject:[NoshiInlineResult resultWithRow:&rows[i]]];
                page = [NoshiInlinePage pageWithRow:&row results:results];
            } else {
                error = NoshiParseFailure("messages.getInlineBotResults", status);
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(page, deliveredError); [done release]; }];
    }];
    [text release];
    [start release];
}

- (void)sendInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              completion:(NoshiSendCompletion)completion {
    [self sendInlineResult:result queryId:queryId toDialog:dialog randomId:randomId replyTo:0 completion:completion];
}

- (void)sendInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *resultId = [result.resultId copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_status status = noshi_inline_send_request(arena, &peer, randomId, queryId, resultId.UTF8String, request);
        if (status == NOSHI_OK) status = noshi_set_reply(arena, *request, &peer, replyTo);
        return status;
    } handler:^(const noshi_mt_rpc_result *reply) {
        [self finishSend:reply randomId:randomId completion:done];
    }];
    [resultId release];
}

- (void)loadWebFile:(NoshiWebFile *)file completion:(void (^)(NSData *, NSString *))completion {
    void (^done)(NSData *, NSString *) = [completion copy];
    NSString *url = [file.url copy];
    long long hash = file.accessHash;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *location = noshi_tl_new_obj(arena, "inputWebFileLocation");
        *request = noshi_tl_new_obj(arena, "upload.getWebFile");
        if (!location || !*request) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_set_str(arena, location, "url", url.UTF8String);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, location, "access_hash", hash);
        if (status == NOSHI_OK) status = noshi_tl_set(*request, "location", location);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *request, "offset", 0);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, *request, "limit", WEB_FILE_LIMIT);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSData *data = nil;
        NSString *error = nil;
        const uint8_t *bytes = NULL;
        size_t len = 0;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len > 0 && len <= WEB_FILE_LIMIT) data = [NSData dataWithBytes:bytes length:len];
        else error = @"INTERNAL";
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(data, deliveredError); [done release]; }];
    }];
    [url release];
}

- (void)loadUser:(long long)userId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiPerson *, NSString *))completion {
    void (^done)(NoshiPerson *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_user_from_message_request(arena, &peer, messageId, userId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiPerson *person = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_person_row row;
            noshi_status status = noshi_user_from_message_parse(result->value, userId, &row);
            if (status == NOSHI_OK) person = [[[NoshiPerson alloc] initWithRow:&row] autorelease];
            else error = status == NOSHI_E_NOTFOUND ? @"USER_ID_INVALID" : NoshiParseFailure("users.getUsers", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(person, deliveredError); [done release]; }];
    }];
}

#pragma mark signing in on a site

- (void)finishUrlAuth:(const noshi_mt_rpc_result *)result method:(const char *)method completion:(void (^)(NoshiUrlAuth *, NSString *))done {
    NoshiUrlAuth *auth = nil;
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_url_auth *row = calloc(1, sizeof(*row));
        noshi_status status = row ? noshi_url_auth_parse(result->value, row) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) auth = [NoshiUrlAuth authWithRow:row];
        else error = NoshiParseFailure(method, status);
        free(row);
    }
    [self noteRpcError:error];
    NSString *deliveredError = [[error copy] autorelease];
    [self deliverMain:^{ done(auth, deliveredError); [done release]; }];
}

- (void)requestUrlAuthForButton:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
                     completion:(void (^)(NoshiUrlAuth *, NSString *))completion {
    void (^done)(NoshiUrlAuth *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t buttonId = button.row.button_id;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_url_auth_request(arena, &peer, messageId, buttonId, NULL, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.requestUrlAuth" completion:done];
    }];
}

- (void)requestUrlAuthForUrl:(NSString *)url completion:(void (^)(NoshiUrlAuth *, NSString *))completion {
    void (^done)(NoshiUrlAuth *, NSString *) = [completion copy];
    NSString *address = [url copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_url_auth_request(arena, NULL, 0, 0, address.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.requestUrlAuth" completion:done];
    }];
    [address release];
}

- (void)acceptUrlAuth:(NoshiUrlAuth *)auth button:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
         writeAllowed:(BOOL)writeAllowed code:(NSString *)code completion:(void (^)(NoshiUrlAuth *, NSString *))completion {
    void (^done)(NoshiUrlAuth *, NSString *) = [completion copy];
    BOOL forButton = button != nil && dialog != nil;
    noshi_peer_ref peer;
    memset(&peer, 0, sizeof(peer));
    if (forButton) peer = NoshiPeerRefOfDialog(dialog);
    int32_t buttonId = button.row.button_id;
    NSString *address = [(forButton ? @"" : auth.url) copy], *match = [code copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_url_auth_accept_request(arena, forButton ? &peer : NULL, messageId, buttonId, address.UTF8String, writeAllowed, 0,
                                               match.length ? match.UTF8String : NULL, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishUrlAuth:result method:"messages.acceptUrlAuth" completion:done];
    }];
    [address release];
    [match release];
}

#pragma mark invoices

- (void)loadStarsInvoice:(NoshiStarsInvoice *)invoice completion:(void (^)(NoshiStarsInvoice *, NSString *))completion {
    void (^done)(NoshiStarsInvoice *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *input = NULL;
        noshi_status status = invoice->slug ? noshi_invoice_slug_input(arena, invoice->slug.UTF8String, &input)
                                              : noshi_invoice_message_input(arena, &invoice->peer, invoice->messageId, &input);
        if (status == NOSHI_OK) status = noshi_payment_form_request(arena, input, request);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        noshi_stars_form form;
        memset(&form, 0, sizeof(form));
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = noshi_stars_form_parse(result->value, &form);
            if (status == NOSHI_E_UNSUPPORTED) error = @"STARS_UNSUPPORTED";
            else if (status != NOSHI_OK) error = NoshiParseFailure("payments.getPaymentForm", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSString *title = [NSString stringWithUTF8String:form.title], *text = [NSString stringWithUTF8String:form.description];
        [self deliverMain:^{
            if (!deliveredError) {
                invoice->formId = form.form_id;
                invoice->botId = form.bot_id;
                invoice->stars = form.stars;
                [invoice->title release];
                invoice->title = [(title ? title : @"") copy];
                [invoice->invoiceDescription release];
                invoice->invoiceDescription = [(text ? text : @"") copy];
            }
            done(deliveredError ? nil : invoice, deliveredError);
            [done release];
        }];
    }];
}

- (void)loadStarsInvoiceOfMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiStarsInvoice *, NSString *))completion {
    NoshiStarsInvoice *invoice = [[[NoshiStarsInvoice alloc] init] autorelease];
    invoice->peer = NoshiPeerRefOfDialog(dialog);
    invoice->messageId = messageId;
    [self loadStarsInvoice:invoice completion:completion];
}

- (void)loadStarsInvoiceOfSlug:(NSString *)slug completion:(void (^)(NoshiStarsInvoice *, NSString *))completion {
    NoshiStarsInvoice *invoice = [[[NoshiStarsInvoice alloc] init] autorelease];
    invoice->slug = [slug copy];
    [self loadStarsInvoice:invoice completion:completion];
}

- (void)payStarsInvoice:(NoshiStarsInvoice *)invoice completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NoshiStarsInvoice *held = [invoice retain];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *input = NULL;
        noshi_status status = held->slug ? noshi_invoice_slug_input(arena, held->slug.UTF8String, &input)
                                           : noshi_invoice_message_input(arena, &held->peer, held->messageId, &input);
        if (status == NOSHI_OK) status = noshi_payment_send_request(arena, held->formId, input, request);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = noshi_payment_result_check(result->value);
            if (status == NOSHI_E_UNSUPPORTED) error = @"STARS_UNSUPPORTED";
            else if (status != NOSHI_OK) error = NoshiParseFailure("payments.sendStarsForm", status);
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
    [held release];
}

#pragma mark answers to a keyboard

- (void)sendContactPhone:(NSString *)phone name:(NSString *)name toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *number = [phone copy], *first = [name copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_send_contact_request(arena, &peer, number.UTF8String, first.UTF8String, "", randomId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
    [number release];
    [first release];
}

- (void)sendRequestedDialogs:(NSArray *)dialogs buttonId:(int32_t)buttonId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
                  completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref chat = NoshiPeerRefOfDialog(dialog);
    NSUInteger count = MIN(dialogs.count, (NSUInteger)10);
    NSMutableData *packed = [NSMutableData dataWithLength:(count ? count : 1) * sizeof(noshi_peer_ref)];
    noshi_peer_ref *peers = packed.mutableBytes;
    for (NSUInteger i = 0; i < count; ++i) peers[i] = NoshiPeerRefOfDialog([dialogs objectAtIndex:i]);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_requested_peers_request(arena, &chat, messageId, buttonId, packed.bytes, count, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

@end

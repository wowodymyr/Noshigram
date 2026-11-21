#import "noshi_session_internal.h"

#include "noshi_message_actions.h"

#import "noshi_rpc.h"
#import "noshi_session_actions.h"

#include "noshi_poll.h"
#include "noshi_reactions.h"
#include <string.h>

/* the ids of an array of numbers, in a buffer the worker block owns */
static NSData *NoshiPackIds(NSArray *ids) {
    NSMutableData *data = [NSMutableData dataWithLength:(ids.count ? ids.count : 1) * sizeof(int32_t)];
    int32_t *values = data.mutableBytes;
    NSUInteger count = 0;
    for (NSNumber *number in ids) {
        if (count >= NOSHI_MESSAGES_MAX) break;
        values[count++] = number.intValue;
    }
    return data;
}

static int32_t NoshiCachedSharingPeriod(NoshiSession *session) {
    NSString *key = [NSString stringWithFormat:@"noshigram.sharing.period.%lld", (long long)[session workerAccount]];
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([stored isKindOfClass:[NSNumber class]] && [stored longLongValue] >= 0 && [stored longLongValue] <= INT32_MAX) return [stored intValue];
    return NOSHI_SHARING_PERIOD_DEFAULT;
}

@implementation NoshiSession (Actions)

- (void)loadReactorsOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog offset:(NSString *)offset
                    completion:(void (^)(NSArray *, NSDictionary *, NSString *, NSString *))completion {
    void (^done)(NSArray *, NSDictionary *, NSString *, NSString *) = [completion copy];
    NSString *cursor = [offset copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_reaction_people_request(arena, &peer, messageId, cursor.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NSMutableArray *items = nil;
        NSDictionary *people = nil;
        NSString *next = nil;
        if (!error) {
            noshi_reaction_person rows[NOSHI_REACTION_PEOPLE_PAGE];
            size_t count = 0;
            char nextOffset[NOSHI_REACTION_OFFSET_MAX];
            noshi_status status = noshi_reaction_people_parse(result->value, rows, NOSHI_REACTION_PEOPLE_PAGE, &count, nextOffset, sizeof(nextOffset));
            if (status == NOSHI_OK && nextOffset[0] && (!count || (cursor && !strcmp(cursor.UTF8String, nextOffset)))) status = NOSHI_E_MALFORMED;
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: reaction participants rejected: %s", noshi_status_name(status));
                error = @"MALFORMED";
            } else {
                items = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    long long key = rows[i].peer_kind == 1 ? rows[i].peer_id : -rows[i].peer_id;
                    [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:key], @"peer", [NSNumber numberWithInt:rows[i].date], @"date",
                                      [NoshiReaction reactionWithRow:&rows[i].reaction], @"reaction", nil]];
                }
                people = NoshiPeopleOfAnswer(self, result->value);
                if (nextOffset[0]) next = [NSString stringWithUTF8String:nextOffset];
            }
        }
        [self noteRpcError:error];
        NSArray *delivered = [[items copy] autorelease];
        NSDictionary *names = [[people copy] autorelease];
        NSString *following = [[next copy] autorelease];
        NSString *problem = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered, names, following, problem); [done release]; }];
    }];
    [cursor release];
}

- (void)loadSharingPeriod:(void (^)(int32_t, int64_t, NSString *))completion {
    void (^done)(int32_t, int64_t, NSString *) = [completion copy];
    [self post:^{
        int32_t cached = NoshiCachedSharingPeriod(self);
        int64_t offset = [self workerServerTimeOffsetMilliseconds];
        [self deliverMain:^{ done(cached, offset, nil); }];
    }];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "help.getAppConfig");
        return *request ? noshi_tl_set_i32(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        int32_t period = NoshiCachedSharingPeriod(self);
        NSString *key = [NSString stringWithFormat:@"noshigram.sharing.period.%lld", (long long)[self workerAccount]];
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error) {
            int32_t parsed = 0;
            noshi_status status = noshi_sharing_period_parse(result->value, &parsed);
            if (status == NOSHI_OK || status == NOSHI_E_NOTFOUND) {
                period = status == NOSHI_OK ? parsed : NOSHI_SHARING_PERIOD_DEFAULT;
                [[NSUserDefaults standardUserDefaults] setInteger:period forKey:key];
            } else error = @"CONFIG_INVALID";
        }
        int64_t offset = [self workerServerTimeOffsetMilliseconds];
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(period, offset, delivered); [done release]; }];
    }];
}

- (void)setSharingRestricted:(BOOL)restricted ofDialog:(NoshiDialog *)dialog requestId:(int32_t)requestId completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_sharing_request(arena, &peer, restricted ? 1 : 0, requestId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
}

- (void)finishAction:(const noshi_mt_rpc_result *)result completion:(void (^)(NSString *))done {
    NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
    [self noteRpcError:error];
    NSString *delivered = [[error copy] autorelease];
    [self deliverMain:^{ done(delivered); [done release]; }];
}

- (void)deleteMessageIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog revoke:(BOOL)revoke completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSData *packed = [NoshiPackIds(ids) retain];
    size_t count = MIN(ids.count, (NSUInteger)NOSHI_MESSAGES_MAX);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_delete_messages_request(arena, &peer, packed.bytes, count, revoke, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else if (noshi_delete_messages_parse(result->value) != NOSHI_OK) {
            error = @"MALFORMED";
        } else {
            /* the server keeps no message to send back as an update, so the kept copy is cleaned here */
            const int32_t *values = packed.bytes;
            noshi_peer channel = {3, peer.id};
            for (size_t i = 0; i < count; ++i) {
                noshi_status status = peer.kind == 3 ? noshi_store_delete([self workerStore], NOSHI_RECORD_MESSAGE, channel, values[i])
                                                       : noshi_store_delete_common_message([self workerStore], values[i]);
                if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) NSLog(@"noshigram: kept message %d not removed: %s", values[i], noshi_status_name(status));
            }
        }
        [packed release];
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)pinMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog unpin:(BOOL)unpin completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_pin_message_request(arena, &peer, messageId, unpin, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
}

- (void)editMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_edit_message_request(arena, &peer, messageId, body.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
    [body release];
}

- (void)editCaptionOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog text:(NSString *)text completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_edit_caption_request(arena, &peer, messageId, body.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishAction:result completion:done];
    }];
    [body release];
}

- (void)transcribeMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *, BOOL, NSString *))completion {
    void (^done)(NSString *, BOOL, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_transcribe_request(arena, &peer, messageId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil, *text = nil;
        BOOL pending = NO;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_transcript *transcript = calloc(1, sizeof(*transcript));
            if (transcript && noshi_transcribe_parse(result->value, transcript) == NOSHI_OK) {
                text = [NSString stringWithUTF8String:transcript->text];
                pending = transcript->pending;
            } else {
                NSLog(@"noshigram: the transcription answer was rejected");
                error = @"MALFORMED";
            }
            free(transcript);
        }
        [self noteRpcError:error];
        NSString *deliveredText = [[text copy] autorelease];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredText ? deliveredText : @"", pending, delivered); [done release]; }];
    }];
}

- (void)loadReadDateOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_read_date_request(arena, &peer, messageId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        int32_t date = 0;
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_read_date_parse(result->value, &date) != NOSHI_OK) error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(date, delivered); [done release]; }];
    }];
}

- (void)loadGroupReadDatesOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *, NSString *))completion {
    void (^done)(NSArray *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_group_read_dates_request(arena, &peer, messageId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        noshi_group_read_date rows[256];
        size_t count = 0;
        NSMutableArray *readers = [NSMutableArray array];
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_group_read_dates_parse(result->value, rows, 256, &count) != NOSHI_OK) error = @"MALFORMED";
        else for (size_t i = 0; i < count; ++i) {
            [readers addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:rows[i].user_id], @"user", [NSNumber numberWithInt:rows[i].date], @"date", nil]];
        }
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(error ? nil : readers, delivered); [done release]; }];
    }];
}

- (void)scheduleText:(NSString *)text atDate:(int32_t)date toDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    [self scheduleText:text entities:nil atDate:date toDialog:dialog replyTo:0 completion:completion];
}

- (void)scheduleText:(NSString *)text entities:(NSArray *)entities atDate:(int32_t)date toDialog:(NoshiDialog *)dialog replyTo:(int32_t)replyTo completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    NSMutableData *strings = nil;
    size_t count = 0;
    NSMutableData *packed = NoshiPackSendEntities(entities, &strings, &count);
    int64_t randomId;
    do {
        randomId = (int64_t)((((uint64_t)arc4random() << 32) | arc4random()) & 0x7fffffffffffffffULL);
    } while (randomId == 0);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        /* the block keeps the data objects, not only the pointers into them */
        noshi_status status = noshi_send_text_reply_request(arena, &peer, body.UTF8String, packed.bytes, count, randomId, replyTo, request);
        (void)strings;
        return status == NOSHI_OK ? noshi_set_schedule(arena, *request, date) : status;
    } handler:^(const noshi_mt_rpc_result *result) {
        [body release];
        [self finishAction:result completion:done];
    }];
}

- (void)exportLinkOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *, NSString *))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_message_link_request(arena, &peer, messageId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *link = nil, *error = nil;
        char buffer[256];
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else if (noshi_message_link_parse(result->value, buffer, sizeof(buffer)) == NOSHI_OK) {
            link = [NSString stringWithUTF8String:buffer];
        } else {
            error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *deliveredLink = [[link copy] autorelease], *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredLink, deliveredError); [done release]; }];
    }];
}

- (void)sendVoteOptions:(NSArray *)options forMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSMutableData *packed = [[NSMutableData alloc] initWithLength:(options.count ? options.count : 1) * sizeof(noshi_poll_choice)];
    noshi_poll_choice *choices = packed.mutableBytes;
    size_t count = 0;
    for (NSData *token in options) {
        if (count >= NOSHI_POLL_ANSWERS_MAX || !token.length || token.length > NOSHI_POLL_OPTION_MAX) continue;
        memcpy(choices[count].option, token.bytes, token.length);
        choices[count].option_len = token.length;
        ++count;
    }
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_poll_vote_request(arena, &peer, messageId, choices, count, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [packed release];
        [self finishAction:result completion:done];
    }];
}

- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion {
    [self loadMessagesWithIds:ids ofDialog:dialog withPeople:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        if (completion) completion(messages, errorName);
    }];
}

- (void)loadMessagesWithIds:(NSArray *)ids ofDialog:(NoshiDialog *)dialog withPeople:(NoshiHistoryCompletion)completion {
    NoshiHistoryCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    int32_t values[NOSHI_MESSAGES_MAX];
    size_t count = 0;
    for (NSNumber *identifier in ids) if (count < NOSHI_MESSAGES_MAX) values[count++] = identifier.intValue;
    NSData *packed = [[NSData alloc] initWithBytes:values length:count * sizeof(int32_t)];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_messages_by_id_request(arena, &peer, packed.bytes, packed.length / sizeof(int32_t), request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *messages = nil;
        NSDictionary *people = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_message_row *rows = calloc(NOSHI_MESSAGES_MAX, sizeof(*rows));
            size_t found = 0;
            if (rows && noshi_messages_parse(result->value, rows, NOSHI_MESSAGES_MAX, &found) == NOSHI_OK) {
                people = NoshiPeopleOfAnswer(self, result->value);
                messages = [NSMutableArray arrayWithCapacity:found];
                for (size_t i = 0; i < found; ++i) {
                    NoshiMessage *message = [NoshiMessage messageWithRow:&rows[i]];
                    if (message) [messages addObject:message];
                }
            } else {
                error = @"MALFORMED";
            }
            free(rows);
        }
        [packed release];
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        NSArray *deliveredMessages = [[messages copy] autorelease];
        NSDictionary *deliveredPeople = [[people copy] autorelease];
        [self deliverMain:^{
            if (done) done(deliveredMessages, deliveredPeople, deliveredError);
            [done release];
        }];
    }];
}

- (void)forwardMessageIds:(NSArray *)ids fromDialog:(NoshiDialog *)from toDialog:(NoshiDialog *)to hideAuthor:(BOOL)hideAuthor completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref source = NoshiPeerRefOfDialog(from);
    noshi_peer_ref target = NoshiPeerRefOfDialog(to);
    NSData *packed = [NoshiPackIds(ids) retain];
    size_t count = MIN(ids.count, (NSUInteger)NOSHI_MESSAGES_MAX);
    NSMutableData *randoms = [[NSMutableData alloc] initWithLength:(count ? count : 1) * sizeof(int64_t)];
    int64_t *random = randoms.mutableBytes;
    for (size_t i = 0; i < count; ++i) {
        do {
            random[i] = (int64_t)((((uint64_t)arc4random() << 32) | arc4random()) & 0x7fffffffffffffffULL);
        } while (random[i] == 0);
    }
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_forward_messages_request(arena, &source, &target, packed.bytes, randoms.bytes, count, hideAuthor ? 1 : 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [packed release];
        [randoms release];
        [self finishAction:result completion:done];
    }];
}

@end

#import "noshi_session_internal.h"

#import "noshi_chat_settings.h"
#import "noshi_rpc.h"
#import "noshi_story.h"

@implementation NoshiSession (Stories)

- (void)loadStoryPeers:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_all_request(arena, 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *peers = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_story_peer *rows = calloc(NOSHI_STORY_PEERS_MAX, sizeof(*rows));
            size_t count = 0;
            int more = 0;
            noshi_status status = rows ? noshi_story_peers_parse(result->value, [self workerAccount], rows, NOSHI_STORY_PEERS_MAX,
                                                                      &count, &more) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK || status == NOSHI_E_NOTFOUND) {
                peers = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [peers addObject:[NoshiStoryPeer peerWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: stories.getAllStories answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:peers error:error completion:done];
        [done release];
    }];
}

/* worker only: replaces the stories the server sent as bare headers with their content */
- (void)completeSkipped:(NSMutableArray *)rows peer:(noshi_peer_ref)peer then:(void (^)(NSString *error))then {
    NSMutableData *ids = [NSMutableData data];
    for (NSValue *value in rows) {
        noshi_story_row row;
        [value getValue:&row];
        if (row.skipped) {
            int32_t id = row.id;
            [ids appendBytes:&id length:sizeof(id)];
        }
    }
    size_t wanted = ids.length / sizeof(int32_t);
    if (!wanted) { then(nil); return; }
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_ids_request(arena, &peer, ids.bytes, wanted, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) { then(NoshiRpcErrorName(result)); return; }
        noshi_story_row *fresh = calloc(NOSHI_STORIES_MAX, sizeof(*fresh));
        size_t count = 0;
        noshi_status status = fresh ? noshi_stories_parse(result->value, fresh, NOSHI_STORIES_MAX, &count) : NOSHI_E_NOMEM;
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: stories.getStoriesByID answer rejected: %s", noshi_status_name(status));
            free(fresh);
            then(@"INTERNAL");
            return;
        }
        for (NSUInteger i = 0; i < rows.count; ++i) {
            noshi_story_row row;
            [[rows objectAtIndex:i] getValue:&row];
            if (!row.skipped) continue;
            BOOL replaced = NO;
            for (size_t j = 0; j < count; ++j) {
                if (fresh[j].id != row.id || fresh[j].skipped) continue;
                [rows replaceObjectAtIndex:i withObject:[NSValue valueWithBytes:&fresh[j] objCType:@encode(noshi_story_row)]];
                replaced = YES;
                break;
            }
            /* a story that stays a header has nothing to show, so it drops out */
            if (!replaced) {
                [rows removeObjectAtIndex:i];
                --i;
            }
        }
        free(fresh);
        then(nil);
    }];
}

- (void)loadStoriesOfDialog:(NoshiDialog *)dialog completion:(NoshiStoriesCompletion)completion {
    NoshiStoriesCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_peer_request(arena, &peer, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        void (^fail)(NSString *) = ^(NSString *error) {
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, nil, delivered); [done release]; }];
        };
        if (result->status != NOSHI_OK) { fail(NoshiRpcErrorName(result)); return; }
        noshi_story_row *rows = calloc(NOSHI_STORIES_MAX, sizeof(*rows));
        noshi_story_peer owner;
        size_t count = 0;
        noshi_status status = rows ? noshi_story_peer_parse(result->value, [self workerAccount], &owner, rows, NOSHI_STORIES_MAX,
                                                                &count) : NOSHI_E_NOMEM;
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: stories.getPeerStories answer rejected: %s", noshi_status_name(status));
            free(rows);
            fail(@"INTERNAL");
            return;
        }
        NSMutableArray *packed = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) [packed addObject:[NSValue valueWithBytes:&rows[i] objCType:@encode(noshi_story_row)]];
        free(rows);
        [self completeSkipped:packed peer:peer then:^(NSString *error) {
            if (error) { fail(error); return; }
            NSMutableArray *stories = [NSMutableArray arrayWithCapacity:packed.count];
            for (NSValue *value in packed) {
                noshi_story_row row;
                [value getValue:&row];
                [stories addObject:[NoshiStory storyWithRow:&row]];
            }
            NoshiStoryPeer *ring = [NoshiStoryPeer peerWithRow:&owner];
            [self deliverMain:^{ done(ring, stories, nil); [done release]; }];
        }];
    }];
}

- (void)loadViewersOfStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog offset:(NSString *)offset
                completion:(void (^)(NSArray *, NSDictionary *, NSString *, int32_t, int32_t, NSString *))completion {
    void (^done)(NSArray *, NSDictionary *, NSString *, int32_t, int32_t, NSString *) = [completion copy];
    NSString *cursor = [offset copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_viewers_request(arena, &peer, storyId, cursor.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NSMutableArray *items = nil;
        NSDictionary *people = nil;
        NSString *next = nil;
        int32_t total = 0, reactionTotal = 0;
        if (!error) {
            noshi_story_viewer rows[NOSHI_STORY_VIEWERS_PAGE];
            size_t count = 0;
            char nextOffset[NOSHI_STORY_VIEWERS_OFFSET_MAX];
            noshi_status status = noshi_story_viewers_parse(result->value, rows, NOSHI_STORY_VIEWERS_PAGE, &count, nextOffset, sizeof(nextOffset), &total, &reactionTotal);
            /* a page that names itself as the next one would be asked for forever */
            if (status == NOSHI_OK && nextOffset[0] && (!count || (cursor.length && !strcmp(cursor.UTF8String, nextOffset)))) nextOffset[0] = 0;
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: story viewers rejected: %s", noshi_status_name(status));
                error = @"MALFORMED";
            } else {
                items = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:rows[i].user_id], @"peer", [NSNumber numberWithInt:rows[i].date], @"date",
                                                  [NSNumber numberWithBool:rows[i].blocked != 0], @"blocked", nil];
                    if (rows[i].reacted) [entry setObject:[NoshiReaction reactionWithRow:&rows[i].reaction] forKey:@"reaction"];
                    [items addObject:entry];
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
        [self deliverMain:^{ done(delivered, names, following, total, reactionTotal, problem); [done release]; }];
    }];
    [cursor release];
}

- (void)markStoriesSeenOfDialog:(NoshiDialog *)dialog upTo:(int32_t)storyId {
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_read_request(arena, &peer, storyId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            NSLog(@"noshigram: stories.readStories failed: %@", error);
            [self noteRpcError:error];
        }
    }];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_views_request(arena, &peer, &storyId, 1, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) {
            NSString *error = NoshiRpcErrorName(result);
            NSLog(@"noshigram: stories.incrementStoryViews failed: %@", error);
            [self noteRpcError:error];
        }
    }];
}

- (void)reactToStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog reaction:(NoshiReaction *)reaction
          completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    BOOL has = reaction != nil;
    noshi_reaction row;
    memset(&row, 0, sizeof(row));
    if (has) row = reaction.row;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_react_request(arena, &peer, storyId, has ? &row : NULL, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

- (void)loadLinkOfStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *link, NSString *errorName))completion {
    void (^done)(NSString *, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_link_request(arena, &peer, storyId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *link = nil, *error = nil;
        char buffer[256];
        if (result->status != NOSHI_OK) error = NoshiRpcErrorName(result);
        else if (noshi_story_link_parse(result->value, buffer, sizeof(buffer)) == NOSHI_OK) link = [NSString stringWithUTF8String:buffer];
        else error = @"MALFORMED";
        [self noteRpcError:error];
        NSString *deliveredLink = [[link copy] autorelease], *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredLink, deliveredError); [done release]; }];
    }];
}

- (void)setStoriesOfDialog:(NoshiDialog *)dialog hidden:(BOOL)hidden completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_hide_peer_request(arena, &peer, hidden, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)replyToStory:(int32_t)storyId ofDialog:(NoshiDialog *)dialog text:(NSString *)text randomId:(long long)randomId
          completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *body = [text copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_reply_request(arena, &peer, storyId, body.UTF8String, randomId, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
    [body release];
}

- (void)forwardStory:(int32_t)storyId ofDialog:(NoshiDialog *)owner toDialog:(NoshiDialog *)target randomId:(long long)randomId
          completion:(NoshiSendCompletion)completion {
    NoshiSendCompletion done = [completion copy];
    noshi_peer_ref from = NoshiPeerRefOfDialog(owner);
    noshi_peer_ref to = NoshiPeerRefOfDialog(target);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_status status = noshi_story_forward_request(arena, &to, &from, storyId, randomId, request);
        return status == NOSHI_OK ? NoshiApplySendAs(self, &to, arena, *request) : status;
    } handler:^(const noshi_mt_rpc_result *result) {
        [self finishSend:result randomId:randomId completion:done];
    }];
}

/* worker only: the stories of a stories.stories answer, as a delivered list */
- (void)deliverStoriesResult:(const noshi_mt_rpc_result *)result completion:(NoshiListCompletion)done {
    NSMutableArray *stories = nil;
    NSString *error = nil;
    if (result->status != NOSHI_OK) {
        error = NoshiRpcErrorName(result);
    } else {
        noshi_story_row *rows = calloc(NOSHI_STORIES_MAX, sizeof(*rows));
        size_t count = 0;
        noshi_status status = rows ? noshi_stories_parse(result->value, rows, NOSHI_STORIES_MAX, &count) : NOSHI_E_NOMEM;
        if (status == NOSHI_OK) {
            stories = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) {
                /* a header without content has nothing to show in a grid */
                if (!rows[i].skipped) [stories addObject:[NoshiStory storyWithRow:&rows[i]]];
            }
        } else {
            NSLog(@"noshigram: stories page rejected: %s", noshi_status_name(status));
            error = @"INTERNAL";
        }
        free(rows);
    }
    [self finishLoad:stories error:error completion:done];
    [done release];
}

- (void)loadPinnedStories:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    noshi_peer_ref self_peer;
    memset(&self_peer, 0, sizeof(self_peer));
    self_peer.kind = 1;
    self_peer.self = 1;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_pinned_request(arena, &self_peer, 0, NOSHI_STORIES_MAX, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverStoriesResult:result completion:done];
    }];
}

- (void)loadStoryArchiveBefore:(int32_t)beforeId completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    noshi_peer_ref self_peer;
    memset(&self_peer, 0, sizeof(self_peer));
    self_peer.kind = 1;
    self_peer.self = 1;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_story_archive_request(arena, &self_peer, beforeId, 30, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        [self deliverStoriesResult:result completion:done];
    }];
}

#pragma mark management

/* one call on our own account, answered with the error name or nil */
- (void)runStoryCall:(noshi_status (^)(noshi_arena *arena, const noshi_peer_ref *self, noshi_tl_value **request))build completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_peer_ref mine;
        memset(&mine, 0, sizeof(mine));
        mine.kind = 1;
        mine.id = [self workerAccount];
        mine.self = 1;
        return build(arena, &mine, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        [self deliverMain:^{ done(error); [done release]; }];
    }];
}

- (void)editStory:(int32_t)storyId caption:(NSString *)caption privacy:(NSNumber *)privacy completion:(void (^)(NSString *errorName))completion {
    NSString *text = [caption copy];
    BOOL setPrivacy = privacy != nil;
    noshi_story_privacy audience = (noshi_story_privacy)privacy.intValue;
    [self runStoryCall:^noshi_status(noshi_arena *arena, const noshi_peer_ref *mine, noshi_tl_value **request) {
        return noshi_story_edit_request(arena, mine, storyId, text ? text.UTF8String : NULL, setPrivacy, audience, request);
    } completion:completion];
    [text release];
}

- (void)editStory:(int32_t)storyId caption:(NSString *)caption audience:(NoshiStoryAudience *)audience completion:(void (^)(NSString *errorName))completion {
    NSString *text = [caption copy];
    BOOL setAudience = audience != nil;
    noshi_story_audience *rules = calloc(1, sizeof(*rules));
    if (!rules) { [text release]; if (completion) completion(@"NO_MEMORY"); return; }
    if (audience) [audience fillAudience:rules];
    NSData *held = [NSData dataWithBytesNoCopy:rules length:sizeof(*rules) freeWhenDone:YES];
    [self runStoryCall:^noshi_status(noshi_arena *arena, const noshi_peer_ref *mine, noshi_tl_value **request) {
        return noshi_story_edit_audience_request(arena, mine, storyId, text ? text.UTF8String : NULL, setAudience, (const noshi_story_audience *)held.bytes, request);
    } completion:completion];
    [text release];
}

- (void)deleteStory:(int32_t)storyId completion:(void (^)(NSString *errorName))completion {
    [self runStoryCall:^noshi_status(noshi_arena *arena, const noshi_peer_ref *mine, noshi_tl_value **request) {
        int32_t one = storyId;
        return noshi_story_delete_request(arena, mine, &one, 1, request);
    } completion:completion];
}

- (void)setStory:(int32_t)storyId pinned:(BOOL)pinned completion:(void (^)(NSString *errorName))completion {
    [self runStoryCall:^noshi_status(noshi_arena *arena, const noshi_peer_ref *mine, noshi_tl_value **request) {
        int32_t one = storyId;
        return noshi_story_pin_request(arena, mine, &one, 1, pinned, request);
    } completion:completion];
}

@end

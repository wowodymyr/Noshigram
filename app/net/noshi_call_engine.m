#import "noshi_call_engine.h"

#import "noshi_person.h"
#import "noshi_call_video.h"
#import "noshi_tgc_runtime.h"
#import "noshi_rpc.h"
#import "noshi_session.h"
#import "noshi_session_internal.h"
#import "noshi_voip_bridge.h"
#import "noshi_weak_reference.h"

#include "noshi_random.h"
#include "noshi_mt_client.h"

/* a caller waits this long for the callee's phone to get the call, and then this long for it to be answered */
#define RECEIVE_TIMEOUT_SECONDS 20.0
#define RING_TIMEOUT_SECONDS 90.0
/* a request that rings older than this came out of a backlog, and the caller has long given up */
#define STALE_CALL_SECONDS 90

/* what the audio engine's threads hand back: the engine they belong to, and which call it was, so a late word of a
   finished call is dropped */
@interface NoshiCallMediaContext : NSObject {
@public
    NoshiWeakReference *engine;
    NSUInteger generation;
}
@end

@implementation NoshiCallMediaContext
- (void)dealloc {
    [engine release];
    [super dealloc];
}
@end

/* blocks cannot capture a C array, so a public value travels in a struct */
typedef struct { uint8_t bytes[NOSHI_CALL_KEY_LEN]; } NoshiCallValue;

@interface NoshiCallEngine () <NoshiTgcRuntimeDelegate> {
    NoshiSession *_session;
    BOOL _active;
    NSUInteger _generation;
    NoshiCallPhase _phase;
    BOOL _outgoing;
    long long _peerId;
    NSString *_peerName;
    NoshiPhoto *_peerPhoto;
    noshi_peer_ref _userRef;

    noshi_phone_call _call;
    BOOL _haveCall;
    noshi_phone_call _pending;
    BOOL _hasPending;
    BOOL _cancelWhenKnown;
    uint8_t _gaHash[32];

    noshi_call_dh _dh;
    BOOL _haveDh;
    uint8_t _secret[NOSHI_CALL_KEY_LEN];
    uint8_t _pub[NOSHI_CALL_KEY_LEN];
    uint8_t _callerPub[NOSHI_CALL_KEY_LEN];
    uint8_t _key[NOSHI_CALL_KEY_LEN];
    BOOL _haveKey;
    NSArray *_emoji;

    noshi_voip *_voip;
    NoshiTgcRuntime *_tgc;
    NSMutableArray *_earlySignals;
    BOOL _wantsVideo;
    /* the camera button pressed before the media link exists; the runtime applies it as it starts */
    BOOL _cameraWish;
    NoshiCallMediaContext *_mediaContext;
    NSTimeInterval _startedAt;
    BOOL _muted;
    int _bars;
    BOOL _discardSent;
    BOOL _cameraOn;
    BOOL _remoteVideo;
    BOOL _remoteMuted;
    NoshiCallVideo *_activeVideo;
}
@end

static void NoshiCallMediaState(void *context, int state);
static void NoshiCallMediaBars(void *context, int bars);

@implementation NoshiCallEngine

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = session;
    return self;
}

- (void)dealloc {
    [_peerName release];
    [_peerPhoto release];
    [_emoji release];
    [_earlySignals release];
    [_mediaContext release];
    [_activeVideo release];
    [super dealloc];
}

#pragma mark publishing

/* the screens get a fresh snapshot of the call at every change */
- (void)publishEnd:(NoshiCallEnd)end {
    NoshiCall *snapshot = [[[NoshiCall alloc] initWithCallId:_haveCall ? _call.id : 0 peerId:_peerId peerName:_peerName outgoing:_outgoing phase:_phase end:end
                                                            emoji:_emoji startedAt:_startedAt muted:_muted bars:_bars] autorelease];
    snapshot.photo = _peerPhoto;
    snapshot.video = _wantsVideo;
    snapshot.cameraOn = _cameraOn;
    snapshot.remoteVideo = _remoteVideo;
    snapshot.remoteMuted = _remoteMuted;
    NoshiSession *session = _session;
    [session deliverMain:^{ [session.callDelegate session:session callDidChange:snapshot]; }];
}

- (void)setPhase:(NoshiCallPhase)phase {
    _phase = phase;
    [self publishEnd:NoshiCallEndNone];
}

#pragma mark timers

/* a timer is a delay on the main queue that hops back to the worker, and it fires only for the call that set it */
- (void)afterSeconds:(NSTimeInterval)seconds do:(void (^)(void))block {
    NSUInteger generation = _generation;
    void (^action)(void) = [block copy];
    NoshiSession *session = _session;
    NoshiCallEngine *engine = [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [session post:^{
            if (generation == engine->_generation && engine->_active) action();
            [action release];
            [engine release];
        }];
    });
}

#pragma mark api

- (void)startCallToDialog:(NoshiDialog *)dialog {
    [self startCallToDialog:dialog video:NO];
}

- (void)startCallToDialog:(NoshiDialog *)dialog video:(BOOL)video {
    noshi_peer_ref ref = NoshiPeerRefOfDialog(dialog);
    long long peerId = dialog.peerId;
    NSString *name = [[dialog.title copy] autorelease];
    NoshiPhoto *photo = [[dialog.photo retain] autorelease];
    [_session post:^{ [self beginOutgoingTo:ref peerId:peerId name:name photo:photo video:video]; }];
}

- (void)acceptIncoming {
    [_session post:^{ [self answer]; }];
}

- (void)declineIncoming {
    [_session post:^{
        if (_active && _phase == NoshiCallPhaseIncoming) [self finishWithReason:NOSHI_CALL_REASON_HANGUP end:NoshiCallEndDeclined sendDiscard:YES];
    }];
}

- (void)hangUp {
    [_session post:^{
        if (!_active) return;
        BOOL talked = _startedAt > 0;
        NoshiCallEnd end = talked ? NoshiCallEndHangup : (_phase == NoshiCallPhaseIncoming ? NoshiCallEndDeclined : NoshiCallEndHangup);
        [self finishWithReason:NOSHI_CALL_REASON_HANGUP end:end sendDiscard:YES];
    }];
}

- (void)setMuted:(BOOL)muted {
    [_session post:^{
        _muted = muted;
        noshi_voip_set_muted(_voip, muted ? 1 : 0);
        [_tgc setMuted:muted];
        if (_active) [self publishEnd:NoshiCallEndNone];
    }];
}

- (void)shutdown {
    if (!_active) return;
    ++_generation;
    [self stopMediaThen:nil];
    _active = NO;
}

#pragma mark starting a call

- (void)resetForCallOutgoing:(BOOL)outgoing peerId:(long long)peerId name:(NSString *)name photo:(NoshiPhoto *)photo {
    ++_generation;
    _active = YES;
    _outgoing = outgoing;
    _peerId = peerId;
    [_peerName release];
    _peerName = [name copy];
    [_peerPhoto release];
    _peerPhoto = [photo retain];
    memset(&_call, 0, sizeof(_call));
    memset(&_pending, 0, sizeof(_pending));
    _haveCall = NO;
    _hasPending = NO;
    _cancelWhenKnown = NO;
    _haveKey = NO;
    memset(_key, 0, sizeof(_key));
    memset(_secret, 0, sizeof(_secret));
    [_emoji release];
    _emoji = nil;
    _startedAt = 0;
    _bars = 0;
    _discardSent = NO;
    _muted = NO;
    _wantsVideo = NO;
    _cameraWish = NO;
    _cameraOn = NO;
    _remoteVideo = NO;
    _remoteMuted = NO;
    [_earlySignals release];
    _earlySignals = nil;
}

/* the camera goes on or off for the runtime of this call; the answer says whether the device gave it, and the screens learn it from the next snapshot */
- (void)applyCamera:(BOOL)on {
    NSUInteger generation = _generation;
    NoshiTgcRuntime *runtime = _tgc;
    if (!runtime) return;
    [runtime setCameraOn:on completion:^(BOOL ok) {
        [_session post:^{
            if (generation != _generation || !_active || _tgc != runtime) return;
            _cameraOn = on && ok;
            [self publishEnd:NoshiCallEndNone];
        }];
    }];
}

- (void)setCameraOn:(BOOL)on {
    [_session post:^{
        if (!_active || _phase == NoshiCallPhaseEnded) return;
        if (_tgc) [self applyCamera:on];
        else _cameraWish = on;
    }];
}

- (NoshiCallVideo *)activeVideo {
    @synchronized (self) {
        return [[_activeVideo retain] autorelease];
    }
}

- (void)beginOutgoingTo:(noshi_peer_ref)ref peerId:(long long)peerId name:(NSString *)name photo:(NoshiPhoto *)photo video:(BOOL)video {
    if (_active) {
        /* one call at a time: a second one is reported and leaves the first alone */
        NoshiCall *busy = [[[NoshiCall alloc] initWithCallId:0 peerId:peerId peerName:name outgoing:YES phase:NoshiCallPhaseEnded end:NoshiCallEndFailed
                                                            emoji:nil startedAt:0 muted:NO bars:0] autorelease];
        NoshiSession *session = _session;
        [session deliverMain:^{ [session.callDelegate session:session callDidChange:busy]; }];
        return;
    }
    [self resetForCallOutgoing:YES peerId:peerId name:name photo:photo];
    _userRef = ref;
    _wantsVideo = video;
    [self setPhase:NoshiCallPhaseRequesting];
    NSUInteger generation = _generation;
    [self fetchDhThen:^(BOOL ok) {
        if (generation != _generation || !_active) return;
        if (!ok) {
            [self finishWithReason:NOSHI_CALL_REASON_NONE end:NoshiCallEndFailed sendDiscard:NO];
            return;
        }
        [self sendRequest];
    }];
}

/* the key parameters, fetched fresh each call; the server only resends them when the version the app holds is stale */
- (void)fetchDhThen:(void (^)(BOOL ok))then {
    void (^done)(BOOL) = [then copy];
    NSUInteger generation = _generation;
    int32_t version = _haveDh ? _dh.version : 0;
    [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_dh_request(arena, version, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        BOOL ok = NO;
        if (generation == _generation && _active) {
            uint8_t random[NOSHI_CALL_KEY_LEN];
            noshi_call_dh fresh;
            noshi_status status = result->status == NOSHI_OK ? noshi_call_dh_parse(result->value, _haveDh ? &_dh : NULL, &fresh, random) : result->status;
            if (status == NOSHI_OK) {
                _dh = fresh;
                _haveDh = YES;
                ok = noshi_call_make_secret(&_dh, random, _secret, _pub) == NOSHI_OK;
                if (!ok) NSLog(@"noshigram: the call key parameters were refused");
            } else {
                NSLog(@"noshigram: messages.getDhConfig for a call failed: %@", result->status == NOSHI_OK ? [NSString stringWithUTF8String:noshi_status_name(status)] : NoshiRpcErrorName(result));
            }
        }
        done(ok);
        [done release];
    }];
}

- (BOOL)directPathAllowed {
    return YES;
}

- (void)sendRequest {
    NoshiCallValue hash;
    int32_t randomId = 0;
    NSUInteger generation = _generation;
    BOOL video = _wantsVideo;
    noshi_peer_ref ref = _userRef;
    int p2p = [self directPathAllowed];
    noshi_random(&randomId, sizeof(randomId));
    memcpy(_callerPub, _pub, sizeof(_callerPub));
    noshi_call_commit(_pub, hash.bytes);
    [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_request_request(arena, &ref, randomId, hash.bytes, video ? 1 : 0, p2p, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (generation != _generation || !_active) return;
        noshi_phone_call call;
        if (result->status != NOSHI_OK || noshi_phone_call_from_answer(result->value, &call) != NOSHI_OK) {
            NSString *name = result->status == NOSHI_OK ? @"INTERNAL" : NoshiRpcErrorName(result);
            NoshiCallEnd end = [name isEqualToString:@"PARTICIPANT_VERSION_OUTDATED"] ? NoshiCallEndOutdated :
                                 ([name isEqualToString:@"USER_PRIVACY_RESTRICTED"] ? NoshiCallEndPrivacy : NoshiCallEndFailed);
            NSLog(@"noshigram: phone.requestCall failed: %@", name);
            [self finishWithReason:NOSHI_CALL_REASON_NONE end:end sendDiscard:NO];
            return;
        }
        _call = call;
        _haveCall = YES;
        if (_cancelWhenKnown) {
            [self finishWithReason:NOSHI_CALL_REASON_HANGUP end:NoshiCallEndHangup sendDiscard:YES];
            return;
        }
        [self setPhase:NoshiCallPhaseCalling];
        [self afterSeconds:RECEIVE_TIMEOUT_SECONDS do:^{
            if (_phase == NoshiCallPhaseCalling) [self finishWithReason:NOSHI_CALL_REASON_MISSED end:NoshiCallEndMissed sendDiscard:YES];
        }];
        if (_hasPending) {
            noshi_phone_call early = _pending;
            _hasPending = NO;
            [self handlePhoneCall:&early];
        }
    }];
}

#pragma mark updates

- (void)handlePhoneCall:(const noshi_phone_call *)update {
    if (!update) return;
    if (!_active) {
        if (update->kind == NOSHI_CALL_REQUESTED) [self beginIncoming:update];
        return;
    }
    if (!_haveCall) {
        /* our request has no answer yet, and the news of the call already came */
        if (_outgoing && _phase == NoshiCallPhaseRequesting) {
            _pending = *update;
            _hasPending = YES;
        }
        return;
    }
    if (update->id != _call.id) {
        if (update->kind == NOSHI_CALL_REQUESTED) [self turnAwayBusy:update];
        return;
    }
    switch (update->kind) {
    case NOSHI_CALL_WAITING:
        if (_outgoing && _phase == NoshiCallPhaseCalling && update->receive_date != 0) {
            [self setPhase:NoshiCallPhaseRinging];
            [self afterSeconds:RING_TIMEOUT_SECONDS do:^{
                if (_phase == NoshiCallPhaseRinging) [self finishWithReason:NOSHI_CALL_REASON_MISSED end:NoshiCallEndMissed sendDiscard:YES];
            }];
        }
        break;
    case NOSHI_CALL_ACCEPTED:
        if (_outgoing && !_haveKey) [self processAccepted:update];
        break;
    case NOSHI_CALL_ACTIVE:
        if (!_haveKey) [self processActive:update];
        break;
    case NOSHI_CALL_DISCARDED:
        [self processDiscarded:update];
        break;
    default:
        break;
    }
}

- (void)beginIncoming:(const noshi_phone_call *)call {
    NoshiPerson *person = [_session storedPersonWithKey:call->admin_id];
    if (call->date > 0 && (int32_t)[[NSDate date] timeIntervalSince1970] - call->date > STALE_CALL_SECONDS) return;
    /* the server names the library version both sides share; this app speaks tgcalls 7.0.0 and libtgvoip */
    if ((strcmp(call->version, NOSHI_CALL_LIBRARY_VERSION) != 0 && strcmp(call->version, NOSHI_CALL_TGCALLS_VERSION) != 0) || !call->has_hash) {
        NSLog(@"noshigram: a call with library %s is not ours to answer", call->version);
        [self discardForeign:call reason:NOSHI_CALL_REASON_BUSY];
        return;
    }
    [self resetForCallOutgoing:NO peerId:call->admin_id name:person.name photo:person.photo];
    _wantsVideo = call->video ? YES : NO;
    _call = *call;
    _haveCall = YES;
    memcpy(_gaHash, call->g_hash, sizeof(_gaHash));
    [self setPhase:NoshiCallPhaseIncoming];
    int64_t callId = call->id, accessHash = call->access_hash;
    [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_received_request(arena, callId, accessHash, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) NSLog(@"noshigram: phone.receivedCall failed: %@", NoshiRpcErrorName(result));
    }];
    [self afterSeconds:RING_TIMEOUT_SECONDS do:^{
        if (_phase == NoshiCallPhaseIncoming) [self finishWithReason:NOSHI_CALL_REASON_MISSED end:NoshiCallEndMissed sendDiscard:YES];
    }];
}

/* a second call while one runs is turned away with a busy signal, and the first goes on untouched */
- (void)turnAwayBusy:(const noshi_phone_call *)call {
    [self discardForeign:call reason:NOSHI_CALL_REASON_BUSY];
}

- (void)discardForeign:(const noshi_phone_call *)call reason:(noshi_call_reason)reason {
    int64_t callId = call->id, accessHash = call->access_hash;
    [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_discard_request(arena, callId, accessHash, 0, reason, 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (result->status != NOSHI_OK) NSLog(@"noshigram: phone.discardCall of another call failed: %@", NoshiRpcErrorName(result));
    }];
}

- (void)answer {
    if (!_active || _phase != NoshiCallPhaseIncoming) return;
    [self setPhase:NoshiCallPhaseExchanging];
    NSUInteger generation = _generation;
    [self fetchDhThen:^(BOOL ok) {
        if (generation != _generation || !_active) return;
        if (!ok) {
            [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
            return;
        }
        int64_t callId = _call.id, accessHash = _call.access_hash;
        int p2p = [self directPathAllowed];
        NoshiCallValue pub;
        memcpy(pub.bytes, _pub, sizeof(pub.bytes));
        [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_call_accept_request(arena, callId, accessHash, pub.bytes, p2p, request);
        } handler:^(const noshi_mt_rpc_result *result) {
            if (generation != _generation || !_active) return;
            noshi_phone_call call;
            if (result->status != NOSHI_OK || noshi_phone_call_from_answer(result->value, &call) != NOSHI_OK) {
                NSLog(@"noshigram: phone.acceptCall failed: %@", result->status == NOSHI_OK ? @"INTERNAL" : NoshiRpcErrorName(result));
                [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
                return;
            }
            /* the answer can already be the finished call or a discard, and is treated like the push of either */
            if (call.kind == NOSHI_CALL_DISCARDED || call.kind == NOSHI_CALL_ACTIVE) [self handlePhoneCall:&call];
        }];
    }];
}

/* the callee's value arrived: make the key, tell the callee, and start the audio from the endpoints the confirmation brings */
- (void)processAccepted:(const noshi_phone_call *)accepted {
    int64_t fingerprint = 0;
    if (!accepted->has_g || noshi_call_make_key(&_dh, accepted->g, _secret, _key, &fingerprint) != NOSHI_OK) {
        NSLog(@"noshigram: the callee's key value was refused");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    _haveKey = YES;
    [self showEmoji];
    [self setPhase:NoshiCallPhaseExchanging];
    NSUInteger generation = _generation;
    int64_t callId = _call.id, accessHash = _call.access_hash;
    int p2p = [self directPathAllowed];
    NoshiCallValue pub;
    memcpy(pub.bytes, _pub, sizeof(pub.bytes));
    [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_call_confirm_request(arena, callId, accessHash, pub.bytes, fingerprint, p2p, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        if (generation != _generation || !_active) return;
        noshi_phone_call call;
        if (result->status != NOSHI_OK || noshi_phone_call_from_answer(result->value, &call) != NOSHI_OK || call.kind != NOSHI_CALL_ACTIVE) {
            NSLog(@"noshigram: phone.confirmCall failed: %@", result->status == NOSHI_OK ? @"INTERNAL" : NoshiRpcErrorName(result));
            [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
            return;
        }
        _call = call;
        [self startMedia];
    }];
}

/* the callee side of the exchange: the caller's value must be the one it committed to before it saw ours */
- (void)processActive:(const noshi_phone_call *)active {
    uint8_t hash[32];
    int64_t fingerprint = 0;
    if (_outgoing) return;
    if (!active->has_g || noshi_call_commit(active->g, hash) != NOSHI_OK || memcmp(hash, _gaHash, sizeof(hash)) != 0) {
        NSLog(@"noshigram: the caller's key value does not match its commitment");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    if (noshi_call_make_key(&_dh, active->g, _secret, _key, &fingerprint) != NOSHI_OK || fingerprint != active->key_fingerprint) {
        NSLog(@"noshigram: the call key does not match the caller's fingerprint");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    memcpy(_callerPub, active->g, sizeof(_callerPub));
    _haveKey = YES;
    _call = *active;
    [self showEmoji];
    [self startMedia];
}

- (void)processDiscarded:(const noshi_phone_call *)discarded {
    NoshiCallEnd end = NoshiCallEndHangup;
    BOOL talked = _startedAt > 0;
    switch (discarded->reason) {
    case NOSHI_CALL_REASON_BUSY: end = NoshiCallEndBusy; break;
    case NOSHI_CALL_REASON_MISSED: end = _outgoing ? NoshiCallEndMissed : NoshiCallEndMissed; break;
    case NOSHI_CALL_REASON_DISCONNECT: end = NoshiCallEndFailed; break;
    default:
        /* a hangup before the audio ran is the callee turning the call down, or the caller giving up */
        if (!talked) end = _outgoing ? NoshiCallEndDeclined : NoshiCallEndMissed;
        break;
    }
    [self finishWithReason:NOSHI_CALL_REASON_NONE end:end sendDiscard:NO];
}

- (void)showEmoji {
    uint16_t indexes[NOSHI_CALL_EMOJI_SHOWN];
    if (noshi_call_emoji_indexes(_key, _callerPub, indexes) != NOSHI_OK) return;
    NSMutableArray *emoji = [NSMutableArray arrayWithCapacity:NOSHI_CALL_EMOJI_SHOWN];
    for (int i = 0; i < NOSHI_CALL_EMOJI_SHOWN; ++i) {
        NSString *text = [NSString stringWithUTF8String:noshi_call_emoji[indexes[i]]];
        if (text) [emoji addObject:text];
    }
    [_emoji release];
    _emoji = [emoji copy];
}

#pragma mark audio

static void NoshiCallMediaState(void *context, int state) {
    NoshiCallMediaContext *media = (NoshiCallMediaContext *)context;
    NSUInteger generation = media->generation;
    /* the engine's threads own the callback, so it only hands the word to the worker; the pool is theirs to drain */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NoshiWeakReference *reference = [media->engine retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        NoshiCallEngine *engine = reference.target;
        if (engine) [engine->_session post:^{ [engine mediaState:state generation:generation]; }];
        [reference release];
    });
    [pool drain];
}

static void NoshiCallMediaBars(void *context, int bars) {
    NoshiCallMediaContext *media = (NoshiCallMediaContext *)context;
    NSUInteger generation = media->generation;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NoshiWeakReference *reference = [media->engine retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        NoshiCallEngine *engine = reference.target;
        if (engine) [engine->_session post:^{ [engine mediaBars:bars generation:generation]; }];
        [reference release];
    });
    [pool drain];
}

- (void)startMedia {
    if (strcmp(_call.version, NOSHI_CALL_TGCALLS_VERSION) == 0) {
        [self startTgcalls];
        return;
    }
    noshi_voip_endpoint endpoints[NOSHI_CALL_CONNECTIONS_MAX];
    size_t count = _call.connection_count;
    if (count == 0) {
        NSLog(@"noshigram: the call came with no reflector to reach");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        memset(&endpoints[i], 0, sizeof(endpoints[i]));
        endpoints[i].id = _call.connections[i].id;
        endpoints[i].port = _call.connections[i].port;
        endpoints[i].tcp = _call.connections[i].tcp;
        strncpy(endpoints[i].ip, _call.connections[i].ip, sizeof(endpoints[i].ip) - 1);
        strncpy(endpoints[i].ipv6, _call.connections[i].ipv6, sizeof(endpoints[i].ipv6) - 1);
        memcpy(endpoints[i].peer_tag, _call.connections[i].peer_tag, sizeof(endpoints[i].peer_tag));
    }
    [_mediaContext release];
    _mediaContext = [[NoshiCallMediaContext alloc] init];
    _mediaContext->engine = [[NoshiWeakReference referenceTo:self] retain];
    _mediaContext->generation = _generation;
    int32_t layer = _call.max_layer > 0 ? _call.max_layer : NOSHI_CALL_MAX_LAYER;
    _voip = noshi_voip_create(endpoints, count, _key, _outgoing ? 1 : 0, _call.p2p_allowed && [self directPathAllowed] ? 1 : 0, layer, NoshiCallMediaState, NoshiCallMediaBars, _mediaContext);
    if (!_voip) {
        NSLog(@"noshigram: the call engine could not be made");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    noshi_voip_set_muted(_voip, _muted ? 1 : 0);
    [self setPhase:NoshiCallPhaseConnecting];
    noshi_voip_start(_voip);
}

/* the call settled on tgcalls 7.0.0: the signaling goes through the session, the media through the reflectors */
- (void)startTgcalls {
    _tgc = [[NoshiTgcRuntime alloc] initWithConnections:_call.connections count:_call.connection_count turns:_call.turns turnCount:_call.turn_count key:_key outgoing:_outgoing video:_wantsVideo delegate:self];
    if (!_tgc) {
        NSLog(@"noshigram: the tgcalls call could not be made");
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    [_tgc setMuted:_muted];
    /* the screens take the camera and the pictures from this object while the runtime lives */
    @synchronized (self) {
        [_activeVideo release];
        _activeVideo = [_tgc.video retain];
    }
    [self setPhase:NoshiCallPhaseConnecting];
    if (![_tgc start]) {
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        return;
    }
    /* what the other phone sent before this side had the key goes in now */
    for (NSData *data in _earlySignals) [_tgc receiveSignaling:data];
    [_earlySignals release];
    _earlySignals = nil;
    /* a call that began as a video call, or a camera button pressed while it connected, starts the camera now */
    if (_wantsVideo || _cameraWish) [self applyCamera:YES];
}

- (void)handleSignalingData:(NSData *)data callId:(int64_t)callId {
    if (!_active || !_haveCall || callId != _call.id) return;
    if (_tgc) {
        [_tgc receiveSignaling:data];
        return;
    }
    /* the other phone is ahead of this one: its first messages wait for the media to start, which is when the key exists */
    if (!_earlySignals) _earlySignals = [[NSMutableArray alloc] init];
    if (_earlySignals.count < 128) [_earlySignals addObject:data];
}

#pragma mark tgcalls runtime

/* the runtime's queue calls these; each hops to the session worker, and drops a word of a call that is over or of another runtime */
- (void)tgcRuntime:(NoshiTgcRuntime *)runtime sendSignaling:(NSData *)data {
    NSUInteger generation = _generation;
    NSData *bytes = [data copy];
    [_session post:^{
        if (generation == _generation && _active && _tgc == runtime && _haveCall) {
            int64_t callId = _call.id, accessHash = _call.access_hash;
            [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
                return noshi_call_signaling_request(arena, callId, accessHash, bytes.bytes, bytes.length, request);
            } handler:^(const noshi_mt_rpc_result *result) {
                if (result->status != NOSHI_OK) NSLog(@"noshigram: phone.sendSignalingData failed: %@", NoshiRpcErrorName(result));
            }];
        }
        [bytes release];
    }];
}

- (void)tgcRuntime:(NoshiTgcRuntime *)runtime didChangeState:(noshi_tgc_call_state)state {
    NSUInteger generation = _generation;
    [_session post:^{
        if (generation != _generation || !_active || _tgc != runtime) return;
        switch (state) {
        case NOSHI_TGC_CALL_CONNECTED:
            if (_startedAt == 0) _startedAt = [NSDate timeIntervalSinceReferenceDate];
            [self setPhase:NoshiCallPhaseActive];
            break;
        case NOSHI_TGC_CALL_RECONNECTING:
            [self setPhase:NoshiCallPhaseReconnecting];
            break;
        case NOSHI_TGC_CALL_FAILED:
            NSLog(@"noshigram: the tgcalls call failed (%@)", [runtime diagnostics]);
            [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
            break;
        default:
            break;
        }
    }];
}

- (void)tgcRuntime:(NoshiTgcRuntime *)runtime remoteMuted:(BOOL)muted video:(int)videoState rotation:(int)rotation {
    NSUInteger generation = _generation;
    (void)rotation;
    [_session post:^{
        if (generation != _generation || !_active || _tgc != runtime) return;
        _remoteMuted = muted;
        _remoteVideo = videoState == 2;
        [self publishEnd:NoshiCallEndNone];
    }];
}

- (void)tgcRuntimeDidChangeStreams:(NoshiTgcRuntime *)runtime {
    (void)runtime;
}

- (void)mediaState:(int)state generation:(NSUInteger)generation {
    if (generation != _generation || !_active || !_voip) return;
    switch (state) {
    case NOSHI_VOIP_ESTABLISHED:
        if (_startedAt == 0) _startedAt = [NSDate timeIntervalSinceReferenceDate];
        [self setPhase:NoshiCallPhaseActive];
        break;
    case NOSHI_VOIP_RECONNECTING:
        [self setPhase:NoshiCallPhaseReconnecting];
        break;
    case NOSHI_VOIP_FAILED:
        NSLog(@"noshigram: the call audio failed with error %d", noshi_voip_last_error(_voip));
        [self finishWithReason:NOSHI_CALL_REASON_DISCONNECT end:NoshiCallEndFailed sendDiscard:YES];
        break;
    default:
        if (_phase != NoshiCallPhaseActive && _phase != NoshiCallPhaseReconnecting) [self setPhase:NoshiCallPhaseConnecting];
        break;
    }
}

- (void)mediaBars:(int)bars generation:(NSUInteger)generation {
    if (generation != _generation || !_active) return;
    _bars = bars;
    [self publishEnd:NoshiCallEndNone];
}

/* the engine joins its threads when it goes, so it goes on a queue of its own, and the next step waits for it */
- (void)stopMediaThen:(void (^)(void))then {
    noshi_voip *voip = _voip;
    NoshiTgcRuntime *tgc = _tgc;
    NoshiCallMediaContext *context = _mediaContext;
    _voip = NULL;
    _tgc = nil;
    _mediaContext = nil;
    @synchronized (self) {
        [_activeVideo release];
        _activeVideo = nil;
    }
    if (!voip && !tgc) {
        [context release];
        if (then) then();
        return;
    }
    void (^next)(void) = [then copy];
    NoshiSession *session = _session;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (voip) noshi_voip_destroy(voip);
        if (tgc) {
            [tgc stop];
            [tgc release];
        }
        [context release];
        [session post:^{
            if (next) next();
            [next release];
        }];
    });
}

#pragma mark ending

- (void)finishWithReason:(noshi_call_reason)reason end:(NoshiCallEnd)end sendDiscard:(BOOL)send {
    if (!_active) return;
    if (send && !_haveCall) {
        /* the request has no answer yet, so there is nothing to discard; the answer ends the call when it comes */
        _cancelWhenKnown = YES;
        return;
    }
    ++_generation;
    int32_t duration = _startedAt > 0 ? (int32_t)([NSDate timeIntervalSinceReferenceDate] - _startedAt) : 0;
    int64_t connectionId = _voip ? noshi_voip_relay_id(_voip) : 0;
    int64_t callId = _haveCall ? _call.id : 0, accessHash = _haveCall ? _call.access_hash : 0;
    if (send && reason != NOSHI_CALL_REASON_NONE && callId != 0 && !_discardSent) {
        _discardSent = YES;
        [_session submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_call_discard_request(arena, callId, accessHash, duration, reason, connectionId, request);
        } handler:^(const noshi_mt_rpc_result *result) {
            if (result->status != NOSHI_OK) NSLog(@"noshigram: phone.discardCall failed: %@", NoshiRpcErrorName(result));
        }];
    }
    NoshiCallEnd finalEnd = end;
    _phase = NoshiCallPhaseEnded;
    [self stopMediaThen:^{
        [self publishEnd:finalEnd];
        _active = NO;
        _haveCall = NO;
        memset(_key, 0, sizeof(_key));
        memset(_secret, 0, sizeof(_secret));
    }];
}

@end

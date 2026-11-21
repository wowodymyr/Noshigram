#import "noshi_media_link.h"
#import "noshi_proxy_settings.h"

#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>

#include "noshi_client.h"
#include "noshi_credentials.h"
#include "noshi_mt_socket.h"
#include "noshi_session_file.h"
#include "noshi_session_key.h"

#import "noshi_files.h"
#import "noshi_rpc.h"

#define CONNECT_TIMEOUT_MS 10000
#define WRITE_TIMEOUT_MS 15000
#define RETRY_LIMIT 4
#define POLL_CAP_MS 1000
#define READ_CHUNK 16384
#define READS_PER_WAKE 64
#define RPC_TIMEOUT_MS 30000

@interface NoshiMediaJob : NSObject {
@public
    NoshiRemoteFile *file;
    NoshiDownloadCompletion completion;
    BOOL retried;
    /* a part of a large file: the answer may be shorter than the limit, or empty at the end of the file */
    BOOL ranged;
    long long offset;
    int32_t limit;
    /* a request that is no file part: built on the link's thread, and its answer is handed to the block there too */
    noshi_status (^build)(noshi_arena *arena, noshi_tl_value **request);
    void (^answer)(const noshi_mt_rpc_result *result);
}
@end

@implementation NoshiMediaJob
- (void)dealloc {
    [file release];
    [completion release];
    [build release];
    [answer release];
    [super dealloc];
}
@end

@interface NoshiMediaLink () {
    NSString *_directory;
    NSString *_deviceModel;
    NSString *_systemVersion;
    NSString *_appVersion;
    NSString *_langCode;
    /* the client keeps these pointers for its whole life and rebuilds its handshake preamble from them after a
       data center change */
    char *_cDeviceModel;
    char *_cSystemVersion;
    char *_cAppVersion;
    char *_cLangCode;
    NSLock *_lock;
    NSMutableArray *_commands;
    int _wake[2];
    dispatch_semaphore_t _exited;
    BOOL _started;
    BOOL _stopping;

    /* worker only */
    noshi_client _client;
    BOOL _clientLive;
    noshi_mt_socket _socket;
    unsigned _failures;
    uint64_t _retryAt;
    BOOL _wantLink;
    NoshiShiro *_shiro;
    NSMutableDictionary *_handlers;
    NSMutableArray *_waiting;
    BOOL _authorizing;
    NoshiAuthorizer _authorizer;
}
@end

@implementation NoshiMediaLink

@synthesize dc = _dc;
@synthesize shiro = _shiro;

static uint64_t NoshiMediaNowMs(void) {
    return noshi_system_clock.monotonic_ms(NULL);
}

- (id)initWithDc:(int32_t)dc directory:(NSString *)directory deviceModel:(NSString *)deviceModel
   systemVersion:(NSString *)systemVersion appVersion:(NSString *)appVersion langCode:(NSString *)langCode {
    self = [super init];
    if (!self) return nil;
    _dc = dc;
    _directory = [directory copy];
    _deviceModel = [deviceModel copy];
    _systemVersion = [systemVersion copy];
    _appVersion = [appVersion copy];
    _langCode = [langCode copy];
    _cDeviceModel = strdup(_deviceModel.UTF8String);
    _cSystemVersion = strdup(_systemVersion.UTF8String);
    _cAppVersion = strdup(_appVersion.UTF8String);
    _cLangCode = strdup(_langCode.UTF8String);
    _lock = [[NSLock alloc] init];
    _commands = [[NSMutableArray alloc] init];
    _handlers = [[NSMutableDictionary alloc] init];
    _waiting = [[NSMutableArray alloc] init];
    _wake[0] = _wake[1] = -1;
    noshi_mt_socket_init(&_socket);
    _exited = dispatch_semaphore_create(0);
    return self;
}

- (void)dealloc {
    for (int i = 0; i < 2; ++i) if (_wake[i] >= 0) close(_wake[i]);
    if (_exited) dispatch_release(_exited);
    [_directory release];
    [_deviceModel release];
    [_systemVersion release];
    [_appVersion release];
    [_langCode release];
    free(_cDeviceModel);
    free(_cSystemVersion);
    free(_cAppVersion);
    free(_cLangCode);
    [_lock release];
    [_commands release];
    [_handlers release];
    [_waiting release];
    [_authorizer release];
    [super dealloc];
}

#pragma mark commands

- (BOOL)post:(void (^)(void))block {
    [_lock lock];
    if (_stopping) {
        [_lock unlock];
        return NO;
    }
    [_commands addObject:[[block copy] autorelease]];
    [_lock unlock];
    char byte = 1;
    /* a full pipe already holds a wake up, so a short write loses nothing */
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"noshigram: media link wake up failed, errno %d", errno);
    return YES;
}

/* the thread starts with the first job, so a data center nobody needs is never dialled */
- (BOOL)ensureStarted {
    [_lock lock];
    if (_started) {
        BOOL usable = _wake[1] >= 0 && !_stopping;
        [_lock unlock];
        return usable;
    }
    _started = YES;
    BOOL piped = pipe(_wake) == 0;
    if (!piped) {
        _wake[0] = _wake[1] = -1;
    } else {
        for (int i = 0; i < 2; ++i) {
            fcntl(_wake[i], F_SETFL, fcntl(_wake[i], F_GETFL, 0) | O_NONBLOCK);
            fcntl(_wake[i], F_SETFD, FD_CLOEXEC);
        }
    }
    [_lock unlock];
    if (!piped) {
        NSLog(@"noshigram: media link pipe failed, errno %d", errno);
        return NO;
    }
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
    return YES;
}

- (void)stop {
    [_lock lock];
    BOOL running = _started && !_stopping && _wake[1] >= 0;
    _stopping = YES;
    [_lock unlock];
    if (!running) return;
    char byte = 1;
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"noshigram: media link stop wake up failed, errno %d", errno);
    dispatch_semaphore_wait(_exited, DISPATCH_TIME_FOREVER);
}

- (BOOL)isStopping {
    [_lock lock];
    BOOL stopping = _stopping;
    [_lock unlock];
    return stopping;
}

#pragma mark downloads

static void NoshiFinishJob(NoshiMediaJob *job, NSData *data, NSString *error) {
    if (job->answer) {
        /* the link could not carry the request; the block sees what any lost connection shows, so its error name is OFFLINE */
        noshi_mt_rpc_result failed;
        memset(&failed, 0, sizeof(failed));
        failed.status = NOSHI_E_STATE;
        job->answer(&failed);
        return;
    }
    NoshiDownloadCompletion done = [job->completion retain];
    NSData *delivered = [[data copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        done(delivered, deliveredError);
        [done release];
    });
}

- (void)downloadFile:(NoshiRemoteFile *)file authorizer:(NoshiAuthorizer)authorizer completion:(NoshiDownloadCompletion)completion {
    [self downloadFile:file offset:0 limit:NOSHI_REMOTE_FILE_PART ranged:NO authorizer:authorizer completion:completion];
}

- (void)downloadFile:(NoshiRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          authorizer:(NoshiAuthorizer)authorizer completion:(NoshiDownloadCompletion)completion {
    NoshiMediaJob *job = [[[NoshiMediaJob alloc] init] autorelease];
    job->ranged = ranged;
    job->offset = offset;
    job->limit = limit;
    job->file = [file retain];
    job->completion = [completion copy];
    [self enqueueJob:job authorizer:authorizer];
}

- (void)invokeBuilt:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build
            handler:(void (^)(const noshi_mt_rpc_result *result))handler authorizer:(NoshiAuthorizer)authorizer {
    NoshiMediaJob *job = [[[NoshiMediaJob alloc] init] autorelease];
    job->build = [build copy];
    job->answer = [handler copy];
    [self enqueueJob:job authorizer:authorizer];
}

- (void)enqueueJob:(NoshiMediaJob *)job authorizer:(NoshiAuthorizer)authorizer {
    NoshiAuthorizer authorize = [authorizer copy];
    if (![self ensureStarted]) {
        NoshiFinishJob(job, nil, @"INTERNAL");
        [authorize release];
        return;
    }
    BOOL posted = [self post:^{
        if (!_authorizer) _authorizer = [authorize retain];
        if (!_wantLink) {
            _failures = 0;
            _retryAt = 0;
            _wantLink = YES;
        }
        [self submitJob:job];
    }];
    if (!posted) NoshiFinishJob(job, nil, @"OFFLINE");
    [authorize release];
}

/* worker only */
- (void)submitJob:(NoshiMediaJob *)job {
    noshi_arena arena;
    noshi_tl_value *request, *location = NULL;
    uint64_t id = 0;
    noshi_status status = _clientLive ? NOSHI_OK : NOSHI_E_STATE;
    noshi_arena_init(&arena, 64u * 1024u);
    if (job->build) {
        request = NULL;
        if (status == NOSHI_OK) status = job->build(&arena, &request);
        if (status == NOSHI_OK && !request) status = NOSHI_E_NOMEM;
    } else {
        request = status == NOSHI_OK ? noshi_tl_new_obj(&arena, "upload.getFile") : NULL;
        if (status == NOSHI_OK && !request) status = NOSHI_E_NOMEM;
        if (status == NOSHI_OK) status = [job->file buildLocation:&arena into:&location];
        if (status == NOSHI_OK) status = noshi_tl_set(request, "location", location);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(&arena, request, "offset", job->offset);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(&arena, request, "limit", job->limit);
    }
    if (status == NOSHI_OK) status = noshi_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    noshi_arena_free(&arena);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: request on dc %d failed: %s", (int)_dc, noshi_status_name(status));
        NoshiFinishJob(job, nil, @"INTERNAL");
        return;
    }
    [_handlers setObject:[[^(const noshi_mt_rpc_result *result) {
        [self fileResult:result forJob:job];
    } copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
}

- (void)fileResult:(const noshi_mt_rpc_result *)result forJob:(NoshiMediaJob *)job {
    if (job->answer) {
        /* a key that never signed in on this data center is signed in once, as for a file part */
        if (result->status != NOSHI_OK && !job->retried && _authorizer &&
            [NoshiDownloadErrorName(result) isEqualToString:@"AUTH_KEY_UNREGISTERED"]) {
            job->retried = YES;
            [_waiting addObject:job];
            if (!_authorizing) [self authorize];
            return;
        }
        job->answer(result);
        return;
    }
    if (result->status == NOSHI_OK) {
        const uint8_t *bytes;
        size_t len;
        if (job->ranged) {
            if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len <= (size_t)job->limit) {
                NoshiFinishJob(job, [NSData dataWithBytes:bytes length:len], nil);
            } else {
                NoshiFinishJob(job, nil, @"INTERNAL");
            }
            return;
        }
        if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len >= NOSHI_REMOTE_FILE_PART) {
            NoshiFinishJob(job, nil, @"FILE_TOO_BIG");
        } else if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len > 0) {
            NoshiFinishJob(job, [NSData dataWithBytes:bytes length:len], nil);
        } else {
            NoshiFinishJob(job, nil, @"INTERNAL");
        }
        return;
    }
    NSString *error = NoshiDownloadErrorName(result);
    /* a key that never signed in on this data center is signed in once, then the waiting jobs go again */
    if ([error isEqualToString:@"AUTH_KEY_UNREGISTERED"] && !job->retried && _authorizer) {
        job->retried = YES;
        [_waiting addObject:job];
        if (!_authorizing) [self authorize];
        return;
    }
    NoshiFinishJob(job, nil, error);
}

- (void)failWaiting:(NSString *)error {
    NSArray *jobs = [[_waiting copy] autorelease];
    [_waiting removeAllObjects];
    for (NoshiMediaJob *job in jobs) NoshiFinishJob(job, nil, error);
}

- (void)authorize {
    _authorizing = YES;
    _authorizer(^(long long authId, NSData *bytes, NSString *errorName) {
        NSData *copy = [bytes copy];
        NSString *error = [errorName copy];
        [self post:^{
            if (error || !copy) {
                _authorizing = NO;
                [self failWaiting:error ? error : @"INTERNAL"];
            } else {
                [self importAuthorization:authId bytes:copy];
            }
        }];
        [copy release];
        [error release];
    });
}

- (void)importAuthorization:(long long)authId bytes:(NSData *)bytes {
    noshi_arena arena;
    noshi_tl_value *request;
    uint64_t id = 0;
    noshi_status status = _clientLive ? NOSHI_OK : NOSHI_E_STATE;
    noshi_arena_init(&arena, 64u * 1024u);
    request = status == NOSHI_OK ? noshi_tl_new_obj(&arena, "auth.importAuthorization") : NULL;
    if (status == NOSHI_OK && !request) status = NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_i64(&arena, request, "id", authId);
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(&arena, request, "bytes", bytes.bytes, bytes.length);
    if (status == NOSHI_OK) status = noshi_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    noshi_arena_free(&arena);
    if (status != NOSHI_OK) {
        _authorizing = NO;
        [self failWaiting:@"INTERNAL"];
        return;
    }
    [_handlers setObject:[[^(const noshi_mt_rpc_result *result) {
        _authorizing = NO;
        if (result->status != NOSHI_OK) {
            [self failWaiting:NoshiRpcErrorName(result)];
            return;
        }
        NSArray *jobs = [[_waiting copy] autorelease];
        [_waiting removeAllObjects];
        for (NoshiMediaJob *job in jobs) [self submitJob:job];
    } copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
}

#pragma mark client callbacks

static noshi_status NoshiMediaSend(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    NoshiMediaLink *link = ctx;
    (void)dc;
    if (link->_socket.fd < 0) return NOSHI_E_STATE;
    return noshi_mt_socket_write_all(&link->_socket, data, len, WRITE_TIMEOUT_MS);
}

static noshi_status NoshiMediaLoad(void *ctx, int32_t dc, noshi_mt_session_state *out) {
    NoshiMediaLink *link = ctx;
    return NoshiSessionLoad(link->_directory, dc, out);
}

static noshi_status NoshiMediaSave(void *ctx, int32_t dc, const noshi_mt_session_state *state) {
    NoshiMediaLink *link = ctx;
    return NoshiSessionStore(link->_directory, dc, state);
}

static void NoshiMediaResult(void *ctx, uint64_t id, const noshi_mt_rpc_result *result) {
    NoshiMediaLink *link = ctx;
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:id];
    void (^handler)(const noshi_mt_rpc_result *) = [[link->_handlers objectForKey:key] retain];
    if (!handler) return;
    [link->_handlers removeObjectForKey:key];
    handler(result);
    [handler release];
}

static void NoshiMediaError(void *ctx, noshi_status status, const char *boundary) {
    (void)ctx;
    NSLog(@"noshigram: media link error at %s: %s", boundary, noshi_status_name(status));
}

#pragma mark worker

- (noshi_status)initClient {
    noshi_mt_client_config config;
    noshi_client_events events;
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    config.dc_id = _dc;
    config.transport = NOSHI_MT_INTERMEDIATE;
    config.obfuscation.enabled = 1;
    config.obfuscation.dc_id = (int16_t)_dc;
    config.api_id = NOSHI_API_ID;
    config.device_model = _cDeviceModel;
    config.system_version = _cSystemVersion;
    config.app_version = _cAppVersion;
    config.system_lang_code = _cLangCode;
    config.lang_pack = "ios";
    config.lang_code = _cLangCode;
    events.ctx = self;
    events.send = NoshiMediaSend;
    events.load_session = NoshiMediaLoad;
    events.save_session = NoshiMediaSave;
    events.error = NoshiMediaError;
    events.result = NoshiMediaResult;
    noshi_status status = noshi_client_init(&_client, &config, NOSHI_API_HASH, &events);
    _clientLive = status == NOSHI_OK;
    return status;
}

/* every request still waiting is failed, so no download hangs after the link gave up */
- (void)failEverything:(NSString *)error {
    noshi_mt_rpc_result failed;
    memset(&failed, 0, sizeof(failed));
    failed.status = NOSHI_E_STATE;
    NSArray *handlers = [_handlers allValues];
    [_handlers removeAllObjects];
    for (void (^handler)(const noshi_mt_rpc_result *) in handlers) handler(&failed);
    [self failWaiting:error];
    _authorizing = NO;
}

- (void)linkLost:(noshi_status)reason {
    int32_t transport = _clientLive ? noshi_mt_client_transport_error(&_client.mt) : 0;
    int64_t securityValue = 0;
    const char *securityNote = _clientLive ? noshi_mt_client_security_note(&_client.mt, &securityValue) : NULL;
    NSLog(@"noshigram: media link to dc %d lost: %s (transport error %d%s%s %lld)", (int)_dc, noshi_status_name(reason), (int)transport,
          securityNote ? ", refused: " : "", securityNote ? securityNote : "", (long long)securityValue);
    noshi_mt_socket_close(&_socket);
    if (_clientLive) noshi_client_disconnected(&_client);
    if (transport == -404) {
        /* the server forgot the key: a new handshake replaces it, and the account signs in again on the first job */
        unlink(NoshiSessionPath(_directory, _dc).fileSystemRepresentation);
        noshi_client_free(&_client);
        _clientLive = NO;
        [self failEverything:@"OFFLINE"];
        if ([self initClient] != NOSHI_OK) _wantLink = NO;
        _failures = 0;
        return;
    }
    if (++_failures >= RETRY_LIMIT) {
        _wantLink = NO;
        [self failEverything:@"OFFLINE"];
        return;
    }
    _retryAt = NoshiMediaNowMs() + (1000u << (_failures - 1));
}

- (void)openLink {
    noshi_status status = NoshiProxyConnect(_shiro, &_socket, noshi_dc_host(_dc), noshi_dc_port(), CONNECT_TIMEOUT_MS, &_client.config, NULL);
    if (status == NOSHI_OK) {
        _client.mt.config.transport = _client.config.transport;
        _client.mt.config.obfuscation = _client.config.obfuscation;
    }
    if (status == NOSHI_OK) status = noshi_client_connect(&_client);
    if (status != NOSHI_OK) [self linkLost:status];
}

- (void)readLink {
    uint8_t buf[READ_CHUNK];
    for (int i = 0; i < READS_PER_WAKE && _socket.fd >= 0; ++i) {
        size_t got = 0;
        noshi_status status = noshi_mt_socket_read(&_socket, buf, sizeof(buf), &got, 0);
        if (status == NOSHI_E_TIMEOUT) return;
        if (status != NOSHI_OK) {
            [self linkLost:status];
            return;
        }
        status = noshi_client_feed(&_client, buf, got);
        if ((status != NOSHI_OK && status != NOSHI_E_RETRY) || _client.mt.state == NOSHI_MT_CLIENT_DEAD) {
            [self linkLost:status != NOSHI_OK ? status : NOSHI_E_STATE];
            return;
        }
    }
}

- (void)drainCommands {
    [_lock lock];
    NSArray *batch = [[_commands copy] autorelease];
    [_commands removeAllObjects];
    [_lock unlock];
    for (void (^command)(void) in batch) command();
}

- (void)run {
    NSAutoreleasePool *setup = [[NSAutoreleasePool alloc] init];
    noshi_status status = [self initClient];
    if (status != NOSHI_OK) NSLog(@"noshigram: media link start failed: %s", noshi_status_name(status));
    [setup drain];

    while (_clientLive && ![self isStopping]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self drainCommands];
        if (_wantLink && _socket.fd < 0 && NoshiMediaNowMs() >= _retryAt) [self openLink];
        uint32_t next = POLL_CAP_MS;
        if (_clientLive && noshi_client_tick(&_client, &next) != NOSHI_OK) next = POLL_CAP_MS;
        /* only a frame the server sent and the client accepted counts as a link that works, as on the main link */
        if (_socket.fd >= 0 && _client.mt.state == NOSHI_MT_CLIENT_READY && noshi_mt_client_heard(&_client.mt)) _failures = 0;
        if (next > POLL_CAP_MS) next = POLL_CAP_MS;
        if (_wantLink && _socket.fd < 0) {
            uint64_t now = NoshiMediaNowMs();
            uint32_t until = _retryAt > now ? (uint32_t)MIN(_retryAt - now, (uint64_t)POLL_CAP_MS) : 0;
            if (until < next) next = until;
        }
        struct pollfd fds[2];
        nfds_t count = 1;
        fds[0].fd = _wake[0];
        fds[0].events = POLLIN;
        fds[0].revents = 0;
        if (_socket.fd >= 0) {
            fds[1].fd = _socket.fd;
            fds[1].events = POLLIN;
            fds[1].revents = 0;
            count = 2;
        }
        int ready = poll(fds, count, (int)next);
        if (ready < 0 && errno != EINTR) {
            NSLog(@"noshigram: media link poll failed, errno %d", errno);
            [self linkLost:NOSHI_E_IO];
        } else if (ready > 0) {
            if (fds[0].revents & POLLIN) {
                char drain[64];
                while (read(_wake[0], drain, sizeof(drain)) > 0) {}
            }
            if (count == 2 && (fds[1].revents & (POLLIN | POLLERR | POLLHUP))) [self readLink];
        }
        [pool drain];
    }

    NSAutoreleasePool *teardown = [[NSAutoreleasePool alloc] init];
    /* commands accepted before stop still own jobs that must be failed */
    [self drainCommands];
    noshi_mt_socket_close(&_socket);
    if (_clientLive) noshi_client_free(&_client);
    _clientLive = NO;
    [self failEverything:@"OFFLINE"];
    [teardown drain];
    dispatch_semaphore_signal(_exited);
}

@end

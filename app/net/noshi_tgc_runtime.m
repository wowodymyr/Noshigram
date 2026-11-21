#import "noshi_tgc_runtime.h"

#import <mach/mach_time.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#import "noshi_call_audio.h"
#import "noshi_call_video.h"
#import "noshi_shiro.h"
#import "noshi_shiro_network.h"

#include "noshi_bytes.h"
#include "noshi_udp.h"

#define TICK_MS 20
/* a key frame this often even when nobody asked: the other side's decoder starts from one, and the clients seen so far send no request when the first
   one is lost */
#define KEY_FRAME_INTERVAL_MS 4000
#define MAX_ENDPOINTS (NOSHI_TGC_ICE_MAX_REFLECTORS + NOSHI_TGC_ICE_MAX_TURNS)
#define RECEIVE_BUFFER 2048
#define AUDIO_FRAME_SAMPLES 960
#define DIAGNOSTIC_INTERVAL_MS 3000
#define DIAGNOSTIC_LIMIT_MS 45000
#define TRACE_FILE_LIMIT (512 * 1024)
#define TRACE_FILE_NAME @"noshigram-call-trace.log"

typedef struct {
    int fd;
    dispatch_source_t source;
    /* a socket of the tunnel speaks frames and is not connected, so it remembers the reflector it stands for */
    BOOL tunneled;
    uint32_t ip;
    uint16_t port;
} NoshiTgcSocket;

static uint64_t NoshiTgcNowMs(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return mach_absolute_time() * base.numer / base.denom / 1000000ull;
}

@interface NoshiTgcRuntime () {
@public
    noshi_tgc_call *_call;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    NoshiTgcSocket _sockets[MAX_ENDPOINTS];
    size_t _socketCount;
    id<NoshiTgcRuntimeDelegate> _delegate;
    NoshiCallAudio *_audio;
    NoshiCallVideo *_video;
    BOOL _cameraOn;
    noshi_tgc_call_config _config;
    BOOL _stopped;
    BOOL _started;
    uint64_t _startedAt;
    uint64_t _lastKeyMs;
    /* what the sockets did, for the diagnostic line: frames and datagrams in, those refused on the way in, those sent and those the socket would not take */
    unsigned _rxCount, _rxRefused, _txCount, _txFailed;
    int _txErrno;
    uint64_t _lastDiagnostic;
    NSString *_diagnostics;
    BOOL _muted;
    FILE *_trace;
    long _traceBytes;
}
- (void)tick;
- (void)receiveOn:(size_t)index;
- (void)stateChanged:(noshi_tgc_call_state)state;
@end

/* what the call does, one line each: to the log, and to a file in the app's documents that a developer reads off the phone; the file starts afresh for each call */
static void NoshiTgcTrace(void *context, const char *line) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    NSLog(@"noshigram: tgc %s", line);
    if (runtime->_trace && runtime->_traceBytes < TRACE_FILE_LIMIT) {
        long ms = (long)(NoshiTgcNowMs() - runtime->_startedAt);
        int n = fprintf(runtime->_trace, "%6ld.%03ld %s\n", ms / 1000, ms % 1000, line);
        fflush(runtime->_trace);
        if (n > 0) runtime->_traceBytes += n;
    }
}

static void NoshiTgcSendSignaling(void *context, const uint8_t *data, size_t len) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [runtime->_delegate tgcRuntime:runtime sendSignaling:[NSData dataWithBytes:data length:len]];
    [pool drain];
}

static void NoshiTgcSendDatagram(void *context, unsigned index, const uint8_t *data, size_t len) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    if (index >= runtime->_socketCount || runtime->_sockets[index].fd < 0) return;
    /* a datagram the socket will not take now is lost, which the path does to datagrams as well; the protocols above resend what matters */
    if (runtime->_sockets[index].tunneled) {
        uint8_t frame[NOSHI_UDP_FRAME_HEADER + NOSHI_UDP_MAX_PAYLOAD];
        size_t frame_len = 0;
        if (noshi_udp_frame_encode(runtime->_sockets[index].ip, runtime->_sockets[index].port, data, len, frame, sizeof(frame), &frame_len) != NOSHI_OK) return;
        if (send(runtime->_sockets[index].fd, frame, frame_len, 0) < 0) {
            ++runtime->_txFailed;
            runtime->_txErrno = errno;
        } else {
            ++runtime->_txCount;
        }
        return;
    }
    if (send(runtime->_sockets[index].fd, data, len, 0) < 0) {
        ++runtime->_txFailed;
        runtime->_txErrno = errno;
    } else {
        ++runtime->_txCount;
    }
}

static void NoshiTgcState(void *context, noshi_tgc_call_state state) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [runtime stateChanged:state];
    [pool drain];
}

static void NoshiTgcStreams(void *context) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    [runtime->_delegate tgcRuntimeDidChangeStreams:runtime];
}

static void NoshiTgcRemoteMedia(void *context, int muted, int videoState, int rotation) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    [runtime->_delegate tgcRuntime:runtime remoteMuted:muted != 0 video:videoState rotation:rotation];
}

static void NoshiTgcVideo(void *context, const uint8_t *frame, size_t len, int keyFrame, uint32_t timestamp) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)timestamp;
    [runtime->_video receiveFrame:[NSData dataWithBytes:frame length:len] keyFrame:keyFrame != 0];
    [pool drain];
}

static void NoshiTgcKeyFrameRequested(void *context) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    [runtime->_video requestKeyFrame];
}

static void NoshiTgcAudio(void *context, const uint8_t *opus, size_t len, uint16_t sequence, uint32_t timestamp) {
    NoshiTgcRuntime *runtime = (NoshiTgcRuntime *)context;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)timestamp;
    [runtime->_audio receivePacket:[NSData dataWithBytes:opus length:len] sequence:sequence];
    [pool drain];
}

@implementation NoshiTgcRuntime

/* the fill-in of a reflector from a connection of the call, for one address family; NO when the address does not parse */
static BOOL NoshiTgcReflector(const noshi_call_connection *connection, uint8_t serverId, BOOL ipv6, noshi_tgc_ice_reflector_config *out) {
    const char *text = ipv6 ? connection->ipv6 : connection->ip;
    memset(out, 0, sizeof(*out));
    if (!text[0]) return NO;
    if (ipv6) {
        if (inet_pton(AF_INET6, text, out->address) != 1) return NO;
        out->ipv6 = 1;
    } else if (inet_pton(AF_INET, text, out->address) != 1) {
        return NO;
    }
    out->server_id = serverId;
    out->port = connection->port;
    out->tcp = connection->tcp;
    memcpy(out->peer_tag, connection->peer_tag, sizeof(out->peer_tag));
    return YES;
}

- (id)initWithConnections:(const noshi_call_connection *)connections count:(size_t)count turns:(const noshi_call_turn *)turns turnCount:(size_t)turnCount
                      key:(const uint8_t *)key outgoing:(BOOL)outgoing video:(BOOL)video delegate:(id<NoshiTgcRuntimeDelegate>)delegate {
    int64_t ids[NOSHI_CALL_CONNECTIONS_MAX];
    uint8_t numbers[NOSHI_CALL_CONNECTIONS_MAX];
    noshi_tgc_call_events events;
    size_t i;
    self = [super init];
    if (!self) return nil;
    if (!connections || !key || count == 0 || count > NOSHI_CALL_CONNECTIONS_MAX) {
        [self release];
        return nil;
    }
    _delegate = delegate;
    for (i = 0; i < count; ++i) ids[i] = connections[i].id;
    /* the numbers the other clients give the servers come from all the connections of the call, the TCP ones included */
    if (noshi_tgc_reflector_server_ids(ids, count, numbers) != NOSHI_OK) {
        [self release];
        return nil;
    }
    memset(&_config, 0, sizeof(_config));
    _config.is_outgoing = outgoing ? 1 : 0;
    _config.with_video = video ? 1 : 0;
    memcpy(_config.key, key, sizeof(_config.key));
    /* the UDP reflectors, IPv4 before IPv6: the path of this app is UDP only, so a connection that asks for TCP is skipped */
    {
        int pass;
        for (pass = 0; pass < 2; ++pass) {
            for (i = 0; i < count && _config.reflector_count < MAX_ENDPOINTS; ++i) {
                noshi_tgc_ice_reflector_config reflector;
                if (connections[i].tcp) continue;
                if (NoshiTgcReflector(&connections[i], numbers[i], pass == 1, &reflector)) _config.reflectors[_config.reflector_count++] = reflector;
            }
        }
    }
    /* the TURN servers, IPv4 only: a server whose address does not parse is left out */
    for (i = 0; turns && i < turnCount && _config.turn_count < NOSHI_TGC_ICE_MAX_TURNS; ++i) {
        struct in_addr address;
        noshi_tgc_call_turn *turn = &_config.turns[_config.turn_count];
        if (inet_pton(AF_INET, turns[i].ip, &address) != 1 || turns[i].port == 0) continue;
        turn->ip = ntohl(address.s_addr);
        turn->port = turns[i].port;
        snprintf(turn->username, sizeof(turn->username), "%s", turns[i].username);
        snprintf(turn->password, sizeof(turn->password), "%s", turns[i].password);
        ++_config.turn_count;
        NSLog(@"noshigram: call turn server %s:%u", turns[i].ip, (unsigned)turns[i].port);
    }
    if (_config.reflector_count == 0) {
        NSLog(@"noshigram: the call has no UDP reflector to reach");
        [self release];
        return nil;
    }
    memset(&events, 0, sizeof(events));
    events.context = self;
    events.send_signaling = NoshiTgcSendSignaling;
    events.send_datagram = NoshiTgcSendDatagram;
    events.state = NoshiTgcState;
    events.streams = NoshiTgcStreams;
    events.remote_media = NoshiTgcRemoteMedia;
    events.audio = NoshiTgcAudio;
    events.video = NoshiTgcVideo;
    events.key_frame_requested = NoshiTgcKeyFrameRequested;
    events.trace = NoshiTgcTrace;
    _startedAt = NoshiTgcNowMs();
    {
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        if (documents) _trace = fopen([[documents stringByAppendingPathComponent:TRACE_FILE_NAME] fileSystemRepresentation], "w");
    }
    if (noshi_tgc_call_new(&_call, &_config, &events) != NOSHI_OK) {
        NSLog(@"noshigram: the tgcalls call could not be made");
        [self release];
        return nil;
    }
    _queue = dispatch_queue_create("noshigram.tgcalls", DISPATCH_QUEUE_SERIAL);
    for (i = 0; i < MAX_ENDPOINTS; ++i) {
        _sockets[i].fd = -1;
        _sockets[i].tunneled = NO;
    }
    {
        NoshiTgcRuntime *runtime = self;
        /* the frames of the camera come on the capture queue and go over to the call's queue; a frame before the video channel is agreed is dropped there */
        _video = [[NoshiCallVideo alloc] initWithFrameHandler:^(NSData *frame, BOOL keyFrame, uint32_t timestamp) {
            NSData *copy = [frame retain];
            dispatch_async(runtime->_queue, ^{
                if (!runtime->_stopped) {
                    uint64_t now = NoshiTgcNowMs();
                    noshi_status status = noshi_tgc_call_send_video(runtime->_call, copy.bytes, copy.length, timestamp, now);
                    if (status == NOSHI_OK && keyFrame) runtime->_lastKeyMs = now;
                    /* a frame sent before the channel was agreed is gone, and the other side can only start from a key frame: the next one is made one */
                    if (status == NOSHI_E_STATE || (status == NOSHI_OK && now - runtime->_lastKeyMs >= KEY_FRAME_INTERVAL_MS)) [runtime->_video requestKeyFrame];
                    if (status != NOSHI_OK && status != NOSHI_E_STATE) NSLog(@"noshigram: tgcalls video frame refused (%s)", noshi_status_name(status));
                }
                [copy release];
            });
        }];
        _video.traceHandler = ^(NSString *line) { NoshiTgcTrace(runtime, line.UTF8String); };
        _video.keyFrameNeededHandler = ^{
            dispatch_async(runtime->_queue, ^{
                if (!runtime->_stopped) noshi_tgc_call_request_key_frame(runtime->_call, NoshiTgcNowMs());
            });
        };
    }
    memset(_config.key, 0, sizeof(_config.key));
    return self;
}

- (void)dealloc {
    [self stop];
    if (_queue) dispatch_release(_queue);
    [_diagnostics release];
    [_video release];
    [super dealloc];
}

/* the socket of reflector number index, or of TURN server index - reflector_count */
- (BOOL)openSocketFor:(size_t)index {
    noshi_tgc_ice_reflector_config turnAddress;
    const noshi_tgc_ice_reflector_config *r = index < _config.reflector_count ? &_config.reflectors[index] : &turnAddress;
    struct sockaddr_storage storage;
    socklen_t length;
    int fd, flags, on = 1;
    int route = NoshiShiroNetworkRoute();
    if (index >= _config.reflector_count) {
        const noshi_tgc_call_turn *turn = &_config.turns[index - _config.reflector_count];
        memset(&turnAddress, 0, sizeof(turnAddress));
        turnAddress.address[0] = (uint8_t)(turn->ip >> 24);
        turnAddress.address[1] = (uint8_t)(turn->ip >> 16);
        turnAddress.address[2] = (uint8_t)(turn->ip >> 8);
        turnAddress.address[3] = (uint8_t)turn->ip;
        turnAddress.port = turn->port;
    }
    /* a VPN that is wanted and not up carries nothing, and one that is up carries IPv4 only; neither falls back to the direct path */
    if (route == (int)NoshiShiroRouteBlocked) return NO;
    if (route == (int)NoshiShiroRouteTunnel) {
        if (r->ipv6) return NO;
        fd = -1;
        if (NoshiShiroNetworkOpenDatagram(&fd) != NOSHI_OK) return NO;
        _sockets[index].tunneled = YES;
        _sockets[index].ip = noshi_get_u32be(r->address);
        _sockets[index].port = r->port;
        return [self watchSocket:index descriptor:fd];
    }
    memset(&storage, 0, sizeof(storage));
    if (r->ipv6) {
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)&storage;
        a->sin6_len = sizeof(*a);
        a->sin6_family = AF_INET6;
        a->sin6_port = htons(r->port);
        memcpy(&a->sin6_addr, r->address, 16);
        length = sizeof(*a);
    } else {
        struct sockaddr_in *a = (struct sockaddr_in *)&storage;
        a->sin_len = sizeof(*a);
        a->sin_family = AF_INET;
        a->sin_port = htons(r->port);
        memcpy(&a->sin_addr, r->address, 4);
        length = sizeof(*a);
    }
    fd = socket(storage.ss_family, SOCK_DGRAM, 0);
    if (fd < 0) return NO;
    flags = fcntl(fd, F_GETFL, 0);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 || connect(fd, (struct sockaddr *)&storage, length) < 0) {
        close(fd);
        return NO;
    }
    _sockets[index].tunneled = NO;
    return [self watchSocket:index descriptor:fd];
}

- (BOOL)watchSocket:(size_t)index descriptor:(int)fd {
    _sockets[index].fd = fd;
    _sockets[index].source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _queue);
    dispatch_source_set_event_handler(_sockets[index].source, ^{ [self receiveOn:index]; });
    dispatch_resume(_sockets[index].source);
    return YES;
}

- (BOOL)start {
    size_t i, opened = 0;
    if (_started) return YES;
    _started = YES;
    _socketCount = _config.reflector_count + _config.turn_count;
    for (i = 0; i < _socketCount; ++i) {
        if ([self openSocketFor:i]) ++opened;
    }
    if (opened == 0) {
        NSLog(@"noshigram: no reflector socket could be opened");
        return NO;
    }
    _startedAt = NoshiTgcNowMs();
    dispatch_async(_queue, ^{
        if (_stopped) return;
        noshi_tgc_call_start(_call, NoshiTgcNowMs());
    });
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_event_handler(_timer, ^{ [self tick]; });
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)TICK_MS * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    dispatch_resume(_timer);
    return YES;
}

- (void)receiveOn:(size_t)index {
    uint8_t buffer[RECEIVE_BUFFER];
    int guard;
    if (_stopped || index >= _socketCount) return;
    for (guard = 0; guard < 64; ++guard) {
        ssize_t n = recv(_sockets[index].fd, buffer, sizeof(buffer), 0);
        const uint8_t *payload = buffer;
        size_t payload_len = (size_t)n;
        if (n <= 0) break;
        ++_rxCount;
        if (_sockets[index].tunneled) {
            uint32_t ip = 0;
            uint16_t port = 0;
            /* a socket of the tunnel hears every peer; the call talks to one reflector, and a datagram from anyone else is not for it */
            if (noshi_udp_frame_decode(buffer, (size_t)n, &ip, &port, &payload, &payload_len) != NOSHI_OK) continue;
            if (ip != _sockets[index].ip || port != _sockets[index].port) {
                ++_rxRefused;
                continue;
            }
        }
        noshi_tgc_call_datagram(_call, (unsigned)index, payload, payload_len, NoshiTgcNowMs());
    }
}

- (void)tick {
    uint64_t now = NoshiTgcNowMs();
    if (_stopped) return;
    noshi_tgc_call_tick(_call, now);
    if (now - _lastDiagnostic >= DIAGNOSTIC_INTERVAL_MS) {
        int ice = 0, dtls = 0, sctp = 0;
        unsigned in = 0, out = 0;
        _lastDiagnostic = now;
        noshi_tgc_call_diagnostics(_call, &ice, &dtls, &sctp, &in, &out);
        unsigned long long tunnelIn = 0, tunnelOut = 0;
        (void)NoshiShiroNetworkTransferred(&tunnelIn, &tunnelOut);
        NSString *line = [NSString stringWithFormat:@"ice %d dtls %d sctp %d, signals in %u out %u, %llus, sockets rx %u refused %u tx %u failed %u (errno %d), tunnel in %llu out %llu",
                          ice, dtls, sctp, in, out, (unsigned long long)((now - _startedAt) / 1000), _rxCount, _rxRefused, _txCount, _txFailed, _txErrno, tunnelIn, tunnelOut];
        @synchronized (self) {
            [_diagnostics release];
            _diagnostics = [line copy];
        }
        if (now - _startedAt < DIAGNOSTIC_LIMIT_MS) NoshiTgcTrace(self, line.UTF8String);
    }
}

- (NSString *)diagnostics {
    @synchronized (self) {
        return [[_diagnostics retain] autorelease];
    }
}

/* the media path came up: the microphone and the speaker start, and go on until the call ends */
- (void)stateChanged:(noshi_tgc_call_state)state {
    if (_stopped) return;
    if (state == NOSHI_TGC_CALL_CONNECTED && !_audio) {
        NoshiTgcRuntime *runtime = self;
        _audio = [[NoshiCallAudio alloc] initWithFrameHandler:^(NSData *frame) {
            /* the audio queue is not the call's: the frame goes over to it */
            NSData *copy = [frame retain];
            dispatch_async(runtime->_queue, ^{
                if (!runtime->_stopped) noshi_tgc_call_send_audio(runtime->_call, copy.bytes, copy.length, AUDIO_FRAME_SAMPLES, NoshiTgcNowMs());
                [copy release];
            });
        }];
        _audio.muted = _muted;
        if (![_audio start]) NSLog(@"noshigram: the call is up but the audio could not start");
    }
    [_delegate tgcRuntime:self didChangeState:state];
}

- (void)receiveSignaling:(NSData *)data {
    NSData *copy = [data copy];
    dispatch_async(_queue, ^{
        if (!_stopped) {
            noshi_status status = noshi_tgc_call_signaling(_call, copy.bytes, copy.length, NoshiTgcNowMs());
            if (status != NOSHI_OK && status != NOSHI_E_RETRY) NSLog(@"noshigram: tgcalls signaling refused (%s)", noshi_status_name(status));
        }
        [copy release];
    });
}

- (void)setMuted:(BOOL)muted {
    dispatch_async(_queue, ^{
        if (_stopped) return;
        _muted = muted;
        _audio.muted = muted;
        noshi_tgc_call_set_muted(_call, muted ? 1 : 0, NoshiTgcNowMs());
    });
}

@synthesize video = _video;

- (BOOL)cameraOn { return _cameraOn; }

- (void)setCameraOn:(BOOL)on completion:(void (^)(BOOL))completion {
    void (^done)(BOOL) = [completion copy];
    /* the capture session and the status bar orientation belong to the main thread */
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL ok = YES;
        if (_stopped) {
            if (done) done(NO);
            [done release];
            return;
        }
        if (on) ok = [_video startCamera];
        else [_video stopCamera];
        if (ok) _cameraOn = on;
        dispatch_async(_queue, ^{
            /* a camera that would not start leaves the channel withdrawn, so the other phone does not wait for a picture */
            if (!_stopped) noshi_tgc_call_set_video(_call, on && ok ? 1 : 0, 0, NoshiTgcNowMs());
        });
        if (done) done(ok);
        [done release];
    });
}

- (void)stop {
    size_t i;
    if (!_queue) return;
    dispatch_sync(_queue, ^{
        _stopped = YES;
        _delegate = nil;
    });
    if (_timer) {
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
        _timer = NULL;
    }
    for (i = 0; i < _socketCount; ++i) {
        if (_sockets[i].source) {
            dispatch_source_cancel(_sockets[i].source);
            dispatch_release(_sockets[i].source);
            _sockets[i].source = NULL;
        }
    }
    /* what the sources had queued runs out before the sockets close and the call goes */
    dispatch_sync(_queue, ^{});
    for (i = 0; i < _socketCount; ++i) {
        if (_sockets[i].fd >= 0) {
            close(_sockets[i].fd);
            _sockets[i].fd = -1;
        }
    }
    [_audio stop];
    [_audio release];
    _audio = nil;
    [_video stop];
    noshi_tgc_call_free(_call);
    _call = NULL;
    if (_trace) {
        fclose(_trace);
        _trace = NULL;
    }
}

@end

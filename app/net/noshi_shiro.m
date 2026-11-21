#import "noshi_shiro.h"
#import "noshi_traffic_store.h"
#include "noshi_mt_traffic.h"

#import <UIKit/UIKit.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <pthread.h>
#include <stdarg.h>
#include <sys/utsname.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "noshi_bytes.h"
#include "noshi_dns.h"
#include "noshi_https.h"
#include "noshi_random.h"
#include "noshi_shiro_engine.h"
#include "noshi_shiro_store.h"
#include "noshi_warp.h"

#import "noshi_files.h"
#import "noshi_shiro_network.h"

NSString *const NoshiShiroStateDidChangeNotification = @"NoshiShiroStateDidChange";
static NSString *const NoshiShiroEnabledKey = @"noshigram.shiro.enabled";
static NSString *const NoshiShiroAccountFile = @"shiro.account";

/* the registration call of the account; the path carries the version of the API and the header the build of the
   official client it was taken from, so they change together */
#define REGISTRATION_HOST "api.cloudflareclient.com"
#define REGISTRATION_PORT 443
#define REGISTRATION_PATH "/v0a4471/reg"
#define REGISTRATION_VERSION "CF-Client-Version: a-6.38-4471"
#define REGISTRATION_TIMEOUT_MS 12000
/* the call failed at once, which a device does at launch while its radio or wifi is still coming up (getaddrinfo answers at once with nothing): the round is tried again after
   a pause, three more times, and a failure that took longer than this is a dead path and is not waited on */
#define REGISTRATION_ROUNDS 4
#define REGISTRATION_QUICK_FAIL_MS 3000
#define REGISTRATION_PAUSE_MS 1500
/* the first servers are the ones of the account, the rest are drawn; a silent network stops here instead of dialing for ever */
#define SERVER_ATTEMPTS 5u
/* after that many servers without an answer the tunnel is tried again on its own, this many times, the first pause being this long and each next one twice as long */
#define AUTO_RETRIES_MAX 3u
#define AUTO_RETRY_FIRST_SECONDS 15u
/* how often the addresses of this phone are looked at to see that the network changed */
#define PATH_WATCH_SECONDS 3.0
/* the journal keeps the last lines of a run, so a report of a failure carries how it came about */
#define LOG_LINES_MAX 400u
#define LOG_LINES_DROP 100u
#define INSTALL_ID_ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

typedef struct {
    NoshiShiro *owner;
    uint32_t run;
    uint32_t serial;
} NoshiShiroContext;

@interface NoshiShiro () {
    NSString *_directory;
    /* account file, registration, and the start and stop of engines, one after another */
    dispatch_queue_t _queue;
    /* a stream is opened under the read side, so an engine cannot be freed while a caller is inside it; main never takes the write side */
    pthread_rwlock_t _engineLock;
    noshi_shiro_engine *_engine;
    /* queue only */
    NoshiShiroContext *_context;
    noshi_warp_identity _identity;
    BOOL _identityLoaded;
    /* guards what other threads read: the route and the run that is still wanted */
    NSLock *_stateLock;
    NoshiShiroRoute _route;
    uint32_t _liveRun;
    /* main thread only */
    NoshiShiroState _state;
    NoshiShiroFailure _failure;
    NSString *_failureDetail;
    NSString *_failureText;
    NSLock *_logLock;
    NSMutableArray *_log;
    /* queue only: the status line of the last registration call, for the words of the failure */
    int _registrationHttp;
    BOOL _enabled;
    uint32_t _run;
    /* every engine start gets a number, so a late word from an engine that was replaced is told apart */
    uint32_t _serial;
    unsigned _attempt;
    NoshiShiroStats _lastStats;
    /* main thread only: the watch on the network path, and the tries that follow a tunnel that did not open */
    NSTimer *_pathTimer;
    NSString *_pathSignature;
    NSString *_pathCandidate;
    unsigned _autoRetries;
}
@end

@implementation NoshiShiro

@synthesize state = _state;
@synthesize failure = _failure;
@synthesize enabled = _enabled;

- (id)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _directory = [directory copy];
    _queue = dispatch_queue_create("noshigram.shiro", NULL);
    pthread_rwlock_init(&_engineLock, NULL);
    _stateLock = [[NSLock alloc] init];
    _logLock = [[NSLock alloc] init];
    _log = [[NSMutableArray alloc] init];
    _enabled = [[NSUserDefaults standardUserDefaults] boolForKey:NoshiShiroEnabledKey];
    /* a launch with the VPN wanted starts blocked, so nothing is sent before the tunnel is up */
    _route = _enabled ? NoshiShiroRouteBlocked : NoshiShiroRouteDirect;
    return self;
}

- (void)dealloc {
    [_pathTimer invalidate];
    [_pathSignature release];
    [_pathCandidate release];
    /* every queued block holds self, so the queue is idle here; dispatch_sync would deadlock when the last release comes from a block on that queue */
    [self stopEngine];
    dispatch_release(_queue);
    pthread_rwlock_destroy(&_engineLock);
    noshi_wipe(&_identity, sizeof(_identity));
    [_stateLock release];
    [_directory release];
    [_failureDetail release];
    [_failureText release];
    [_log release];
    [_logLock release];
    [super dealloc];
}

#pragma mark journal

static void NoshiShiroStamp(char out[16]) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    time_t seconds = (time_t)now;
    struct tm parts;
    gmtime_r(&seconds, &parts);
    int millis = (int)((now - (NSTimeInterval)seconds) * 1000.0);
    if (millis < 0 || millis > 999) millis = 0;
    snprintf(out, 16, "%02d:%02d:%02d.%03d", parts.tm_hour, parts.tm_min, parts.tm_sec, millis);
}

/* any thread: the engine reports from its own */
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    va_end(arguments);
    char stamp[16];
    NoshiShiroStamp(stamp);
    NSLog(@"noshigram: shiro: %@", text);
    [_logLock lock];
    [_log addObject:[NSString stringWithFormat:@"%s %@", stamp, text]];
    if (_log.count > LOG_LINES_MAX) [_log removeObjectsInRange:NSMakeRange(0, LOG_LINES_DROP)];
    [_logLock unlock];
}

- (NSString *)logText {
    struct utsname machine;
    uname(&machine);
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *state[] = {@"off", @"registering", @"connecting", @"up", @"failed"};
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"Noshigram %@ (%@)\n", [info objectForKey:@"CFBundleShortVersionString"], [info objectForKey:@"CFBundleVersion"]];
    [text appendFormat:@"%s, iOS %@, %@ network\n", machine.machine, [[UIDevice currentDevice] systemVersion], NoshiNetworkOnCellular() ? @"cellular" : @"other"];
    NoshiShiroState now = _state;
    [text appendFormat:@"shiro: %@%@%@\n", state[now], _failureDetail.length ? @", " : @"", _failureDetail ? _failureDetail : @""];
    [_logLock lock];
    for (NSString *line in _log) [text appendFormat:@"%@\n", line];
    [_logLock unlock];
    return text;
}

#pragma mark state

- (NoshiShiroRoute)route {
    [_stateLock lock];
    NoshiShiroRoute route = _route;
    [_stateLock unlock];
    return route;
}

- (BOOL)runIsLive:(uint32_t)run {
    [_stateLock lock];
    BOOL live = _liveRun == run;
    [_stateLock unlock];
    return live;
}

/* main thread */
- (uint32_t)newRun {
    ++_run;
    [_stateLock lock];
    _liveRun = _run;
    [_stateLock unlock];
    return _run;
}

- (void)setState:(NoshiShiroState)state failure:(NoshiShiroFailure)failure {
    _state = state;
    _failure = failure;
    NoshiShiroRoute route = !_enabled ? NoshiShiroRouteDirect : (state == NoshiShiroStateUp ? NoshiShiroRouteTunnel : NoshiShiroRouteBlocked);
    [_stateLock lock];
    _route = route;
    [_stateLock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiShiroStateDidChangeNotification object:self];
}

- (void)resume {
    if (_enabled) [self begin];
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) return;
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:NoshiShiroEnabledKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the VPN switch was not saved");
    if (enabled) {
        _autoRetries = 0;
        [self begin];
        return;
    }
    [self stopPathWatch];
    [self newRun];
    [self setState:NoshiShiroStateOff failure:NoshiShiroFailureNone];
    dispatch_async(_queue, ^{ [self stopEngine]; });
}

- (void)retry {
    if (!_enabled || _state != NoshiShiroStateFailed) return;
    _autoRetries = 0;
    /* a key the server refused is the account's own, so the try that follows makes a new account */
    [self beginDiscardingAccount:_failure == NoshiShiroFailureKey];
}

- (void)begin {
    [self beginDiscardingAccount:NO];
}

- (void)beginDiscardingAccount:(BOOL)discard {
    [self startPathWatch];
    uint32_t run = [self newRun];
    uint32_t serial = ++_serial;
    _attempt = 0;
    [self log:@"start, run %u%@", run, discard ? @", the stored account is dropped" : @""];
    [self setState:NoshiShiroStateConnecting failure:NoshiShiroFailureNone];
    dispatch_async(_queue, ^{ [self prepareRun:run serial:serial discardAccount:discard]; });
}

- (NSString *)failureDetail {
    return _failureDetail;
}

- (NSString *)failureText {
    return _failureText;
}

- (void)failRun:(uint32_t)run with:(NoshiShiroFailure)failure detail:(NSString *)detail text:(NSString *)text {
    if (run != _run || !_enabled) return;
    [self log:@"failed: %@", detail];
    [_failureDetail release];
    _failureDetail = [detail copy];
    [_failureText release];
    _failureText = [text copy];
    [self newRun];
    [self setState:NoshiShiroStateFailed failure:failure];
    dispatch_async(_queue, ^{ [self stopEngine]; });
}

- (void)registeringRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:NoshiShiroStateRegistering failure:NoshiShiroFailureNone];
}

- (void)connectingRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:NoshiShiroStateConnecting failure:NoshiShiroFailureNone];
}

#pragma mark network path

/* the addresses of the interfaces that reach the world (Wi-Fi and cellular), as one line: it changes when the phone moves from one network to another, and a tunnel that was
   made on the old one is dead although its socket does not say so */
static NSString *NoshiShiroPathSignature(void) {
    struct ifaddrs *list = NULL;
    NSMutableArray *parts = [NSMutableArray array];
    if (getifaddrs(&list) != 0) return @"";
    for (struct ifaddrs *item = list; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET || !(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK)) continue;
        if (strncmp(item->ifa_name, "en", 2) != 0 && strncmp(item->ifa_name, "pdp_ip", 6) != 0) continue;
        uint32_t address = ntohl(((struct sockaddr_in *)item->ifa_addr)->sin_addr.s_addr);
        /* a link-local address is what an interface has while it has none yet */
        if ((address >> 16) == 0xA9FE || address == 0) continue;
        [parts addObject:[NSString stringWithFormat:@"%s=%u.%u.%u.%u", item->ifa_name, address >> 24, (address >> 16) & 255u, (address >> 8) & 255u, address & 255u]];
    }
    freeifaddrs(list);
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@","];
}

- (void)startPathWatch {
    if (_pathTimer) return;
    [_pathSignature release];
    _pathSignature = [NoshiShiroPathSignature() retain];
    [_pathCandidate release];
    _pathCandidate = nil;
    _pathTimer = [[NSTimer scheduledTimerWithTimeInterval:PATH_WATCH_SECONDS target:self selector:@selector(pathTick) userInfo:nil repeats:YES] retain];
}

- (void)stopPathWatch {
    [_pathTimer invalidate];
    [_pathTimer release];
    _pathTimer = nil;
    [_pathCandidate release];
    _pathCandidate = nil;
}

- (void)pathTick {
    if (!_enabled) {
        [self stopPathWatch];
        return;
    }
    NSString *now = NoshiShiroPathSignature();
    if ([now isEqualToString:_pathSignature]) {
        [_pathCandidate release];
        _pathCandidate = nil;
        return;
    }
    /* a change is acted on when the next look finds the same, so an interface that flickers does not restart the tunnel again and again */
    if (![now isEqualToString:_pathCandidate]) {
        [_pathCandidate release];
        _pathCandidate = [now copy];
        return;
    }
    [_pathSignature release];
    _pathSignature = [now retain];
    [_pathCandidate release];
    _pathCandidate = nil;
    /* no address at all is a phone with no network: the tunnel stays as it is, and starts again when an address is back */
    if (!now.length) {
        [self log:@"the network is gone"];
        return;
    }
    if (_state == NoshiShiroStateOff) return;
    [self log:@"the network changed (%@), the tunnel starts again", now];
    _autoRetries = 0;
    [self beginDiscardingAccount:NO];
}

/* main thread, from the engine's callback */
- (void)engineState:(noshi_shiro_state)state reason:(noshi_status)reason run:(uint32_t)run serial:(uint32_t)serial {
    if (run != _run || serial != _serial || !_enabled) return;
    if (state == NOSHI_SHIRO_UP) {
        _attempt = 0;
        _autoRetries = 0;
        [self log:@"the tunnel is up"];
        [self setState:NoshiShiroStateUp failure:NoshiShiroFailureNone];
        return;
    }
    if (state != NOSHI_SHIRO_DOWN) return;
    BOOL wasUp = _state == NoshiShiroStateUp;
    /* a tunnel that was working starts again from the account's own server; one that never answered goes on to the next server */
    _attempt = wasUp ? 0 : _attempt + 1;
    if (_attempt >= SERVER_ATTEMPTS && reason != NOSHI_E_SECURITY && _autoRetries < AUTO_RETRIES_MAX) {
        /* a network that did not answer five servers may only be one that is changing (a lift, a tunnel, a switch from Wi-Fi to the cellular): the tunnel is tried again after a
           pause that grows, with the traffic still blocked, before the person is told that it failed */
        unsigned pause = AUTO_RETRY_FIRST_SECONDS << _autoRetries++;
        uint32_t waiting = run;
        [self log:@"no server answered, trying again in %u s (%u of %u)", pause, _autoRetries, AUTO_RETRIES_MAX];
        _attempt = 0;
        [self setState:NoshiShiroStateConnecting failure:NoshiShiroFailureNone];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)pause * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            /* nothing else began or ended the run meanwhile */
            if (waiting != _run || !_enabled || _state != NoshiShiroStateConnecting) return;
            [self beginDiscardingAccount:NO];
        });
        return;
    }
    if (_attempt >= SERVER_ATTEMPTS) {
        BOOL refused = reason == NOSHI_E_SECURITY;
        [self failRun:run with:refused ? NoshiShiroFailureKey : NoshiShiroFailureServer
               detail:[NSString stringWithFormat:@"tunnel: %s", noshi_status_name(reason)]
                 text:NSLocalizedString(refused ? @"shiro.why.key" : @"shiro.why.server", nil)];
        return;
    }
    [self log:@"the tunnel went down (%s), next server is %u", noshi_status_name(reason), _attempt];
    uint32_t next = ++_serial;
    unsigned attempt = _attempt;
    [self setState:NoshiShiroStateConnecting failure:NoshiShiroFailureNone];
    dispatch_async(_queue, ^{ [self startEngineForRun:run serial:next attempt:attempt]; });
}

static void NoshiShiroEngineState(void *context, noshi_shiro_state state, noshi_status reason) {
    NoshiShiroContext *c = context;
    NoshiShiro *owner = c->owner;
    uint32_t run = c->run, serial = c->serial;
    dispatch_async(dispatch_get_main_queue(), ^{ [owner engineState:state reason:reason run:run serial:serial]; });
}

static void NoshiShiroEngineTrace(void *context, const char *line) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NoshiShiroContext *c = context;
    [c->owner log:@"engine: %s", line];
    [pool drain];
}

#pragma mark queue

- (NSString *)accountPath {
    return NoshiFilePath(_directory, NoshiShiroAccountFile);
}

/* NOSHI_E_NOTFOUND when there is no usable account; an unreadable one is deleted, since only a new registration repairs it */
- (noshi_status)loadIdentity {
    uint8_t buf[NOSHI_SHIRO_STORE_LEN + 1];
    size_t len = 0;
    noshi_status status = NoshiReadFile([self accountPath], buf, sizeof(buf), &len);
    if (status != NOSHI_OK) return status;
    status = noshi_shiro_store_unpack(buf, len, &_identity);
    noshi_wipe(buf, sizeof(buf));
    if (status != NOSHI_OK) {
        [self log:@"account: the stored one is unusable, registering a new one"];
        unlink([self accountPath].fileSystemRepresentation);
        return NOSHI_E_NOTFOUND;
    }
    return NOSHI_OK;
}

- (noshi_status)storeIdentity {
    uint8_t buf[NOSHI_SHIRO_STORE_LEN];
    size_t len = 0;
    noshi_status status = noshi_shiro_store_pack(&_identity, buf, sizeof(buf), &len);
    if (status == NOSHI_OK) status = NoshiWriteFile([self accountPath], buf, len);
    noshi_wipe(buf, sizeof(buf));
    return status;
}

static noshi_status NoshiShiroInstallId(char id[NOSHI_WARP_INSTALL_ID_LEN + 1]) {
    size_t filled = 0;
    for (int round = 0; round < 8 && filled < NOSHI_WARP_INSTALL_ID_LEN; ++round) {
        uint8_t raw[32];
        if (noshi_random(raw, sizeof(raw)) != NOSHI_OK) return NOSHI_E_CRYPTO;
        for (size_t i = 0; i < sizeof(raw) && filled < NOSHI_WARP_INSTALL_ID_LEN; ++i) {
            /* 248 is the largest multiple of 62 in a byte, so the letters come out evenly */
            if (raw[i] < 248) id[filled++] = INSTALL_ID_ALPHABET[raw[i] % 62];
        }
    }
    id[filled] = '\0';
    return filled == NOSHI_WARP_INSTALL_ID_LEN ? NOSHI_OK : NOSHI_E_CRYPTO;
}

static void NoshiShiroTimestamp(char out[32]) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    time_t seconds = (time_t)now;
    struct tm parts;
    gmtime_r(&seconds, &parts);
    int millis = (int)((now - (NSTimeInterval)seconds) * 1000.0);
    if (millis < 0 || millis > 999) millis = 0;
    snprintf(out, 32, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec,
             millis);
}

/* what the resolver says of a host, for the log of a call that failed before it could have reached the network */
- (void)logResolutionOfHost:(const char *)host {
    struct addrinfo hints, *list = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int rc = getaddrinfo(host, "443", &hints, &list);
    if (rc != 0 || !list) {
        [self log:@"registration: the resolver gave nothing for %s: %s", host, rc ? gai_strerror(rc) : "empty list"];
        return;
    }
    int v4 = 0, v6 = 0;
    for (struct addrinfo *ai = list; ai; ai = ai->ai_next) {
        if (ai->ai_family == AF_INET) ++v4;
        else if (ai->ai_family == AF_INET6) ++v6;
    }
    freeaddrinfo(list);
    [self log:@"registration: the resolver gave %d IPv4 and %d IPv6 addresses for %s, so the connect or the handshake failed", v4, v6, host];
}

/* makes the account on the first start */
- (noshi_status)registerIdentityForRun:(uint32_t)run {
    NSString *rootsPath = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    NSData *roots = rootsPath ? [NSData dataWithContentsOfFile:rootsPath] : nil;
    _registrationHttp = 0;
    if (![roots length]) {
        [self log:@"registration: the bundled roots are missing"];
        return NOSHI_E_NOTFOUND;
    }

    uint8_t privateKey[NOSHI_WG_KEY_LEN], publicKey[NOSHI_WG_KEY_LEN];
    char installId[NOSHI_WARP_INSTALL_ID_LEN + 1], tos[32], body[1024];
    size_t bodyLen = 0;
    noshi_status status = noshi_warp_generate_key(privateKey, publicKey);
    if (status == NOSHI_OK) status = NoshiShiroInstallId(installId);
    if (status != NOSHI_OK) goto done;
    NoshiShiroTimestamp(tos);
    status = noshi_warp_registration_body(publicKey, installId, tos, body, sizeof(body), &bodyLen);
    if (status != NOSHI_OK) goto done;

    static const char *const headers[] = {"Content-Type: application/json; charset=UTF-8", "User-Agent: okhttp/3.12.1", REGISTRATION_VERSION, NULL};
    noshi_https_request request;
    noshi_https_response response;
    memset(&request, 0, sizeof(request));
    request.host = REGISTRATION_HOST;
    request.port = REGISTRATION_PORT;
    request.path = REGISTRATION_PATH;
    request.headers = headers;
    request.body = (const uint8_t *)body;
    request.body_len = bodyLen;
    request.roots_pem = roots.bytes;
    request.roots_len = roots.length;
    request.timeout_ms = REGISTRATION_TIMEOUT_MS;
    for (int round = 0; round < REGISTRATION_ROUNDS; ++round) {
        if (round) {
            /* a pause that ends as soon as the run does, in slices, so a cancel is not held up */
            for (int waited = 0; waited < REGISTRATION_PAUSE_MS * round; waited += 100) {
                if (![self runIsLive:run]) {
                    status = NOSHI_E_STATE;
                    goto done;
                }
                usleep(100 * 1000);
            }
        }
        CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
        /* the byebyedpi layer: a network that reads the SNI of one record or one segment drops the plain hello, so the account call starts with the hello cut inside the
           name (the tlsrec strategy), then cut at the middle, then in small pieces, and only then whole. a cut hello keeps the handshake as it was, so the first one that
           gets through is the one that is used; only a path that does not answer is worth the next */
        static const struct { int mode; const char *name; } hellos[] = {
            {NOSHI_HELLO_RECORD, "cut in the SNI"}, {NOSHI_HELLO_RECORD_MIDDLE, "cut in the middle of the SNI"},
            {NOSHI_HELLO_PIECES, "in pieces"}, {NOSHI_HELLO_WHOLE, "whole"}};
        for (size_t attempt = 0; attempt < sizeof(hellos) / sizeof(hellos[0]); ++attempt) {
            if (![self runIsLive:run]) {
                status = NOSHI_E_STATE;
                goto done;
            }
            request.split_hello = hellos[attempt].mode;
            status = noshi_https_post(&request, &response);
            [self log:@"registration: call to %s, hello %s: %s", REGISTRATION_HOST, hellos[attempt].name, noshi_status_name(status)];
            if (status == NOSHI_OK || (status != NOSHI_E_IO && status != NOSHI_E_TIMEOUT)) break;
        }
        if (status != NOSHI_E_IO || (CFAbsoluteTimeGetCurrent() - began) * 1000.0 > REGISTRATION_QUICK_FAIL_MS) break;
        [self logResolutionOfHost:REGISTRATION_HOST];
    }
    if (status != NOSHI_OK) goto done;
    _registrationHttp = response.status;
    if (response.status < 200 || response.status > 299) {
        [self log:@"registration: the call answered HTTP %d, %zu bytes", response.status, response.body_len];
        status = NOSHI_E_RPC;
    } else {
        status = noshi_warp_parse_registration((const char *)response.body, response.body_len, privateKey, &_identity);
        [self log:@"registration: the answer was read: %s", noshi_status_name(status)];
    }
    noshi_https_response_free(&response);
    if (status == NOSHI_OK) {
        status = [self storeIdentity];
        if (status != NOSHI_OK) noshi_wipe(&_identity, sizeof(_identity));
    }
done:
    noshi_wipe(privateKey, sizeof(privateKey));
    return status;
}

/* what the person is told when the account could not be made, by what stopped it */
- (NSString *)registrationTextForStatus:(noshi_status)status {
    switch (status) {
    case NOSHI_E_IO:
    case NOSHI_E_TIMEOUT: return NSLocalizedString(@"shiro.why.account.net", nil);
    case NOSHI_E_SECURITY: return NSLocalizedString(@"shiro.why.account.tls", nil);
    case NOSHI_E_RPC: return [NSString stringWithFormat:NSLocalizedString(@"shiro.why.account.refused", nil), _registrationHttp];
    case NOSHI_E_MALFORMED: return NSLocalizedString(@"shiro.why.account.answer", nil);
    case NOSHI_E_NOTFOUND: return NSLocalizedString(@"shiro.why.account.roots", nil);
    default: return NSLocalizedString(@"shiro.why.account.other", nil);
    }
}

- (void)prepareRun:(uint32_t)run serial:(uint32_t)serial discardAccount:(BOOL)discard {
    if (![self runIsLive:run]) return;
    if (discard) {
        unlink([self accountPath].fileSystemRepresentation);
        noshi_wipe(&_identity, sizeof(_identity));
        _identityLoaded = NO;
    }
    if (!_identityLoaded) {
        noshi_status status = [self loadIdentity];
        if (status == NOSHI_E_NOTFOUND) {
            [self log:@"account: none stored, registering"];
            dispatch_async(dispatch_get_main_queue(), ^{ [self registeringRun:run]; });
            status = [self registerIdentityForRun:run];
            if (status != NOSHI_OK) [self log:@"registration failed: %s", noshi_status_name(status)];
            dispatch_async(dispatch_get_main_queue(), ^{ [self connectingRun:run]; });
        } else if (status == NOSHI_OK) {
            [self log:@"account: loaded from the file"];
        }
        if (status != NOSHI_OK) {
            NSString *detail = [NSString stringWithFormat:@"account: %s", noshi_status_name(status)];
            NSString *text = [self registrationTextForStatus:status];
            dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:NoshiShiroFailureAccount detail:detail text:text]; });
            return;
        }
        _identityLoaded = YES;
    }
    [self startEngineForRun:run serial:serial attempt:0];
}

- (void)startEngineForRun:(uint32_t)run serial:(uint32_t)serial attempt:(unsigned)attempt {
    [self stopEngine];
    /* a run that ended while this block waited its turn must not bring a tunnel up */
    if (![self runIsLive:run]) return;
    uint32_t ip = 0;
    uint16_t port = 0;
    noshi_status status = noshi_warp_endpoint(&_identity, attempt, &ip, &port);
    if (status == NOSHI_OK) [self log:@"engine: server %u.%u.%u.%u:%u, try %u", ip >> 24, (ip >> 16) & 255u, (ip >> 8) & 255u, ip & 255u, port, attempt + 1u];
    NoshiShiroContext *context = status == NOSHI_OK ? calloc(1, sizeof(*context)) : NULL;
    noshi_shiro_engine *engine = NULL;
    if (context) {
        context->owner = self;
        context->run = run;
        context->serial = serial;
        noshi_shiro_events events = {context, NoshiShiroEngineState, NoshiShiroEngineTrace};
        status = noshi_shiro_engine_start(&engine, &_identity, ip, port, &events);
    } else if (status == NOSHI_OK) {
        status = NOSHI_E_NOMEM;
    }
    if (status != NOSHI_OK) {
        [self log:@"the engine did not start: %s", noshi_status_name(status)];
        free(context);
        NSString *detail = [NSString stringWithFormat:@"engine: %s", noshi_status_name(status)];
        NSString *text = NSLocalizedString(@"shiro.why.engine", nil);
        dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:NoshiShiroFailureServer detail:detail text:text]; });
        return;
    }
    pthread_rwlock_wrlock(&_engineLock);
    _engine = engine;
    pthread_rwlock_unlock(&_engineLock);
    _context = context;
}

/* queue only; the write side waits for the streams that are being opened, then the engine ends them and joins its
   thread, so no callback comes after it */
- (void)stopEngine {
    pthread_rwlock_wrlock(&_engineLock);
    noshi_shiro_engine *engine = _engine;
    _engine = NULL;
    if (engine) noshi_shiro_engine_stop(engine);
    pthread_rwlock_unlock(&_engineLock);
    free(_context);
    _context = NULL;
}

#pragma mark use

- (BOOL)stats:(NoshiShiroStats *)stats {
    if (_state != NoshiShiroStateUp || pthread_rwlock_tryrdlock(&_engineLock) != 0) {
        if (stats) *stats = _lastStats;
        return NO;
    }
    BOOL got = NO;
    if (_engine) {
        noshi_shiro_stats raw;
        memset(&raw, 0, sizeof(raw));
        noshi_shiro_engine_stats(_engine, &raw);
        _lastStats.bytesIn = raw.bytes_in;
        _lastStats.bytesOut = raw.bytes_out;
        _lastStats.ageMs = raw.session_age_ms;
        _lastStats.handshakes = raw.handshakes;
        got = YES;
    }
    pthread_rwlock_unlock(&_engineLock);
    if (stats) *stats = _lastStats;
    return got;
}

/* resolve through the tunnel to avoid leaking DNS, and cache briefly because map tiles share a few hosts */
#define RESOLVER_ADDRESS 0x01010101u
#define NAME_KEEP_MAX 300

static NSMutableDictionary *NoshiShiroNames;

- (noshi_status)resolveName:(const char *)host timeout:(int)timeoutMs address:(uint32_t *)address {
    NSString *key = [[NSString stringWithUTF8String:host] lowercaseString];
    if (!key.length || !address) return NOSHI_E_ARG;
    @synchronized([NoshiShiro class]) {
        NSDictionary *known = [NoshiShiroNames objectForKey:key];
        if ([[known objectForKey:@"expires"] timeIntervalSinceNow] > 0) {
            *address = [[known objectForKey:@"ip"] unsignedIntValue];
            return NOSHI_OK;
        }
    }
    uint8_t packet[2 + NOSHI_DNS_QUERY_MAX], reply[2 + NOSHI_DNS_ANSWER_MAX];
    size_t length = 0, have = 0, want = 2;
    uint16_t identifier = 0;
    uint32_t ip = 0, life = 0;
    noshi_status status = noshi_random(&identifier, sizeof(identifier));
    if (status == NOSHI_OK) status = noshi_dns_query_a(host, identifier, packet + 2, sizeof(packet) - 2, &length);
    if (status != NOSHI_OK) return status;
    packet[0] = (uint8_t)(length >> 8);
    packet[1] = (uint8_t)length;
    int fd = -1;
    status = [self openStreamToAddress:RESOLVER_ADDRESS port:53 timeout:timeoutMs descriptor:&fd];
    if (status != NOSHI_OK) return status;
    noshi_mt_socket socket;
    noshi_mt_socket_init(&socket);
    status = noshi_mt_socket_adopt(&socket, fd);
    if (status != NOSHI_OK) {
        close(fd);
        return status;
    }
    status = noshi_mt_socket_write_all(&socket, packet, length + 2, timeoutMs);
    /* a TCP answer is two bytes of length and the message, and may arrive in pieces */
    while (status == NOSHI_OK && have < want) {
        size_t got = 0;
        status = noshi_mt_socket_read(&socket, reply + have, want - have, &got, timeoutMs);
        if (status != NOSHI_OK) break;
        have += got;
        if (want == 2 && have == 2) {
            want = 2 + (((size_t)reply[0] << 8) | reply[1]);
            if (want == 2 || want > sizeof(reply)) status = NOSHI_E_MALFORMED;
        }
    }
    noshi_mt_socket_close(&socket);
    if (status == NOSHI_E_EOF) status = NOSHI_E_IO;
    if (status != NOSHI_OK) return status;
    status = noshi_dns_answer_a(reply + 2, want - 2, identifier, &ip, &life);
    if (status != NOSHI_OK) return status;
    @synchronized([NoshiShiro class]) {
        if (!NoshiShiroNames) NoshiShiroNames = [[NSMutableDictionary alloc] init];
        if (NoshiShiroNames.count > 64) [NoshiShiroNames removeAllObjects];
        [NoshiShiroNames setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:ip], @"ip",
                                      [NSDate dateWithTimeIntervalSinceNow:MIN(life, (uint32_t)NAME_KEEP_MAX)], @"expires", nil] forKey:key];
    }
    *address = ip;
    return NOSHI_OK;
}

- (noshi_status)openStreamToHost:(const char *)host port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd {
    uint32_t ip = 0;
    if (fd) *fd = -1;
    if (!host || !fd) return NOSHI_E_ARG;
    /* the data centers of Telegram are addresses; a name is asked of the resolver through the tunnel */
    if (noshi_warp_parse_ipv4(host, strlen(host), &ip) != NOSHI_OK) {
        noshi_status status = [self resolveName:host timeout:timeoutMs address:&ip];
        if (status != NOSHI_OK) return status;
    }
    return [self openStreamToAddress:ip port:port timeout:timeoutMs descriptor:fd];
}

- (noshi_status)openStreamToAddress:(uint32_t)ip port:(uint16_t)port timeout:(int)timeoutMs descriptor:(int *)fd {
    if (fd) *fd = -1;
    if (!fd) return NOSHI_E_ARG;
    if (self.route != NoshiShiroRouteTunnel) return NOSHI_E_STATE;
    /* the engine is held only while the stream is queued: the wait for the far side (seconds, on a bad network) used to be made under the read side, so a turn off
       waited for every stream that was still dialing, and with a writer waiting the new calls queued up behind it as well */
    int waitFd = -1;
    uint64_t deadline = 0;
    pthread_rwlock_rdlock(&_engineLock);
    noshi_status status = _engine ? noshi_shiro_engine_dial(_engine, ip, port, timeoutMs, &waitFd, &deadline) : NOSHI_E_STATE;
    pthread_rwlock_unlock(&_engineLock);
    if (status != NOSHI_OK) return status;
    return noshi_shiro_dial_finish(waitFd, deadline, fd);
}

- (BOOL)transferredIn:(unsigned long long *)bytesIn out:(unsigned long long *)bytesOut {
    BOOL got = NO;
    if (bytesIn) *bytesIn = 0;
    if (bytesOut) *bytesOut = 0;
    if (pthread_rwlock_tryrdlock(&_engineLock) != 0) return NO;
    if (_engine) {
        noshi_shiro_stats raw;
        memset(&raw, 0, sizeof(raw));
        noshi_shiro_engine_stats(_engine, &raw);
        if (bytesIn) *bytesIn = raw.bytes_in;
        if (bytesOut) *bytesOut = raw.bytes_out;
        got = YES;
    }
    pthread_rwlock_unlock(&_engineLock);
    return got;
}

- (noshi_status)openDatagramDescriptor:(int *)fd {
    if (fd) *fd = -1;
    if (!fd) return NOSHI_E_ARG;
    if (self.route != NoshiShiroRouteTunnel) return NOSHI_E_STATE;
    pthread_rwlock_rdlock(&_engineLock);
    noshi_status status = _engine ? noshi_shiro_engine_open_udp(_engine, fd) : NOSHI_E_STATE;
    pthread_rwlock_unlock(&_engineLock);
    return status;
}

@end

noshi_status NoshiShiroConnectSocket(NoshiShiro *shiro, noshi_mt_socket *socket, const char *host, uint16_t port, int timeoutMs, BOOL *tunneled) {
    if (tunneled) *tunneled = NO;
    /* what the new connection carries is counted for the network it was opened on */
    noshi_traffic_set_cellular(NoshiNetworkOnCellular());
    NoshiShiroRoute route = shiro ? shiro.route : NoshiShiroRouteDirect;
    if (route == NoshiShiroRouteDirect) return noshi_mt_socket_connect(socket, host, port, timeoutMs);
    if (route == NoshiShiroRouteBlocked) return NOSHI_E_STATE;
    int fd = -1;
    noshi_status status = [shiro openStreamToHost:host port:port timeout:timeoutMs descriptor:&fd];
    if (status != NOSHI_OK) return status;
    status = noshi_mt_socket_adopt(socket, fd);
    if (status != NOSHI_OK) {
        close(fd);
        return status;
    }
    if (tunneled) *tunneled = YES;
    return NOSHI_OK;
}

/* set once at launch and cleared before the object goes; the readers are the call threads, which the app stops first */
static NoshiShiro *NoshiShiroActiveInstance;

void NoshiShiroSetActive(NoshiShiro *shiro) {
    @synchronized([NoshiShiro class]) { NoshiShiroActiveInstance = shiro; }
}

NoshiShiro *NoshiShiroActive(void) {
    @synchronized([NoshiShiro class]) { return NoshiShiroActiveInstance; }
}

int NoshiShiroNetworkRoute(void) {
    NoshiShiro *shiro = NoshiShiroActiveInstance;
    return shiro ? (int)shiro.route : (int)NoshiShiroRouteDirect;
}

noshi_status NoshiShiroNetworkConnectSocket(noshi_mt_socket *socket, const char *host, uint16_t port, int timeout_ms) {
    NoshiShiro *shiro;
    @synchronized([NoshiShiro class]) { shiro=[NoshiShiroActiveInstance retain]; }
    noshi_status status=NoshiShiroConnectSocket(shiro, socket, host, port, timeout_ms, NULL);
    [shiro release];
    return status;
}

int NoshiShiroNetworkTransferred(unsigned long long *bytesIn, unsigned long long *bytesOut) {
    NoshiShiro *shiro = NoshiShiroActiveInstance;
    if (bytesIn) *bytesIn = 0;
    if (bytesOut) *bytesOut = 0;
    return shiro ? [shiro transferredIn:bytesIn out:bytesOut] : 0;
}

noshi_status NoshiShiroNetworkOpenDatagram(int *fd) {
    NoshiShiro *shiro = NoshiShiroActiveInstance;
    if (fd) *fd = -1;
    return shiro ? [shiro openDatagramDescriptor:fd] : NOSHI_E_STATE;
}

noshi_status NoshiShiroNetworkOpenStream(uint32_t ip, uint16_t port, int timeout_ms, int *fd) {
    NoshiShiro *shiro = NoshiShiroActiveInstance;
    if (fd) *fd = -1;
    return shiro ? [shiro openStreamToAddress:ip port:port timeout:timeout_ms descriptor:fd] : NOSHI_E_STATE;
}

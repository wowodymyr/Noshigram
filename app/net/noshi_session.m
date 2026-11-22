#import "noshi_session_folders.h"
#import "noshi_session.h"

#import "noshi_dialog.h"
#import "noshi_forum_summaries.h"
#import "noshi_files.h"
#import "noshi_media_link.h"
#import "noshi_proxy_settings.h"
#import "noshi_photo.h"
#import "noshi_person.h"
#import "noshi_remote_file.h"
#import "noshi_notifier.h"
#import "noshi_voip_socket.h"
#import "noshi_session_internal.h"
#import "noshi_session_drafts.h"
#import "noshi_rpc.h"
#import "noshi_call_engine.h"
#import "noshi_group_call_engine.h"

#import <UIKit/UIKit.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

#include <limits.h>

#include "noshi_client.h"
#include "noshi_credentials.h"
#include "noshi_device.h"
#include "noshi_dialogs.h"
#include "noshi_people.h"
#include "noshi_mt_socket.h"
#include <sys/socket.h>
#include "noshi_session_file.h"
#include "noshi_session_key.h"
#include "noshi_tl_ids.h"

#define CONNECT_TIMEOUT_MS 10000
#define WRITE_TIMEOUT_MS 15000
/* consecutive failed connections before the worker reports the device offline; a signed in link keeps trying, a login stops */
#define RETRY_LIMIT 4
/* the longest pause between two attempts of a link that keeps trying */
#define RETRY_PAUSE_MAX_MS 30000u
/* the longest sleep between ticks; the client names its own next deadline (ping, pong, request timeouts, login
   waits), commands and a stop come through the wake pipe */
#define POLL_CAP_MS 60000
#define SYNC_RETRY_FIRST_MS 3000
#define SYNC_RETRY_MAX_MS 60000
#define READ_CHUNK 16384
#define READS_PER_WAKE 64
/* the server reports an unknown auth key as a transport error with this code */
#define TRANSPORT_AUTH_KEY_UNKNOWN (-404)
#define RPC_TIMEOUT_MS 30000
#define DIALOGS_PER_REQUEST 100

@interface NoshiAuthEvent ()
- (id)initWithKind:(NoshiAuthEventKind)kind;
- (void)setCodeKind:(NoshiCodeKind)kind length:(NSInteger)length resendAfter:(NSInteger)resendAfter;
- (void)setHint:(NSString *)hint;
- (void)setHasRecovery:(BOOL)has;
- (void)setEmailPattern:(NSString *)pattern;
- (void)setErrorName:(NSString *)name number:(NSInteger)number;
- (void)setUserId:(long long)userId;
- (void)setQrUrl:(NSString *)url expires:(NSTimeInterval)expires;
@end

@implementation NoshiAuthEvent

@synthesize kind = _kind;
@synthesize codeKind = _codeKind;
@synthesize codeLength = _codeLength;
@synthesize resendAfter = _resendAfter;
@synthesize errorNumber = _errorNumber;
@synthesize hint = _hint;
@synthesize errorName = _errorName;
@synthesize userId = _userId;
@synthesize hasRecovery = _hasRecovery;
@synthesize emailPattern = _emailPattern;
@synthesize qrUrl = _qrUrl;
@synthesize qrExpires = _qrExpires;

- (id)initWithKind:(NoshiAuthEventKind)kind {
    self = [super init];
    if (!self) return nil;
    _kind = kind;
    _resendAfter = -1;
    return self;
}

- (void)setCodeKind:(NoshiCodeKind)kind length:(NSInteger)length resendAfter:(NSInteger)resendAfter {
    _codeKind = kind;
    _codeLength = length;
    _resendAfter = resendAfter;
}

- (void)setHint:(NSString *)hint {
    if (hint == _hint) return;
    [_hint release];
    _hint = [hint copy];
}

- (void)setHasRecovery:(BOOL)has {
    _hasRecovery = has;
}

- (void)setEmailPattern:(NSString *)pattern {
    if (pattern == _emailPattern) return;
    [_emailPattern release];
    _emailPattern = [pattern copy];
}

- (void)setErrorName:(NSString *)name number:(NSInteger)number {
    [_errorName release];
    _errorName = [name copy];
    _errorNumber = number;
}

- (void)setUserId:(long long)userId {
    _userId = userId;
}

- (void)setQrUrl:(NSString *)url expires:(NSTimeInterval)expires {
    if (url != _qrUrl) {
        [_qrUrl release];
        _qrUrl = [url copy];
    }
    _qrExpires = expires;
}

- (void)dealloc {
    [_emailPattern release];
    [_hint release];
    [_errorName release];
    [_qrUrl release];
    [super dealloc];
}

@end

@interface NoshiSession () {
    NSString *_directory;
    NoshiPerson *_ownPerson;
    BOOL _ownPersonRead;
    NSLock *_lock;
    NSMutableArray *_commands;
    int _wake[2];
    dispatch_semaphore_t _exited;
    BOOL _started;
    BOOL _stopping;
    BOOL _connected;

    /* everything below belongs to the worker thread */
    noshi_client _client;
    BOOL _clientLive;
    BOOL _linkReported;
    noshi_mt_socket _socket;
    noshi_store *_store;
    int32_t _dc;
    unsigned _failures;
    uint32_t _pingInterval;
    uint64_t _retryAt;
    uint64_t _syncRetryAt;
    uint32_t _syncBackoffMs;
    BOOL _wantLink;
    int32_t _migrateDc;
    BOOL _dropKeyPending;
    BOOL _archiveLoading;
    BOOL _mainListHasMore;
    BOOL _archiveSummaryStale;
    BOOL _archiveSummarySeen;
    uint64_t _archiveSummaryAtMs;
    int32_t _archiveLiveUnread;
    BOOL _archiveLiveMuted;
    int64_t _authorizedAccount;
    int64_t _account;
    NSMutableDictionary *_handlers;
    NSMutableDictionary *_links;
    NSMutableDictionary *_storeObservers;
    /* who put the observer there, compared by address and never used: a screen that is gone must not remove the observer of the one that took its place */
    void (^_changeHook)(void);
    void *_voip;
    NoshiTypingBoard *_typing;
    NoshiForumSummaries *_forumSummaries;
    NSMutableDictionary *_readOutbox;
    /* main thread only: failed sends by chat, see keepUnsentMessage:forDialog: */
    NSMutableDictionary *_unsent;
    /* worker only: the random ids of pending messages whose upload the person stopped, read by the next step of that upload */
    NSMutableSet *_cancelledSends;
    NoshiCallEngine *_calls;
    NoshiGroupCallEngine *_groupCalls;
    NSString *_deviceModel;
    NSString *_systemVersion;
    NSString *_appVersion;
    /* what the device really is, for the way back after a plugin changed the three above */
    NSString *_realDeviceModel;
    NSString *_realSystemVersion;
    NSString *_realAppVersion;
    NSString *_langCode;
    /* the client keeps these pointers for its whole life and rebuilds its handshake preamble from them after a
       data center change */
    char *_cDeviceModel;
    char *_cSystemVersion;
    char *_cAppVersion;
    char *_cLangCode;
}
@end

NSString *const NoshiArchiveSummaryDidChangeNotification = @"NoshiArchiveSummaryDidChange";
NSString *const NoshiForumSummariesDidChangeNotification = @"NoshiForumSummariesDidChange";

NSString *const NoshiSessionConnectionDidChangeNotification = @"NoshiSessionConnectionDidChange";
NSString *const NoshiSessionDialogsUpdatedNotification = @"NoshiSessionDialogsUpdated";

@implementation NoshiSession

@synthesize delegate = _delegate;
@synthesize connected = _connected;
@synthesize callDelegate = _callDelegate;
@synthesize groupCallDelegate = _groupCallDelegate;
@synthesize groupCalls = _groupCalls;
@synthesize directory = _directory;
@synthesize typing = _typing;
@synthesize drafts = _drafts;

NSString *const NoshiReadOutboxDidChangeNotification = @"NoshiReadOutboxDidChange";
NSString *const NoshiUserStatusDidChangeNotification = @"NoshiUserStatusDidChange";
NSString *const NoshiUploadProgressNotification = @"NoshiUploadProgress";
NSString *const NoshiOwnProfileDidChangeNotification = @"NoshiOwnProfileDidChange";

- (int32_t)readOutboxOfKind:(int32_t)kind peer:(long long)peer topic:(int32_t)topic {
    return [[_readOutbox objectForKey:[NSString stringWithFormat:@"%d:%lld:%d", (int)kind, peer, (int)topic]] intValue];
}

static NSString *NoshiUnsentKey(NoshiDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld:%d", (int)dialog.peerKind, dialog.peerId, (int)dialog.topicId];
}

- (void)keepUnsentMessage:(NoshiMessage *)message forDialog:(NoshiDialog *)dialog {
    if (!message || !dialog) return;
    if (!_unsent) _unsent = [[NSMutableDictionary alloc] init];
    NSString *key = NoshiUnsentKey(dialog);
    NSMutableArray *held = [_unsent objectForKey:key];
    if (!held) {
        held = [NSMutableArray array];
        [_unsent setObject:held forKey:key];
    }
    if (![held containsObject:message]) [held addObject:message];
}

- (NSArray *)takeUnsentMessagesForDialog:(NoshiDialog *)dialog {
    NSString *key = NoshiUnsentKey(dialog);
    NSArray *held = [[[_unsent objectForKey:key] copy] autorelease];
    [_unsent removeObjectForKey:key];
    return held ? held : [NSArray array];
}

- (void)noteReadOutbox:(int32_t)maxId ofKind:(int32_t)kind peer:(long long)peer topic:(int32_t)topic {
    if (!_readOutbox) _readOutbox = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%d:%lld:%d", (int)kind, peer, (int)topic];
    if ([[_readOutbox objectForKey:key] intValue] >= maxId) return;
    [_readOutbox setObject:[NSNumber numberWithInt:maxId] forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiReadOutboxDidChangeNotification object:self
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kind], @"kind", [NSNumber numberWithLongLong:peer], @"peer", [NSNumber numberWithInt:topic], @"topic", [NSNumber numberWithInt:maxId], @"maxId", nil]];
}

static uint64_t NoshiNowMs(void) {
    return noshi_system_clock.monotonic_ms(NULL);
}

+ (BOOL)hasAccountInDirectory:(NSString *)directory {
    uint8_t buf[NOSHI_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int32_t dc;
    int64_t account;
    if (NoshiReadFile(NoshiAccountPath(directory), buf, sizeof(buf), &len) != NOSHI_OK) return NO;
    return noshi_account_unpack(buf, len, &dc, &account) == NOSHI_OK;
}

+ (long long)accountIdInDirectory:(NSString *)directory {
    uint8_t buf[NOSHI_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int32_t dc;
    int64_t account = 0;
    if (NoshiReadFile(NoshiAccountPath(directory), buf, sizeof(buf), &len) != NOSHI_OK) return 0;
    if (noshi_account_unpack(buf, len, &dc, &account) != NOSHI_OK) return 0;
    return account;
}

static NSString *NoshiMachineName(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0 || size > 64) return nil;
    char name[64];
    if (sysctlbyname("hw.machine", name, &size, NULL, 0) != 0) return nil;
    name[sizeof(name) - 1] = '\0';
    return [NSString stringWithUTF8String:name];
}

- (id)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _directory = [directory copy];
    _lock = [[NSLock alloc] init];
    _commands = [[NSMutableArray alloc] init];
    _handlers = [[NSMutableDictionary alloc] init];
    _links = [[NSMutableDictionary alloc] init];
    _typing = [[NoshiTypingBoard alloc] init];
    _forumSummaries = [[NoshiForumSummaries alloc] init];
    _drafts = [[NoshiDraftBoard alloc] init];
    _calls = [[NoshiCallEngine alloc] initWithSession:self];
    _groupCalls = [[NoshiGroupCallEngine alloc] initWithSession:self];
    _wake[0] = _wake[1] = -1;
    noshi_mt_socket_init(&_socket);
    _exited = dispatch_semaphore_create(0);
    UIDevice *device = [UIDevice currentDevice];
    NSString *machine = NoshiMachineName();
    const char *marketing = noshi_device_name(machine.UTF8String);
    _deviceModel = [(marketing ? [NSString stringWithUTF8String:marketing] : (machine ? machine : device.model)) copy];
    _systemVersion = [[NSString stringWithFormat:@"%@ %@", device.systemName, device.systemVersion] copy];
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    _appVersion = [(version ? version : @"") copy];
    NSString *language = [[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : @"en";
    NSRange dash = [language rangeOfString:@"-"];
    _langCode = [(dash.location == NSNotFound ? language : [language substringToIndex:dash.location]) copy];
    _realDeviceModel = [_deviceModel retain];
    _realSystemVersion = [_systemVersion retain];
    _realAppVersion = [_appVersion retain];
    _cDeviceModel = strdup(_deviceModel.UTF8String);
    _cSystemVersion = strdup(_systemVersion.UTF8String);
    _cAppVersion = strdup(_appVersion.UTF8String);
    _cLangCode = strdup(_langCode.UTF8String);
    return self;
}

- (void)dealloc {
    for (int i = 0; i < 2; ++i) if (_wake[i] >= 0) close(_wake[i]);
    [_sendAsChoices release];
    [_chatFolders release];
    if (_exited) dispatch_release(_exited);
    [_directory release];
    [_ownPerson release];
    [_lock release];
    [_commands release];
    [_handlers release];
    [_links release];
    [_typing release];
    [_forumSummaries release];
    [_drafts release];
    [_calls release];
    [_groupCalls release];
    [_storeObservers release];
    [_deviceModel release];
    [_systemVersion release];
    [_appVersion release];
    [_realDeviceModel release];
    [_realSystemVersion release];
    [_realAppVersion release];
    [_langCode release];
    free(_cDeviceModel);
    free(_cSystemVersion);
    free(_cAppVersion);
    free(_cLangCode);
    [_readOutbox release];
    [_unsent release];
    [_cancelledSends release];
    [super dealloc];
}

#pragma mark calls

/* bots and telegram's service account cannot receive calls */
- (void)startCallToDialog:(NoshiDialog *)dialog {
    if (dialog.kind == NOSHI_DIALOG_BOT || (dialog.peerKind == 1 && dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID)) {
        NSLog(@"noshigram: a call to service user %lld was not started", dialog.peerId);
        return;
    }
    [_calls startCallToDialog:dialog];
}

- (void)startVideoCallToDialog:(NoshiDialog *)dialog {
    if (dialog.kind == NOSHI_DIALOG_BOT || (dialog.peerKind == 1 && dialog.peerId == NOSHI_TELEGRAM_SERVICE_USER_ID)) {
        NSLog(@"noshigram: a video call to service user %lld was not started", dialog.peerId);
        return;
    }
    [_calls startCallToDialog:dialog video:YES];
}
- (void)acceptCall { [_calls acceptIncoming]; }
- (void)declineCall { [_calls declineIncoming]; }
- (void)hangUpCall { [_calls hangUp]; }
- (void)setCallMuted:(BOOL)muted { [_calls setMuted:muted]; }
- (void)setCallCameraOn:(BOOL)on { [_calls setCameraOn:on]; }
- (NoshiCallVideo *)activeCallVideo { return [_calls activeVideo]; }

#pragma mark delivery

- (void)deliver:(NoshiAuthEvent *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate session:self didReceiveAuthEvent:event];
    });
}

- (void)deliverKind:(NoshiAuthEventKind)kind {
    [self deliver:[[[NoshiAuthEvent alloc] initWithKind:kind] autorelease]];
}

- (void)deliverFailure:(NSString *)name number:(NSInteger)number {
    NoshiAuthEvent *event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventFailed] autorelease];
    [event setErrorName:name number:number];
    [self deliver:event];
}

#pragma mark commands

- (void)post:(void (^)(void))block {
    [_lock lock];
    [_commands addObject:[[block copy] autorelease]];
    [_lock unlock];
    char byte = 1;
    /* a full pipe already holds a wake up, so a short write loses nothing */
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"noshigram: session wake up failed, errno %d", errno);
}

- (void)afterPendingWork:(void (^)(void))block {
    void (^done)(void) = [block copy];
    [self post:^{
        dispatch_async(dispatch_get_main_queue(), ^{ done(); [done release]; });
    }];
}

- (void)start {
    [_lock lock];
    if (_started) {
        [_lock unlock];
        return;
    }
    _started = YES;
    [_lock unlock];
    if (pipe(_wake) != 0) {
        NSLog(@"noshigram: session pipe failed, errno %d", errno);
        _wake[0] = _wake[1] = -1;
        [self deliverFailure:@"INTERNAL" number:0];
        return;
    }
    for (int i = 0; i < 2; ++i) {
        fcntl(_wake[i], F_SETFL, fcntl(_wake[i], F_GETFL, 0) | O_NONBLOCK);
        fcntl(_wake[i], F_SETFD, FD_CLOEXEC);
    }
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}

- (void)stop {
    [_lock lock];
    BOOL running = _started && !_stopping && _wake[1] >= 0;
    _stopping = YES;
    [_lock unlock];
    if (!running) return;
    char byte = 1;
    if (write(_wake[1], &byte, 1) < 0 && errno != EAGAIN) NSLog(@"noshigram: session stop wake up failed, errno %d", errno);
    dispatch_semaphore_wait(_exited, DISPATCH_TIME_FOREVER);
}

- (BOOL)isStopping {
    [_lock lock];
    BOOL stopping = _stopping;
    [_lock unlock];
    return stopping;
}

- (void)routeChanged {
    [self post:^{
        /* a media link made on the old path would go on using it, so the next download makes a new one */
        for (NoshiMediaLink *link in [_links allValues]) [link stop];
        [_links removeAllObjects];
        if (_socket.fd >= 0) {
            [self closeSocket];
            if (_clientLive) noshi_client_disconnected(&_client);
        }
        _failures = 0;
        _retryAt = 0;
    }];
}

- (void)setPingInterval:(uint32_t)milliseconds {
    [self post:^{
        _pingInterval = milliseconds;
        if (_clientLive) noshi_mt_client_set_ping_interval(&_client.mt, milliseconds ? milliseconds : NOSHI_MT_PING_INTERVAL_DEFAULT);
    }];
}

- (void)reconnect {
    [self post:^{
        _failures = 0;
        _retryAt = 0;
        _wantLink = YES;
    }];
}

/* auth calls run on the worker; a session whose client never started answers with a failure instead of crashing */
- (void)authCommand:(const char *)boundary action:(noshi_status (^)(noshi_auth *auth))action {
    [self post:^{
        if (!_clientLive) {
            [self authCallFailed:NOSHI_E_STATE boundary:boundary];
            return;
        }
        [self linkWanted];
        noshi_status status = action(&_client.auth);
        if (status != NOSHI_OK) [self authCallFailed:status boundary:boundary];
    }];
}

- (void)requestCodeForNumber:(NSString *)number {
    NSString *copy = [number copy];
    [self authCommand:"phone" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_phone(auth, copy.UTF8String, NULL);
    }];
    [copy release];
}

- (void)submitCode:(NSString *)code {
    NSString *copy = [code copy];
    [self authCommand:"code" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_code(auth, copy.UTF8String, NULL);
    }];
    [copy release];
}

- (void)requestQrLogin {
    [self authCommand:"qr" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_qr(auth, NULL, 0);
    }];
}

- (void)resendCode {
    [self authCommand:"resend" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_resend(auth, NULL);
    }];
}

- (void)submitPassword:(NSString *)password {
    NSString *copy = [password copy];
    [self authCommand:"password" action:^noshi_status(noshi_auth *auth) {
        const char *bytes = copy.UTF8String;
        return noshi_auth_password(auth, (const uint8_t *)bytes, strlen(bytes));
    }];
    [copy release];
}

- (void)requestPasswordRecovery {
    [self authCommand:"recovery" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_recovery(auth);
    }];
}

- (void)submitRecoveryCode:(NSString *)code {
    NSString *copy = [code copy];
    [self authCommand:"recover code" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_recover_code(auth, copy.UTF8String);
    }];
    [copy release];
}

- (void)submitFirstName:(NSString *)first lastName:(NSString *)last {
    NSString *firstCopy = [first copy];
    NSString *lastCopy = [last copy];
    [self authCommand:"signup" action:^noshi_status(noshi_auth *auth) {
        return noshi_auth_signup(auth, firstCopy.UTF8String, lastCopy.UTF8String);
    }];
    [firstCopy release];
    [lastCopy release];
}

- (void)cancelLogin {
    [self post:^{
        if (_clientLive) noshi_auth_cancel(&_client.auth);
    }];
}

/* an argument or state error means the screen sent something the state machine cannot take */
- (void)authCallFailed:(noshi_status)status boundary:(const char *)boundary {
    NSLog(@"noshigram: auth %s rejected locally: %s", boundary, noshi_status_name(status));
    [self deliverFailure:@"INTERNAL" number:status];
}

#pragma mark requests

/* runs on the worker: the handler gets the result there, and an arena that is already gone, so it must copy what
   it keeps */
- (void)invoke:(const char *)method configure:(noshi_status (^)(noshi_arena *arena, noshi_tl_value *request))configure
       handler:(void (^)(const noshi_mt_rpc_result *result))handler {
    void (^copy)(const noshi_mt_rpc_result *) = [handler copy];
    noshi_status (^configureCopy)(noshi_arena *, noshi_tl_value *) = [configure copy];
    [self post:^{
        [self submit:method configure:configureCopy handler:copy];
    }];
    [copy release];
    [configureCopy release];
}

/* the same for a request that a builder in the core makes whole, so that it reaches the worker like any other */
- (void)invokeBuilt:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build
            handler:(void (^)(const noshi_mt_rpc_result *result))handler {
    void (^copy)(const noshi_mt_rpc_result *) = [handler copy];
    noshi_status (^buildCopy)(noshi_arena *, noshi_tl_value **) = [build copy];
    [self post:^{
        [self submitBuilt:buildCopy handler:copy];
    }];
    [copy release];
    [buildCopy release];
}

- (void)setDeviceModel:(NSString *)model systemVersion:(NSString *)system appVersion:(NSString *)app completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *newModel = [[(model ? model : _realDeviceModel) copy] autorelease];
    NSString *newSystem = [[(system ? system : _realSystemVersion) copy] autorelease];
    NSString *newApp = [[(app ? app : _realAppVersion) copy] autorelease];
    [self post:^{
        char *cModel = strdup(newModel.UTF8String), *cSystem = strdup(newSystem.UTF8String), *cApp = strdup(newApp.UTF8String);
        noshi_status status = cModel && cSystem && cApp ? NOSHI_OK : NOSHI_E_NOMEM;
        /* the client takes the strings at once or refuses them, and keeps the old ones in the second case */
        if (status == NOSHI_OK && _clientLive) status = noshi_mt_client_set_device(&_client.mt, cModel, cSystem, cApp);
        if (status != NOSHI_OK) {
            free(cModel);
            free(cSystem);
            free(cApp);
            NSString *error = status == NOSHI_E_ARG ? @"DEVICE_INVALID" : @"INTERNAL";
            [self deliverMain:^{ done(error); [done release]; }];
            return;
        }
        free(_cDeviceModel);
        free(_cSystemVersion);
        free(_cAppVersion);
        _cDeviceModel = cModel;
        _cSystemVersion = cSystem;
        _cAppVersion = cApp;
        [_deviceModel release];
        [_systemVersion release];
        [_appVersion release];
        _deviceModel = [newModel retain];
        _systemVersion = [newSystem retain];
        _appVersion = [newApp retain];
        if (!_clientLive) {
            /* the next connection starts with these */
            [self deliverMain:^{ done(nil); [done release]; }];
            return;
        }
        /* the metadata rides on a request, so one goes out now and its answer says whether the server has it */
        [self submit:"help.getNearestDc" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
            (void)arena;
            (void)request;
            return NOSHI_OK;
        } handler:^(const noshi_mt_rpc_result *result) {
            NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
            [self noteRpcError:error];
            NSString *delivered = [[error copy] autorelease];
            [self deliverMain:^{ done(delivered); [done release]; }];
        }];
    }];
}

/* worker only: the same, for code that already runs there */
- (void)submit:(const char *)method configure:(noshi_status (^)(noshi_arena *arena, noshi_tl_value *request))configure
       handler:(void (^)(const noshi_mt_rpc_result *result))handler {
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **out) {
        *out = noshi_tl_new_obj(arena, method);
        return *out ? configure(arena, *out) : NOSHI_E_NOMEM;
    } handler:handler];
}

- (void)submitBuilt:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build
            handler:(void (^)(const noshi_mt_rpc_result *result))handler {
    noshi_arena arena;
    noshi_tl_value *request = NULL;
    uint64_t id = 0;
    noshi_status status = NOSHI_E_STATE;
    /* the limit is a ceiling, nothing is reserved: an upload part of 128 KB and its copy in the request need more than 64 KB */
    noshi_arena_init(&arena, 512u * 1024u);
    if (_clientLive) status = build(&arena, &request);
    if (request && status == NOSHI_OK) {
        [self linkWanted];
        status = noshi_client_request(&_client, request, RPC_TIMEOUT_MS, &id);
    } else if (status == NOSHI_OK) {
        status = NOSHI_E_ARG;
    }
    noshi_arena_free(&arena);
    if (status == NOSHI_OK) {
        [_handlers setObject:[[handler copy] autorelease] forKey:[NSNumber numberWithUnsignedLongLong:id]];
    } else {
        noshi_mt_rpc_result failed;
        memset(&failed, 0, sizeof(failed));
        failed.status = status;
        handler(&failed);
    }
}

- (void)noteRpcError:(NSString *)error {
    if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
}

- (noshi_store *)workerStore {
    return _store;
}

- (void)workerCancelSend:(long long)randomId {
    if (!_cancelledSends) _cancelledSends = [[NSMutableSet alloc] init];
    [_cancelledSends addObject:[NSNumber numberWithLongLong:randomId]];
}

- (BOOL)workerSendIsCancelled:(long long)randomId {
    return [_cancelledSends containsObject:[NSNumber numberWithLongLong:randomId]];
}

- (void)workerForgetSend:(long long)randomId {
    [_cancelledSends removeObject:[NSNumber numberWithLongLong:randomId]];
}

- (int64_t)workerAccount {
    return _account;
}

- (int32_t)workerDc {
    return _dc;
}

- (int64_t)workerServerTimeOffsetMilliseconds {
    return _clientLive ? _client.mt.time_offset_ms : 0;
}

- (void)setStoreObserver:(void (^)(void))observer {
    [self setStoreObserver:observer owner:NULL];
}

- (void)setStoreObserver:(void (^)(void))observer owner:(void *)owner {
    if (!_storeObservers) _storeObservers = [[NSMutableDictionary alloc] init];
    NSValue *key = [NSValue valueWithPointer:owner];
    if (observer) {
        void (^copied)(void) = [observer copy];
        [_storeObservers setObject:copied forKey:key];
        [copied release];
    } else [_storeObservers removeObjectForKey:key];
}

- (void)clearStoreObserverOwnedBy:(void *)owner {
    if (owner) [_storeObservers removeObjectForKey:[NSValue valueWithPointer:owner]];
}

- (void)setChangeHook:(void (^)(void))hook {
    void (^old)(void) = _changeHook;
    _changeHook = [hook copy];
    [old release];
}

- (NSString *)workerDirectory {
    return _directory;
}

- (void)storeChanged {
    if (_store) {
        NSArray *observers = [[_storeObservers allValues] copy];
        for (void (^observer)(void) in observers) observer();
        [observers release];
    }
    /* presence and typing change nothing a notification could say, and a contact list sends them all day; the answer to the notifier's own look at the
       chat list is not news either, or each look would start the next one and the list would be asked for until the server answers with a wait */
    if (_changeHook && _store && !(_clientLive && (_client.change_quiet || _client.change_rpc_cache))) _changeHook();
    if (_clientLive && (!_client.change_quiet || _client.change_list) && !_client.change_rpc_cache) {
        [self deliverMain:^{ [[NSNotificationCenter defaultCenter] postNotificationName:NoshiSessionDialogsUpdatedNotification object:self]; }];
    }
}

/* hands a finished load to the main thread; a dropped key also queues the client restart */
- (void)finishLoad:(NSArray *)items error:(NSString *)error completion:(NoshiListCompletion)done {
    /* the client is still inside its own callback, so the restart waits for settleClient */
    if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
    NSArray *delivered = [[items copy] autorelease];
    NSString *deliveredError = [[error copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{ done(delivered, deliveredError); });
}

/* parse turns the answer into model objects, or returns nil and sets *error to the name the screen shows */
- (void)load:(const char *)method configure:(noshi_status (^)(noshi_arena *, noshi_tl_value *))configure
       parse:(NSArray * (^)(const noshi_tl_value *answer))parse completion:(NoshiListCompletion)completion {
    [self load:method configure:configure parse:parse keep:nil completion:completion];
}

/* keep runs on the worker after the parsed items are on their way to the main thread: the store syncs to disk at every commit, and a list that waited for it showed
   the new chat order late on a phone with slow flash */
- (void)load:(const char *)method configure:(noshi_status (^)(noshi_arena *, noshi_tl_value *))configure
       parse:(NSArray * (^)(const noshi_tl_value *answer))parse keep:(void (^)(const noshi_tl_value *answer))keep
  completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invoke:method configure:configure handler:^(const noshi_mt_rpc_result *result) {
        NSArray *items = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
            if (strcmp(method, "messages.getDialogs") == 0) {
                error = NoshiDownloadErrorName(result);
                [self rememberFolderFloodError:error];
            }
        } else {
            items = parse(result->value);
            if (!items) {
                NSLog(@"noshigram: %s answer rejected", method);
                error = @"INTERNAL";
            }
        }
        [self finishLoad:items error:error completion:done];
        if (keep && items) keep(result->value);
    }];
    [done release];
}

- (BOOL)mainListHasMore {
    return _mainListHasMore;
}

- (void)loadDialogs:(NoshiListCompletion)completion {
    [self loadDialogsInFolder:0 completion:completion];
}

static noshi_status NoshiConfigureDialogList(noshi_arena *arena, noshi_tl_value *request, int32_t folder) {
    noshi_tl_value *empty = noshi_tl_new_obj(arena, "inputPeerEmpty");
    if (!empty) return NOSHI_E_NOMEM;
    noshi_status status = noshi_tl_set(request, "offset_peer", empty);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", 0);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", DIALOGS_PER_REQUEST);
    /* folder 0 excludes archived chats, its optional archive shortcut is restored after parsing */
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "folder_id", folder);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "hash", 0);
    return status;
}

static BOOL NoshiDialogIsPageCursor(NoshiDialog *item);

- (void)loadDialogsInFolder:(int32_t)folder completion:(NoshiListCompletion)completion {
    NSString *wait = [self folderFloodError];
    if (wait) {
        if (completion) completion(nil, wait);
        return;
    }
    NSUInteger draftRevision = self.drafts.revision;
    NoshiListCompletion shown = completion;
    /* messages.dialogs is the whole list and messages.dialogsSlice has more behind it; a whole list needs no second request, which is one less getDialogs toward the flood wait */
    __block BOOL hasMorePages = NO;
    if (folder > 0 && completion) {
        /* a request holds the newest hundred chats of the archive, and the older ones were never asked for, so a long archive ended at the hundredth chat; the pages that follow are
           walked here, up to the limit the search uses, and a page that fails leaves the chats that came */
        NoshiListCompletion whole = [completion copy];
        shown = [[^(NSArray *items, NSString *errorName) {
            if (!items || errorName || !hasMorePages) { whole(items, errorName); return; }
            NSMutableArray *all = [NSMutableArray arrayWithArray:items];
            NSMutableSet *keys = [NSMutableSet set];
            NoshiDialog *cursor = nil;
            for (NoshiDialog *item in items) {
                [keys addObject:[NSString stringWithFormat:@"%d:%lld", (int)item.peerKind, item.peerId]];
                if (NoshiDialogIsPageCursor(item)) cursor = item;
            }
            [self walkRemainingDialogsInFolder:folder all:all keys:keys cursor:cursor pages:0 completion:^(NSArray *every) { whole(every, nil); }];
        } copy] autorelease];
        [whole release];
    }
    [self load:"messages.getDialogs" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        return NoshiConfigureDialogList(arena, request, folder);
    } parse:^NSArray *(const noshi_tl_value *answer) {
        hasMorePages = noshi_tl_is(answer, NOSHI_TL_ID_messages_dialogsSlice);
        if (folder == 0) _mainListHasMore = hasMorePages;
        NSArray *dialogs = [self dialogsFromAnswer:answer folder:folder];
        NSUInteger folders = 0;
        for (NoshiDialog *entry in dialogs) if (entry.folder) ++folders;
        NSLog(@"noshigram: chat list of folder %d: %lu rows, %lu archive entries", (int)folder, (unsigned long)dialogs.count, (unsigned long)folders);
        if (dialogs && folder == 0) [self refreshArchiveSummary];
        if (dialogs) {
            [self noteDraftsOfDialogsAnswer:answer complete:YES since:draftRevision];
            if (folder == 0) [self requestAllDraftsOnce];
        }
        return dialogs;
    } keep:^(const noshi_tl_value *answer) {
        /* the whole answer is kept so the list opens at once next time, before the network answers */
        noshi_peer none = {0, 0};
        noshi_status status = noshi_store_put([self workerStore], NOSHI_RECORD_DIALOG, none, (int64_t)folder + 1, answer);
        if (status != NOSHI_OK) NSLog(@"noshigram: cannot keep the chat list of folder %d: %s", (int)folder, noshi_status_name(status));
    } completion:shown];
}

- (void)loadDialogPageInFolder:(int32_t)folder after:(NoshiDialog *)cursor completion:(void (^)(NSArray *, NoshiDialog *, NSString *))completion {
    noshi_peer_ref peer = {0};
    if (cursor) {
        peer.kind = cursor.peerKind; peer.id = cursor.peerId; peer.access_hash = cursor.peerHash; peer.self = cursor.saved;
    }
    int32_t date = cursor.date, message = cursor.topMessage;
    __block BOOL more = NO;
    void (^done)(NSArray *, NoshiDialog *, NSString *) = [completion copy];
    [self load:"messages.getDialogs" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        noshi_status status = NoshiConfigureDialogList(arena, request, folder);
        if (status != NOSHI_OK || !cursor) return status;
        noshi_tl_value *input = NULL;
        status = noshi_input_peer(arena, &peer, &input);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "offset_peer", input);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_date", date);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "offset_id", message);
        if (status == NOSHI_OK) status = noshi_tl_set_flag(request, "exclude_pinned");
        return status;
    } parse:^NSArray *(const noshi_tl_value *answer) {
        const noshi_tl_value *dialogs = NULL;
        more = noshi_tl_is(answer, NOSHI_TL_ID_messages_dialogsSlice) &&
               noshi_tl_get_vec(answer, "dialogs", &dialogs) == NOSHI_OK && dialogs->u.vec.count > 0;
        return [self dialogsFromAnswer:answer folder:folder];
    } completion:^(NSArray *items, NSString *errorName) {
        NoshiDialog *next = nil;
        if (items && more) {
            for (NoshiDialog *item in [items reverseObjectEnumerator]) {
                if (!item.folder && !item.community && item.topMessage > 0 && item.date > 0 && (item.peerKind == 2 || item.saved || item.peerHash)) { next = item; break; }
            }
            if (!next || (cursor && next.peerKind == cursor.peerKind && next.peerId == cursor.peerId && next.topMessage == cursor.topMessage)) errorName = @"DIALOG_PAGINATION_FAILED";
        }
        done(items, errorName ? nil : next, errorName);
        [done release];
    }];
}

#define REMAINING_DIALOG_PAGES_MAX 10

static BOOL NoshiDialogIsPageCursor(NoshiDialog *item) {
    return !item.folder && !item.community && item.topMessage > 0 && item.date > 0 && (item.peerKind == 2 || item.saved || item.peerHash);
}

- (void)loadRemainingDialogsAfter:(NSArray *)known completion:(void (^)(NSArray *))completion {
    void (^done)(NSArray *) = [completion copy];
    NSMutableArray *all = [NSMutableArray arrayWithArray:known];
    NSMutableSet *keys = [NSMutableSet set];
    NoshiDialog *cursor = nil;
    for (NoshiDialog *item in known) {
        [keys addObject:[NSString stringWithFormat:@"%d:%lld", (int)item.peerKind, item.peerId]];
        if (NoshiDialogIsPageCursor(item)) cursor = item;
    }
    [self walkRemainingDialogsInFolder:0 all:all keys:keys cursor:cursor pages:0 completion:done];
    [done release];
}

- (void)walkRemainingDialogsInFolder:(int32_t)folder all:(NSMutableArray *)all keys:(NSMutableSet *)keys cursor:(NoshiDialog *)cursor pages:(NSUInteger)pages completion:(void (^)(NSArray *))done {
    /* the first page of a list is the one the screen holds, so a list with no cursor has no later page */
    if (!cursor || pages >= REMAINING_DIALOG_PAGES_MAX) { done(all); return; }
    void (^finish)(NSArray *) = [done copy];
    [self loadDialogPageInFolder:folder after:cursor completion:^(NSArray *items, NoshiDialog *next, NSString *errorName) {
        if (!items || errorName) {
            if (errorName) NSLog(@"noshigram: the rest of the chat list of folder %d did not load: %@", (int)folder, errorName);
            finish(all);
            [finish release];
            return;
        }
        for (NoshiDialog *item in items) {
            NSString *key = [NSString stringWithFormat:@"%d:%lld", (int)item.peerKind, item.peerId];
            if (item.folder || [keys containsObject:key]) continue;
            [keys addObject:key];
            [all addObject:item];
        }
        [self walkRemainingDialogsInFolder:folder all:all keys:keys cursor:next pages:pages + 1 completion:finish];
        [finish release];
    }];
}

- (NoshiForumSummaries *)forumSummaries {
    return _forumSummaries;
}

- (NSArray *)dialogsFromAnswer:(const noshi_tl_value *)answer folder:(int32_t)folder {
    noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX + 1, sizeof(*rows));
    size_t count = 0;
    NSMutableArray *dialogs = nil;
    if (rows && noshi_dialogs_parse(answer, _account, (int32_t)[[NSDate date] timeIntervalSince1970],
                                      rows, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
        if (folder == 0 && noshi_dialogs_ensure_archive(rows, NOSHI_DIALOGS_MAX + 1, &count) != NOSHI_OK) {
            NSLog(@"noshigram: archive shortcut could not be inserted");
            free(rows);
            return nil;
        }
        noshi_dialog_row summary;
        if (folder == 0) {
            /* the counters of the folder entry move when the chats inside it do, which is what asks for a new summary */
            for (size_t i = 0; i < count; ++i) {
                if (!rows[i].folder || rows[i].folder_id != 1) continue;
                if (!_archiveSummarySeen || rows[i].unread_count != _archiveLiveUnread || (rows[i].muted != 0) != _archiveLiveMuted) _archiveSummaryStale = YES;
                _archiveSummarySeen = YES;
                _archiveLiveUnread = rows[i].unread_count;
                _archiveLiveMuted = rows[i].muted != 0;
            }
        }
        if (folder == 0 && [self readArchiveSummary:&summary]) {
            for (size_t i = 0; i < count; ++i) if (rows[i].folder && rows[i].folder_id == 1) rows[i] = summary;
        }
        dialogs = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; ++i) {
            if (!rows[i].folder && rows[i].folder_id != folder) continue;
            if (rows[i].folder && folder != 0) continue;
            [dialogs addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
        }
        [_forumSummaries applyToDialogs:dialogs];
        [self refreshForumSummariesOfDialogs:dialogs];
    }
    free(rows);
    return dialogs;
}

/* negative list keys keep folder metadata separate from the folder's chat list */
#define NOSHI_ARCHIVE_INFO_KEY (-2)

- (BOOL)readArchiveSummary:(noshi_dialog_row *)summary {
    noshi_arena arena;
    noshi_tl_value *info = NULL, *contents = NULL;
    noshi_peer none = {0, 0};
    noshi_arena_init(&arena, 16u * 1024u * 1024u);
    noshi_status status = noshi_store_get(_store, NOSHI_RECORD_DIALOG, none, NOSHI_ARCHIVE_INFO_KEY, &arena, &info);
    if (status == NOSHI_OK) status = noshi_store_get(_store, NOSHI_RECORD_DIALOG, none, 2, &arena, &contents);
    if (status == NOSHI_OK) status = noshi_archive_summary_parse(info, contents, _account,
        (int32_t)[[NSDate date] timeIntervalSince1970], summary);
    if (status != NOSHI_OK && status != NOSHI_E_NOTFOUND) NSLog(@"noshigram: cannot read archive summary: %s", noshi_status_name(status));
    noshi_arena_free(&arena);
    return status == NOSHI_OK;
}

- (void)finishArchiveRefreshWithError:(NSString *)error {
    _archiveLoading = NO;
    /* a refresh that failed has not shown the new archive, so the next load asks again */
    _archiveSummaryStale = YES;
    [self noteRpcError:error];
    NSLog(@"noshigram: archive summary refresh failed: %@", error);
}

#define ARCHIVE_SUMMARY_FRESH_MS 120000u

- (void)refreshArchiveSummary {
    /* the summary asks getPeerDialogs and getDialogs, and a list that reloads on every update asked for both each time, until getDialogs answered with a flood wait that held
       back the list of the archive too. the entry is asked for again after a move, when its counters changed, and when the last answer is old */
    if (_archiveLoading || !_account || [self folderFloodError]) return;
    uint64_t now = noshi_system_clock.monotonic_ms(noshi_system_clock.ctx);
    if (!_archiveSummaryStale && _archiveSummaryAtMs && now - _archiveSummaryAtMs < ARCHIVE_SUMMARY_FRESH_MS) return;
    _archiveSummaryStale = NO;
    _archiveSummaryAtMs = now;
    _archiveLoading = YES;
    int64_t account = _account;
    [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **out) {
        noshi_tl_value *request = noshi_tl_new_obj(arena, "messages.getPeerDialogs");
        noshi_tl_value *folder = noshi_tl_new_obj(arena, "inputDialogPeerFolder");
        noshi_tl_value *peers = noshi_tl_new_vec(arena, 1);
        if (!request || !folder || !peers) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_set_i32(arena, folder, "folder_id", 1);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(peers, 0, folder);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "peers", peers);
        if (status == NOSHI_OK) *out = request;
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        if (account != _account) { _archiveLoading = NO; return; }
        if (result->status != NOSHI_OK) { [self finishArchiveRefreshWithError:NoshiRpcErrorName(result)]; return; }
        noshi_peer none = {0, 0};
        noshi_status status = noshi_store_put(_store, NOSHI_RECORD_DIALOG, none, NOSHI_ARCHIVE_INFO_KEY, result->value);
        if (status != NOSHI_OK) { [self finishArchiveRefreshWithError:@"STORAGE"]; return; }
        [self submitBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **out) {
            noshi_tl_value *request = noshi_tl_new_obj(arena, "messages.getDialogs");
            if (!request) return NOSHI_E_NOMEM;
            noshi_status built = NoshiConfigureDialogList(arena, request, 1);
            if (built == NOSHI_OK) *out = request;
            return built;
        } handler:^(const noshi_mt_rpc_result *contents) {
            _archiveLoading = NO;
            if (account != _account) return;
            if (contents->status != NOSHI_OK) {
                NSString *error = NoshiDownloadErrorName(contents);
                [self rememberFolderFloodError:error];
                [self finishArchiveRefreshWithError:error];
                return;
            }
            noshi_peer key = {0, 0};
            noshi_status kept = noshi_store_put(_store, NOSHI_RECORD_DIALOG, key, 2, contents->value);
            if (kept != NOSHI_OK) { [self finishArchiveRefreshWithError:@"STORAGE"]; return; }
            noshi_dialog_row row;
            if (![self readArchiveSummary:&row]) { [self finishArchiveRefreshWithError:@"INTERNAL"]; return; }
            NoshiDialog *summary = [[[NoshiDialog alloc] initWithRow:&row] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:NoshiArchiveSummaryDidChangeNotification object:self
                    userInfo:[NSDictionary dictionaryWithObject:summary forKey:@"dialog"]];
            });
        }];
    }];
}

- (void)loadCachedDialogsInFolder:(int32_t)folder completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self post:^{
        noshi_arena arena;
        noshi_tl_value *answer = NULL;
        noshi_peer none = {0, 0};
        NSArray *dialogs = nil;
        noshi_arena_init(&arena, 16u * 1024u * 1024u);
        noshi_status status = noshi_store_get([self workerStore], NOSHI_RECORD_DIALOG, none, (int64_t)folder + 1, &arena, &answer);
        if (status == NOSHI_OK) {
            dialogs = [self dialogsFromAnswer:answer folder:folder];
            if (dialogs) [self noteDraftsOfDialogsAnswer:answer complete:NO];
        } else if (status != NOSHI_E_NOTFOUND) NSLog(@"noshigram: cannot read the kept chat list: %s", noshi_status_name(status));
        noshi_arena_free(&arena);
        /* nothing kept is not an error, the screen just waits for the network */
        [self finishLoad:dialogs error:nil completion:done];
        [done release];
    }];
}

- (void)moveDialog:(NoshiDialog *)dialog toFolder:(int32_t)folder completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    int32_t kind = dialog.peerKind;
    long long peerId = dialog.peerId, hash = dialog.peerHash;
    [self invoke:"folders.editPeerFolders" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        static const char *const ctors[] = {NULL, "inputPeerUser", "inputPeerChat", "inputPeerChannel"};
        static const char *const fields[] = {NULL, "user_id", "chat_id", "channel_id"};
        if (kind < 1 || kind > 3 || (kind != 2 && hash == 0)) return NOSHI_E_ARG;
        noshi_tl_value *peer = noshi_tl_new_obj(arena, ctors[kind]);
        noshi_tl_value *entry = noshi_tl_new_obj(arena, "inputFolderPeer");
        noshi_tl_value *list = noshi_tl_new_vec(arena, 1);
        if (!peer || !entry || !list) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_set_i64(arena, peer, fields[kind], peerId);
        if (status == NOSHI_OK && kind != 2) status = noshi_tl_set_i64(arena, peer, "access_hash", hash);
        if (status == NOSHI_OK) status = noshi_tl_set(entry, "peer", peer);
        if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, entry, "folder_id", folder);
        if (status == NOSHI_OK) status = noshi_tl_vec_set(list, 0, entry);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "folder_peers", list);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NSLog(@"noshigram: editPeerFolders of chat %lld to folder %d answered: %@", peerId, (int)folder, error ? error : @"ok");
        if (!error) _archiveSummaryStale = YES;
        if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ done(error); });
    }];
    [done release];
}

- (void)createChannelTitled:(NSString *)title megagroup:(BOOL)megagroup completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *name = [title copy];
    [self invoke:"channels.createChannel" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        noshi_status status = noshi_tl_set_flag(request, megagroup ? "megagroup" : "broadcast");
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "title", name.UTF8String);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "about", "");
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NSLog(@"noshigram: createChannel answered: %@", error ? error : @"ok");
        if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
        NSString *delivered = [[error copy] autorelease];
        dispatch_async(dispatch_get_main_queue(), ^{ done(delivered); [done release]; });
    }];
    [name release];
}

- (void)createGroupTitled:(NSString *)title people:(NSArray *)people completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    NSString *name = [title copy];
    NSArray *members = [people copy];
    [self invoke:"messages.createChat" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        noshi_tl_value *users = noshi_tl_new_vec(arena, (uint32_t)members.count);
        noshi_status status = users ? NOSHI_OK : NOSHI_E_NOMEM;
        for (NSUInteger i = 0; status == NOSHI_OK && i < members.count; ++i) {
            NoshiPerson *person = [members objectAtIndex:i];
            noshi_tl_value *input = noshi_tl_new_obj(arena, "inputUser");
            if (!input) return NOSHI_E_NOMEM;
            status = noshi_tl_set_i64(arena, input, "user_id", person.userId);
            if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, input, "access_hash", person.accessHash);
            if (status == NOSHI_OK) status = noshi_tl_vec_set(users, (uint32_t)i, input);
        }
        if (status == NOSHI_OK) status = noshi_tl_set(request, "users", users);
        if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "title", name.UTF8String);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        NSLog(@"noshigram: createChat answered: %@", error ? error : @"ok");
        if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
        NSString *delivered = [[error copy] autorelease];
        dispatch_async(dispatch_get_main_queue(), ^{ done(delivered); [done release]; });
    }];
    [name release];
    [members release];
}

- (void)searchPeers:(NSString *)query completion:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    NSString *text = [query copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_found_request(arena, text.UTF8String, 30, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *dialogs = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_dialog_row *rows = calloc(NOSHI_DIALOGS_MAX + 1, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_found_parse(result->value, _account, rows, NOSHI_DIALOGS_MAX, &count) == NOSHI_OK) {
                dialogs = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [dialogs addObject:[[[NoshiDialog alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: contacts.search answer rejected");
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:dialogs error:error completion:done];
        [done release];
    }];
    [text release];
}

- (void)loadContacts:(NoshiListCompletion)completion {
    [self load:"contacts.getContacts" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        return noshi_tl_set_i64(arena, request, "hash", 0);
    } parse:^NSArray *(const noshi_tl_value *answer) {
        noshi_person_row *rows = calloc(NOSHI_PEOPLE_MAX, sizeof(*rows));
        size_t count = 0;
        NSMutableArray *people = nil;
        if (rows && noshi_contacts_parse(answer, rows, NOSHI_PEOPLE_MAX, &count) == NOSHI_OK) {
            people = [NSMutableArray arrayWithCapacity:count];
            for (size_t i = 0; i < count; ++i) [people addObject:[[[NoshiPerson alloc] initWithRow:&rows[i]] autorelease]];
        }
        free(rows);
        return people;
    } completion:completion];
}

/* the own profile is kept in a small file of the account, a magic and the size of the row before the row itself, so a row of another build is not read */
#define OWN_PERSON_MAGIC 0x45584f50u

- (NSString *)ownPersonPath {
    return [_directory stringByAppendingPathComponent:@"own.person"];
}

- (NoshiPerson *)ownPerson {
    if (!_ownPersonRead) {
        _ownPersonRead = YES;
        NSData *data = [NSData dataWithContentsOfFile:[self ownPersonPath]];
        uint32_t head[2];
        if (data.length == sizeof(head) + sizeof(noshi_person_row)) {
            memcpy(head, data.bytes, sizeof(head));
            if (head[0] == OWN_PERSON_MAGIC && head[1] == sizeof(noshi_person_row)) {
                noshi_person_row row;
                memcpy(&row, (const uint8_t *)data.bytes + sizeof(head), sizeof(row));
                _ownPerson = [[NoshiPerson alloc] initWithRow:&row];
            }
        }
    }
    return _ownPerson;
}

- (void)loadSelf:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    NSString *path = [self ownPersonPath];
    [self load:"users.getUsers" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        noshi_tl_value *ids = noshi_tl_new_vec(arena, 1);
        noshi_tl_value *self_input = noshi_tl_new_obj(arena, "inputUserSelf");
        if (!ids || !self_input) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_vec_set(ids, 0, self_input);
        if (status == NOSHI_OK) status = noshi_tl_set(request, "id", ids);
        return status;
    } parse:^NSArray *(const noshi_tl_value *answer) {
        noshi_person_row row;
        if (!answer || answer->kind != NOSHI_TL_V_VEC || answer->u.vec.count < 1 ||
            noshi_person_parse(answer->u.vec.items[0], &row) != NOSHI_OK) return nil;
        uint8_t packed[2 * sizeof(uint32_t) + sizeof(row)];
        uint32_t head[2] = {OWN_PERSON_MAGIC, (uint32_t)sizeof(row)};
        memcpy(packed, head, sizeof(head));
        memcpy(packed + sizeof(head), &row, sizeof(row));
        if (![[NSData dataWithBytes:packed length:sizeof(packed)] writeToFile:path atomically:YES]) NSLog(@"noshigram: the own profile was not kept");
        return [NSArray arrayWithObject:[[[NoshiPerson alloc] initWithRow:&row] autorelease]];
    } completion:^(NSArray *items, NSString *errorName) {
        if (items.count) {
            [_ownPerson release];
            _ownPerson = [[items objectAtIndex:0] retain];
            _ownPersonRead = YES;
        }
        if (done) done(items, errorName);
        [done release];
    }];
}

/* a file on the account's own data center comes over the main connection; any other data center gets a link of its
   own, signed in through an authorization this connection exports */
- (void)downloadFile:(NoshiRemoteFile *)file completion:(NoshiDownloadCompletion)completion {
    [self downloadFile:file offset:0 limit:NOSHI_REMOTE_FILE_PART ranged:NO completion:completion];
}

- (void)downloadFile:(NoshiRemoteFile *)file offset:(long long)offset limit:(int32_t)limit completion:(NoshiDownloadCompletion)completion {
    [self downloadFile:file offset:offset limit:limit ranged:YES completion:completion];
}

- (void)downloadFile:(NoshiRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          completion:(NoshiDownloadCompletion)completion {
    NoshiDownloadCompletion done = [completion copy];
    if (!file) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"INTERNAL"); [done release]; });
        return;
    }
    [self post:^{
        if (file.dc == _dc) {
            [self submit:"upload.getFile" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
                noshi_tl_value *location = NULL;
                noshi_status status = [file buildLocation:arena into:&location];
                if (status == NOSHI_OK) status = noshi_tl_set(request, "location", location);
                if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, request, "offset", offset);
                if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", limit);
                return status;
            } handler:^(const noshi_mt_rpc_result *result) {
                const uint8_t *bytes = NULL;
                size_t len = 0;
                NSData *data = nil;
                NSString *error = nil;
                if (result->status != NOSHI_OK) error = NoshiDownloadErrorName(result);
                else if (ranged) {
                    if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len <= (size_t)limit) data = [NSData dataWithBytes:bytes length:len];
                    else error = @"INTERNAL";
                }
                else if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len >= NOSHI_REMOTE_FILE_PART) error = @"FILE_TOO_BIG";
                else if (noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK && len > 0) data = [NSData dataWithBytes:bytes length:len];
                else error = @"INTERNAL";
                if (NoshiIsRevokedError(error)) _dropKeyPending = YES;
                dispatch_async(dispatch_get_main_queue(), ^{ done(data, error); [done release]; });
            }];
            return;
        }
        NoshiMediaLink *link = [self workerLinkForDc:file.dc];
        if (!link) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"INTERNAL"); [done release]; });
            return;
        }
        [link downloadFile:file offset:offset limit:limit ranged:ranged authorizer:[self workerAuthorizerForDc:file.dc] completion:^(NSData *data, NSString *error) {
            done(data, error);
            [done release];
        }];
    }];
}

/* worker only: the link to another data center, made at first use; nil when the app has no address for it */
- (NoshiMediaLink *)workerLinkForDc:(int32_t)dc {
    NSNumber *key = [NSNumber numberWithInt:dc];
    NoshiMediaLink *link = [_links objectForKey:key];
    if (!link && noshi_dc_host(dc)) {
        link = [[[NoshiMediaLink alloc] initWithDc:dc directory:_directory deviceModel:_deviceModel
                                       systemVersion:_systemVersion appVersion:_appVersion langCode:_langCode] autorelease];
        [_links setObject:link forKey:key];
    }
    return link;
}

/* the link signs in on its data center with an authorization this connection exports for it */
- (NoshiAuthorizer)workerAuthorizerForDc:(int32_t)dc {
    return [[^(NoshiAuthorizationDelivery deliver) {
        NoshiAuthorizationDelivery deliverCopy = [deliver copy];
        [self post:^{
            [self submit:"auth.exportAuthorization" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
                return noshi_tl_set_i32(arena, request, "dc_id", dc);
            } handler:^(const noshi_mt_rpc_result *result) {
                int64_t authId = 0;
                const uint8_t *bytes = NULL;
                size_t len = 0;
                if (result->status == NOSHI_OK && noshi_tl_get_i64(result->value, "id", &authId) == NOSHI_OK &&
                    noshi_tl_get_bytes(result->value, "bytes", &bytes, &len) == NOSHI_OK) {
                    deliverCopy(authId, [NSData dataWithBytes:bytes length:len], nil);
                } else {
                    deliverCopy(0, nil, result->status == NOSHI_OK ? @"INTERNAL" : NoshiRpcErrorName(result));
                }
                [deliverCopy release];
            }];
        }];
    } copy] autorelease];
}

- (void)invokeBuilt:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build onDc:(int32_t)dc
            handler:(void (^)(const noshi_mt_rpc_result *result))handler {
    noshi_status (^builder)(noshi_arena *, noshi_tl_value **) = [build copy];
    void (^answer)(const noshi_mt_rpc_result *) = [handler copy];
    [self post:^{
        if (dc == _dc) {
            [self invokeBuilt:builder handler:answer];
            return;
        }
        NoshiMediaLink *link = [self workerLinkForDc:dc];
        if (!link) {
            noshi_mt_rpc_result failed;
            memset(&failed, 0, sizeof(failed));
            failed.status = NOSHI_E_STATE;
            answer(&failed);
            return;
        }
        [link invokeBuilt:builder handler:answer authorizer:[self workerAuthorizerForDc:dc]];
    }];
    [builder release];
    [answer release];
}

- (void)signOut:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    [self invoke:"auth.logOut" configure:^noshi_status(noshi_arena *arena, noshi_tl_value *request) {
        (void)arena;
        (void)request;
        return NOSHI_OK;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        /* a key the server already dropped is as good as a finished logout */
        if (!error || NoshiIsRevokedError(error)) {
            _dropKeyPending = YES;
            error = nil;
        }
        NSString *delivered = [[error copy] autorelease];
        dispatch_async(dispatch_get_main_queue(), ^{ done(delivered); });
    }];
    [done release];
}

#pragma mark client callbacks

static noshi_status NoshiSend(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    NoshiSession *session = ctx;
    (void)dc;
    if (session->_socket.fd < 0) return NOSHI_E_STATE;
    return noshi_mt_socket_write_all(&session->_socket, data, len, WRITE_TIMEOUT_MS);
}

static noshi_status NoshiLoadSession(void *ctx, int32_t dc, noshi_mt_session_state *out) {
    NoshiSession *session = ctx;
    return NoshiSessionLoad(session->_directory, dc, out);
}

static noshi_status NoshiSaveSession(void *ctx, int32_t dc, const noshi_mt_session_state *state) {
    NoshiSession *session = ctx;
    return NoshiSessionStore(session->_directory, dc, state);
}

static void NoshiRpcResult(void *ctx, uint64_t id, const noshi_mt_rpc_result *result) {
    NoshiSession *session = ctx;
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:id];
    void (^handler)(const noshi_mt_rpc_result *) = [[session->_handlers objectForKey:key] retain];
    if (!handler) return;
    [session->_handlers removeObjectForKey:key];
    handler(result);
    [handler release];
}

/* the client has put something new in the store; whoever watches a chat reads it from there on the worker */
static void NoshiClientChanged(void *ctx) {
    [(NoshiSession *)ctx storeChanged];
}

static void NoshiClientPhoneCall(void *ctx, const noshi_tl_value *value) {
    NoshiSession *session = (NoshiSession *)ctx;
    noshi_phone_call call;
    noshi_status status = noshi_phone_call_parse(value, &call);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: a phone call update was rejected: %s", noshi_status_name(status));
        return;
    }
    [session->_calls handlePhoneCall:&call];
}

static void NoshiClientPhoneSignaling(void *ctx, int64_t callId, const uint8_t *data, size_t len) {
    NoshiSession *session = (NoshiSession *)ctx;
    NSData *bytes = [NSData dataWithBytes:data length:len];
    [session->_calls handleSignalingData:bytes callId:callId];
}

static void NoshiClientGroupCall(void *ctx, const noshi_tl_value *update, const noshi_tl_value *container) {
    NoshiSession *session = (NoshiSession *)ctx;
    [session->_groupCalls handleUpdate:update container:container];
}

static void NoshiClientFoldersChanged(void *ctx) {
    NoshiSession *session = ctx;
    [session deliverMain:^{
        [NSObject cancelPreviousPerformRequestsWithTarget:session selector:@selector(refreshChangedChatFolders) object:nil];
        [session performSelector:@selector(refreshChangedChatFolders) withObject:nil afterDelay:0];
    }];
}

NSString *const NoshiNewMessageDidArriveNotification = @"NoshiNewMessageDidArrive";
NSString *const NoshiDialogReadNotification = @"NoshiDialogRead";

static void NoshiClientNewMessage(void *ctx, const noshi_tl_value *message, const noshi_tl_value *users, const noshi_tl_value *chats) {
    NoshiSession *session = (NoshiSession *)ctx;
    noshi_dialog_row row;
    if (noshi_dialog_message_row(message, users, chats, session->_account, NOSHI_DIALOG_USER, &row) != NOSHI_OK) return;
    NoshiDialog *asUser = [[NoshiDialog alloc] initWithRow:&row];
    if (noshi_dialog_message_row(message, users, chats, session->_account, NOSHI_DIALOG_GROUP, &row) != NOSHI_OK) {
        [asUser release];
        return;
    }
    NoshiDialog *asGroup = [[NoshiDialog alloc] initWithRow:&row];
    [session deliverMain:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiNewMessageDidArriveNotification object:session
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:asUser, @"user", asGroup, @"group", nil]];
        [asUser release];
        [asGroup release];
    }];
}

static void NoshiClientReadOutbox(void *ctx, int32_t kind, int64_t peer, int32_t topic, int32_t maxId) {
    NoshiSession *session = (NoshiSession *)ctx;
    [session deliverMain:^{ [session noteReadOutbox:maxId ofKind:kind peer:peer topic:topic]; }];
}

static void NoshiClientUserStatus(void *ctx, int64_t user, noshi_presence presence, int32_t seen) {
    NoshiSession *session = (NoshiSession *)ctx;
    [session deliverMain:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiUserStatusDidChangeNotification object:session
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:user], @"user", [NSNumber numberWithInt:(int)presence], @"presence", [NSNumber numberWithInt:seen], @"seen", nil]];
    }];
}

static void NoshiClientTyping(void *ctx, const noshi_typing *typing) {
    NoshiSession *session = (NoshiSession *)ctx;
    int32_t kind = typing->peer_kind, top = typing->top_message;
    long long peer = typing->peer_id, user = typing->user_id;
    int action = (int)typing->action;
    /* a group names who writes, by the first name of a person the store knows; this runs on the worker, which is where the store may be read */
    NSString *name = nil;
    if (kind != 1 && user > 0 && action != NOSHI_TYPING_CANCEL) {
        NSString *full = [[session storedPersonWithKey:user] name];
        NSRange space = [full rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        name = space.location == NSNotFound ? full : [full substringToIndex:space.location];
    }
    [session deliverMain:^{
        /* typing is live only and runs out in seconds, so nobody sees it from the background, where the app is kept awake just for its link */
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
        [session.typing noteKind:kind peer:peer user:user action:action top:top name:name];
    }];
}

static void NoshiClientDraft(void *ctx, const noshi_tl_value *update) {
    [(NoshiSession *)ctx noteDraftUpdate:update];
}

static void NoshiClientError(void *ctx, noshi_status status, const char *boundary) {
    (void)ctx;
    NSLog(@"noshigram: client error at %s: %s", boundary, noshi_status_name(status));
}

static NSString *NoshiTlString(const noshi_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(object, field, &data, &len) != NOSHI_OK) return nil;
    return [[[NSString alloc] initWithBytes:data length:len encoding:NSUTF8StringEncoding] autorelease];
}

static NoshiCodeKind NoshiCodeKindOf(const noshi_tl_value *type) {
    if (noshi_tl_is(type, NOSHI_TL_ID_auth_sentCodeTypeApp)) return NoshiCodeKindApp;
    if (noshi_tl_is(type, NOSHI_TL_ID_auth_sentCodeTypeSms)) return NoshiCodeKindSms;
    if (noshi_tl_is(type, NOSHI_TL_ID_auth_sentCodeTypeCall)) return NoshiCodeKindCall;
    return NoshiCodeKindOther;
}

- (void)failureFromStatus:(noshi_status)status text:(const char *)text {
    char name[128];
    int32_t number = 0;
    name[0] = '\0';
    if (status == NOSHI_E_RPC && text) noshi_mt_rpc_error_split(text, name, sizeof(name), &number);
    else if (status == NOSHI_E_TIMEOUT) snprintf(name, sizeof(name), "TIMEOUT");
    else {
        NSLog(@"noshigram: auth failed: %s", noshi_status_name(status));
        snprintf(name, sizeof(name), "INTERNAL");
    }
    [self deliverFailure:[NSString stringWithUTF8String:name] number:number];
}

static void NoshiAuthChanged(void *ctx, noshi_auth_state state, noshi_status status,
                               const noshi_tl_value *value, const char *error) {
    NoshiSession *session = ctx;
    NoshiAuthEvent *event;
    /* these two arrive with the rpc error that caused them */
    if (state == NOSHI_AUTH_MIGRATE) {
        session->_migrateDc = session->_client.auth.migrate_dc;
        return;
    }
    if (state == NOSHI_AUTH_FLOOD_WAIT) {
        [session failureFromStatus:status text:error];
        return;
    }
    if (status != NOSHI_OK) {
        [session failureFromStatus:status text:error];
        return;
    }
    switch (state) {
    case NOSHI_AUTH_CODE: {
        const noshi_tl_value *type = noshi_tl_get(value, "type");
        int32_t length = 0, timeout = 0;
        noshi_tl_get_i32(type, "length", &length);
        if (noshi_tl_has(value, "timeout")) noshi_tl_get_i32(value, "timeout", &timeout);
        event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventCode] autorelease];
        [event setCodeKind:NoshiCodeKindOf(type) length:length
               resendAfter:noshi_tl_has(value, "next_type") ? timeout : -1];
        [session deliver:event];
        break;
    }
    case NOSHI_AUTH_PASSWORD:
        event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventPassword] autorelease];
        [event setHint:NoshiTlString(value, "hint")];
        [event setHasRecovery:noshi_tl_has(value, "has_recovery")];
        [session deliver:event];
        break;
    case NOSHI_AUTH_SIGNUP:
        [session deliverKind:NoshiAuthEventSignUp];
        break;
    case NOSHI_AUTH_AUTHORIZED: {
        int64_t account = 0;
        noshi_tl_get_i64(noshi_tl_get(value, "user"), "id", &account);
        session->_authorizedAccount = account;
        break;
    }
    case NOSHI_AUTH_QR: {
        char url[512];
        int32_t expires = 0;
        if (noshi_auth_qr_url(value, url, sizeof(url)) != NOSHI_OK || noshi_tl_get_i32(value, "expires", &expires) != NOSHI_OK) {
            NSLog(@"noshigram: the login token cannot be shown");
            [session deliverFailure:@"INTERNAL" number:0];
            break;
        }
        event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventQr] autorelease];
        [event setQrUrl:[NSString stringWithUTF8String:url] expires:(NSTimeInterval)expires];
        [session deliver:event];
        break;
    }
    case NOSHI_AUTH_EMAIL_SETUP:
    case NOSHI_AUTH_EMAIL_CODE:
        [session deliverKind:NoshiAuthEventUnsupported];
        break;
    case NOSHI_AUTH_RECOVERY:
        event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventRecovery] autorelease];
        [event setEmailPattern:NoshiTlString(value, "email_pattern")];
        [session deliver:event];
        break;
    case NOSHI_AUTH_IDLE:
    case NOSHI_AUTH_WAITING:
    case NOSHI_AUTH_MIGRATE:
    case NOSHI_AUTH_FLOOD_WAIT:
        break;
    }
}

#pragma mark worker

- (noshi_status)initClient {
    noshi_mt_client_config config;
    noshi_client_events events;
    memset(&config, 0, sizeof(config));
    memset(&events, 0, sizeof(events));
    config.dc_id = _dc;
    config.transport = NOSHI_MT_INTERMEDIATE;
    /* the header hides the protocol from providers that block plain telegram traffic */
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
    events.send = NoshiSend;
    events.load_session = NoshiLoadSession;
    events.save_session = NoshiSaveSession;
    events.auth = NoshiAuthChanged;
    events.error = NoshiClientError;
    events.changed = NoshiClientChanged;
    events.phone_call = NoshiClientPhoneCall;
    events.phone_signaling = NoshiClientPhoneSignaling;
    events.group_call = NoshiClientGroupCall;
    events.typing = NoshiClientTyping;
    events.read_outbox = NoshiClientReadOutbox;
    events.new_message = NoshiClientNewMessage;
    events.user_status = NoshiClientUserStatus;
    events.draft = NoshiClientDraft;
    events.folders_changed = NoshiClientFoldersChanged;
    events.result = NoshiRpcResult;
    noshi_status status = noshi_client_init(&_client, &config, NOSHI_API_HASH, &events);
    _clientLive = status == NOSHI_OK;
    if (_clientLive && _pingInterval) noshi_mt_client_set_ping_interval(&_client.mt, _pingInterval);
    return status;
}

- (void)closeSocket {
    if (_voip) {
        /* the streams of a voip socket hold a copy of the descriptor, so closing ours alone would leave the connection up */
        if (_socket.fd >= 0) shutdown(_socket.fd, SHUT_RDWR);
        NoshiVoipSocketDetach(_voip);
        _voip = NULL;
    }
    noshi_mt_socket_close(&_socket);
}

- (void)closeStore {
    if (!_store) return;
    noshi_status status = noshi_store_close(_store);
    if (status != NOSHI_OK) NSLog(@"noshigram: database close failed: %s", noshi_status_name(status));
    _store = NULL;
}

- (noshi_status)attachStoreForAccount:(int64_t)account {
    NSString *path = NoshiFilePath(_directory, [NSString stringWithFormat:@"noshigram-%lld.db", (long long)account]);
    noshi_status status = noshi_store_open(&_store, path.fileSystemRepresentation, account);
    if (status != NOSHI_OK) return status;
    status = noshi_client_attach_store(&_client, _store, account);
    if (status != NOSHI_OK) [self closeStore];
    return status;
}

/* a client that is gone cannot answer, so its waiting requests are failed instead of left hanging */
- (void)failPendingRequests {
    NSArray *handlers = [_handlers allValues];
    [_handlers removeAllObjects];
    noshi_mt_rpc_result failed;
    memset(&failed, 0, sizeof(failed));
    failed.status = NOSHI_E_STATE;
    for (void (^handler)(const noshi_mt_rpc_result *) in handlers) handler(&failed);
}

- (void)linkWanted {
    if (_wantLink) return;
    _failures = 0;
    _retryAt = 0;
    _wantLink = YES;
}

/* a failed link retries with a doubling pause; a login gives up after RETRY_LIMIT in a row and waits for its
   screen to ask again */
- (void)linkLost:(noshi_status)reason {
    int32_t transport = _clientLive ? noshi_mt_client_transport_error(&_client.mt) : 0;
    int64_t securityValue = 0;
    const char *securityNote = _clientLive ? noshi_mt_client_security_note(&_client.mt, &securityValue) : NULL;
    NSLog(@"noshigram: link to dc %d lost: %s (transport error %d, last message 0x%08x%s%s %lld)", (int)_dc, noshi_status_name(reason),
          (int)transport, _clientLive ? noshi_mt_client_last_ctor(&_client.mt) : 0u, securityNote ? ", refused: " : "",
          securityNote ? securityNote : "", (long long)securityValue);
    [self closeSocket];
    if (_clientLive) noshi_client_disconnected(&_client);
    if (transport == TRANSPORT_AUTH_KEY_UNKNOWN) {
        [self dropSessionKey];
        return;
    }
    if (_failures < UINT_MAX) ++_failures;
    if (_failures >= RETRY_LIMIT && _account <= 0) {
        _wantLink = NO;
        if (_clientLive) noshi_auth_cancel(&_client.auth);
        [self deliverKind:NoshiAuthEventOffline];
        return;
    }
    /* the shift is bounded so a long outage cannot overflow it */
    unsigned shift = MIN(_failures - 1, 5u);
    _retryAt = NoshiNowMs() + MIN(1000u << shift, RETRY_PAUSE_MAX_MS);
}

/* the server forgot the key: a stored account is lost, a login in progress just needs a new handshake */
- (void)dropSessionKey {
    BOOL hadAccount = [NoshiSession hasAccountInDirectory:_directory];
    unlink(NoshiSessionPath(_directory, _dc).fileSystemRepresentation);
    if (hadAccount) {
        unlink(NoshiAccountPath(_directory).fileSystemRepresentation);
        [self closeStore];
        _account = 0;
    }
    noshi_client_free(&_client);
    _clientLive = NO;
    [self failPendingRequests];
    noshi_status status = [self initClient];
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: client restart failed: %s", noshi_status_name(status));
        _wantLink = NO;
        [self deliverFailure:@"INTERNAL" number:status];
        return;
    }
    _failures = 0;
    _retryAt = 0;
    if (hadAccount) {
        /* the app replaces this session with a new one for the directory, which makes its own key. this one must not open a link of its own meanwhile: two connections
           that make keys into one session file, or one that still holds the old key while the next signs in, are what the server answers with AUTH_KEY_DUPLICATED */
        _wantLink = NO;
        [self deliverKind:NoshiAuthEventLoggedOut];
    }
}

/* worker only: tells the main thread when the link starts or stops working */
- (void)reportLink:(BOOL)works {
    if (works == _linkReported) return;
    _linkReported = works;
    dispatch_async(dispatch_get_main_queue(), ^{
        _connected = works;
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiSessionConnectionDidChangeNotification object:self];
    });
}

- (void)openLink {
    const char *host = noshi_dc_host(_dc);
    noshi_status status = NoshiProxyConnect(&_socket, host, noshi_dc_port(), CONNECT_TIMEOUT_MS, &_client.config);
    if (status == NOSHI_OK) {
        _client.mt.config.transport = _client.config.transport;
        _client.mt.config.obfuscation = _client.config.obfuscation;
    }
    /* a signed in link that should keep working while the app sleeps is made a voip socket */
    if (status == NOSHI_OK && _account > 0 && NoshiBackgroundLinkWanted()) _voip = NoshiVoipSocketAttach(_socket.fd);
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
        [self settleClient];
        if (status != NOSHI_OK && status != NOSHI_E_RETRY) {
            [self linkLost:status];
            return;
        }
        if (_client.mt.state == NOSHI_MT_CLIENT_DEAD) {
            [self linkLost:NOSHI_E_STATE];
            return;
        }
    }
}

/* work a callback asked for but could not do from inside the client */
- (void)settleClient {
    if (_dropKeyPending) {
        _dropKeyPending = NO;
        [self closeSocket];
        [self dropSessionKey];
        return;
    }
    if (_migrateDc) {
        int32_t dc = _migrateDc;
        _migrateDc = 0;
        [self closeSocket];
        noshi_status status = noshi_client_migrate(&_client, dc);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: migration to dc %d failed: %s", (int)dc, noshi_status_name(status));
            [self deliverFailure:@"INTERNAL" number:status];
            return;
        }
        _dc = dc;
        _failures = 0;
        _retryAt = 0;
        _wantLink = YES;
    }
    if (_authorizedAccount) {
        int64_t account = _authorizedAccount;
        _authorizedAccount = 0;
        [self completeAuthorization:account];
    }
}

- (void)completeAuthorization:(int64_t)account {
    uint8_t buf[NOSHI_ACCOUNT_FILE_LEN];
    size_t len;
    noshi_status status = noshi_account_pack(_dc, account, buf, sizeof(buf), &len);
    if (status == NOSHI_OK) status = [self attachStoreForAccount:account];
    if (status == NOSHI_OK) status = NoshiWriteFile(NoshiAccountPath(_directory), buf, len);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: account could not be stored: %s", noshi_status_name(status));
        [self deliverFailure:@"STORAGE" number:status];
        return;
    }
    _account = account;
    NoshiAuthEvent *event = [[[NoshiAuthEvent alloc] initWithKind:NoshiAuthEventAuthorized] autorelease];
    [event setUserId:account];
    [self deliver:event];
}

- (void)drainCommands {
    [_lock lock];
    NSArray *batch = [[_commands copy] autorelease];
    [_commands removeAllObjects];
    [_lock unlock];
    for (void (^command)(void) in batch) {
        command();
        [self settleClient];
    }
}

- (void)run {
    NSAutoreleasePool *setup = [[NSAutoreleasePool alloc] init];
    uint8_t buf[NOSHI_ACCOUNT_FILE_LEN + 1];
    size_t len;
    int64_t account = 0;
    _dc = 2;
    if (NoshiReadFile(NoshiAccountPath(_directory), buf, sizeof(buf), &len) == NOSHI_OK &&
        noshi_account_unpack(buf, len, &_dc, &account) != NOSHI_OK) {
        NSLog(@"noshigram: account file is unusable, starting signed out");
        account = 0;
        _dc = 2;
    }
    noshi_status status = [self initClient];
    if (status == NOSHI_OK && account > 0) status = [self attachStoreForAccount:account];
    if (status == NOSHI_OK) _account = account;
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: session start failed: %s", noshi_status_name(status));
        [self deliverFailure:@"INTERNAL" number:status];
    } else {
        _wantLink = YES;
    }
    [setup drain];

    while (_clientLive && ![self isStopping]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self drainCommands];
        uint64_t now = NoshiNowMs();
        if (_wantLink && _socket.fd < 0 && now >= _retryAt) [self openLink];

        /* a failed difference pauses the sync, and the pause lifts after a growing delay: left alone it holds back every new message until the app restarts */
        if (_clientLive && _client.sync_suspended && _client.sync_retry) {
            if (!_syncRetryAt) {
                if (!_syncBackoffMs) _syncBackoffMs = SYNC_RETRY_FIRST_MS;
                _syncRetryAt = now + _syncBackoffMs;
                _syncBackoffMs = MIN(_syncBackoffMs * 2, (uint32_t)SYNC_RETRY_MAX_MS);
            } else if (now >= _syncRetryAt) {
                _syncRetryAt = 0;
                noshi_client_resume_sync(&_client);
            }
        } else if (_clientLive && !_client.updates.needs_difference) {
            _syncRetryAt = 0;
            _syncBackoffMs = 0;
        }

        uint32_t next = POLL_CAP_MS;
        if (_clientLive && noshi_client_tick(&_client, &next) != NOSHI_OK) next = POLL_CAP_MS;
        /* a request can fail in this tick, after the retry deadline was checked */
        if (_clientLive && _client.sync_suspended && _client.sync_retry && !_syncRetryAt) next = 0;
        if (_syncRetryAt) {
            now = NoshiNowMs();
            uint32_t wait = _syncRetryAt > now ? (uint32_t)MIN(_syncRetryAt - now, (uint64_t)POLL_CAP_MS) : 0;
            if (wait < next) next = wait;
        }
        [self settleClient];
        /* a restored key is ready the moment it connects, so only a frame the server sent and the client accepted
           counts as a link that works */
        BOOL linkWorks = _clientLive && _socket.fd >= 0 && _client.mt.state == NOSHI_MT_CLIENT_READY && noshi_mt_client_heard(&_client.mt);
        if (linkWorks) _failures = 0;
        [self reportLink:linkWorks];
        if (next > POLL_CAP_MS) next = POLL_CAP_MS;
        if (_wantLink && _socket.fd < 0) {
            now = NoshiNowMs();
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
            NSLog(@"noshigram: poll failed, errno %d", errno);
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
    [_calls shutdown];
    [_groupCalls shutdown];
    for (NoshiMediaLink *link in [_links allValues]) [link stop];
    [self closeSocket];
    if (_clientLive) noshi_client_free(&_client);
    _clientLive = NO;
    [self failPendingRequests];
    [self closeStore];
    [teardown drain];
    dispatch_semaphore_signal(_exited);
}

@end

#import "noshi_updater.h"

#import <UIKit/UIKit.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#import "noshi_shiro_network.h"
#import "noshi_system_notifications.h"
#include "noshi_crypto.h"
#include "noshi_https.h"
#include "noshi_release.h"
#include "noshi_update.h"

#define UPDATE_TIMEOUT_MS (30 * 60 * 1000)
#define DIGEST_TIMEOUT_MS 20000
#define DIGEST_FILE_LIMIT 512u
#define IPA_LIMIT (128u * 1024u * 1024u)
#define REDIRECT_LIMIT 4
#define DOWNLOAD_SHARE 0.7f
#define APP_FOLDER "Noshigram.app"

extern char **environ;

typedef struct fetch_state {
    int fd;                         /* the file the body goes to, or -1 when it goes to text */
    char *text;
    size_t text_len, text_cap;
    noshi_digest *digest;
    uint64_t received;
    void *owner;
    void (*note)(void *owner, uint64_t received, uint64_t total);
    /* the length the server announced for the body being read; a release found through the web page has no size in its record */
    const uint64_t *length;
    volatile int *cancelled;
} fetch_state;

static int fetch_cancelled(void *ctx) {
    fetch_state *state = (fetch_state *)ctx;
    return state->cancelled && *state->cancelled;
}

static noshi_status fetch_take(void *ctx, const uint8_t *data, size_t len) {
    fetch_state *state = (fetch_state *)ctx;
    if (state->fd < 0) {
        if (len > state->text_cap - state->text_len) return NOSHI_E_LIMIT;
        memcpy(state->text + state->text_len, data, len);
        state->text_len += len;
        return NOSHI_OK;
    }
    if (state->digest && noshi_digest_update(state->digest, data, len) != NOSHI_OK) return NOSHI_E_CRYPTO;
    while (len > 0) {
        ssize_t put = write(state->fd, data, len);
        if (put < 0 && errno == EINTR) continue;
        if (put <= 0) {
            NSLog(@"noshigram: update temporary file write failed: %s", put < 0 ? strerror(errno) : "zero bytes written");
            return NOSHI_E_STORAGE;
        }
        data += put;
        len -= (size_t)put;
        state->received += (uint64_t)put;
    }
    if (state->note) state->note(state->owner, state->received, state->length ? *state->length : 0);
    return NOSHI_OK;
}

/* a GET that follows at most REDIRECT_LIMIT redirects, each one an absolute https url on a GitHub host; the body of the final 200 goes to state.
   No credentials are ever sent, so a redirect to the download host carries nothing from the first request */
static noshi_status fetch(NSString *url, NSData *roots, int timeout_ms, size_t max_body, fetch_state *state) {
    static const char *const headers[] = {"User-Agent: Noshigram", "Accept: application/octet-stream", "Accept-Encoding: identity", NULL};
    char current[NOSHI_RELEASE_URL_MAX + 2048];
    int hop;
    if (![url getCString:current maxLength:sizeof(current) encoding:NSUTF8StringEncoding]) return NOSHI_E_LIMIT;
    for (hop = 0; hop <= REDIRECT_LIMIT; ++hop) {
        char host[NOSHI_RELEASE_HOST_MAX], path[2048];
        noshi_https_request request;
        noshi_https_head head;
        noshi_status status = noshi_release_url_split(current, host, sizeof(host), path, sizeof(path));
        if (status != NOSHI_OK) return status;
        memset(&request, 0, sizeof(request));
        request.host = host;
        request.path = path;
        request.port = 443;
        request.headers = headers;
        request.roots_pem = (const char *)roots.bytes;
        request.roots_len = roots.length;
        request.timeout_ms = timeout_ms;
        request.max_response = max_body;
        request.is_cancelled = fetch_cancelled;
        request.cancel_ctx = state;
        memset(&head, 0, sizeof(head));
        state->length = &head.content_length;
        request.connect_socket = NoshiShiroNetworkConnectSocket;
        status = noshi_https_get_stream(&request, &head, fetch_take, state);
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: update request to %s failed: %s, received %llu bytes", host, noshi_status_name(status), (unsigned long long)state->received);
            return status;
        }
        if (head.status == 200) return NOSHI_OK;
        if ((head.status == 301 || head.status == 302 || head.status == 303 || head.status == 307 || head.status == 308) && head.location[0]) {
            if (strlen(head.location) >= sizeof(current)) return NOSHI_E_LIMIT;
            strcpy(current, head.location);
            continue;
        }
        NSLog(@"noshigram: update download answered HTTP %d", head.status);
        return head.status == 404 ? NOSHI_E_NOTFOUND : NOSHI_E_IO;
    }
    return NOSHI_E_LIMIT;
}

@interface NoshiUpdater () {
    NSString *_ipaURL;
    NSString *_digestURL;
    void (^_onChange)(void);
    NoshiUpdaterState _state;
    float _fraction;
    uint64_t _downloaded;
    uint64_t _expected;
    BOOL _installing;
    noshi_status _failure;
    volatile int _cancelled;
    UIBackgroundTaskIdentifier _background;
}
- (void)setDownloaded:(uint64_t)received total:(uint64_t)total;
- (void)setInstallFraction:(float)fraction;
- (BOOL)isCancelled;
- (noshi_status)runWithIpaPath:(NSString *)ipaPath;
@end

@implementation NoshiUpdater

@synthesize onChange = _onChange;
@synthesize state = _state;
@synthesize fraction = _fraction;
@synthesize downloaded = _downloaded;
@synthesize expected = _expected;
@synthesize installing = _installing;
@synthesize failure = _failure;

+ (NSData *)trustedRoots {
    NSData *base = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"]];
    NSData *github = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"github-roots" ofType:@"pem"]];
    if (!base.length || !github.length) return nil;
    NSMutableData *roots = [NSMutableData dataWithData:base];
    [roots appendData:github];
    return roots;
}

/* a user app installed with an apple signature has no entitlement to write its own bundle, so the probe below fails and it is left alone; an ldid
   install of the jailbreak ipa (appsync, 3utools on a jailbroken phone) keeps the entitlement and passes */
+ (BOOL)canInstallInPlace {
    NSString *bundle = [[[NSBundle mainBundle] bundlePath] stringByResolvingSymlinksInPath];
    if (![bundle hasPrefix:@"/Applications/"] && ![bundle hasPrefix:@"/var/jb/Applications/"] &&
        ![bundle hasPrefix:@"/private/var/jb/Applications/"] && ![bundle hasPrefix:@"/private/var/containers/Bundle/Application/"] &&
        ![bundle hasPrefix:@"/var/containers/Bundle/Application/"]) return NO;
    if (access("/usr/bin/uicache", X_OK) != 0 && access("/var/jb/usr/bin/uicache", X_OK) != 0) return NO;
    NSString *template = [bundle stringByAppendingPathComponent:@".noshigram-update-probe-XXXXXX"];
    char *path = strdup([template fileSystemRepresentation]);
    if (!path) return NO;
    int fd = mkstemp(path);
    BOOL writable = fd >= 0;
    if (fd >= 0) {
        if (close(fd) != 0) writable = NO;
        if (unlink(path) != 0) writable = NO;
    }
    free(path);
    return writable;
}

+ (BOOL)openDownloadOfIpaURL:(NSString *)ipaURL {
    NSURL *url = ipaURL.length ? [NSURL URLWithString:ipaURL] : nil;
    if (!url) url = [NSURL URLWithString:@"https://github.com/wowodymyr/Noshigram/releases/latest"];
    BOOL opened = [[UIApplication sharedApplication] openURL:url];
    if (!opened) NSLog(@"noshigram: the system did not take the release download link");
    return opened;
}

- (id)initWithIpaURL:(NSString *)ipaURL digestURL:(NSString *)digestURL size:(uint64_t)size {
    self = [super init];
    if (!self) return nil;
    _ipaURL = [ipaURL copy];
    _digestURL = [digestURL copy];
    _expected = size;
    _background = UIBackgroundTaskInvalid;
    return self;
}

- (void)dealloc {
    [_ipaURL release];
    [_digestURL release];
    [_onChange release];
    [super dealloc];
}

/* the object stays alive until the block has run, since the change that ends the run lets go of the owner's hold on it */
- (void)changeOnMain:(void (^)(void))change {
    [self retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        change();
        if (_onChange) _onChange();
        [self release];
    });
}

- (void)cancel {
    _cancelled = 1;
}

- (void)start {
    if (_state != NoshiUpdaterIdle) return;
    _state = NoshiUpdaterWorking;
    [self retain];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    _background = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        /* the time the system grants is over: stop cleanly rather than be killed with a file half moved */
        _cancelled = 1;
    }];
    if (_onChange) _onChange();
    NSString *ipaPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"noshigram-update.ipa"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        noshi_status status = [self runWithIpaPath:ipaPath];
        BOOL cancelled = _cancelled && status != NOSHI_OK;
        [self changeOnMain:^{
            _state = status == NOSHI_OK ? NoshiUpdaterDone : cancelled ? NoshiUpdaterCancelled : NoshiUpdaterFailed;
            _failure = status;
            if (status == NOSHI_OK) _fraction = 1;
            [UIApplication sharedApplication].idleTimerDisabled = NO;
            if (_background != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:_background];
            _background = UIBackgroundTaskInvalid;
            [self release];
        }];
        [pool drain];
    });
}

static void note_download(void *owner, uint64_t received, uint64_t total) {
    NoshiUpdater *updater = (NoshiUpdater *)owner;
    static CFAbsoluteTime last;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    /* the main thread is told about a tenth of a second of data at a time, not about every read */
    if (now - last < 0.1 && received != updater.expected) return;
    last = now;
    [updater setDownloaded:received total:total];
}

- (void)setDownloaded:(uint64_t)received total:(uint64_t)total {
    [self changeOnMain:^{
        _downloaded = received;
        if (!_expected && total <= IPA_LIMIT) _expected = total;
        _fraction = _expected ? MIN(1.0f, (float)((double)received / (double)_expected)) * DOWNLOAD_SHARE : 0;
    }];
}

static noshi_status install_progress(void *ctx, noshi_update_phase phase, uint64_t done, uint64_t total) {
    NoshiUpdater *updater = (NoshiUpdater *)ctx;
    float part = total ? (float)((double)done / (double)total) : 1.0f;
    /* compare reads the installed files, staging inflates the changed ones, moving is the quick end */
    float fraction = phase == NOSHI_UPDATE_COMPARE ? 0.25f * part : phase == NOSHI_UPDATE_STAGE ? 0.25f + 0.65f * part : 0.9f + 0.1f * part;
    [updater setInstallFraction:DOWNLOAD_SHARE + (1.0f - DOWNLOAD_SHARE) * fraction];
    /* only before the first file is moved can the user stop it */
    return phase != NOSHI_UPDATE_COMMIT && [updater isCancelled] ? NOSHI_E_RETRY : NOSHI_OK;
}

- (BOOL)isCancelled {
    return _cancelled != 0;
}

- (void)setInstallFraction:(float)fraction {
    [self changeOnMain:^{
        _installing = YES;
        _fraction = fraction;
    }];
}

/* a small program run with an argument vector and waited for; the home screen's cache of the app is refilled by uicache */
static void refresh_home_screen(void) {
    char *argv[] = {"uicache", NULL};
    pid_t pid = 0;
    int status = 0;
    const char *path = access("/usr/bin/uicache", X_OK) == 0 ? "/usr/bin/uicache" : "/var/jb/usr/bin/uicache";
    if (posix_spawn(&pid, path, NULL, NULL, argv, environ) != 0) {
        NSLog(@"noshigram: uicache did not start after the update");
        return;
    }
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) NSLog(@"noshigram: uicache ended with status %d after the update", status);
}

- (noshi_status)runWithIpaPath:(NSString *)ipaPath {
    NSData *roots = [NoshiUpdater trustedRoots];
    const char *path = ipaPath.fileSystemRepresentation;
    fetch_state state;
    uint8_t wanted[32], got[32];
    char text[DIGEST_FILE_LIMIT];
    noshi_status status;
    noshi_digest *digest;
    NSString *plistExecutable = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"];
    if (!roots) {
        NSLog(@"noshigram: update trust roots are missing");
        return NOSHI_E_SECURITY;
    }
    if (!_ipaURL.length || !_digestURL.length || !plistExecutable.length) return NOSHI_E_ARG;
    if (![NoshiUpdater canInstallInPlace]) return NOSHI_E_STATE;
    if (_expected > IPA_LIMIT) return NOSHI_E_LIMIT;

    memset(&state, 0, sizeof(state));
    state.fd = -1;
    state.text = text;
    state.text_cap = sizeof(text);
    state.cancelled = &_cancelled;
    status = fetch(_digestURL, roots, DIGEST_TIMEOUT_MS, DIGEST_FILE_LIMIT, &state);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: update checksum download failed: %s", noshi_status_name(status));
        return status;
    }
    status = noshi_release_parse_sha256(text, state.text_len, wanted);
    if (status != NOSHI_OK) return status;

    if (unlink(path) != 0 && errno != ENOENT) {
        NSLog(@"noshigram: update temporary file removal failed: %s", strerror(errno));
        return NOSHI_E_STORAGE;
    }
    memset(&state, 0, sizeof(state));
    state.fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (state.fd < 0) {
        NSLog(@"noshigram: update temporary file creation failed: %s", strerror(errno));
        return NOSHI_E_STORAGE;
    }
    digest = noshi_digest_new(1);
    if (!digest) {
        close(state.fd);
        unlink(path);
        return NOSHI_E_CRYPTO;
    }
    state.digest = digest;
    state.owner = self;
    state.note = note_download;
    state.cancelled = &_cancelled;
    status = fetch(_ipaURL, roots, UPDATE_TIMEOUT_MS, IPA_LIMIT, &state);
    if (close(state.fd) != 0 && status == NOSHI_OK) {
        NSLog(@"noshigram: update temporary file close failed: %s", strerror(errno));
        status = NOSHI_E_STORAGE;
    }
    if (status != NOSHI_OK) NSLog(@"noshigram: update ipa download failed: %s", noshi_status_name(status));
    if (status == NOSHI_OK) status = noshi_digest_finish(digest, got, sizeof(got));
    noshi_digest_free(digest);
    if (status == NOSHI_OK && memcmp(got, wanted, sizeof(got)) != 0) status = NOSHI_E_SECURITY;
    if (status == NOSHI_OK) {
        [self setDownloaded:state.received total:0];
        [self setInstallFraction:DOWNLOAD_SHARE];
        status = noshi_update_apply(path, [[NSBundle mainBundle] bundlePath].fileSystemRepresentation, APP_FOLDER, plistExecutable.UTF8String, install_progress, self);
        if (status != NOSHI_OK) NSLog(@"noshigram: update installation failed: %s", noshi_status_name(status));
        if (status == NOSHI_OK) {
            /* the new Info.plist comes from the ipa and has no internal tag, so ios 5 and 6 would stop giving the app banners; the tag goes back before the cache is rebuilt */
            if (NoshiSystemNotificationsRun("on") != 0) NSLog(@"noshigram: the notification setup for /Applications failed after the update, banners will not show on ios 5 and 6");
            refresh_home_screen();
        }
    }
    unlink(path);
    return status;
}

@end

#import "noshi_release_check.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_theme.h"
#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_updater.h"
#import "noshi_wave_progress.h"
#include "noshi_https.h"
#include "noshi_release.h"
#include <math.h>
#include <string.h>

#define RELEASE_RESPONSE_LIMIT (64u * 1024u)
#define RELEASE_TIMEOUT_MS 15000

typedef enum { NoticeOffer, NoticeWorking, NoticeDone, NoticeFailed } NoticeMode;

@interface NoshiReleaseNotice : UIView <UIGestureRecognizerDelegate> {
    UIView *_card;
    UILabel *_title;
    UITextView *_notes;
    UILabel *_status;
    NoshiWaveProgress *_wave;
    UIButton *_primary;
    UIButton *_secondary;
    NSString *_version;
    NSString *_releaseNotes;
    NSString *_ipaURL;
    NSString *_digestURL;
    uint64_t _size;
    NoshiUpdater *_updater;
    NoticeMode _mode;
    BOOL _leaving;
}
- (id)initWithTag:(NSString *)tag notes:(NSString *)notes ipaURL:(NSString *)ipaURL digestURL:(NSString *)digestURL size:(uint64_t)size;
@end

@implementation NoshiReleaseNotice
- (UIButton *)buttonWithAction:(SEL)action bold:(BOOL)bold {
    UIButton *button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    button.titleLabel.font = bold ? NoshiFontBold(16) : NoshiFontMedium(15);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:button];
    return button;
}
- (id)initWithTag:(NSString *)tag notes:(NSString *)notes ipaURL:(NSString *)ipaURL digestURL:(NSString *)digestURL size:(uint64_t)size {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.48];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _version = [([tag hasPrefix:@"v"] || [tag hasPrefix:@"V"] ? tag : [@"v" stringByAppendingString:tag]) copy];
    _releaseNotes = [(notes.length ? notes : NSLocalizedString(@"release.empty", nil)) copy];
    _ipaURL = [ipaURL copy];
    _digestURL = [digestURL copy];
    _size = size;
    _card = [[UIView alloc] init];
    /* the plate of the classic menus, with its shadow outside the card, so the card does not clip */
    NoshiClassicApplyMenuPlate(_card, 14);
    [self addSubview:_card];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = NoshiClassicMenuTextColor();
    _title.font = NoshiFontBold(19);
    NoshiClassicStyleMenuLabel(_title, 19);
    _title.textAlignment = NoshiTextAlignmentCenter;
    _title.numberOfLines = 2;
    [_card addSubview:_title];
    _notes = [[UITextView alloc] init];
    _notes.backgroundColor = [UIColor clearColor];
    _notes.textColor = [NoshiClassicMenuTextColor() colorWithAlphaComponent:0.8f];
    _notes.font = NoshiFontRegular(14);
    _notes.editable = NO;
    [_card addSubview:_notes];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = NoshiColorSecondary();
    _status.font = NoshiFontMedium(14);
    _status.textAlignment = NoshiTextAlignmentCenter;
    _status.numberOfLines = 3;
    [_card addSubview:_status];
    _wave = [[NoshiWaveProgress alloc] init];
    _wave.userInteractionEnabled = NO;
    [_card addSubview:_wave];
    _primary = [self buttonWithAction:@selector(primaryTapped) bold:YES];
    [_primary setBackgroundImage:NoshiClassicKeyImage(NoshiClassicKeyAccent, NO) forState:UIControlStateNormal];
    [_primary setBackgroundImage:NoshiClassicKeyImage(NoshiClassicKeyAccent, YES) forState:UIControlStateHighlighted];
    [_primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _secondary = [self buttonWithAction:@selector(secondaryTapped) bold:NO];
    [_secondary setTitleColor:NoshiClassicMenuTextColor() forState:UIControlStateNormal];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped)] autorelease];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    [self showMode:NoticeOffer failure:NOSHI_OK];
    return self;
}
- (void)dealloc {
    _updater.onChange = nil;
    [_updater cancel];
    [_updater release];
    [_card release]; [_title release]; [_notes release]; [_status release]; [_wave release];
    [_primary release]; [_secondary release];
    [_version release]; [_releaseNotes release]; [_ipaURL release]; [_digestURL release];
    [super dealloc];
}
/* a tap on the dimmed part closes the notice, except while files are being replaced or the app waits for its restart */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return (_mode == NoticeOffer || _mode == NoticeFailed) && !CGRectContainsPoint(_card.frame, [touch locationInView:self]);
}
- (void)backdropTapped { [self close]; }

/* the notice can install only a release that has the files, into an app folder this process may write */
- (BOOL)canUpdate {
    return _ipaURL.length && _digestURL.length && [NoshiUpdater canInstallInPlace];
}
- (NSString *)failureText:(noshi_status)status {
    NSString *key;
    switch (status) {
    case NOSHI_E_IO: key = _updater.installing ? @"release.fail.install" : @"release.fail.network"; break;
    /* the chain, the host name or the digest did not check out */
    case NOSHI_E_SECURITY: key = @"release.fail.security"; break;
    case NOSHI_E_STORAGE: key = @"release.fail.storage"; break;
    case NOSHI_E_NOTFOUND: key = @"release.fail.missing"; break;
    case NOSHI_E_STATE: key = [NoshiUpdater canInstallInPlace] ? @"release.fail.install" : @"release.fail.readonly"; break;
    case NOSHI_E_MALFORMED: case NOSHI_E_UNSUPPORTED: case NOSHI_E_LIMIT: key = @"release.fail.format"; break;
    default: key = @"release.fail.network"; break;
    }
    return NSLocalizedString(key, nil);
}
- (void)showMode:(NoticeMode)mode failure:(noshi_status)failure {
    _mode = mode;
    BOOL offer = mode == NoticeOffer, working = mode == NoticeWorking;
    _notes.hidden = working;
    _status.hidden = !working && !(offer && ![self canUpdate]);
    _wave.hidden = !working;
    _primary.hidden = working;
    _secondary.hidden = mode == NoticeDone;
    if (offer) {
        _title.text = [NSString stringWithFormat:NSLocalizedString(@"release.title", nil), _version];
        _notes.text = _releaseNotes;
        _notes.contentOffset = CGPointZero;
        BOOL can = [self canUpdate];
        _status.text = can ? @"" : NSLocalizedString(_ipaURL.length && _digestURL.length ? @"release.readonly" : @"release.noasset", nil);
        [_primary setTitle:NSLocalizedString(can ? @"release.update" : @"release.open", nil) forState:UIControlStateNormal];
        [_secondary setTitle:NSLocalizedString(@"release.later", nil) forState:UIControlStateNormal];
    } else if (working) {
        _title.text = NSLocalizedString(@"release.updating", nil);
        [_secondary setTitle:NSLocalizedString(@"release.cancel", nil) forState:UIControlStateNormal];
    } else if (mode == NoticeDone) {
        _title.text = [NSString stringWithFormat:NSLocalizedString(@"release.updated", nil), _version];
        _notes.text = NSLocalizedString(@"release.restart.note", nil);
        [_primary setTitle:NSLocalizedString(@"release.restart", nil) forState:UIControlStateNormal];
    } else {
        _title.text = NSLocalizedString(@"release.fail.title", nil);
        _notes.text = [self failureText:failure];
        [_primary setTitle:NSLocalizedString(@"release.retry", nil) forState:UIControlStateNormal];
        [_secondary setTitle:NSLocalizedString(@"release.open", nil) forState:UIControlStateNormal];
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(1, MIN(360, self.bounds.size.width - 32));
    CGFloat height = MAX(1, MIN(420, self.bounds.size.height - 32));
    CGFloat inner = width - 32;
    CGFloat y = 14;
    /* the card keeps its size while it springs in or out, so the frame is set with the transform put aside */
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - height) / 2), width, height);
    NoshiClassicFitPlate(_card, 0);
    _card.transform = held;
    _title.frame = CGRectMake(16, y, inner, 48);
    y += 52;
    CGFloat bottom = height - 108;
    _notes.frame = CGRectMake(16, y, inner, MAX(0, bottom - y - (_status.hidden || _mode == NoticeWorking ? 0 : 52)));
    _status.frame = CGRectMake(16, _mode == NoticeWorking ? y + 12 : bottom - 52, inner, _mode == NoticeWorking ? 40 : 50);
    _wave.frame = CGRectMake(16 - NoshiWaveProgressInset, _mode == NoticeWorking ? y + 56 : 0, inner + 2 * NoshiWaveProgressInset, NoshiWaveProgressHeight);
    _primary.frame = CGRectMake(16, height - 104, inner, 44);
    _secondary.frame = CGRectMake(16, height - 56, inner, 40);
}
/* the notice comes up as the other popups do: the dim fades in and the card springs from a little smaller */
- (void)presentInView:(UIView *)host {
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    if (NoshiReduceMotionEnabled()) return;
    self.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale());
    NoshiAnimateView(self, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(_card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}
- (void)close {
    if (_leaving) return;
    _leaving = YES;
    if (NoshiReduceMotionEnabled() || !self.superview) {
        [self removeFromSuperview];
        return;
    }
    [self retain];
    NoshiAnimateView(self, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_card, CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()), 1, NoshiPopupCurve(NO), ^(BOOL done) {
        (void)done;
        [self removeFromSuperview];
        [self autorelease];
    });
}
- (void)openRelease {
    [NoshiUpdater openDownloadOfIpaURL:_ipaURL];
    [self close];
}
- (void)primaryTapped {
    if (_mode == NoticeDone) {
        /* the files on disk are the new version and this process is the old one; the system starts the new program on the next launch */
        exit(0);
    }
    if (_mode == NoticeOffer && ![self canUpdate]) {
        [self openRelease];
        return;
    }
    [self startUpdate];
}
- (void)secondaryTapped {
    if (_mode == NoticeWorking) {
        [_updater cancel];
        _secondary.enabled = NO;
        return;
    }
    if (_mode == NoticeFailed) [self openRelease];
    else [self close];
}
- (NSString *)megabytes:(uint64_t)bytes {
    return [NSString stringWithFormat:@"%.1f", (double)bytes / (1024.0 * 1024.0)];
}
- (void)startUpdate {
    _updater.onChange = nil;
    [_updater release];
    _updater = [[NoshiUpdater alloc] initWithIpaURL:_ipaURL digestURL:_digestURL size:_size];
    NoshiReleaseNotice *notice = self;
    _updater.onChange = ^{ [notice updaterChanged]; };
    _secondary.enabled = YES;
    _wave.value = 0;
    /* the classic look has no waves: there the bar lies flat */
    _wave.waving = NO;
    _status.text = NSLocalizedString(@"release.preparing", nil);
    [self showMode:NoticeWorking failure:NOSHI_OK];
    [_updater start];
}
- (void)updaterChanged {
    switch (_updater.state) {
    case NoshiUpdaterWorking:
        if (_updater.installing) _status.text = NSLocalizedString(@"release.installing", nil);
        else if (_updater.downloaded > 0) _status.text = [NSString stringWithFormat:NSLocalizedString(@"release.progress", nil), [self megabytes:_updater.downloaded], [self megabytes:_updater.expected]];
        [_wave setValue:_updater.fraction gliding:YES];
        break;
    case NoshiUpdaterDone:
        _wave.value = 1;
        _wave.waving = NO;
        [self showMode:NoticeDone failure:NOSHI_OK];
        break;
    case NoshiUpdaterCancelled:
        _secondary.enabled = YES;
        [self showMode:NoticeOffer failure:NOSHI_OK];
        break;
    case NoshiUpdaterFailed:
        _secondary.enabled = YES;
        NSLog(@"noshigram: update failed: %s", noshi_status_name(_updater.failure));
        [self showMode:NoticeFailed failure:_updater.failure];
        break;
    case NoshiUpdaterIdle:
        break;
    }
}
@end

@interface NoshiReleaseCheck : NSObject {
    UIWindow *_window;
    NSString *_tag;
    NSString *_notes;
    NSString *_ipaURL;
    NSString *_digestURL;
    uint64_t _size;
}
- (id)initWithWindow:(UIWindow *)window;
- (void)start;
@end

@implementation NoshiReleaseCheck
- (id)initWithWindow:(UIWindow *)window {
    self = [super init];
    if (!self) return nil;
    _window = [window retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowChanged:) name:UIWindowDidBecomeKeyNotification object:window];
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_window release]; [_tag release]; [_notes release]; [_ipaURL release]; [_digestURL release];
    [super dealloc];
}
- (void)showIfReady {
    if (!_tag || ![_window isKeyWindow] || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if ([[_window.rootViewController presentedViewController] isKindOfClass:[UIViewController class]]) return;
    UIView *host = _window.rootViewController.view;
    if (!host.window) return;
    NoshiReleaseNotice *notice = [[[NoshiReleaseNotice alloc] initWithTag:_tag notes:_notes ipaURL:_ipaURL digestURL:_digestURL size:_size] autorelease];
    [notice presentInView:host];
    [_tag release]; _tag = nil;
    [_notes release]; _notes = nil;
    [_ipaURL release]; _ipaURL = nil;
    [_digestURL release]; _digestURL = nil;
}
- (void)windowChanged:(NSNotification *)notification {
    (void)notification;
    [self showIfReady];
}
- (void)start {
    [self retain];
    NoshiFetchLatestRelease(^(NSDictionary *release, NSString *error) {
        if (error) NSLog(@"noshigram: release check failed: %@", error);
        NSString *tag = [release objectForKey:@"tag"];
        int newer = 0;
        NSString *installed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        noshi_status status = tag ? noshi_release_compare(tag.UTF8String, installed.UTF8String, &newer) : NOSHI_E_STATE;
        if (tag && status != NOSHI_OK) NSLog(@"noshigram: release version rejected: %s", noshi_status_name(status));
        if (status == NOSHI_OK && newer) {
            _tag = [tag copy];
            _notes = [[release objectForKey:@"notes"] copy];
            _ipaURL = [[release objectForKey:@"ipa"] copy];
            _digestURL = [[release objectForKey:@"digest"] copy];
            _size = [[release objectForKey:@"size"] unsignedLongLongValue];
            [self showIfReady];
        }
        [self release];
    });
}
@end

/* what the update page shows for a check that failed: the cause in words, with the status name after it for a bug report */
static NSString *NoshiReleaseFailureText(noshi_status status) {
    NSString *key;
    switch (status) {
    case NOSHI_E_IO: case NOSHI_E_TIMEOUT: key = @"update.page.error.network"; break;
    /* the chain or the host name did not check out */
    case NOSHI_E_SECURITY: key = @"update.page.error.security"; break;
    case NOSHI_E_MALFORMED: case NOSHI_E_UNSUPPORTED: case NOSHI_E_LIMIT: key = @"update.page.error.format"; break;
    default: return [NSString stringWithUTF8String:noshi_status_name(status)];
    }
    return [NSString stringWithFormat:@"%@ (%s)", NSLocalizedString(key, nil), noshi_status_name(status)];
}

void NoshiFetchLatestRelease(void (^completion)(NSDictionary *, NSString *)) {
    void (^done)(NSDictionary *, NSString *) = [completion copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *roots = [NoshiUpdater trustedRoots];
        const char *headers[] = {"Accept: application/vnd.github+json", "User-Agent: Noshigram", "Accept-Encoding: identity", NULL};
        noshi_https_request request;
        noshi_https_response response;
        noshi_release release;
        memset(&request, 0, sizeof(request));
        memset(&response, 0, sizeof(response));
        request.host = "api.github.com";
        request.path = "/repos/wowodymyr/Noshigram/releases/latest";
        request.port = 443;
        request.headers = headers;
        request.roots_pem = roots.bytes;
        request.roots_len = roots.length;
        request.timeout_ms = RELEASE_TIMEOUT_MS;
        request.max_response = RELEASE_RESPONSE_LIMIT;
        noshi_status status = roots.length ? noshi_https_get(&request, &response) : NOSHI_E_STATE;
        NSString *error = nil;
        /* api.github.com answers 403 or 429 once an address has used its 60 requests an hour, which a shared address reaches soon.
           the release page of the web site has no such limit and names the tag in its redirect; that one answer is read and nothing is retried. a connection
           to the api host that fails or times out takes the same way, since github.com can be reachable when it is not */
        if ((status == NOSHI_OK && (response.status == 403 || response.status == 429)) || status == NOSHI_E_IO || status == NOSHI_E_TIMEOUT) {
            static const char *const web_headers[] = {"User-Agent: Noshigram", "Accept-Encoding: identity", NULL};
            NSLog(@"noshigram: release api failed (%s, HTTP %d), reading the release page", noshi_status_name(status), response.status);
            noshi_https_response_free(&response);
            memset(&response, 0, sizeof(response));
            request.host = "github.com";
            request.path = "/wowodymyr/Noshigram/releases/latest";
            request.headers = web_headers;
            status = noshi_https_get(&request, &response);
            if (status == NOSHI_OK && response.status >= 300 && response.status < 400) status = noshi_release_from_redirect(response.headers, &release);
            else if (status == NOSHI_OK) error = [NSString stringWithFormat:@"HTTP %d", response.status];
        } else if (status == NOSHI_OK && response.status != 200)
            error = [NSString stringWithFormat:@"HTTP %d", response.status];
        else if (status == NOSHI_OK)
            status = noshi_release_parse((const char *)response.body, response.body_len, &release);
        if (status != NOSHI_OK && !error) error = NoshiReleaseFailureText(status);
        NSDictionary *info = nil;
        if (!error) info = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithUTF8String:release.tag], @"tag", [NSString stringWithUTF8String:release.body], @"notes",
            [NSString stringWithUTF8String:release.ipa_url], @"ipa", [NSString stringWithUTF8String:release.sha_url], @"digest",
            [NSNumber numberWithUnsignedLongLong:release.ipa_size], @"size", nil];
        noshi_https_response_free(&response);
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(info, error); [done release]; });
        [pool drain];
    });
}

void NoshiShowReleasePreview(UIView *host) {
    if (!host) return;
    NoshiReleaseNotice *notice = [[[NoshiReleaseNotice alloc] initWithTag:@"v9.9.9-preview" notes:@"- the notice as the person sees it\n- no file behind it, so nothing is installed" ipaURL:nil digestURL:nil size:0] autorelease];
    [notice presentInView:host];
}

void NoshiReleaseCheckStart(UIWindow *window) {
    static NoshiReleaseCheck *check;
    if (check || !window) return;
    check = [[NoshiReleaseCheck alloc] initWithWindow:window];
    [check start];
}

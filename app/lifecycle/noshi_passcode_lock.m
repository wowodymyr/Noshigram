#import <QuartzCore/QuartzCore.h>
#import "noshi_passcode_lock.h"

#import "noshi_biometric.h"
#import "noshi_passcode_entry_view.h"
#import "noshi_passcode_store.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* the lock stands on the accent of the theme, darkened so the white ink of the pad reads on a light accent too, and fading from a lighter top to a deeper foot. the dark theme
   goes a good deal deeper than the light one, where the flat accent shone too brightly in the night */
static void NoshiLockColors(UIColor **top, UIColor **bottom) {
    UIColor *accent = NoshiColorAccent(), *black = [UIColor blackColor];
    BOOL dark = NoshiThemeIsDark();
    *top = NoshiMixedColor(accent, black, dark ? 0.45 : 0.26);
    *bottom = NoshiMixedColor(accent, black, dark ? 0.72 : 0.46);
}

/* the ground of the lock: a vertical gradient, which a view gets from the layer it is made of */
@interface NoshiLockBackdrop : UIView
@end

@implementation NoshiLockBackdrop
+ (Class)layerClass { return [CAGradientLayer class]; }

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    UIColor *top = nil, *bottom = nil;
    NoshiLockColors(&top, &bottom);
    CAGradientLayer *layer = (CAGradientLayer *)self.layer;
    layer.colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
    layer.startPoint = CGPointMake(0.5, 0);
    layer.endPoint = CGPointMake(0.5, 1);
    return self;
}
@end

@interface NoshiPasscodeLockController : UIViewController {
    NoshiPasscodeEntryView *_entry;
    void (^_unlocked)(void);
    BOOL _asking;
    NoshiWeakReference *_weak;
    /* the open question to the sensor, nil when none runs */
    id _biometricToken;
    /* the sensor is asked by itself once for each time the lock rises; after that only its button asks, or a cancelled sheet would come back
       on every return of the app to the foreground */
    BOOL _biometricOffered;
}
- (id)initWithUnlocked:(void (^)(void))unlocked;
/* the plain color, or the pad that asks for the code */
- (void)setAsking:(BOOL)asking;
/* once per rise of the lock, when the app is active */
- (void)offerBiometric;
- (void)askBiometric;
- (void)codeEntered:(NSString *)code;
@end

@implementation NoshiPasscodeLockController

- (id)initWithUnlocked:(void (^)(void))unlocked {
    self = [super init];
    if (!self) return nil;
    _unlocked = [unlocked copy];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    NoshiBiometricCancel(_biometricToken);
    [_biometricToken release];
    [_entry release];
    [_unlocked release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[NoshiLockBackdrop alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _entry = [[NoshiPasscodeEntryView alloc] initWithFrame:root.bounds];
    _entry.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _entry.accented = YES;
    _entry.hidden = YES;
    NoshiPasscodeLockController *lock = self;
    _entry.submit = ^(NSString *code) { [lock codeEntered:code]; };
    [root addSubview:_entry];
}

- (void)setAsking:(BOOL)asking {
    [self view];
    if (asking == _asking) {
        if (asking) [_entry focus];
        return;
    }
    _asking = asking;
    _entry.hidden = !asking;
    if (!asking) {
        [self cancelBiometric];
        [_entry resignFirstResponder];
        return;
    }
    _biometricOffered = NO;
    [self applyBiometricButton];
    _entry.type = NoshiPasscodeType();
    _entry.title = NoshiPasscodeText(@"passcode.enter", _entry.type);
    _entry.message = nil;
    [_entry reset];
    [_entry holdForSeconds:NoshiPasscodeWaitRemaining()];
    [_entry focus];
}

- (BOOL)biometricWanted {
    return NoshiPasscodeBiometricEnabled() && NoshiBiometricAvailable() != NoshiBiometricNone;
}

- (void)applyBiometricButton {
    NoshiPasscodeLockController *lock = self;
    BOOL wanted = [self biometricWanted];
    _entry.biometricFingerprint = NoshiBiometricAvailable() == NoshiBiometricTouchID;
    _entry.biometricTitle = wanted ? NoshiBiometricName(NoshiBiometricAvailable()) : nil;
    _entry.biometric = wanted ? ^{ [lock askBiometric]; } : nil;
}

- (void)cancelBiometric {
    NoshiBiometricCancel(_biometricToken);
    [_biometricToken release];
    _biometricToken = nil;
}

- (void)askBiometric {
    if (!_asking || _biometricToken || ![self biometricWanted]) return;
    NoshiWeakReference *weak = _weak;
    _biometricToken = [NoshiBiometricEvaluate(NSLocalizedString(@"passcode.biometric.reason", nil), ^(BOOL matched) {
        NoshiPasscodeLockController *me = weak.target;
        if (!me) return;
        [me->_biometricToken release];
        me->_biometricToken = nil;
        if (matched && me->_asking && me->_unlocked) me->_unlocked();
    }) retain];
}

/* the app is active: the sensor cannot be asked from an inactive app, and the first return after the lock rose is the first moment it can */
- (void)offerBiometric {
    if (_biometricOffered || !_asking) return;
    _biometricOffered = YES;
    [self askBiometric];
}

- (void)codeEntered:(NSString *)code {
    NSUInteger wait = 0;
    NoshiPasscodeResult result = NoshiPasscodeCheck(code, &wait);
    if (result == NoshiPasscodeResultOK) {
        if (_unlocked) _unlocked();
        return;
    }
    [_entry rejectCode];
    _entry.message = result == NoshiPasscodeResultWrong ? NoshiPasscodeText(@"passcode.wrong", _entry.type) : nil;
    [_entry holdForSeconds:wait];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return NoshiOrientationMask();
}
#pragma clang diagnostic pop

@end

/* how long the lock takes to dissolve once the code is right */
#define UNLOCK_SECONDS 0.42

typedef enum { NoshiLockStateOpen, NoshiLockStateCover, NoshiLockStateAsking } NoshiLockState;

@interface NoshiPasscodeLock () {
    UIWindow *_window;
    NoshiPasscodeLockController *_controller;
    UIWindow *_appWindow;
    NoshiLockState _state;
    /* wall seconds of the last move to the background, 0 when the app has not left since it was last active */
    NSTimeInterval _leftAt;
}
@end

@implementation NoshiPasscodeLock

- (void)dealloc {
    [_window release];
    [_controller release];
    [super dealloc];
}

- (void)showWindow {
    if (_window) return;
    /* the keyboard of the app stands above every window, so what is being typed is let go before the lock rises */
    for (UIWindow *window in [[UIApplication sharedApplication] windows]) [window endEditing:YES];
    /* the window of the app, not whichever one is key now: an alert, the keyboard's window or the lock's own earlier window can be key at this moment, and handing
       key back to it (or to a window that is gone) left the app window without it, where a text field takes a tap and never shows its keyboard */
    id<UIApplicationDelegate> delegate = [[UIApplication sharedApplication] delegate];
    UIWindow *main = [delegate respondsToSelector:@selector(window)] ? [delegate window] : nil;
    _appWindow = main ? main : [[UIApplication sharedApplication] keyWindow];
    NoshiPasscodeLock *me = self;
    _controller = [[NoshiPasscodeLockController alloc] initWithUnlocked:^{ [me open]; }];
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.windowLevel = UIWindowLevelAlert + 100;
    UIColor *ground = nil, *unused = nil;
    NoshiLockColors(&ground, &unused);
    _window.backgroundColor = ground;
    _window.rootViewController = _controller;
    [_window makeKeyAndVisible];
}

/* a right code lets the lock dissolve into the app: the pad stays while it fades and swells a little, as if the app came up through it, and a lock that vanished at once
   showed as a cut. the window that fades is no longer the lock's own, so a cover can rise again at once if the app leaves meanwhile */
- (void)open {
    _state = NoshiLockStateOpen;
    _leftAt = 0;
    UIWindow *window = _window, *appWindow = _appWindow;
    NoshiPasscodeLockController *controller = _controller;
    _window = nil;
    _controller = nil;
    _appWindow = nil;
    [appWindow makeKeyWindow];
    /* the code that opened the lock is still running on the pad of this controller, so the last release waits for the end of the animation, or of the run loop pass */
    void (^finish)(void) = ^{
        [controller setAsking:NO];
        window.hidden = YES;
        window.rootViewController = nil;
        [window release];
        [controller release];
    };
    if (NoshiReduceMotionEnabled() || ![UIView areAnimationsEnabled]) {
        finish();
        return;
    }
    /* touches in the meantime belong to the app under the fading lock */
    window.userInteractionEnabled = NO;
    [UIView animateWithDuration:UNLOCK_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        window.alpha = 0;
        controller.view.transform = CGAffineTransformMakeScale(1.08f, 1.08f);
    } completion:^(BOOL finished) {
        (void)finished;
        finish();
    }];
}

- (void)ask {
    [self showWindow];
    _state = NoshiLockStateAsking;
    [_controller setAsking:YES];
}

- (void)lockAtLaunch {
    if (NoshiPasscodeEnabled()) [self ask];
}

- (void)cover {
    if (!NoshiPasscodeEnabled() || _state != NoshiLockStateOpen) return;
    [self showWindow];
    _state = NoshiLockStateCover;
}

- (void)noteLeave {
    _leftAt = [[NSDate date] timeIntervalSince1970];
}

- (void)evaluateReturn {
    if (_state != NoshiLockStateCover) {
        if (_state == NoshiLockStateAsking) {
            [_controller setAsking:YES];
            [_controller offerBiometric];
        }
        return;
    }
    /* the cover rises only after a move to the background, which notes the leave first; a call or the notification center never raises it */
    BOOL left = _leftAt > 0;
    BOOL lock = left && noshi_passcode_should_lock(NoshiPasscodeAutoLock(), (int64_t)_leftAt, (int64_t)[[NSDate date] timeIntervalSince1970]);
    _leftAt = 0;
    if (lock) {
        [self ask];
        [_controller offerBiometric];
    } else {
        [self open];
    }
}

@end

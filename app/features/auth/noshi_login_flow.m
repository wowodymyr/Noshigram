#import "noshi_login_flow.h"
#import "noshi_alert_view.h"

typedef enum {
    NoshiLoginStagePhone,
    NoshiLoginStageCode,
    NoshiLoginStagePassword,
    NoshiLoginStageName,
    NoshiLoginStageRecovery,
    NoshiLoginStageQr
} NoshiLoginStage;

@interface NoshiLoginFlow () {
    UINavigationController *_navigation;
    NoshiSession *_session;
    NoshiCountryBook *_book;
    NoshiPhoneController *_phone;
    NoshiFormController *_form;
    NoshiQrController *_qr;
    NSString *_display;
    NoshiLoginStage _stage;
    BOOL _hasRecovery;
    /* events that arrive after the user backed out belong to a request nobody waits for */
    BOOL _awaiting;
}
@end

@implementation NoshiLoginFlow

@synthesize delegate = _delegate;

- (id)initWithNavigation:(UINavigationController *)navigation session:(NoshiSession *)session
            countryBook:(NoshiCountryBook *)book {
    self = [super init];
    if (!self) return nil;
    _navigation = [navigation retain];
    _session = [session retain];
    _book = [book retain];
    return self;
}

- (void)dealloc {
    _phone.delegate = nil;
    _form.delegate = nil;
    _qr.delegate = nil;
    if (_session.delegate == self) _session.delegate = nil;
    [_navigation release];
    [_session release];
    [_book release];
    [_phone release];
    [_form release];
    [_qr release];
    [_display release];
    [super dealloc];
}

- (void)begin {
    _session.delegate = self;
    [_phone release];
    _phone = [[NoshiPhoneController alloc] initWithCountryBook:_book];
    _phone.delegate = self;
    _stage = NoshiLoginStagePhone;
    _awaiting = NO;
    [_navigation pushViewController:_phone animated:YES];
}

- (void)beginWithQr {
    _session.delegate = self;
    [_phone release];
    _phone = [[NoshiPhoneController alloc] initWithCountryBook:_book];
    _phone.delegate = self;
    [self phoneControllerDidRequestQr:_phone];
}

#pragma mark texts

static NSString *NoshiDuration(NSInteger seconds) {
    if (seconds < 120) return [NSString stringWithFormat:NSLocalizedString(@"duration.seconds", nil), (int)seconds];
    if (seconds < 7200) return [NSString stringWithFormat:NSLocalizedString(@"duration.minutes", nil), (int)((seconds + 59) / 60)];
    return [NSString stringWithFormat:NSLocalizedString(@"duration.hours", nil), (int)((seconds + 3599) / 3600)];
}

static NSString *NoshiLoginErrorText(NoshiAuthEvent *event) {
    static NSString *const known[][2] = {
        {@"PHONE_NUMBER_INVALID", @"error.phone.invalid"},
        {@"PHONE_NUMBER_BANNED", @"error.phone.banned"},
        {@"PHONE_NUMBER_FLOOD", @"error.flood.generic"},
        {@"SEND_CODE_UNAVAILABLE", @"error.code.unavailable"},
        {@"PHONE_CODE_INVALID", @"error.code.invalid"},
        {@"PHONE_CODE_EMPTY", @"error.code.invalid"},
        {@"PHONE_CODE_EXPIRED", @"error.code.expired"},
        {@"PASSWORD_HASH_INVALID", @"error.password.invalid"},
        {@"PASSWORD_RECOVERY_NA", @"error.recovery.unavailable"},
        {@"PASSWORD_RECOVERY_EXPIRED", @"error.code.expired"},
        {@"CODE_INVALID", @"error.code.invalid"},
        {@"CODE_EMPTY", @"error.code.invalid"},
        {@"AUTH_RESTART", @"error.auth.restart"},
        {@"PHONE_CODE_HASH_EMPTY", @"error.auth.restart"},
        {@"API_ID_INVALID", @"error.api"},
        {@"API_ID_PUBLISHED_FLOOD", @"error.api"},
        {@"TIMEOUT", @"error.timeout"},
        {@"INTERNAL", @"error.internal"},
        {@"STORAGE", @"error.storage"},
    };
    switch (event.kind) {
    case NoshiAuthEventOffline:
        return NSLocalizedString(@"error.offline", nil);
    case NoshiAuthEventUnsupported:
        return NSLocalizedString(@"error.unsupported", nil);
    default:
        break;
    }
    NSString *name = event.errorName;
    if ([name isEqualToString:@"FLOOD_WAIT"] || [name isEqualToString:@"FLOOD_PREMIUM_WAIT"]) {
        return [NSString stringWithFormat:NSLocalizedString(@"error.flood", nil), NoshiDuration(event.errorNumber)];
    }
    for (size_t i = 0; i < sizeof(known) / sizeof(known[0]); ++i) {
        if ([name isEqualToString:known[i][0]]) return NSLocalizedString(known[i][1], nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), name];
}

static NSString *NoshiCodeMessage(NoshiCodeKind kind) {
    switch (kind) {
    case NoshiCodeKindApp: return NSLocalizedString(@"code.message.app", nil);
    case NoshiCodeKindSms: return NSLocalizedString(@"code.message.sms", nil);
    case NoshiCodeKindCall: return NSLocalizedString(@"code.message.call", nil);
    case NoshiCodeKindOther: break;
    }
    return NSLocalizedString(@"code.message.other", nil);
}

/* the code screen names the number without printing it whole: the plus, the first digit and the last four */
static NSString *NoshiMaskedNumber(NSString *number) {
    NSString *digits = [number hasPrefix:@"+"] ? [number substringFromIndex:1] : number;
    if (digits.length < 6) return @"+\u2022\u2022\u2022";
    return [NSString stringWithFormat:@"+%@ \u2022\u2022\u2022 %@", [digits substringToIndex:1],
            [digits substringFromIndex:digits.length - 4]];
}

#pragma mark screens

- (NoshiFormController *)pushFormOfKind:(NoshiFormKind)kind {
    [_form release];
    _form = [[NoshiFormController alloc] initWithKind:kind];
    _form.delegate = self;
    [_navigation pushViewController:_form animated:YES];
    return _form;
}

- (void)applyCode:(NoshiAuthEvent *)event toForm:(NoshiFormController *)form {
    form.message = NoshiCodeMessage(event.codeKind);
    form.codeLength = event.codeLength;
    [form setActionTitle:event.resendAfter >= 0 ? NSLocalizedString(@"code.resend", nil) : nil
             waitSeconds:event.resendAfter];
}

- (void)showFailure:(NoshiAuthEvent *)event {
    NSString *text = NoshiLoginErrorText(event);
    if (_stage == NoshiLoginStageQr) {
        [_qr showFailure:text];
        return;
    }
    if (_stage == NoshiLoginStagePhone) {
        _phone.busy = NO;
        Class alertClass = NoshiAlertClass();
        id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }
    _form.busy = NO;
    [_form showError:text];
}

#pragma mark session

- (void)session:(NoshiSession *)session didReceiveAuthEvent:(NoshiAuthEvent *)event {
    (void)session;
    if (!_awaiting) return;
    switch (event.kind) {
    case NoshiAuthEventCode:
        if (_stage == NoshiLoginStagePhone) {
            _phone.busy = NO;
            NoshiFormController *form = [self pushFormOfKind:NoshiFormKindCode];
            form.heading = _display;
            [self applyCode:event toForm:form];
            _stage = NoshiLoginStageCode;
        } else {
            _form.busy = NO;
            [_form clearFields];
            [self applyCode:event toForm:_form];
        }
        break;
    case NoshiAuthEventQr:
        if (_stage == NoshiLoginStageQr) [_qr showUrl:event.qrUrl];
        break;
    case NoshiAuthEventPassword:
        if (_stage == NoshiLoginStageCode || _stage == NoshiLoginStageQr) {
            NoshiFormController *form = [self pushFormOfKind:NoshiFormKindPassword];
            form.heading = NSLocalizedString(@"password.title", nil);
            form.message = event.hint.length
                ? [NSString stringWithFormat:NSLocalizedString(@"password.hint", nil), event.hint]
                : NSLocalizedString(@"password.message", nil);
            form.fieldHint = event.hint;
            [form setActionTitle:NSLocalizedString(@"password.forgot", nil) waitSeconds:0];
            _hasRecovery = event.hasRecovery;
            _stage = NoshiLoginStagePassword;
        } else {
            /* the server asked for a fresh challenge after a stale one */
            _form.busy = NO;
        }
        break;
    case NoshiAuthEventRecovery:
        if (_stage == NoshiLoginStagePassword) {
            NoshiFormController *form = [self pushFormOfKind:NoshiFormKindCode];
            form.heading = NSLocalizedString(@"recovery.title", nil);
            form.message = [NSString stringWithFormat:NSLocalizedString(@"recovery.message", nil), event.emailPattern.length ? event.emailPattern : @""];
            _stage = NoshiLoginStageRecovery;
        } else {
            _form.busy = NO;
        }
        break;
    case NoshiAuthEventSignUp: {
        NoshiFormController *form = [self pushFormOfKind:NoshiFormKindName];
        form.heading = NSLocalizedString(@"name.title", nil);
        form.message = NSLocalizedString(@"name.message", nil);
        _stage = NoshiLoginStageName;
        break;
    }
    case NoshiAuthEventAuthorized:
        _awaiting = NO;
        [_delegate loginFlow:self didAuthorizeUser:event.userId];
        break;
    case NoshiAuthEventFailed:
    case NoshiAuthEventUnsupported:
    case NoshiAuthEventOffline:
        _awaiting = NO;
        [self showFailure:event];
        break;
    case NoshiAuthEventLoggedOut:
        break;
    }
}

#pragma mark phone screen

- (void)phoneController:(NoshiPhoneController *)controller didSubmitNumber:(NSString *)number {
    (void)controller;
    [_display release];
    _display = [NoshiMaskedNumber(number) copy];
    _phone.busy = YES;
    _awaiting = YES;
    [_session requestCodeForNumber:number];
}

#pragma mark qr screen

- (void)phoneControllerDidRequestQr:(NoshiPhoneController *)controller {
    (void)controller;
    [_qr release];
    _qr = [[NoshiQrController alloc] init];
    _qr.delegate = self;
    _stage = NoshiLoginStageQr;
    _awaiting = YES;
    [_navigation pushViewController:_qr animated:YES];
    [_session requestQrLogin];
}

/* the code screen and the phone screen are two ways into the same login, so leaving one for the other gives the first up */
- (void)leaveQr {
    _awaiting = NO;
    [_session cancelLogin];
    _stage = NoshiLoginStagePhone;
    _phone.busy = NO;
    if ([_navigation.viewControllers containsObject:_phone]) [_navigation popToViewController:_phone animated:YES];
    else [_navigation popViewControllerAnimated:YES];
}

/* the QR screen was opened from the welcome screen, so the phone screen is not under it: it takes its place */
- (void)replaceQrWithPhone {
    _awaiting = NO;
    [_session cancelLogin];
    _stage = NoshiLoginStagePhone;
    _phone.busy = NO;
    if ([_navigation.viewControllers containsObject:_phone]) {
        [_navigation popToViewController:_phone animated:YES];
        return;
    }
    NSMutableArray *stack = [NSMutableArray arrayWithArray:_navigation.viewControllers];
    [stack removeLastObject];
    [stack addObject:_phone];
    [_navigation setViewControllers:stack animated:YES];
}

- (void)qrControllerDidGoBack:(NoshiQrController *)controller {
    (void)controller;
    [self leaveQr];
}

- (void)qrControllerDidChoosePhone:(NoshiQrController *)controller {
    (void)controller;
    [self replaceQrWithPhone];
}

- (void)qrControllerDidRequestRetry:(NoshiQrController *)controller {
    (void)controller;
    _awaiting = YES;
    [_session cancelLogin];
    [_session requestQrLogin];
}

#pragma mark form screens

- (void)formController:(NoshiFormController *)controller didSubmitValues:(NSArray *)values {
    controller.busy = YES;
    _awaiting = YES;
    switch (_stage) {
    case NoshiLoginStageCode:
        [_session submitCode:[values objectAtIndex:0]];
        break;
    case NoshiLoginStagePassword:
        [_session submitPassword:[values objectAtIndex:0]];
        break;
    case NoshiLoginStageRecovery:
        [_session submitRecoveryCode:[values objectAtIndex:0]];
        break;
    case NoshiLoginStageName:
        [_session submitFirstName:[values objectAtIndex:0] lastName:[values objectAtIndex:1]];
        break;
    case NoshiLoginStagePhone:
    case NoshiLoginStageQr:
        break;
    }
}

- (void)formControllerDidTapAction:(NoshiFormController *)controller {
    if (_stage == NoshiLoginStagePassword) {
        /* without a recovery e-mail the only way back in is the seven-day reset, which only the official apps can ask for */
        if (!_hasRecovery) {
            Class alertClass = NoshiAlertClass();
            id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"recovery.none.title", nil) message:NSLocalizedString(@"recovery.none.message", nil)
                                                delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }
        controller.busy = YES;
        _awaiting = YES;
        [_session requestPasswordRecovery];
        return;
    }
    controller.busy = YES;
    _awaiting = YES;
    [_session resendCode];
}

/* the state machine cannot step back, so every back button cancels the login and returns to the phone */
- (void)formControllerDidGoBack:(NoshiFormController *)controller {
    (void)controller;
    _awaiting = NO;
    [_session cancelLogin];
    _stage = NoshiLoginStagePhone;
    _phone.busy = NO;
    [_navigation popToViewController:_phone animated:YES];
}

@end

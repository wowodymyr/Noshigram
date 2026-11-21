#import "noshi_form_controller.h"
#import "noshi_alert_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_bar_button.h"
#import "noshi_form_layout.h"
#import "noshi_geometry.h"
#import "noshi_lottie_view.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_wave_background_view.h"

#define CODE_LENGTH_FALLBACK 8
#define NAME_LENGTH_LIMIT 64

@interface NoshiFormController () {
    NoshiFormKind _kind;
    id<NoshiFormControllerDelegate> _delegate;
    NSString *_heading;
    NSString *_message;
    NSString *_fieldHint;
    NSInteger _codeLength;
    BOOL _busy;
    NSString *_actionTitle;
    NSDate *_actionReady;
    NSTimer *_countdown;
    NoshiWaveBackgroundView *_backdrop;
    NoshiBarButton *_back;
    NoshiBarButton *_next;
    UIActivityIndicatorView *_spinner;
    NoshiLottieView *_art;
    /* the monkey of the password form covers its eyes while the field has the keyboard, and peeks open again when it lets go */
    NoshiLottieView *_closeArt;
    NoshiLottieView *_openArt;
    BOOL _artFits;
    BOOL _eyesClosed;
    BOOL _eyesOpening;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UIView *_card;
    NSMutableArray *_fields;
    NSMutableArray *_lines;
    UILabel *_errorLabel;
    NSString *_errorText;
    BOOL _messageInNote;
    UIButton *_action;
    CGFloat _keyboardHeight;
    BOOL _visible;
}
@end

@implementation NoshiFormController

@synthesize delegate = _delegate;
@synthesize codeLength = _codeLength;
@synthesize busy = _busy;

- (void)setFieldHint:(NSString *)hint {
    if (hint == _fieldHint) return;
    [_fieldHint release];
    _fieldHint = [hint copy];
    if (_kind != NoshiFormKindPassword) return;
    for (UITextField *field in _fields) field.placeholder = _fieldHint.length ? _fieldHint : NSLocalizedString(@"password.placeholder", nil);
}

- (NSString *)fieldHint {
    return _fieldHint;
}

- (id)initWithKind:(NoshiFormKind)kind {
    self = [super init];
    if (!self) return nil;
    _kind = kind;
    return self;
}

- (void)dealloc {
    [_fieldHint release];
    [_countdown invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (UITextField *field in _fields) field.delegate = nil;
    [_heading release];
    [_message release];
    [_actionTitle release];
    [_actionReady release];
    [_backdrop release];
    [_back release];
    [_next release];
    [_spinner release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(eyesOpened) object:nil];
    [_art release];
    [_closeArt release];
    [_openArt release];
    [_titleLabel release];
    [_messageLabel release];
    [_card release];
    [_fields release];
    [_lines release];
    [_errorLabel release];
    [_errorText release];
    [_action release];
    [super dealloc];
}

static UILabel *NoshiFormLabel(UIColor *color, NSInteger lines, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    return label;
}

- (NSInteger)rowCount {
    return _kind == NoshiFormKindName ? 2 : 1;
}

- (UITextField *)fieldForRow:(NSInteger)row {
    UITextField *field = [[[UITextField alloc] init] autorelease];
    field.delegate = self;
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = [UIColor clearColor];
    field.textColor = NoshiColorTitle();
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.clearButtonMode = UITextFieldViewModeNever;
    field.returnKeyType = UIReturnKeyNext;
    switch (_kind) {
    case NoshiFormKindCode:
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.textAlignment = NoshiTextAlignmentCenter;
        field.placeholder = NSLocalizedString(@"code.placeholder", nil);
        break;
    case NoshiFormKindPassword:
        field.secureTextEntry = YES;
        field.returnKeyType = UIReturnKeyGo;
        field.placeholder = _fieldHint.length ? _fieldHint : NSLocalizedString(@"password.placeholder", nil);
        break;
    case NoshiFormKindName:
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.placeholder = NSLocalizedString(row == 0 ? @"name.first" : @"name.last", nil);
        field.returnKeyType = row == 0 ? UIReturnKeyNext : UIReturnKeyGo;
        break;
    }
    return field;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[NoshiWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    static NSString *const stickers[] = {@"form_code", @"form_password", @"form_name"};
    _art = [[NoshiLottieView alloc] initWithAnimationNamed:stickers[_kind]];
    [root addSubview:_art];
    if (_kind == NoshiFormKindPassword) {
        _closeArt = [[NoshiLottieView alloc] initWithAnimationNamed:@"form_password_close"];
        /* the first half of the animation closes the eyes and the second opens them again it: it stops where the
           eyes are shut */
        _closeArt.lastFrame = 49;
        _openArt = [[NoshiLottieView alloc] initWithAnimationNamed:@"form_password_open"];
        _closeArt.hidden = _openArt.hidden = YES;
        [root addSubview:_closeArt];
        [root addSubview:_openArt];
    }

    _titleLabel = NoshiFormLabel(NoshiColorTitle(), 1, NoshiTextAlignmentCenter);
    _titleLabel.text = _heading;
    [root addSubview:_titleLabel];
    _messageLabel = NoshiFormLabel(NoshiColorMessage(), 0, NoshiTextAlignmentCenter);
    _messageLabel.text = _message;
    [root addSubview:_messageLabel];

    _card = [[UIView alloc] init];
    _card.backgroundColor = NoshiColorCard();
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 1.0 / NoshiScreenScale();
    _card.layer.borderColor = NoshiColorHairline().CGColor;
    [root addSubview:_card];

    _fields = [[NSMutableArray alloc] init];
    _lines = [[NSMutableArray alloc] init];
    for (NSInteger row = 0; row < [self rowCount]; ++row) {
        UITextField *field = [self fieldForRow:row];
        [_fields addObject:field];
        [_card addSubview:field];
        if (row > 0) {
            UIView *line = [[[UIView alloc] init] autorelease];
            line.backgroundColor = NoshiColorHairline();
            [_lines addObject:line];
            [_card addSubview:line];
        }
    }

    _errorLabel = NoshiFormLabel([UIColor colorWithRed:0.82 green:0.18 blue:0.2 alpha:1], 2, NoshiTextAlignmentCenter);
    [root addSubview:_errorLabel];
    [self refreshNote];

    _action = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _action.backgroundColor = [UIColor clearColor];
    [_action setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_action setTitleColor:NoshiColorMessage() forState:UIControlStateDisabled];
    [_action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_action];

    _back = [[NoshiBarButton alloc] init];
    _back.chevron = YES;
    _back.title = NSLocalizedString(@"phone.back", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
    _next = [[NoshiBarButton alloc] init];
    _next.bold = YES;
    _next.title = NSLocalizedString(@"phone.next", nil);
    [_next addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_next];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];

    [self refreshAction];
    [self refreshState];
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

#pragma mark properties

- (NSString *)heading {
    return _heading;
}

- (void)setHeading:(NSString *)heading {
    if (heading == _heading || [heading isEqualToString:_heading]) return;
    [_heading release];
    _heading = [heading copy];
    _titleLabel.text = _heading;
}

- (NSString *)message {
    return _message;
}

- (void)setMessage:(NSString *)message {
    if (message == _message || [message isEqualToString:_message]) return;
    [_message release];
    _message = [message copy];
    _messageLabel.text = _message;
}

- (void)setBusy:(BOOL)busy {
    if (busy == _busy) return;
    _busy = busy;
    [self refreshState];
}

- (void)showError:(NSString *)text {
    [_errorText release];
    _errorText = [(text.length ? text : nil) copy];
    [self refreshNote];
    /* with no room for the line, the keyboard hides the only other place the text could show */
    if (_errorText && self.isViewLoaded && _errorLabel.hidden) [self showErrorAlert];
}

/* the line under the card shows the error; when the keyboard leaves no room for the message above the card,
   that line shows the message instead until an error needs it */
- (void)refreshNote {
    BOOL error = _errorText.length > 0;
    _errorLabel.text = error ? _errorText : (_messageInNote ? _message : nil);
    _errorLabel.textColor = error ? [UIColor colorWithRed:0.82 green:0.18 blue:0.2 alpha:1] : NoshiColorSecondary();
}

- (void)showErrorAlert {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:_errorText delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)clearFields {
    for (UITextField *field in _fields) field.text = @"";
    [self refreshState];
}

#pragma mark action and countdown

- (void)setActionTitle:(NSString *)title waitSeconds:(NSInteger)seconds {
    [_actionTitle release];
    _actionTitle = [title copy];
    [_actionReady release];
    _actionReady = seconds > 0 ? [[NSDate dateWithTimeIntervalSinceNow:seconds] retain] : nil;
    [self refreshAction];
    [self restartCountdown];
}

- (void)restartCountdown {
    [_countdown invalidate];
    _countdown = nil;
    if (!_actionReady || !_visible) return;
    _countdown = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(countdownTick)
                                                userInfo:nil repeats:YES];
}

- (void)countdownTick {
    if ([_actionReady timeIntervalSinceNow] <= 0) {
        [_actionReady release];
        _actionReady = nil;
        [_countdown invalidate];
        _countdown = nil;
    }
    [self refreshAction];
}

- (void)refreshAction {
    if (!_action) return;
    NSTimeInterval left = _actionReady ? [_actionReady timeIntervalSinceNow] : 0;
    BOOL waiting = left > 0;
    NSString *title = _actionTitle;
    if (waiting && _actionTitle) {
        NSInteger seconds = (NSInteger)ceil(left);
        title = [NSString stringWithFormat:NSLocalizedString(@"code.resend.wait", nil), (int)(seconds / 60), (int)(seconds % 60)];
    }
    [_action setTitle:title forState:UIControlStateNormal];
    [_action setTitle:title forState:UIControlStateDisabled];
    _action.enabled = !waiting && !_busy;
    _action.hidden = _actionTitle == nil || _action.frame.size.height <= 0;
}

- (void)actionTapped {
    [_delegate formControllerDidTapAction:self];
}

#pragma mark layout

- (void)applyLayout {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGFloat side = insets.left;
    noshi_form_metrics metrics = {size.width - insets.left - insets.right, size.height - _keyboardHeight, insets.top,
                                    _keyboardHeight > 0 ? 0 : insets.bottom, NoshiIsPad() ? 1 : 0, (int)[self rowCount]};
    noshi_form_layout layout;
    if (noshi_form_layout_compute(&metrics, &layout) != NOSHI_OK) {
        NSLog(@"noshigram: form layout does not fit %.0fx%.0f", metrics.width, metrics.height);
    }

    _backdrop.frame = self.view.bounds;
    _back.frame = NoshiCGRectOffset(layout.back, side, 0);
    _next.frame = NoshiCGRectOffset(layout.next, side, 0);
    _back.titleSize = _next.titleSize = (CGFloat)layout.bar_size;
    _spinner.center = CGPointMake(CGRectGetMaxX(_next.frame) - 26, CGRectGetMidY(_next.frame));

    _art.frame = _closeArt.frame = _openArt.frame = NoshiCGRectOffset(layout.art, side, 0);
    _artFits = layout.art.height > 0;
    [self refreshArtPlayback];
    _titleLabel.frame = NoshiCGRectOffset(layout.title, side, 0);
    _titleLabel.hidden = layout.title.height <= 0;
    _titleLabel.font = NoshiFontBold((CGFloat)layout.title_size);
    _messageLabel.frame = NoshiCGRectOffset(layout.message, side, 0);
    _messageLabel.hidden = layout.message.height <= 0;
    _messageLabel.font = NoshiFontRegular((CGFloat)layout.message_size);

    _card.frame = NoshiCGRectOffset(layout.card, side, 0);
    _card.layer.cornerRadius = (CGFloat)layout.card_radius;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    UIFont *fieldFont = NoshiFontRegular((CGFloat)layout.field_size);
    for (NSInteger row = 0; row < [self rowCount]; ++row) {
        CGRect cell = NoshiCGRectOffset(layout.rows[row], -layout.card.x, -layout.card.y);
        UITextField *field = [_fields objectAtIndex:row];
        field.font = fieldFont;
        field.frame = CGRectMake(16, cell.origin.y, cell.size.width - 32, cell.size.height);
        if (row > 0) {
            UIView *line = [_lines objectAtIndex:row - 1];
            line.frame = CGRectMake(0, cell.origin.y - hairline / 2, cell.size.width, hairline);
        }
    }

    _errorLabel.frame = NoshiCGRectOffset(layout.error, side, 0);
    _errorLabel.hidden = layout.error.height <= 0;
    _messageInNote = layout.message.height <= 0 && layout.error.height > 0;
    [self refreshNote];
    _errorLabel.font = NoshiFontRegular((CGFloat)layout.note_size);
    _action.frame = NoshiCGRectOffset(layout.action, side, 0);
    _action.titleLabel.font = NoshiFontRegular((CGFloat)layout.field_size - 2);
    [self refreshAction];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyLayout];
}

/* the sticker holds its parsed animation only while it is on screen */
- (void)refreshArtPlayback {
    _art.hidden = !_artFits || _eyesClosed || _eyesOpening;
    BOOL shown = _visible && !_art.hidden;
    [_art setLoaded:shown];
    [_art setPlaying:shown];
    _closeArt.hidden = !_artFits || !_eyesClosed;
    _openArt.hidden = !_artFits || !_eyesOpening;
    if (_closeArt.hidden) [_closeArt setLoaded:NO];
    if (_openArt.hidden) [_openArt setLoaded:NO];
}

/* the password field took or gave up the keyboard: the monkey closes its eyes at once and stays so, or peeks and goes back to its idle loop */
- (void)setEyesClosed:(BOOL)closed {
    if (_kind != NoshiFormKindPassword || closed == _eyesClosed) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(eyesOpened) object:nil];
    _eyesClosed = closed;
    _eyesOpening = !closed;
    [self refreshArtPlayback];
    NoshiLottieView *moving = closed ? _closeArt : _openArt;
    if (!moving.hidden) {
        [moving rewind];
        [moving playOnce];
    }
    if (!closed) [self performSelector:@selector(eyesOpened) withObject:nil afterDelay:0.6];
}

- (void)eyesOpened {
    _eyesOpening = NO;
    [self refreshArtPlayback];
}

- (void)textFieldDidBeginEditing:(UITextField *)field {
    (void)field;
    [self setEyesClosed:YES];
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    (void)field;
    [self setEyesClosed:NO];
}

#pragma mark keyboard

- (void)keyboardChanged:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect end = [self.view convertRect:[[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat height = MAX(0, self.view.bounds.size.height - end.origin.y);
    if (height == _keyboardHeight) return;
    _keyboardHeight = height;
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSUInteger curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)((curve << 16) | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{ [self applyLayout]; } completion:NULL];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    [self refreshArtPlayback];
    [self restartCountdown];
    [self refreshAction];
    /* the code is read from the sms or the other device, and a keyboard that comes up by itself covers the message about it */
    if (!_busy && _kind != NoshiFormKindCode) [[_fields objectAtIndex:0] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self refreshArtPlayback];
    [_countdown invalidate];
    _countdown = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.view endEditing:YES];
    _keyboardHeight = 0;
}

#pragma mark state

- (NSArray *)values {
    NSMutableArray *values = [NSMutableArray array];
    for (UITextField *field in _fields) {
        NSString *text = field.text ? field.text : @"";
        [values addObject:_kind == NoshiFormKindPassword ? text : [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    }
    return values;
}

- (BOOL)valid {
    NSArray *values = [self values];
    NSString *first = [values objectAtIndex:0];
    if (_kind == NoshiFormKindCode && _codeLength > 0) return (NSInteger)first.length == _codeLength;
    return first.length > 0;
}

- (void)refreshState {
    if (!_next) return;
    _next.dimmed = _busy || ![self valid];
    _next.hidden = _busy;
    if (_busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
    for (UITextField *field in _fields) field.enabled = !_busy;
    [self refreshAction];
}

#pragma mark text fields

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *proposed = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (_kind == NoshiFormKindCode) {
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < proposed.length; ++i) {
            unichar c = [proposed characterAtIndex:i];
            if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
        }
        NSUInteger limit = _codeLength > 0 ? (NSUInteger)_codeLength : CODE_LENGTH_FALLBACK;
        if (digits.length > limit) [digits deleteCharactersInRange:NSMakeRange(limit, digits.length - limit)];
        field.text = digits;
        [self showError:nil];
        [self refreshState];
        if (_codeLength > 0 && (NSInteger)digits.length == _codeLength) [self submit];
        return NO;
    }
    if (_kind == NoshiFormKindName && proposed.length > NAME_LENGTH_LIMIT) return NO;
    [self showError:nil];
    /* the field has not taken the change yet, so the button state is read on the next turn */
    [self performSelector:@selector(refreshState) withObject:nil afterDelay:0];
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSUInteger index = [_fields indexOfObject:field];
    if (index + 1 < [_fields count]) {
        [[_fields objectAtIndex:index + 1] becomeFirstResponder];
        return NO;
    }
    [self submit];
    return NO;
}

#pragma mark actions

- (void)goBack {
    [_delegate formControllerDidGoBack:self];
}

- (void)submit {
    if (_busy || ![self valid]) return;
    [self.view endEditing:YES];
    [self showError:nil];
    [_delegate formController:self didSubmitValues:[self values]];
}

@end

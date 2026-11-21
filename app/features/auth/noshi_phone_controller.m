#import "noshi_phone_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_bar_button.h"
#import "noshi_frame_view.h"
#import "noshi_geometry.h"
#import "noshi_phone.h"
#import "noshi_phone_layout.h"
#import "noshi_phone_ring.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_wave_background_view.h"

@interface NoshiPhoneController () {
    NoshiCountryBook *_book;
    NoshiCountry *_country;
    NSString *_codeDigits;
    NSString *_nationalDigits;
    NoshiWaveBackgroundView *_backdrop;
    NoshiBarButton *_back;
    NoshiBarButton *_next;
    UIActivityIndicatorView *_spinner;
    UIButton *_qr;
    BOOL _busy;
    NoshiFrameView *_art;
    UILabel *_title;
    UILabel *_message;
    UIView *_card;
    UIControl *_countryRow;
    UIImageView *_flagView;
    UILabel *_countryName;
    UILabel *_chevron;
    UIView *_rowLine;
    UIView *_cellLine;
    UILabel *_plus;
    UITextField *_codeField;
    UITextField *_numberField;
    CGFloat _keyboardHeight;
    BOOL _visible;
}
@end

@implementation NoshiPhoneController

@synthesize delegate = _delegate;
@synthesize busy = _busy;

- (id)initWithCountryBook:(NoshiCountryBook *)book {
    self = [super init];
    if (!self) return nil;
    _book = [book retain];
    _country = [_book localCountry];
    _codeDigits = [(_country ? _country.code : @"") copy];
    _nationalDigits = [@"" copy];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _codeField.delegate = nil;
    _numberField.delegate = nil;
    [_book release];
    [_codeDigits release];
    [_nationalDigits release];
    [_backdrop release];
    [_back release];
    [_next release];
    [_spinner release];
    [_qr release];
    [_art release];
    [_title release];
    [_message release];
    [_card release];
    [_countryRow release];
    [_flagView release];
    [_countryName release];
    [_chevron release];
    [_rowLine release];
    [_cellLine release];
    [_plus release];
    [_codeField release];
    [_numberField release];
    [super dealloc];
}

static UILabel *NoshiPhoneLabel(UIColor *color, NSInteger lines, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    return label;
}

static UIView *NoshiHairline(void) {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = NoshiColorHairline();
    return line;
}

static UITextField *NoshiPhoneField(id<UITextFieldDelegate> delegate) {
    UITextField *field = [[UITextField alloc] init];
    field.delegate = delegate;
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = [UIColor clearColor];
    field.textColor = NoshiColorTitle();
    field.keyboardType = UIKeyboardTypePhonePad;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
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

    _art = [[NoshiFrameView alloc] initWithPrefix:@"phone_ring" count:NOSHI_PHONE_RING_FRAMES
                                    framesPerSecond:NOSHI_PHONE_RING_FPS];
    [root addSubview:_art];

    _title = NoshiPhoneLabel(NoshiColorTitle(), 1, NoshiTextAlignmentCenter);
    _title.text = NSLocalizedString(@"phone.title", nil);
    [root addSubview:_title];
    _message = NoshiPhoneLabel(NoshiColorMessage(), 0, NoshiTextAlignmentCenter);
    _message.text = NSLocalizedString(@"phone.message", nil);
    [root addSubview:_message];

    _card = [[UIView alloc] init];
    _card.backgroundColor = NoshiColorCard();
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 1.0 / NoshiScreenScale();
    _card.layer.borderColor = NoshiColorHairline().CGColor;
    [root addSubview:_card];

    _countryRow = [[UIControl alloc] init];
    [_countryRow addTarget:self action:@selector(chooseCountry) forControlEvents:UIControlEventTouchUpInside];
    [_countryRow addTarget:self action:@selector(rowDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_countryRow addTarget:self action:@selector(rowUp)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _countryRow.isAccessibilityElement = YES;
    _countryRow.accessibilityTraits = UIAccessibilityTraitButton;
    [_card addSubview:_countryRow];
    _flagView = [[UIImageView alloc] init];
    _flagView.userInteractionEnabled = NO;
    [_countryRow addSubview:_flagView];
    _countryName = NoshiPhoneLabel(NoshiColorTitle(), 1, NoshiTextAlignmentLeft);
    [_countryRow addSubview:_countryName];
    _chevron = NoshiPhoneLabel(NoshiColorDotOff(), 1, NoshiTextAlignmentCenter);
    _chevron.text = @"\u203A";
    [_countryRow addSubview:_chevron];

    _rowLine = NoshiHairline();
    [_card addSubview:_rowLine];
    _cellLine = NoshiHairline();
    [_card addSubview:_cellLine];

    _plus = NoshiPhoneLabel(NoshiColorTitle(), 1, NoshiTextAlignmentLeft);
    _plus.text = @"+";
    [_card addSubview:_plus];
    _codeField = NoshiPhoneField(self);
    [_card addSubview:_codeField];
    _numberField = NoshiPhoneField(self);
    [_card addSubview:_numberField];

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

    _qr = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qr setTitle:NSLocalizedString(@"phone.qr", nil) forState:UIControlStateNormal];
    [_qr setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_qr setTitleColor:NoshiColorMuted() forState:UIControlStateDisabled];
    [_qr addTarget:self action:@selector(openQr) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_qr];

    _codeField.text = _codeDigits;
    [self refreshCountry];
    [self refreshNumber];
}

- (void)openQr {
    if (_busy) return;
    [_delegate phoneControllerDidRequestQr:self];
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

#pragma mark layout

- (void)applyLayout {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGFloat side = insets.left;
    noshi_phone_metrics metrics = {size.width - insets.left - insets.right, size.height - _keyboardHeight,
                                     insets.top, _keyboardHeight > 0 ? 0 : insets.bottom, NoshiIsPad() ? 1 : 0};
    noshi_phone_layout layout;
    if (noshi_phone_layout_compute(&metrics, &layout) != NOSHI_OK) {
        NSLog(@"noshigram: phone layout does not fit %.0fx%.0f", metrics.width, metrics.height);
    }

    _backdrop.frame = self.view.bounds;
    _back.frame = NoshiCGRectOffset(layout.back, side, 0);
    _next.frame = NoshiCGRectOffset(layout.next, side, 0);
    _back.titleSize = _next.titleSize = (CGFloat)layout.bar_size;
    _spinner.center = CGPointMake(CGRectGetMaxX(_next.frame) - 26, CGRectGetMidY(_next.frame));

    _art.frame = NoshiCGRectOffset(layout.art, side, 0);
    _art.hidden = layout.art.width <= 0;
    _title.frame = NoshiCGRectOffset(layout.title, side, 0);
    _title.hidden = layout.title.height <= 0;
    _title.font = NoshiFontBold((CGFloat)layout.title_size);
    _message.frame = NoshiCGRectOffset(layout.message, side, 0);
    _message.hidden = layout.message.height <= 0;
    _message.font = NoshiFontRegular((CGFloat)layout.message_size);

    _card.frame = NoshiCGRectOffset(layout.card, side, 0);
    _card.layer.cornerRadius = (CGFloat)layout.card_radius;
    CGFloat rowHeight = (CGFloat)layout.country_row.height;
    CGFloat cardWidth = (CGFloat)layout.card.width;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    _countryRow.frame = CGRectMake(0, 0, cardWidth, rowHeight);
    CGFloat flagWidth = (CGFloat)layout.flag_width;
    CGFloat flagHeight = (CGFloat)layout.flag_height;
    _flagView.frame = CGRectMake(16, (rowHeight - flagHeight) / 2, flagWidth, flagHeight);
    _chevron.font = NoshiFontRegular((CGFloat)layout.field_size + 7);
    _chevron.frame = CGRectMake(cardWidth - 38, 0, 30, rowHeight);
    _countryName.font = NoshiFontRegular((CGFloat)layout.field_size);
    _countryName.frame = CGRectMake(16 + flagWidth + 12, 0, cardWidth - 16 - flagWidth - 12 - 38, rowHeight);
    _rowLine.frame = CGRectMake(0, rowHeight - hairline / 2, cardWidth, hairline);

    CGFloat codeWidth = (CGFloat)layout.code_cell.width;
    _cellLine.frame = CGRectMake(codeWidth - hairline / 2, rowHeight, hairline, rowHeight);
    UIFont *fieldFont = NoshiFontRegular((CGFloat)layout.field_size);
    _plus.font = fieldFont;
    _plus.frame = CGRectMake(16, rowHeight, 14, rowHeight);
    _codeField.font = fieldFont;
    _codeField.frame = CGRectMake(30, rowHeight, codeWidth - 30 - 8, rowHeight);
    _numberField.font = fieldFont;
    _numberField.frame = CGRectMake(codeWidth + 14, rowHeight, cardWidth - codeWidth - 14 - 8, rowHeight);

    /* the link sits under the card when the keyboard is down and there is room for it */
    CGFloat linkY = CGRectGetMaxY(_card.frame) + 14;
    _qr.titleLabel.font = NoshiFontSemibold(16);
    _qr.frame = CGRectMake(_card.frame.origin.x, linkY, _card.frame.size.width, 40);
    _qr.hidden = _keyboardHeight > 0 || linkY + 40 > size.height - metrics.bottom_inset - 4;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self applyLayout];
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
    [self refreshArtPlayback];
}

- (void)refreshArtPlayback {
    [_art setPlaying:_visible && !_art.hidden];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    NSString *motion = NoshiReduceMotionChangedNotification();
    if (motion) [center addObserver:self selector:@selector(refreshArtPlayback) name:motion object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    [self refreshArtPlayback];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self refreshArtPlayback];
    if (!self.presentedViewController) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self.view endEditing:YES];
        _keyboardHeight = 0;
    }
}

#pragma mark state

static NSString *NoshiPlaceholder(NSString *pattern) {
    return [pattern stringByReplacingOccurrencesOfString:@"X" withString:@"0"];
}

- (void)refreshCountry {
    _flagView.image = [_book flagForCountry:_country];
    _countryName.text = _country ? _country.name : NSLocalizedString(@"phone.badcode", nil);
    _countryName.textColor = _country ? NoshiColorTitle() : NoshiColorMessage();
    _countryRow.accessibilityLabel = _countryName.text;
    NSString *hint = _country.pattern.length ? NoshiPlaceholder(_country.pattern) : NSLocalizedString(@"phone.placeholder", nil);
    _numberField.placeholder = hint;
}

- (void)refreshNumber {
    char formatted[48];
    const char *pattern = _country ? _country.pattern.UTF8String : "";
    if (noshi_phone_format(pattern, _nationalDigits.UTF8String, formatted, sizeof(formatted)) != NOSHI_OK) {
        NSLog(@"noshigram: phone number did not format");
        formatted[0] = '\0';
    }
    _numberField.text = [NSString stringWithUTF8String:formatted];
    BOOL valid = noshi_phone_valid(_codeDigits.length, _nationalDigits.length) && _country;
    _next.dimmed = !valid;
}

- (void)setBusy:(BOOL)busy {
    _qr.enabled = !busy;
    if (busy == _busy) return;
    _busy = busy;
    _next.hidden = busy;
    if (busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
    _codeField.enabled = _numberField.enabled = !busy;
    _countryRow.enabled = !busy;
}

static NSString *NoshiDigitsOf(NSString *text, NSUInteger limit) {
    char digits[NOSHI_PHONE_MAX_DIGITS * 4 + 1];
    noshi_phone_digits(text.UTF8String, digits, sizeof(digits));
    NSString *all = [NSString stringWithUTF8String:digits];
    return all.length > limit ? [all substringToIndex:limit] : all;
}

/* takes a code and the digits typed after it; digits the code does not use move to the number, and a
   pasted whole number replaces it */
- (void)applyDigits:(NSString *)codeAndRest replaceNumber:(BOOL)replaceNumber {
    NSUInteger used = 0;
    NSString *digits = NoshiDigitsOf(codeAndRest, NOSHI_PHONE_MAX_DIGITS);
    NoshiCountry *match = [_book countryForDigits:digits codeLength:&used];
    if (match) {
        NSString *rest = [digits substringFromIndex:used];
        [_codeDigits release];
        _codeDigits = [[digits substringToIndex:used] copy];
        _country = match;
        if (rest.length || replaceNumber) {
            NSString *national = replaceNumber ? rest : [rest stringByAppendingString:_nationalDigits];
            [_nationalDigits release];
            _nationalDigits = [(national.length > NOSHI_PHONE_MAX_DIGITS - used
                                    ? [national substringToIndex:NOSHI_PHONE_MAX_DIGITS - used] : national) copy];
        }
    } else {
        NSString *code = digits.length > NOSHI_COUNTRY_CODE_MAX ? [digits substringToIndex:NOSHI_COUNTRY_CODE_MAX] : digits;
        [_codeDigits release];
        _codeDigits = [code copy];
        _country = nil;
    }
    _codeField.text = _codeDigits;
    [self refreshCountry];
    [self refreshNumber];
}

#pragma mark text fields

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *text = field.text;
    if (field == _codeField) {
        NSString *proposed = [text stringByReplacingCharactersInRange:range withString:string];
        NSString *digits = NoshiDigitsOf(proposed, NOSHI_PHONE_MAX_DIGITS);
        NSUInteger before = _codeDigits.length;
        [self applyDigits:digits replaceNumber:digits.length > NOSHI_COUNTRY_CODE_MAX];
        /* a digit the code did not take went to the number, so the cursor follows it */
        if (digits.length > _codeDigits.length && _codeDigits.length >= before) [_numberField becomeFirstResponder];
        return NO;
    }
    /* backspace over a separator removes the digit before it, or the field would not move */
    if (string.length == 0 && range.length == 1 && range.location < text.length &&
        NoshiDigitsOf([text substringWithRange:range], 1).length == 0) {
        while (range.location > 0 && NoshiDigitsOf([text substringWithRange:NSMakeRange(range.location, 1)], 1).length == 0) {
            --range.location;
        }
        range.length = 1;
    }
    NSString *proposed = [text stringByReplacingCharactersInRange:range withString:string];
    if ([string hasPrefix:@"+"] && range.location == 0) {
        [self applyDigits:string replaceNumber:YES];
        [self placeCaretAfterDigits:_nationalDigits.length];
        return NO;
    }
    NSUInteger room = NOSHI_PHONE_MAX_DIGITS - _codeDigits.length;
    NSString *typed = NoshiDigitsOf(proposed, room);
    NSString *beforeCaret = [proposed substringToIndex:MIN(proposed.length, range.location + string.length)];
    NSUInteger caretDigits = MIN(NoshiDigitsOf(beforeCaret, room).length, typed.length);
    [_nationalDigits release];
    _nationalDigits = [typed copy];
    [self refreshNumber];
    [self placeCaretAfterDigits:caretDigits];
    return NO;
}

- (void)placeCaretAfterDigits:(NSUInteger)count {
    NSString *text = _numberField.text;
    NSUInteger position = 0;
    NSUInteger seen = 0;
    while (position < text.length && seen < count) {
        unichar c = [text characterAtIndex:position++];
        if (c >= '0' && c <= '9') ++seen;
    }
    UITextPosition *start = [_numberField positionFromPosition:_numberField.beginningOfDocument offset:(NSInteger)position];
    if (start) _numberField.selectedTextRange = [_numberField textRangeFromPosition:start toPosition:start];
}

#pragma mark actions

- (void)rowDown {
    _countryRow.backgroundColor = NoshiColorField();
}

- (void)rowUp {
    _countryRow.backgroundColor = [UIColor clearColor];
}

- (void)chooseCountry {
    NoshiCountryController *picker = [[[NoshiCountryController alloc] initWithCountryBook:_book] autorelease];
    picker.delegate = self;
    if (NoshiIsPad()) picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:NULL];
}

- (void)countryController:(NoshiCountryController *)controller didPickCountry:(NoshiCountry *)country {
    (void)controller;
    [self dismissViewControllerAnimated:YES completion:NULL];
    [self applyDigits:country.code replaceNumber:NO];
}

- (void)countryControllerDidCancel:(NoshiCountryController *)controller {
    (void)controller;
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)submit {
    if (_busy || !_country || !noshi_phone_valid(_codeDigits.length, _nationalDigits.length)) return;
    [self.view endEditing:YES];
    [_delegate phoneController:self didSubmitNumber:[NSString stringWithFormat:@"+%@%@", _codeDigits, _nationalDigits]];
}

@end

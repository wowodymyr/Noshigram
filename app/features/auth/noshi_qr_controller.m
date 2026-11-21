#import "noshi_qr_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#include "noshi_qr.h"

#import "noshi_bar_button.h"
#import "noshi_platform.h"
#import "noshi_qr_view.h"
#import "noshi_theme.h"
#import "noshi_wave_background_view.h"

#define STEPS 3
#define CARD_MAX 280.0
#define CARD_PADDING 14.0

@interface NoshiQrController () {
    NoshiWaveBackgroundView *_backdrop;
    NoshiBarButton *_back;
    UIScrollView *_scroll;
    UIView *_card;
    NoshiQrView *_code;
    UIActivityIndicatorView *_spinner;
    UILabel *_failure;
    UIButton *_retry;
    UILabel *_title;
    UILabel *_steps[STEPS];
    UILabel *_numbers[STEPS];
    UIButton *_phone;
    BOOL _appeared;
    BOOL _hasCode;
    id<NoshiQrControllerDelegate> _delegate;
}
@end

@implementation NoshiQrController

@synthesize delegate = _delegate;

- (void)dealloc {
    [_backdrop release];
    [_back release];
    [_scroll release];
    [_card release];
    [_code release];
    [_spinner release];
    [_failure release];
    [_retry release];
    [_title release];
    for (int i = 0; i < STEPS; ++i) {
        [_steps[i] release];
        [_numbers[i] release];
    }
    [_phone release];
    [super dealloc];
}

static UILabel *NoshiQrLabel(UIColor *color, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[NoshiWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    /* a small screen cannot hold the code and the steps at once, so everything under the back button scrolls */
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    [root addSubview:_scroll];
    _card = [[UIView alloc] init];
    _card.backgroundColor = [UIColor whiteColor];
    _card.layer.cornerRadius = 22;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = 0.18;
    _card.layer.shadowRadius = 14;
    _card.layer.shadowOffset = CGSizeMake(0, 6);
    [_scroll addSubview:_card];
    _code = [[NoshiQrView alloc] init];
    _code.layer.cornerRadius = 12;
    _code.layer.masksToBounds = YES;
    _code.stillMode = NoshiReduceMotionEnabled();
    [_card addSubview:_code];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_card addSubview:_spinner];
    _failure = NoshiQrLabel(NoshiColorMessage(), NoshiTextAlignmentCenter);
    _failure.hidden = YES;
    [_card addSubview:_failure];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [_card addSubview:_retry];

    _title = NoshiQrLabel(NoshiColorTitle(), NoshiTextAlignmentCenter);
    _title.text = NSLocalizedString(@"qr.title", nil);
    [_scroll addSubview:_title];
    NSString *keys[STEPS] = {@"qr.step.open", @"qr.step.settings", @"qr.step.scan"};
    for (int i = 0; i < STEPS; ++i) {
        _numbers[i] = NoshiQrLabel([UIColor whiteColor], NoshiTextAlignmentCenter);
        _numbers[i].backgroundColor = NoshiColorAccent();
        _numbers[i].layer.masksToBounds = YES;
        _numbers[i].text = [NSString stringWithFormat:@"%d", i + 1];
        [_scroll addSubview:_numbers[i]];
        _steps[i] = NoshiQrLabel(NoshiColorMessage(), NoshiTextAlignmentLeft);
        _steps[i].text = NSLocalizedString(keys[i], nil);
        [_scroll addSubview:_steps[i]];
    }
    _phone = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_phone setTitle:NSLocalizedString(@"qr.phone", nil) forState:UIControlStateNormal];
    [_phone setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    [_phone addTarget:self action:@selector(phoneTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_phone];
    _back = [[NoshiBarButton alloc] init];
    _back.chevron = YES;
    _back.title = NSLocalizedString(@"phone.back", nil);
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];
    [self showLoading];
}

#pragma mark state

- (void)showLoading {
    _failure.hidden = YES;
    _retry.hidden = YES;
    if (!_hasCode) [_spinner startAnimating];
}

- (void)showFailure:(NSString *)text {
    [_spinner stopAnimating];
    _hasCode = NO;
    [_code clear];
    _failure.text = text;
    _failure.hidden = NO;
    _retry.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)showUrl:(NSString *)url {
    static uint8_t modules[NOSHI_QR_MAX_MODULES];
    int side = 0;
    const char *text = url.UTF8String;
    noshi_status status = text ? noshi_qr_encode_min_version((const uint8_t *)text, strlen(text), NOSHI_QR_LOGO_MIN_VERSION, modules, sizeof(modules), &side, NULL) : NOSHI_E_ARG;
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the login code does not fit a QR code: %s", noshi_status_name(status));
        [self showFailure:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    [_spinner stopAnimating];
    _failure.hidden = YES;
    _retry.hidden = YES;
    /* the first code appears after the screen does, so its wave is seen; a later one replaces the old with the same wave */
    BOOL animated = YES;
    [_code setModules:[NSData dataWithBytes:modules length:(NSUInteger)(side * side)] side:side animated:animated];
    _hasCode = YES;
}

#pragma mark actions

- (void)goBack {
    [_delegate qrControllerDidGoBack:self];
}

- (void)phoneTapped {
    [_delegate qrControllerDidChoosePhone:self];
}

- (void)retryTapped {
    [self showLoading];
    [_spinner startAnimating];
    _retry.hidden = YES;
    _failure.hidden = YES;
    [_delegate qrControllerDidRequestRetry:self];
}

#pragma mark layout

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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    BOOL wide = size.width > size.height && size.width > 520;
    _backdrop.frame = self.view.bounds;
    _back.frame = CGRectMake(insets.left, insets.top, 90, 44);
    CGFloat top = insets.top + 44;
    CGFloat usableHeight = size.height - top - insets.bottom;
    _scroll.frame = CGRectMake(0, top, size.width, size.height - top);
    CGFloat card = MIN(CARD_MAX, wide ? usableHeight - 40 : MIN(size.width - 80, usableHeight * 0.55));
    card = MAX(card, 170);
    CGFloat textWidth = wide ? MIN(size.width / 2 - 40, 340) : MIN(size.width - 56, 360);
    CGFloat titleSize = NoshiIsPad() ? 26 : 22, stepSize = NoshiIsPad() ? 18 : 16;
    _title.font = NoshiFontBold(titleSize);
    CGSize titleFit = [_title sizeThatFits:CGSizeMake(textWidth, 200)];
    CGFloat stepsHeight = 0;
    CGFloat heights[STEPS];
    for (int i = 0; i < STEPS; ++i) {
        _steps[i].font = NoshiFontRegular(stepSize);
        CGSize fit = [_steps[i] sizeThatFits:CGSizeMake(textWidth - 40, 200)];
        heights[i] = MAX(26, fit.height);
        stepsHeight += heights[i] + 12;
    }
    CGFloat textBlock = titleFit.height + 18 + stepsHeight + 16 + 40;
    /* coordinates below are inside the scroll view */
    CGFloat cardX, cardY, textX, textY, content;
    if (wide) {
        CGFloat total = card + 44 + textWidth;
        cardX = (size.width - total) / 2;
        cardY = MAX(12, (usableHeight - card) / 2);
        textX = cardX + card + 44;
        textY = MAX(12, (usableHeight - textBlock) / 2);
        content = MAX(cardY + card, textY + textBlock) + 24;
    } else {
        cardX = (size.width - card) / 2;
        cardY = MAX(8, (usableHeight - (card + 28 + textBlock)) / 2);
        textX = (size.width - textWidth) / 2;
        textY = cardY + card + 28;
        content = textY + textBlock + 24;
    }
    _scroll.contentSize = CGSizeMake(size.width, MAX(content, usableHeight));
    _card.frame = CGRectMake(cardX, cardY, card, card);
    _code.frame = CGRectInset(_card.bounds, CARD_PADDING, CARD_PADDING);
    _spinner.center = CGPointMake(card / 2, card / 2);
    _failure.font = NoshiFontRegular(15);
    _failure.frame = CGRectMake(20, card / 2 - 50, card - 40, 60);
    _retry.frame = CGRectMake((card - 120) / 2, card / 2 + 14, 120, 40);
    _title.frame = CGRectMake(textX, textY, textWidth, titleFit.height);
    CGFloat y = textY + titleFit.height + 18;
    for (int i = 0; i < STEPS; ++i) {
        _numbers[i].font = NoshiFontSemibold(13);
        _numbers[i].frame = CGRectMake(textX, y + (heights[i] - 24) / 2, 24, 24);
        _numbers[i].layer.cornerRadius = 12;
        _steps[i].frame = CGRectMake(textX + 36, y, textWidth - 36, heights[i]);
        y += heights[i] + 12;
    }
    _phone.titleLabel.font = NoshiFontSemibold(17);
    _phone.frame = CGRectMake(textX, y + 6, textWidth, 40);
    _phone.contentHorizontalAlignment = wide ? UIControlContentHorizontalAlignmentLeft : UIControlContentHorizontalAlignmentCenter;
    _title.textAlignment = wide ? NoshiTextAlignmentLeft : NoshiTextAlignmentCenter;
}

#pragma mark entrance

/* the card rises and settles, then the title and the steps follow one after another */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_appeared) return;
    _appeared = YES;
    if (NoshiReduceMotionEnabled()) return;
    _card.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(0.86, 0.86);
    NoshiAnimateViewAfter(_card, CGAffineTransformIdentity, 1, NOSHI_MOTION_SPRING, 0.05, nil);
    NSMutableArray *views = [NSMutableArray arrayWithObject:_title];
    for (int i = 0; i < STEPS; ++i) {
        [views addObject:_numbers[i]];
        [views addObject:_steps[i]];
    }
    [views addObject:_phone];
    NSUInteger index = 0;
    for (UIView *view in views) {
        view.alpha = 0;
        view.transform = CGAffineTransformMakeTranslation(0, 14);
        NoshiAnimateViewAfter(view, CGAffineTransformIdentity, 1, NOSHI_MOTION_ENTER,
                                0.15 + 0.035 * (NSTimeInterval)index, nil);
        ++index;
    }
}

@end

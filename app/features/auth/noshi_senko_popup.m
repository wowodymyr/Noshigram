#import "noshi_senko_popup.h"

#import "noshi_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

#define CARD_MAX_WIDTH 340.0
#define SIDE_MARGIN 24.0
#define CARD_PAD 16.0
#define BUTTON_HEIGHT 44.0

@interface NoshiSenkoPopup () <UIGestureRecognizerDelegate> {
    UIView *_card;
    UIImageView *_picture;
    UILabel *_title;
    UILabel *_message;
    UIButton *_button;
    NSString *_titleText;
    NSString *_messageText;
    NSString *_buttonTitle;
    NSString *_pictureName;
    CGFloat _pictureHeight;
    void (^_dismissHandler)(void);
    BOOL _shown;
    BOOL _leaving;
}
@end

@implementation NoshiSenkoPopup

@synthesize titleText = _titleText;
@synthesize messageText = _messageText;
@synthesize buttonTitle = _buttonTitle;
@synthesize pictureName = _pictureName;
@synthesize pictureHeight = _pictureHeight;
@synthesize dismissHandler = _dismissHandler;
@synthesize isShown = _shown;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    BOOL classic = NoshiThemeIsClassic();
    _card = [[UIView alloc] init];
    if (classic) {
        /* the plate of the classic menus, which keeps its own corners and shadow */
        NoshiClassicApplyMenuPlate(_card, 14);
    } else {
        _card.backgroundColor = NoshiColorCard();
        _card.layer.cornerRadius = 22;
        _card.layer.shadowColor = [UIColor blackColor].CGColor;
        _card.layer.shadowOpacity = 0.3f;
        _card.layer.shadowRadius = 18;
        _card.layer.shadowOffset = CGSizeMake(0, 8);
    }
    [self addSubview:_card];
    /* the picture is a jpeg of a photo size; the system picks the file for the screen scale */
    _picture = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"senko_meme.jpg"]];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.layer.cornerRadius = 14;
    [_card addSubview:_picture];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = classic ? NoshiClassicMenuTextColor() : NoshiColorTitle();
    _title.font = NoshiFontBold(18);
    if (classic) NoshiClassicStyleMenuLabel(_title, 18);
    _title.textAlignment = NoshiTextAlignmentCenter;
    _title.numberOfLines = 0;
    [_card addSubview:_title];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = classic ? [NoshiClassicMenuTextColor() colorWithAlphaComponent:0.75f] : NoshiColorMessage();
    _message.font = NoshiFontRegular(14);
    _message.textAlignment = NoshiTextAlignmentCenter;
    _message.numberOfLines = 0;
    [_card addSubview:_message];
    _button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _button.titleLabel.font = NoshiFontBold(16);
    if (classic) {
        [_button setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, NO) forState:UIControlStateNormal];
        [_button setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, YES) forState:UIControlStateHighlighted];
        _button.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [_button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
    } else {
        _button.layer.cornerRadius = BUTTON_HEIGHT / 2;
        _button.backgroundColor = NoshiColorAccent();
    }
    [_button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_button];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped:)] autorelease];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    [_card release];
    [_picture release];
    [_title release];
    [_message release];
    [_button release];
    [_titleText release];
    [_messageText release];
    [_buttonTitle release];
    [_pictureName release];
    [_dismissHandler release];
    [super dealloc];
}

/* a tap on the card itself keeps it; only the dimmed part around it closes the window */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return !CGRectContainsPoint(_card.frame, [touch locationInView:self]);
}

- (void)backdropTapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    [self dismiss];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    /* a layout while the window fades reassigns the texts and the picture, and the labels redraw under the fading card */
    if (_leaving) return;
    CGFloat width = MIN(self.bounds.size.width - 2 * SIDE_MARGIN, CARD_MAX_WIDTH);
    CGFloat inner = width - 2 * CARD_PAD;
    if (_pictureName.length) {
        UIImage *named = [UIImage imageNamed:_pictureName];
        if (named && named != _picture.image) _picture.image = named;
    }
    UIImage *image = _picture.image;
    CGFloat pictureHeight = image && image.size.width > 0 ? ceil(inner * image.size.height / image.size.width) : inner;
    if (_pictureHeight > 0) {
        /* a sticker keeps its outline: it is shown whole, with no rounded clip around a box it does not fill */
        pictureHeight = MIN(pictureHeight, _pictureHeight);
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        _picture.clipsToBounds = NO;
        _picture.layer.cornerRadius = 0;
    }
    _title.text = _titleText;
    _message.text = _messageText;
    [_button setTitle:_buttonTitle forState:UIControlStateNormal];
    CGSize title = [_title sizeThatFits:CGSizeMake(inner, 400)];
    CGSize message = [_message sizeThatFits:CGSizeMake(inner, 400)];
    CGFloat y = CARD_PAD;
    _picture.frame = CGRectMake(CARD_PAD, y, inner, pictureHeight);
    y += pictureHeight + 14;
    _title.frame = CGRectMake(CARD_PAD, y, inner, ceil(title.height));
    y += ceil(title.height) + 6;
    _message.frame = CGRectMake(CARD_PAD, y, inner, ceil(message.height));
    y += ceil(message.height) + 16;
    _button.frame = CGRectMake(CARD_PAD, y, inner, BUTTON_HEIGHT);
    y += BUTTON_HEIGHT + CARD_PAD;
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - y) / 2), width, y);
    if (NoshiThemeIsClassic()) NoshiClassicFitPlate(_card, 0);
    else _card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:22].CGPath;
    _card.transform = held;
}

- (void)showInView:(UIView *)host {
    if (_shown) return;
    _shown = YES;
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    BOOL still = NoshiReduceMotionEnabled();
    self.alpha = still ? 1 : 0;
    _card.transform = still ? CGAffineTransformIdentity : CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale());
    if (still) return;
    NoshiAnimateView(self, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(_card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}

- (void)dismiss {
    if (!_shown || _leaving) return;
    _leaving = YES;
    self.userInteractionEnabled = NO;
    [self retain];
    void (^finish)(void) = ^{
        [self removeFromSuperview];
        _shown = NO;
        void (^handler)(void) = [_dismissHandler retain];
        if (handler) handler();
        [handler release];
        [self autorelease];
    };
    if (NoshiReduceMotionEnabled()) {
        finish();
        return;
    }
    /* the window leaves when its own fade ends: the card runs the same curve, but its end can come a frame earlier and take the dim away before the fade reaches zero */
    NoshiAnimateView(_card, CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()), 1, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(self, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), ^(BOOL done) {
        (void)done;
        finish();
    });
}

@end

void NoshiShowPicturePopup(NSString *title, NSString *message, NSString *pictureName, CGFloat pictureHeight) {
    UIView *host = NoshiOverlayHost();
    if (!host) {
        NoshiShowNotice(title, message);
        return;
    }
    NoshiSenkoPopup *popup = [[NoshiSenkoPopup alloc] init];
    popup.pictureName = pictureName;
    popup.pictureHeight = pictureHeight;
    popup.titleText = title;
    popup.messageText = message;
    popup.buttonTitle = NSLocalizedString(@"notice.ok", nil);
    /* the host view holds the popup while it is shown */
    [popup showInView:host];
    [popup release];
}

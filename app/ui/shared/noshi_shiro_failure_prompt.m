#import "noshi_shiro_failure_prompt.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_shiro.h"
#import "noshi_theme.h"

#define CARD_WIDTH_MAX 330.0
#define CARD_MARGIN 24.0
#define BUTTON_HEIGHT 46.0
/* the least height of the picture on a card, below which the card scrolls instead */
#define PICTURE_MIN 110.0

@interface NoshiShiroFailureTarget : NSObject {
@public
    NoshiShiro *shiro;
    UIView *dim;
    UIView *card;
    UIButton *copyButton;
}
@end

static NoshiShiroFailureTarget *NoshiShiroFailureShown;

@implementation NoshiShiroFailureTarget

- (void)close {
    if (NoshiShiroFailureShown != self) return;
    NoshiShiroFailureShown = nil;
    UIView *shade = [dim retain], *plate = [card retain];
    /* the buttons and the tap of the backdrop send to this object, which therefore lives until the fade ends; a second tap meanwhile finds nothing to press */
    shade.userInteractionEnabled = NO;
    plate.userInteractionEnabled = NO;
    NoshiAnimateView(shade, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(plate, CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()), 0, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [shade removeFromSuperview];
        [plate removeFromSuperview];
        [shade release];
        [plate release];
        [self release];
    });
}

- (void)retryTapped {
    NoshiShiro *tunnel = [[shiro retain] autorelease];
    [self close];
    [tunnel retry];
}

- (void)copyTapped {
    [UIPasteboard generalPasteboard].string = [shiro logText];
    [copyButton setTitle:NSLocalizedString(@"shiro.fail.copied", nil) forState:UIControlStateNormal];
}

- (void)offTapped {
    NoshiShiro *tunnel = [[shiro retain] autorelease];
    [self close];
    [tunnel setEnabled:NO];
}

- (void)backdropTapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    [self close];
}

/* a tap on the card itself keeps it, as the buttons on it need their own touches */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return !CGRectContainsPoint(card.frame, [touch locationInView:dim]);
}

- (void)dealloc {
    [shiro release];
    [dim release];
    [card release];
    [super dealloc];
}

@end

static UIButton *NoshiFailureButton(NSString *title, NoshiClassicGloss gloss, BOOL primary, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = NoshiFontSemibold(16);
    [button setTitle:title forState:UIControlStateNormal];
    if (NoshiThemeIsClassic()) {
        [button setBackgroundImage:NoshiClassicGlossButtonImage(gloss, NO) forState:UIControlStateNormal];
        [button setBackgroundImage:NoshiClassicGlossButtonImage(gloss, YES) forState:UIControlStateHighlighted];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    } else {
        button.backgroundColor = primary ? NoshiColorAccent() : NoshiColorField();
        button.layer.cornerRadius = BUTTON_HEIGHT / 2;
        [button setTitleColor:primary ? [UIColor whiteColor] : NoshiColorTitle() forState:UIControlStateNormal];
    }
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

void NoshiShowShiroFailure(NoshiShiro *shiro) {
    UIView *host = NoshiOverlayHost();
    if (!host || !shiro || NoshiShiroFailureShown) return;
    NoshiShiroFailureTarget *target = [[NoshiShiroFailureTarget alloc] init];
    target->shiro = [shiro retain];
    CGFloat width = MIN(host.bounds.size.width - 2 * CARD_MARGIN, CARD_WIDTH_MAX);
    CGFloat inner = width - 40;

    UIView *dim = [[UIView alloc] initWithFrame:host.bounds];
    dim.backgroundColor = [UIColor blackColor];
    dim.alpha = 0;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(backdropTapped:)] autorelease];
    tap.delegate = (id<UIGestureRecognizerDelegate>)target;
    [dim addGestureRecognizer:tap];
    target->dim = dim;

    UIView *card = [[UIView alloc] init];
    BOOL classic = NoshiThemeIsClassic();
    CGFloat radius = classic ? 14 : 26;
    if (classic) {
        NoshiClassicApplyMenuPlate(card, radius);
    } else {
        card.backgroundColor = NoshiColorCard();
        card.layer.cornerRadius = radius;
        card.layer.shadowColor = [UIColor blackColor].CGColor;
        card.layer.shadowOpacity = 0.3f;
        card.layer.shadowRadius = 18;
        card.layer.shadowOffset = CGSizeMake(0, 6);
    }
    target->card = card;

    UILabel *title = [[[UILabel alloc] init] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.font = NoshiFontBold(21);
    title.textColor = classic ? NoshiClassicMenuTextColor() : NoshiColorTitle();
    title.textAlignment = NoshiTextAlignmentCenter;
    title.numberOfLines = 0;
    title.text = NSLocalizedString(@"shiro.fail.title", nil);
    CGSize titleFit = [title sizeThatFits:CGSizeMake(inner, 200)];

    NSString *why = shiro.failureText.length ? shiro.failureText : NSLocalizedString(@"shiro.why.server", nil);
    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.font = NoshiFontRegular(15);
    text.textColor = classic ? [NoshiClassicMenuTextColor() colorWithAlphaComponent:0.7] : NoshiColorSecondary();
    text.textAlignment = NoshiTextAlignmentCenter;
    text.numberOfLines = 0;
    /* the technical line (account: io error) is in the log that the button copies, and is no part of the words the person reads */
    text.text = why;
    CGSize fit = [text sizeThatFits:CGSizeMake(inner, 600)];

    /* the picture takes what the screen has left over the words and the three buttons, up to the width of the card */
    CGFloat rest = 22 + ceil(titleFit.height) + 10 + ceil(fit.height) + 20 + 3 * BUTTON_HEIGHT + 2 * 10 + 20;
    /* the most the card may take of the screen; the picture is never dropped, and a card that does not fit scrolls, since a small phone has no room for the picture, the words and the buttons together */
    CGFloat room = host.bounds.size.height - 2 * CARD_MARGIN - NoshiStatusBarHeight();
    CGFloat side = MIN(inner, room - rest - 14);
    /* a tall card makes room by taking from the picture, which is shown whole in what is left; below the least it scrolls */
    BOOL scrolls = side < PICTURE_MIN;
    if (scrolls) side = PICTURE_MIN;
    UIScrollView *content = [[[UIScrollView alloc] init] autorelease];
    content.showsVerticalScrollIndicator = NO;
    /* a clip with rounded corners makes the card draw off screen at every frame of its move; the card already has its corners, and only a card that scrolls needs the clip */
    content.layer.cornerRadius = radius;
    content.clipsToBounds = scrolls;
    [card addSubview:content];
    CGFloat top = 22;
    {
        UIImageView *picture = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"shiro_error.png"]] autorelease];
        /* the whole sticker, whatever room the screen leaves: a cut of it showed only a middle of the picture */
        picture.contentMode = UIViewContentModeScaleAspectFit;
        picture.clipsToBounds = YES;
        picture.layer.cornerRadius = 0;
        picture.frame = CGRectMake(20, 20, inner, floor(side));
        [content addSubview:picture];
        top = CGRectGetMaxY(picture.frame) + 14;
    }
    title.frame = CGRectMake(20, top, inner, ceil(titleFit.height));
    [content addSubview:title];
    text.frame = CGRectMake(20, CGRectGetMaxY(title.frame) + 10, inner, ceil(fit.height));
    [content addSubview:text];

    CGFloat y = CGRectGetMaxY(text.frame) + 20;
    UIButton *retry = NoshiFailureButton(NSLocalizedString(@"shiro.fail.retry", nil), NoshiClassicGlossGreen, YES, target, @selector(retryTapped));
    retry.frame = CGRectMake(20, y, inner, BUTTON_HEIGHT);
    [content addSubview:retry];
    UIButton *copy = NoshiFailureButton(NSLocalizedString(@"shiro.fail.copy", nil), NoshiClassicGlossSlate, NO, target, @selector(copyTapped));
    copy.frame = CGRectMake(20, y + BUTTON_HEIGHT + 10, inner, BUTTON_HEIGHT);
    [content addSubview:copy];
    target->copyButton = copy;
    UIButton *off = NoshiFailureButton(NSLocalizedString(@"shiro.fail.off", nil), NoshiClassicGlossRed, NO, target, @selector(offTapped));
    off.frame = CGRectMake(20, y + 2 * (BUTTON_HEIGHT + 10), inner, BUTTON_HEIGHT);
    [content addSubview:off];
    CGFloat height = CGRectGetMaxY(off.frame) + 20;
    content.contentSize = CGSizeMake(width, height);
    content.scrollEnabled = scrolls;
    content.frame = CGRectMake(0, 0, width, MIN(height, room));
    card.bounds = CGRectMake(0, 0, width, MIN(height, room));
    card.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    /* the shadow follows a path and the card is drawn once into a picture that then moves, so the spring of its entry costs nothing on a slow phone */
    if (classic) NoshiClassicFitPlate(card, 0);
    else card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:card.bounds cornerRadius:radius].CGPath;
    card.layer.shouldRasterize = YES;
    card.layer.rasterizationScale = [UIScreen mainScreen].scale;

    [host addSubview:dim];
    [host addSubview:card];
    NoshiShiroFailureShown = target;
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale());
    NoshiAnimateView(dim, CGAffineTransformIdentity, 0.5f, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}

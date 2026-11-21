#import "noshi_crash_prompt.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define CARD_WIDTH_MAX 320.0
#define CARD_MARGIN 24.0
#define BUTTON_HEIGHT 48.0
/* the least height of the picture on a card, below which the card scrolls instead */
#define PICTURE_MIN 110.0

@interface NoshiCrashPromptTarget : NSObject {
@public
    UIView *dim;
    UIView *card;
    void (^answer)(BOOL);
}
- (void)finish:(BOOL)send;
@end

static NoshiCrashPromptTarget *NoshiCrashPromptShown;

@implementation NoshiCrashPromptTarget

- (void)finish:(BOOL)send {
    if (NoshiCrashPromptShown != self) return;
    NoshiCrashPromptShown = nil;
    void (^done)(BOOL) = [answer retain];
    UIView *shade = [dim retain], *plate = [card retain];
    /* a second tap while the card fades out (the main thread is busy with the answer, so the fade can be late) must not reach a target that is gone: the
       target lives until the fade ends, and nothing is tappable meanwhile */
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
    if (done) done(send);
    [done release];
}

- (void)sendTapped { [self finish:YES]; }
- (void)laterTapped { [self finish:NO]; }

- (void)dealloc {
    [dim release];
    [card release];
    [answer release];
    [super dealloc];
}

@end

static UIButton *NoshiPromptButton(NSString *title, BOOL primary, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = NoshiFontSemibold(17);
    [button setTitle:title forState:UIControlStateNormal];
    if (NoshiThemeIsClassic()) {
        NoshiClassicGloss gloss = primary ? NoshiClassicGlossGreen : NoshiClassicGlossSlate;
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

BOOL NoshiAskCrashReport(void (^answer)(BOOL send)) {
    UIView *window = NoshiOverlayHost();
    if (!window || NoshiCrashPromptShown) {
        return NO;
    }
    NoshiCrashPromptTarget *target = [[NoshiCrashPromptTarget alloc] init];
    target->answer = [answer copy];
    CGFloat width = MIN(window.bounds.size.width - 2 * CARD_MARGIN, CARD_WIDTH_MAX);
    CGFloat inner = width - 40;

    UIView *dim = [[UIView alloc] initWithFrame:window.bounds];
    dim.backgroundColor = [UIColor blackColor];
    dim.alpha = 0;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    title.font = NoshiFontBold(22);
    title.textColor = classic ? NoshiClassicMenuTextColor() : NoshiColorTitle();
    title.textAlignment = NoshiTextAlignmentCenter;
    title.numberOfLines = 0;
    title.text = NSLocalizedString(@"crash.title", nil);
    CGSize titleFit = [title sizeThatFits:CGSizeMake(inner, 200)];

    UILabel *text = [[[UILabel alloc] init] autorelease];
    text.backgroundColor = [UIColor clearColor];
    text.font = NoshiFontRegular(15);
    text.textColor = classic ? [NoshiClassicMenuTextColor() colorWithAlphaComponent:0.7] : NoshiColorSecondary();
    text.textAlignment = NoshiTextAlignmentCenter;
    text.numberOfLines = 0;
    text.text = NSLocalizedString(@"crash.text", nil);
    CGSize fit = [text sizeThatFits:CGSizeMake(inner, 400)];

    /* the picture takes what the screen has left over the words and the two buttons, up to the width of the card */
    CGFloat rest = 22 + ceil(titleFit.height) + 6 + ceil(fit.height) + 20 + 2 * BUTTON_HEIGHT + 10 + 20;
    /* the most the card may take of the screen; the picture is never dropped, and a card that does not fit scrolls, since a small phone has no room for the picture, the words and the buttons together */
    CGFloat room = window.bounds.size.height - 2 * CARD_MARGIN - NoshiStatusBarHeight();
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
        UIImageView *picture = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"crash_meme.jpg"]] autorelease];
        /* the whole meme, whatever room the screen leaves: a cut of it showed only a middle of the picture */
        picture.contentMode = UIViewContentModeScaleAspectFit;
        picture.clipsToBounds = YES;
        picture.layer.cornerRadius = 14;
        picture.frame = CGRectMake(20, 20, inner, floor(side));
        [content addSubview:picture];
        top = CGRectGetMaxY(picture.frame) + 14;
    }
    title.frame = CGRectMake(20, top, inner, ceil(titleFit.height));
    [content addSubview:title];
    text.frame = CGRectMake(20, CGRectGetMaxY(title.frame) + 6, inner, ceil(fit.height));
    [content addSubview:text];

    CGFloat y = CGRectGetMaxY(text.frame) + 20;
    UIButton *send = NoshiPromptButton(NSLocalizedString(@"crash.send", nil), YES, target, @selector(sendTapped));
    send.frame = CGRectMake(20, y, inner, BUTTON_HEIGHT);
    [content addSubview:send];
    UIButton *later = NoshiPromptButton(NSLocalizedString(@"crash.later", nil), NO, target, @selector(laterTapped));
    later.frame = CGRectMake(20, y + BUTTON_HEIGHT + 10, inner, BUTTON_HEIGHT);
    [content addSubview:later];
    CGFloat height = CGRectGetMaxY(later.frame) + 20;
    content.contentSize = CGSizeMake(width, height);
    content.scrollEnabled = scrolls;
    content.frame = CGRectMake(0, 0, width, MIN(height, room));
    card.bounds = CGRectMake(0, 0, width, MIN(height, room));
    card.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    /* the shadow follows a path and the card is drawn once into a picture that then moves, so the spring of its entry costs nothing on a slow phone */
    if (classic) NoshiClassicFitPlate(card, 0);
    else card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:card.bounds cornerRadius:radius].CGPath;
    card.layer.shouldRasterize = YES;
    card.layer.rasterizationScale = [UIScreen mainScreen].scale;

    [window addSubview:dim];
    [window addSubview:card];
    NoshiCrashPromptShown = target;
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale());
    NoshiAnimateView(dim, CGAffineTransformIdentity, 0.5f, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
    return YES;
}

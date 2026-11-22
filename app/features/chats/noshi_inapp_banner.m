#import "noshi_inapp_banner.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#import "noshi_avatar_view.h"
#import "noshi_emoji_label.h"
#import "noshi_image_decoder.h"
#import "noshi_name_badge.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define SHOW_SECONDS 4.0
#define SLIDE_SECONDS 0.25
/* the banner of telegram for ios 4: a dark band over the status bar, 64 points under it, a round picture of 44 and two lines of white text */
#define BAND 64.0
#define AVATAR 44.0
#define HANDLE_WIDTH 38.0
#define HANDLE_HEIGHT 5.0

static NoshiInAppBanner *NoshiShownBanner;

@interface NoshiInAppBanner () {
    void (^_tap)(void);
    NoshiAvatarView *_avatar;
    UIImageView *_picture;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_body;
    UIView *_ground;
    UIView *_handle;
    CALayer *_press;
    CGFloat _contentTop;
    BOOL _leaving;
}
@end

@implementation NoshiInAppBanner

+ (void)showTitle:(NSString *)title body:(NSString *)body dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars tap:(void (^)(void))tap {
    [self showTitle:title body:body dialog:dialog avatars:avatars tap:tap picture:nil];
}

+ (void)showPowerTitle:(NSString *)title body:(NSString *)body {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = [[NSBundle mainBundle] pathForResource:@"power_meme" ofType:@"png"];
        UIImage *picture = [path ? NoshiDecodeImageAtURL([NSURL fileURLWithPath:path], 300) : nil retain];
        if (!picture) NSLog(@"noshigram: power notice image is missing or invalid");
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive)
                [self showTitle:title body:body dialog:nil avatars:nil tap:nil picture:picture];
            [picture release];
        });
        [pool drain];
    });
}

+ (void)showTitle:(NSString *)title body:(NSString *)body dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars tap:(void (^)(void))tap picture:(UIImage *)picture {
    UIView *window = NoshiOverlayHost();
    if (!window) return;
    [NoshiShownBanner leaveNow];
    NoshiInAppBanner *banner = [[[NoshiInAppBanner alloc] initWithFrame:CGRectZero] autorelease];
    banner->_tap = [tap copy];
    /* a person's name wears the marks of the app and the Premium star as it does in the chat list; the card has no media cache, so a status picture that is not
       on the device is left out instead of drawn as a box */
    NSArray *titleEntities = nil;
    banner->_title.dropsUndrawable = YES;
    banner->_title.text = NoshiNameWithBadge(title.length ? title : @"Telegram", dialog ? NoshiDialogBadgeDocument(dialog) : 0, &titleEntities);
    banner->_title.entities = titleEntities;
    banner->_body.text = body;
    if (dialog) {
        NoshiAvatarView *avatar = banner->_avatar;
        avatar.seed = dialog.avatarSeed;
        avatar.initials = dialog.initials;
        avatar.deleted = dialog.deleted;
        avatar.accent = dialog.saved || dialog.replies;
        avatar.symbol = dialog.replies ? NoshiSymbolReply : NoshiSymbolBookmark;
        avatar.showsSymbol = dialog.saved || dialog.replies;
        [avatar setPhoto:dialog.saved || dialog.replies ? nil : dialog.photo cache:avatars];
        avatar.hidden = NO;
    }
    if (picture) {
        banner->_picture = [[UIImageView alloc] initWithImage:picture];
        banner->_picture.contentMode = UIViewContentModeScaleAspectFit;
        [banner addSubview:banner->_picture];
    }
    UIEdgeInsets insets = NoshiSafeInsets(window);
    /* the band covers the status bar and starts its content under it */
    banner->_contentTop = MAX(insets.top, [UIApplication sharedApplication].statusBarHidden ? 0 : 20);
    CGFloat height = banner->_contentTop + (picture ? 132 : BAND);
    banner.frame = CGRectMake(0, 0, window.bounds.size.width, height);
    [window addSubview:banner];
    NoshiShownBanner = [banner retain];
    if (!NoshiReduceMotionEnabled()) {
        banner.transform = CGAffineTransformMakeTranslation(0, -height);
        [UIView animateWithDuration:SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ banner.transform = CGAffineTransformIdentity; } completion:nil];
    }
    [banner performSelector:@selector(leave) withObject:nil afterDelay:SHOW_SECONDS];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    /* the dark blur of ios 8 under the band, and a dark veil where there is no blur */
    Class blur = NSClassFromString(@"UIBlurEffect"), effectView = NSClassFromString(@"UIVisualEffectView");
    if (blur && effectView) {
        /* UIBlurEffectStyleDark is 2; the classes are looked up by name, as the sdk the slices link against may not declare them for ios 7 */
        id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(blur, NSSelectorFromString(@"effectWithStyle:"), 2);
        _ground = ((id (*)(id, SEL, id))objc_msgSend)([effectView alloc], NSSelectorFromString(@"initWithEffect:"), effect);
    } else {
        _ground = [[UIView alloc] init];
        _ground.backgroundColor = [UIColor colorWithWhite:0 alpha:0.86];
    }
    _ground.userInteractionEnabled = NO;
    [self addSubview:_ground];
    /* a touch lights the band a little */
    _press = [[CALayer layer] retain];
    _press.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _press.opacity = 0;
    [self.layer addSublayer:_press];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.hidden = YES;
    [self addSubview:_avatar];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = NoshiFontMedium(14);
    _title.textColor = [UIColor whiteColor];
    [self addSubview:_title];
    /* the body names who wrote, and a UILabel shows a box for every letter of a styled name that the system font lacks */
    _body = [[NoshiEmojiLabel alloc] init];
    _body.font = NoshiFontRegular(14);
    _body.textColor = [UIColor whiteColor];
    _body.numberOfLines = 2;
    /* the body starts with the sender of a group message, so a styled nick that no font draws is left out of it as it is out of the title, not drawn as a box */
    _body.dropsUndrawable = YES;
    [self addSubview:_body];
    /* the handle says the band can be pulled away */
    _handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, HANDLE_WIDTH, HANDLE_HEIGHT)];
    _handle.backgroundColor = [UIColor colorWithWhite:1 alpha:0.5];
    _handle.layer.cornerRadius = HANDLE_HEIGHT / 2;
    _handle.userInteractionEnabled = NO;
    [self addSubview:_handle];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)] autorelease]];
    /* the band follows the finger to the left, to the right or up, and goes when it is let go far enough or flicked; a tap still opens the chat */
    [self addGestureRecognizer:[[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)] autorelease]];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_tap release];
    [_avatar release];
    [_picture release];
    [_title release];
    [_body release];
    [_ground release];
    [_handle release];
    [_press release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat band = size.height - _contentTop;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _press.frame = self.bounds;
    [CATransaction commit];
    _ground.frame = self.bounds;
    /* the text starts after the picture, and at the edge when the band has none */
    CGFloat left = _picture ? 122 : (_avatar.hidden ? 14 : 10 + AVATAR + 10);
    CGFloat width = MAX(0, size.width - left - 14);
    if (_picture) _picture.frame = CGRectMake(8, _contentTop + 6, 104, band - 12);
    _avatar.frame = CGRectMake(10, _contentTop + 6, AVATAR, AVATAR);
    CGFloat textTop = _contentTop + (_picture ? floor((band - 60) / 2) : 7);
    _title.frame = CGRectMake(left, textTop, width, 18);
    _body.frame = CGRectMake(left, textTop + 18, width, _picture ? 40 : 34);
    _handle.frame = CGRectMake(floor((size.width - HANDLE_WIDTH) / 2), size.height - HANDLE_HEIGHT - 4, HANDLE_WIDTH, HANDLE_HEIGHT);
}

- (void)lightPress:(BOOL)on {
    _press.opacity = on ? 1 : 0;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:YES];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:NO];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self lightPress:NO];
    [super touchesCancelled:touches withEvent:event];
}

- (void)removeNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self removeFromSuperview];
    if (NoshiShownBanner == self) {
        NoshiShownBanner = nil;
        [self autorelease];
    }
}

/* a banner that is replaced does not animate out, the new one is already coming in */
- (void)leaveNow {
    _leaving = YES;
    [self removeNow];
}

- (void)leave {
    if (_leaving) return;
    _leaving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : SLIDE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ self.transform = CGAffineTransformMakeTranslation(0, -(self.frame.origin.y + self.bounds.size.height + 20)); }
                     completion:^(BOOL finished) {
        (void)finished;
        [self removeNow];
    }];
}

/* how far a drag must go, as a part of the card width, or how fast a flick must be (points per second), to send the card away */
#define DISMISS_FRACTION 0.35
#define DISMISS_SPEED 500.0
#define DISMISS_UP_DISTANCE 24.0
/* the card stays this long after a drag that did not send it away */
#define RETURN_SECONDS 3.0

- (void)dragged:(UIPanGestureRecognizer *)pan {
    if (_leaving) return;
    UIView *host = self.superview;
    if (!host) return;
    CGPoint move = [pan translationInView:host];
    /* downward there is nowhere to go: the card rests against its place */
    CGFloat y = MIN(0, move.y);
    CGFloat width = MAX(1, self.bounds.size.width);
    switch (pan.state) {
    case UIGestureRecognizerStateBegan:
        /* the timer must not take the card from under the finger */
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(leave) object:nil];
        break;
    case UIGestureRecognizerStateChanged:
        self.transform = CGAffineTransformMakeTranslation(move.x, y);
        self.alpha = (CGFloat)MAX(0.3, 1.0 - fabs(move.x) / (width * 1.5));
        break;
    case UIGestureRecognizerStateEnded: {
        CGPoint speed = [pan velocityInView:host];
        BOOL sideways = fabs(move.x) > width * DISMISS_FRACTION || fabs(speed.x) > DISMISS_SPEED;
        BOOL up = -y > DISMISS_UP_DISTANCE || speed.y < -DISMISS_SPEED;
        if (sideways && fabs(move.x) >= fabs(y)) {
            [self flyAwayToward:(move.x != 0 ? move.x : speed.x) < 0 ? -1 : 1];
        } else if (up) {
            [self leave];
        } else {
            [self settle];
        }
        break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        [self settle];
        break;
    default:
        break;
    }
}

/* the card leaves across the screen edge on the side it was thrown to */
- (void)flyAwayToward:(int)direction {
    if (_leaving) return;
    _leaving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    CGFloat distance = direction * (self.superview.bounds.size.width + self.bounds.size.width);
    CGFloat lift = self.transform.ty;
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.transform = CGAffineTransformMakeTranslation(distance, lift);
        self.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeNow];
    }];
}

/* a drag that stopped short puts the card back and gives it a few more seconds */
- (void)settle {
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    } completion:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(leave) object:nil];
    [self performSelector:@selector(leave) withObject:nil afterDelay:RETURN_SECONDS];
}

- (void)tapped {
    if (_leaving) return;
    void (^tap)(void) = [[_tap retain] autorelease];
    [self leave];
    if (tap) tap();
}

@end

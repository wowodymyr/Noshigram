#import "noshi_invite_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_avatar_view.h"
#import "noshi_dismiss_pan.h"
#import "noshi_media_cache.h"
#import "noshi_person.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiInviteSheet () {
    UIView *_shade;
    UIView *_card;
    UIScrollView *_content;
    NoshiAvatarView *_avatar;
    UILabel *_title;
    UILabel *_subtitle;
    UILabel *_about;
    UILabel *_request;
    UIButton *_join;
    UIButton *_close;
    void (^_joinHandler)(void);
    NoshiWeakReference *_weak;
    BOOL _closing;
}
@end

@implementation NoshiInviteSheet

static UILabel *InviteLabel(UIFont *font, UIColor *color) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = NoshiTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

+ (void)showInView:(UIView *)host title:(NSString *)title subtitle:(NSString *)subtitle about:(NSString *)about
             photo:(NoshiRemoteFile *)photo media:(NoshiMediaCache *)media requestNeeded:(BOOL)requestNeeded joinTitle:(NSString *)joinTitle join:(void (^)(void))join {
    if (!host) { NSLog(@"noshigram: no host for invite sheet"); return; }
    NoshiInviteSheet *sheet = [[[NoshiInviteSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_joinHandler = [join copy];
    sheet->_weak = [[NoshiWeakReference referenceTo:sheet] retain];
    sheet->_shade = [[UIView alloc] initWithFrame:sheet.bounds];
    sheet->_shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_shade.backgroundColor = [UIColor blackColor];
    sheet->_shade.alpha = 0;
    [sheet->_shade addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:sheet action:@selector(cancel)] autorelease]];
    [sheet addSubview:sheet->_shade];
    sheet->_card = [[UIView alloc] init];
    sheet->_card.backgroundColor = NoshiColorCard();
    sheet->_card.layer.cornerRadius = 22;
    sheet->_card.clipsToBounds = YES;
    [sheet addSubview:sheet->_card];
    NoshiAddDismissPan(sheet->_card, sheet, @selector(cancel));
    sheet->_content = [[UIScrollView alloc] init];
    sheet->_content.showsVerticalScrollIndicator = NO;
    [sheet->_card addSubview:sheet->_content];
    sheet->_avatar = [[NoshiAvatarView alloc] init];
    sheet->_avatar.initials = NoshiInitialsOfName(title);
    sheet->_avatar.seed = (NSUInteger)[title hash];
    [sheet->_content addSubview:sheet->_avatar];
    sheet->_title = [InviteLabel(NoshiFontBold(20), NoshiColorTitle()) retain];
    sheet->_title.text = title;
    [sheet->_content addSubview:sheet->_title];
    sheet->_subtitle = [InviteLabel(NoshiFontRegular(13), NoshiColorSecondary()) retain];
    sheet->_subtitle.text = subtitle;
    [sheet->_content addSubview:sheet->_subtitle];
    sheet->_about = [InviteLabel(NoshiFontRegular(15), NoshiColorTitle()) retain];
    sheet->_about.text = about;
    [sheet->_content addSubview:sheet->_about];
    sheet->_request = [InviteLabel(NoshiFontRegular(13), NoshiColorSecondary()) retain];
    sheet->_request.text = requestNeeded ? NSLocalizedString(@"invite.request", nil) : nil;
    [sheet->_content addSubview:sheet->_request];
    sheet->_join = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    sheet->_join.backgroundColor = NoshiColorAccent();
    sheet->_join.layer.cornerRadius = 23;
    sheet->_join.titleLabel.font = NoshiFontSemibold(16);
    [sheet->_join setTitle:joinTitle.length ? joinTitle : NSLocalizedString(requestNeeded ? @"invite.send" : @"invite.join", nil) forState:UIControlStateNormal];
    [sheet->_join setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [sheet->_join addTarget:sheet action:@selector(joinTapped) forControlEvents:UIControlEventTouchUpInside];
    [sheet->_card addSubview:sheet->_join];
    sheet->_close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    sheet->_close.titleLabel.font = NoshiFontRegular(27);
    [sheet->_close setTitle:@"×" forState:UIControlStateNormal];
    sheet->_close.accessibilityLabel = NSLocalizedString(@"picker.cancel", nil);
    [sheet->_close setTitleColor:NoshiColorSecondary() forState:UIControlStateNormal];
    [sheet->_close addTarget:sheet action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [sheet->_card addSubview:sheet->_close];
    [host addSubview:sheet];
    [sheet setNeedsLayout];
    [sheet layoutIfNeeded];
    if (photo && media) {
        NoshiWeakReference *weak = sheet->_weak;
        [media loadImageForFile:photo maxSide:180 * NoshiScreenScale() completion:^(UIImage *image) {
            NoshiInviteSheet *owner = weak.target;
            if (owner && image) [owner->_avatar showImage:image];
        }];
    }
    sheet->_card.transform = CGAffineTransformMakeTranslation(0, sheet.bounds.size.height - (sheet->_card.center.y - sheet->_card.bounds.size.height / 2));
    NoshiAnimateView(sheet->_shade, CGAffineTransformIdentity, 0.45, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(sheet->_card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_shade release]; [_card release]; [_content release]; [_avatar release];
    [_title release]; [_subtitle release]; [_about release]; [_request release];
    [_join release]; [_close release]; [_joinHandler release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(1, MIN(420, self.bounds.size.width - 20));
    CGFloat inner = MAX(1, width - 48);
    CGFloat y = 24;
    _avatar.frame = CGRectMake(floor((width - 90) / 2), y, 90, 90);
    y += 102;
    UILabel *labels[] = {_title, _subtitle, _about, _request};
    for (NSUInteger i = 0; i < 4; ++i) {
        UILabel *label = labels[i];
        if (!label.text.length) { label.frame = CGRectZero; continue; }
        CGFloat height = ceil([label sizeThatFits:CGSizeMake(inner, 2000)].height);
        label.frame = CGRectMake(24, y, inner, height);
        y += height + (i == 0 ? 4 : 12);
    }
    CGFloat safeBottom = NoshiSafeInsets(self).bottom;
    CGFloat maxHeight = MAX(100, self.bounds.size.height - NoshiStatusBarHeight() - 12 - safeBottom);
    CGFloat height = MIN(y + 70, maxHeight);
    /* the card is moved by its transform while the sheet comes and goes, and a frame set under a transform resizes it */
    NoshiPlaceView(_card, CGRectMake(floor((self.bounds.size.width - width) / 2), self.bounds.size.height - safeBottom - height, width, height));
    _content.frame = CGRectMake(0, 0, width, MAX(0, height - 70));
    _content.contentSize = CGSizeMake(width, y);
    _content.scrollEnabled = y > _content.bounds.size.height;
    _join.frame = CGRectMake(20, height - 58, MAX(1, width - 40), 46);
    _close.frame = CGRectMake(width - 48, 4, 44, 44);
}

- (void)leaveJoining:(BOOL)joining {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^handler)(void) = joining ? [_joinHandler copy] : nil;
    [self retain];
    /* the card leaves on the curve it arrives on: EXIT starts slowly and the card hung for a moment before it dropped */
    NoshiAnimateView(_shade, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_card, CGAffineTransformMakeTranslation(0, self.bounds.size.height - (_card.center.y - _card.bounds.size.height / 2)), 1, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (handler) handler();
        [handler release];
        [self release];
    });
}
- (void)cancel { [self leaveJoining:NO]; }
- (void)joinTapped { [self leaveJoining:YES]; }
@end

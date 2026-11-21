#import "noshi_send_as_menu.h"

#import <QuartzCore/QuartzCore.h>
#import "noshi_animation.h"
#import "noshi_avatar_view.h"
#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_session_sendas.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

@interface NoshiSendAsMenu () {
    NSArray *_options;
    NSUInteger _selected;
    NoshiAvatarCache *_avatars;
    void (^_handler)(NSUInteger);
    UIView *_card;
    BOOL _closing;
}
@end

@implementation NoshiSendAsMenu
- (id)initWithOptions:(NSArray *)options selected:(NSUInteger)selected avatars:(NoshiAvatarCache *)avatars handler:(void (^)(NSUInteger))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _options = [options copy]; _selected = selected; _avatars = [avatars retain]; _handler = [handler copy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIControl *outside = [[[UIControl alloc] init] autorelease];
    outside.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [outside addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:outside];
    return self;
}
- (void)dealloc {
    [_options release]; [_avatars release]; [_handler release]; [_card release];
    [super dealloc];
}
- (void)showInView:(UIView *)host anchor:(CGRect)anchor {
    self.frame = host.bounds;
    [[self.subviews objectAtIndex:0] setFrame:self.bounds];
    UIEdgeInsets insets = NoshiSafeInsets(host);
    CGFloat width = MIN(260, MAX(1, host.bounds.size.width - insets.left - insets.right - 20));
    CGFloat bottom = MAX(insets.top + 60, CGRectGetMinY(anchor) - 8);
    CGFloat height = MIN(450, MIN(48 + _options.count * 54, bottom - insets.top - 10));
    _card = [[UIView alloc] initWithFrame:CGRectMake(MAX(insets.left + 10, MIN(CGRectGetMinX(anchor), host.bounds.size.width - insets.right - width - 10)), bottom - height, width, height)];
    _card.backgroundColor = NoshiColorCard(); _card.layer.cornerRadius = 14;
    _card.layer.shadowColor = [UIColor blackColor].CGColor; _card.layer.shadowOpacity = NoshiThemeIsDark() ? 0.5 : 0.22;
    _card.layer.shadowRadius = 12; _card.layer.shadowOffset = CGSizeMake(0, 4);
    UILabel *header = [[[UILabel alloc] initWithFrame:CGRectMake(16, 0, width - 32, 48)] autorelease];
    header.backgroundColor = [UIColor clearColor]; header.font = NoshiFontSemibold(16); header.textColor = NoshiColorAccent();
    header.text = NSLocalizedString(@"chat.sendas", nil); [_card addSubview:header];
    UIScrollView *scroll = [[[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, width, height - 48)] autorelease];
    scroll.contentSize = CGSizeMake(width, _options.count * 54); scroll.showsVerticalScrollIndicator = NO;
    scroll.clipsToBounds = YES; [_card addSubview:scroll];
    for (NSUInteger i = 0; i < _options.count; ++i) {
        NoshiSendAsOption *option = [_options objectAtIndex:i]; NoshiDialog *identity = option.identity;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom]; row.frame = CGRectMake(0, i * 54, width, 54); row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        NoshiAvatarView *avatar = [[[NoshiAvatarView alloc] initWithFrame:CGRectMake(12, 7, 40, 40)] autorelease];
        avatar.circular = YES; avatar.initials = identity.initials; avatar.seed = (NSUInteger)(identity.peerId % 1000003);
        [avatar setPhoto:identity.photo cache:_avatars]; [row addSubview:avatar];
        NoshiEmojiLabel *title = [[[NoshiEmojiLabel alloc] initWithFrame:CGRectMake(62, 0, MAX(1, width - 100), 54)] autorelease];
        title.font = NoshiFontMedium(16); title.textColor = NoshiColorTitle(); title.text = identity.title; [row addSubview:title];
        if (i == _selected || option.premiumRequired) {
            NoshiSymbol symbol = i == _selected ? NoshiSymbolCheck : NoshiSymbolLock;
            UIImageView *icon = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(symbol, 17, i == _selected ? NoshiColorAccent() : NoshiColorSecondary())] autorelease];
            icon.frame = CGRectMake(width - 30, 18, 18, 18); [row addSubview:icon];
        }
        row.accessibilityLabel = identity.title;
        row.accessibilityTraits = UIAccessibilityTraitButton | (i == _selected ? UIAccessibilityTraitSelected : 0);
        [scroll addSubview:row];
    }
    [self addSubview:_card]; [host addSubview:self];
    _card.transform = CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()); _card.alpha = 0;
    NoshiAnimateView(_card, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}
- (void)leave:(NSInteger)index {
    if (_closing) return;
    _closing = YES; self.userInteractionEnabled = NO;
    [self retain];
    NoshiAnimateView(_card, CGAffineTransformMakeScale(NoshiPopupScale(), NoshiPopupScale()), 0, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (index >= 0 && _handler) _handler((NSUInteger)index);
        [self release];
    });
}
- (void)dismiss { [self leave:-1]; }
- (void)picked:(UIButton *)button { [self leave:button.tag]; }
@end

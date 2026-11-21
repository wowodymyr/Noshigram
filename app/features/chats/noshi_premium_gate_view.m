#import "noshi_premium_gate_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_emoji_label.h"
#import "noshi_link_router.h"
#import "noshi_message.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define CARD_RADIUS 22.0
#define CARD_PAD 22.0
#define DISC 100.0
#define BUBBLE 54.0
#define BUTTON_HEIGHT 40.0

void NoshiOpenPremiumPage(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenLinkNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:@"https://t.me/PremiumBot" forKey:@"url"]];
}

@interface NoshiPremiumGateView () {
    CAGradientLayer *_fill;
    UIView *_disc;
    UIImageView *_bubble;
    UIImageView *_lock;
    NoshiEmojiLabel *_text;
    UIButton *_button;
}
@end

@implementation NoshiPremiumGateView

- (id)initWithName:(NSString *)name {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.layer.cornerRadius = CARD_RADIUS;
    self.layer.masksToBounds = YES;
    _fill = [[CAGradientLayer layer] retain];
    _fill.colors = [NSArray arrayWithObjects:(id)[UIColor colorWithRed:0.20 green:0.20 blue:0.28 alpha:0.96].CGColor,
                                             (id)[UIColor colorWithRed:0.12 green:0.12 blue:0.19 alpha:0.96].CGColor, nil];
    [self.layer addSublayer:_fill];
    _disc = [[UIView alloc] init];
    _disc.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
    _disc.layer.cornerRadius = DISC / 2;
    [self addSubview:_disc];
    _bubble = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolChats, BUBBLE, [UIColor whiteColor])];
    _bubble.contentMode = UIViewContentModeCenter;
    [_disc addSubview:_bubble];
    _lock = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolLock, 22, [UIColor colorWithRed:0.14 green:0.14 blue:0.22 alpha:1])];
    _lock.contentMode = UIViewContentModeCenter;
    [_disc addSubview:_lock];
    _text = [[NoshiEmojiLabel alloc] init];
    _text.font = NoshiFontRegular(17);
    _text.textColor = [UIColor whiteColor];
    _text.textAlignment = NoshiTextAlignmentCenter;
    _text.numberOfLines = 0;
    NSString *line = [NSString stringWithFormat:NSLocalizedString(@"chat.premium.text", nil), name];
    _text.text = line;
    /* the name and the word Premium are bold, as in the Telegram card */
    NSMutableArray *bold = [NSMutableArray array];
    NSRange nameRange = [line rangeOfString:name];
    if (nameRange.location != NSNotFound) [bold addObject:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleBold range:nameRange url:nil] autorelease]];
    NSRange premiumRange = [line rangeOfString:@"Premium" options:NSBackwardsSearch];
    if (premiumRange.location != NSNotFound) [bold addObject:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleBold range:premiumRange url:nil] autorelease]];
    _text.entities = bold;
    [self addSubview:_text];
    _button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    _button.layer.cornerRadius = BUTTON_HEIGHT / 2;
    _button.titleLabel.font = NoshiFontSemibold(17);
    [_button setTitle:NSLocalizedString(@"chat.premium.button", nil) forState:UIControlStateNormal];
    [_button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(openPremium) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_button];
    return self;
}

- (void)dealloc {
    [_fill release];
    [_disc release];
    [_bubble release];
    [_lock release];
    [_text release];
    [_button release];
    [super dealloc];
}

- (void)openPremium {
    NoshiOpenPremiumPage();
}

- (CGSize)cardSizeForWidth:(CGFloat)width {
    CGFloat inner = MIN(width - 64, 320) - 2 * CARD_PAD;
    CGSize text = [_text sizeThatFits:CGSizeMake(inner, 400)];
    return CGSizeMake(inner + 2 * CARD_PAD, CARD_PAD + DISC + 16 + ceil(text.height) + 18 + BUTTON_HEIGHT + CARD_PAD);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat inner = width - 2 * CARD_PAD;
    _fill.frame = self.bounds;
    _disc.frame = CGRectMake((width - DISC) / 2, CARD_PAD, DISC, DISC);
    _bubble.frame = CGRectMake((DISC - BUBBLE - 8) / 2, (DISC - BUBBLE - 8) / 2, BUBBLE + 8, BUBBLE + 8);
    /* the lock sits in the body of the bubble, above the tail */
    _lock.frame = CGRectMake((DISC - 28) / 2, (DISC - 28) / 2 - 3, 28, 28);
    CGSize text = [_text sizeThatFits:CGSizeMake(inner, 400)];
    _text.frame = CGRectMake(CARD_PAD, CGRectGetMaxY(_disc.frame) + 16, inner, ceil(text.height));
    CGFloat buttonWidth = MIN(inner, 240);
    _button.frame = CGRectMake((width - buttonWidth) / 2, CGRectGetMaxY(_text.frame) + 18, buttonWidth, BUTTON_HEIGHT);
}

@end

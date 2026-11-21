#import "noshi_compose_context.h"

#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_emoji_label.h"

#define HEIGHT 44.0
#define SIDE 12.0
#define ICON 22.0
#define CLOSE_WIDTH 44.0

@interface NoshiComposeContext () {
    UIImageView *_icon;
    UIView *_stripe;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_text;
    UIButton *_close;
    UIView *_line;
    void (^_closeHandler)(void);
}
@end

@implementation NoshiComposeContext

@synthesize closeHandler = _closeHandler;

+ (CGFloat)height {
    return HEIGHT;
}

static NoshiEmojiLabel *NoshiContextLabel(UIColor *color, UIFont *font) {
    NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = NoshiColorBar();
    _icon = [[UIImageView alloc] init];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _stripe = [[UIView alloc] init];
    _stripe.backgroundColor = NoshiColorAccent();
    [self addSubview:_stripe];
    _title = [NoshiContextLabel(NoshiColorAccent(), NoshiFontSemibold(13)) retain];
    _title.dropsUndrawable = YES;
    [self addSubview:_title];
    _text = [NoshiContextLabel(NoshiColorSecondary(), NoshiFontRegular(14)) retain];
    [self addSubview:_text];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:NoshiSymbolImage(NoshiSymbolClose, 18, NoshiColorSecondary()) forState:UIControlStateNormal];
    [_close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_close];
    _line = [[UIView alloc] init];
    _line.backgroundColor = NoshiColorHairline();
    [self addSubview:_line];
    return self;
}

- (void)dealloc {
    [_icon release];
    [_stripe release];
    [_title release];
    [_text release];
    [_close release];
    [_line release];
    [_closeHandler release];
    [super dealloc];
}

- (void)showSymbol:(NoshiSymbol)symbol title:(NSString *)title text:(NSString *)text {
    _icon.image = NoshiSymbolImage(symbol, ICON, NoshiColorAccent());
    _title.text = title;
    _text.text = text;
    _close.accessibilityLabel = NSLocalizedString(@"chat.msg.cancel", nil);
    [self setNeedsLayout];
}

- (void)closeTapped {
    if (_closeHandler) _closeHandler();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat hairline = 1.0 / NoshiScreenScale();
    _line.frame = CGRectMake(0, 0, size.width, hairline);
    _icon.frame = CGRectMake(SIDE, (size.height - ICON) / 2, ICON, ICON);
    CGFloat stripeX = SIDE + ICON + 8;
    _stripe.frame = CGRectMake(stripeX, 6, 2, size.height - 12);
    CGFloat textX = stripeX + 8;
    CGFloat width = MAX(0, size.width - textX - CLOSE_WIDTH);
    _title.frame = CGRectMake(textX, 5, width, 17);
    _text.frame = CGRectMake(textX, 23, width, 17);
    _close.frame = CGRectMake(size.width - CLOSE_WIDTH, 0, CLOSE_WIDTH, size.height);
}

@end

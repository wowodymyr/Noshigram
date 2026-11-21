#import "noshi_profile_action.h"
#import "noshi_animation.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#import "noshi_classic_chrome.h"
#import "noshi_theme.h"

@implementation NoshiUserAction

- (id)initWithSymbol:(NoshiSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    NoshiAttachBounce(self, 0.06);
    /* the classic card is a glossy metal key: the slate plate of the app's buttons under a white symbol and word */
    _plate = [[UIImageView alloc] initWithImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, NO)];
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _symbol = symbol;
    _icon = [[UIImageView alloc] initWithImage:NoshiSymbolImage(symbol, 24, [UIColor whiteColor])];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = NoshiTextAlignmentCenter;
    _caption.font = [UIFont boldSystemFontOfSize:12];
    _caption.textColor = [UIColor whiteColor];
    _caption.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    _caption.shadowOffset = CGSizeMake(0, -1);
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.text = title;
    [self addSubview:_caption];
    self.accessibilityLabel = title;
    return self;
}

- (NoshiSymbol)symbol { return _symbol; }
- (NSString *)captionText { return _caption.text; }

- (void)setSymbol:(NoshiSymbol)symbol title:(NSString *)title {
    _symbol = symbol;
    _icon.image = NoshiSymbolImage(symbol, 24, _plate ? [UIColor whiteColor] : (_ink ? _ink : NoshiColorAccent()));
    _caption.text = title;
    self.accessibilityLabel = title;
}

- (UIImage *)plateImagePressed:(BOOL)pressed {
    return _ground ? NoshiClassicGroundKeyImage(_ground, pressed) : NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, pressed);
}

- (void)setGround:(UIColor *)ground {
    if (!_plate || ground == _ground) return;
    [_ground release];
    _ground = [ground retain];
    _plate.image = [self plateImagePressed:NO];
}

- (void)setInk:(UIColor *)ink {
    /* the metal key keeps its own colors on any ground */
    if (_plate || ink == _ink) return;
    [_ink release];
    _ink = [ink retain];
    [self applyPlate];
    _icon.image = NoshiSymbolImage(_symbol, 24, ink ? ink : NoshiColorAccent());
    _caption.textColor = ink ? ink : NoshiColorTitle();
}

/* the plate under the symbol: the card color, a dark veil on a colored ground, and almost clear over a blur */
- (void)applyPlate {
    if (_plate) return;
    if (_blurred) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:_blur ? 0.06f : 0.42f];
        return;
    }
    self.backgroundColor = _ink ? [UIColor colorWithWhite:0 alpha:0.18f] : NoshiColorCard();
}

- (void)setBlurred:(BOOL)blurred {
    if (_plate) {
        /* over the wide photo the metal key lets it show: the plate and its symbol fade as the avatar grows, and come back as it closes; the caller runs this inside its animation */
        _blurred = blurred;
        _plate.alpha = blurred ? 0.3 : 1;
        _icon.alpha = _caption.alpha = blurred ? 0.7 : 1;
        return;
    }
    if (blurred == _blurred) return;
    _blurred = blurred;
    if (blurred && !_blur) {
        Class effectClass = NSClassFromString(@"UIBlurEffect");
        Class viewClass = NSClassFromString(@"UIVisualEffectView");
        /* UIBlurEffectStyleDark */
        id effect = effectClass ? ((id (*)(Class, SEL, NSInteger))objc_msgSend)(effectClass, NSSelectorFromString(@"effectWithStyle:"), 2) : nil;
        if (effect && viewClass) {
            UIView *view = [[viewClass alloc] performSelector:NSSelectorFromString(@"initWithEffect:") withObject:effect];
            view.frame = self.bounds;
            view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            view.userInteractionEnabled = NO;
            view.clipsToBounds = YES;
            view.layer.cornerRadius = self.layer.cornerRadius;
            view.alpha = 0;
            [self insertSubview:view atIndex:0];
            _blur = view;
        }
    }
    [self applyPlate];
    _blur.alpha = blurred ? 1 : 0;
}

- (void)dealloc {
    [_blur release];
    [_plate release];
    [_ground release];
    [_ink release];
    [_icon release];
    [_caption release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _plate.frame = self.bounds;
    _icon.frame = CGRectMake(0, 8, size.width, 28);
    _caption.frame = CGRectMake(6, 38, size.width - 12, 18);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.45;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (_plate) {
        _plate.image = [self plateImagePressed:highlighted];
        return;
    }
    if (self.enabled) self.alpha = highlighted ? 0.6 : 1;
}

@end

CGFloat NoshiLayoutActions(NSArray *actions, CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat gap) {
    NSUInteger count = actions.count;
    if (!count) return 0;
    NSUInteger rows = (count + 3) / 4;
    NSUInteger perRow = (count + rows - 1) / rows;
    for (NSUInteger i = 0; i < count; ++i) {
        NSUInteger row = i / perRow;
        NSUInteger inRow = MIN(perRow, count - row * perRow);
        CGFloat each = (width - gap * (CGFloat)(inRow - 1)) / (CGFloat)inRow;
        ((UIView *)[actions objectAtIndex:i]).frame = CGRectMake(x + (CGFloat)(i - row * perRow) * (each + gap), y + (CGFloat)row * (height + gap), each, height);
    }
    return (CGFloat)rows * height + (CGFloat)(rows - 1) * gap;
}

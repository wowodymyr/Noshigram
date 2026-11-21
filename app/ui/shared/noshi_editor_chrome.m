#import "noshi_editor_chrome.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define PANEL_RADIUS 22

@interface NoshiEditorPanel () {
    UIView *_effect;
    UIView *_content;
    BOOL _floating;
}
@end

@implementation NoshiEditorPanel
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    /* the old system draws the bar flat and edge to edge: a toolbar is the background and the subviews stand on it */
    UIToolbar *bar = [[[UIToolbar alloc] init] autorelease];
    NoshiClassicStyleToolbar(bar);
    bar.userInteractionEnabled = NO;
    _effect = [bar retain];
    _content = self;
    [self addSubview:_effect];
    return self;
}
- (void)dealloc {
    [_effect release];
    [super dealloc];
}
- (UIView *)content { return _content; }
- (BOOL)floating { return _floating; }
- (void)layoutSubviews {
    [super layoutSubviews];
    _effect.frame = self.bounds;
    if (_floating) self.layer.cornerRadius = MIN(self.bounds.size.height / 2, NoshiIsPad() ? 26 : PANEL_RADIUS);
}
@end

/* the editors fill an ipad, so the marks and the captions grow with the screen */
#define TOOL_ICON (NoshiIsPad() ? 30 : 24)
#define PILL_ICON (NoshiIsPad() ? 22 : 18)
#define ROUND_ICON (NoshiIsPad() ? 26 : 22)

@interface NoshiEditorButton () {
    NoshiEditorButtonStyle _style;
    NoshiSymbol _symbol;
    BOOL _hasSymbol;
    BOOL _lit;
    UIView *_plate;
    UIImageView *_icon;
    UILabel *_caption;
}
@end

@implementation NoshiEditorButton
@synthesize lit = _lit;
- (id)initWithStyle:(NoshiEditorButtonStyle)style symbol:(NoshiSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _style = style;
    _symbol = symbol;
    _hasSymbol = YES;
    self.backgroundColor = [UIColor clearColor];
    _plate = [[UIView alloc] init];
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _icon = [[UIImageView alloc] init];
    _icon.userInteractionEnabled = NO;
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.userInteractionEnabled = NO;
    _caption.textAlignment = (NSTextAlignment)NoshiTextAlignmentCenter;
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.minimumFontSize = 8;
    _caption.font = style == NoshiEditorButtonTool ? NoshiFontMedium(NoshiIsPad() ? 12 : 10) : NoshiFontSemibold(NoshiIsPad() ? 17 : 15);
    [self addSubview:_caption];
    _caption.text = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;
    NoshiAttachBounce(self, style == NoshiEditorButtonTool ? 0.1 : 0.06);
    [self refreshAnimated:NO];
    return self;
}
- (id)initWithStyle:(NoshiEditorButtonStyle)style title:(NSString *)title {
    self = [self initWithStyle:style symbol:NoshiSymbolCheck title:title];
    if (self) {
        _hasSymbol = NO;
        [self refreshAnimated:NO];
    }
    return self;
}
- (void)dealloc {
    [_plate release];
    [_icon release];
    [_caption release];
    [super dealloc];
}
- (NSString *)title { return _caption.text; }
- (void)setTitle:(NSString *)title { [self setTitle:title animated:NO]; }
- (void)setTitle:(NSString *)title animated:(BOOL)animated {
    if (title == _caption.text || [title isEqualToString:_caption.text]) return;
    if (animated && self.window && !NoshiReduceMotionEnabled()) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.18;
        [_caption.layer addAnimation:fade forKey:@"noshigram.caption"];
    }
    _caption.text = title;
    self.accessibilityLabel = title;
    [self setNeedsLayout];
}
- (UIColor *)contentColor {
    if (_lit) return [UIColor colorWithRed:0.35 green:0.65 blue:1 alpha:1];
    return [UIColor colorWithWhite:1 alpha:0.94];
}
- (UIColor *)plateColor {
    return [UIColor clearColor];
}
- (void)refreshAnimated:(BOOL)animated {
    UIColor *color = [self contentColor];
    CGFloat side = _style == NoshiEditorButtonTool ? TOOL_ICON : (_style == NoshiEditorButtonRound ? ROUND_ICON : PILL_ICON);
    _icon.image = _hasSymbol ? NoshiSymbolImage(_symbol, side, color) : nil;
    _caption.textColor = color;
    UIColor *plate = [self plateColor];
    void (^apply)(void) = ^{ _plate.backgroundColor = plate; };
    if (animated && self.window && !NoshiReduceMotionEnabled()) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];
    else apply();
    [self setNeedsLayout];
}
- (void)setLit:(BOOL)lit { [self setLit:lit animated:NO]; }
- (void)setLit:(BOOL)lit animated:(BOOL)animated {
    if (_lit == lit) return;
    _lit = lit;
    self.accessibilityTraits = UIAccessibilityTraitButton | (lit ? UIAccessibilityTraitSelected : 0);
    [self refreshAnimated:animated];
    if (animated && lit) NoshiEditorPop(_icon);
}
- (void)setSymbol:(NoshiSymbol)symbol animated:(BOOL)animated {
    if (_hasSymbol && _symbol == symbol) return;
    UIImageView *old = nil;
    if (animated && self.window && !NoshiReduceMotionEnabled() && _icon.image) {
        old = [[UIImageView alloc] initWithImage:_icon.image];
        old.frame = _icon.frame;
        old.contentMode = UIViewContentModeCenter;
        [self insertSubview:old aboveSubview:_icon];
    }
    _symbol = symbol;
    _hasSymbol = YES;
    [self refreshAnimated:NO];
    if (old) {
        NoshiAnimateEnter(_icon, CGAffineTransformMakeScale(0.4, 0.4), 0, NOSHI_MOTION_WOBBLE);
        NoshiAnimateView(old, CGAffineTransformMakeScale(0.4, 0.4), 0, NOSHI_MOTION_DISMISS, ^(BOOL finished) { [old removeFromSuperview]; });
        [old release];
    }
}
- (void)playQuarterTurn {
    if (self.window) NoshiAnimateEnter(_icon, CGAffineTransformMakeRotation((CGFloat)(-M_PI_2)), 1, NOSHI_MOTION_WOBBLE);
}
- (void)playFlip {
    if (self.window) NoshiAnimateEnter(_icon, CGAffineTransformMakeScale(-1, 1), 1, NOSHI_MOTION_WOBBLE);
}
/* the parts dim, not the button, so a card that fades its buttons in and out and a button that is disabled do not fight over one alpha */
- (void)refreshDim {
    CGFloat alpha = (self.enabled ? 1 : 0.38) * (self.highlighted ? 0.7 : 1);
    _icon.alpha = _caption.alpha = _plate.alpha = alpha;
}
- (void)setEnabled:(BOOL)enabled {
    BOOL changed = enabled != self.enabled;
    [super setEnabled:enabled];
    if (!changed) return;
    if (self.window && !NoshiReduceMotionEnabled()) [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ [self refreshDim]; } completion:nil];
    else [self refreshDim];
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self refreshDim];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    BOOL hasTitle = _caption.text.length > 0;
    _icon.transform = CGAffineTransformIdentity;
    if (_style == NoshiEditorButtonTool) {
        _plate.frame = CGRectInset(bounds, 3, 3);
        _plate.layer.cornerRadius = 14;
        CGFloat caption = NoshiIsPad() ? 16 : 13, stack = TOOL_ICON + (hasTitle ? caption + 1 : 0);
        CGFloat top = floor((h - stack) / 2);
        _icon.frame = CGRectMake(floor((w - TOOL_ICON) / 2), top, TOOL_ICON, TOOL_ICON);
        _caption.frame = CGRectMake(2, top + TOOL_ICON + 1, w - 4, caption);
        return;
    }
    _plate.frame = bounds;
    _plate.layer.cornerRadius = h / 2;
    if (_style == NoshiEditorButtonRound) {
        _icon.frame = CGRectMake(floor((w - ROUND_ICON) / 2), floor((h - ROUND_ICON) / 2), ROUND_ICON, ROUND_ICON);
        _caption.frame = CGRectZero;
        return;
    }
    CGFloat textWidth = hasTitle ? MIN(w - 16, ceil([_caption.text sizeWithFont:_caption.font].width)) : 0;
    CGFloat iconWidth = _hasSymbol ? PILL_ICON : 0, gap = _hasSymbol && hasTitle ? 6 : 0;
    CGFloat x = floor((w - iconWidth - gap - textWidth) / 2);
    _icon.frame = CGRectMake(x, floor((h - PILL_ICON) / 2), iconWidth, PILL_ICON);
    _caption.frame = CGRectMake(x + iconWidth + gap, 0, textWidth, h);
}
@end

CGFloat NoshiEditorScale(void) { return NoshiIsPad() ? 1.25 : 1; }

void NoshiEditorPresent(UIView *view, BOOL shown, CGFloat distance) {
    view.userInteractionEnabled = shown;
    view.accessibilityElementsHidden = !shown;
    CGAffineTransform away = CGAffineTransformConcat(CGAffineTransformMakeScale(0.97, 0.97), CGAffineTransformMakeTranslation(0, distance));
    NoshiAnimateView(view, shown ? CGAffineTransformIdentity : away, shown ? 1 : 0, shown ? NOSHI_MOTION_WOBBLE : NOSHI_MOTION_DISMISS, nil);
}

void NoshiEditorRise(NSArray *views, CGFloat distance, NSTimeInterval step) {
    NSTimeInterval delay = 0;
    for (UIView *view in views) {
        CGAffineTransform from = CGAffineTransformMakeTranslation(0, distance);
        view.transform = from;
        view.alpha = 0;
        NoshiAnimateViewAfter(view, CGAffineTransformIdentity, 1, NOSHI_MOTION_WOBBLE, delay, nil);
        delay += step;
    }
}

void NoshiEditorPop(UIView *view) {
    NoshiAnimateEnter(view, CGAffineTransformMakeScale(0.82, 0.82), 1, NOSHI_MOTION_WOBBLE);
}

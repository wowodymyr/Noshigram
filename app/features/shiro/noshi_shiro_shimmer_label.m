#import "noshi_shiro_shimmer_label.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_platform.h"
#import "noshi_shiro_style.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

static NSString *const NoshiShimmerSlideKey = @"shiro.shimmer.slide";
static const CFTimeInterval NoshiShimmerLapSeconds = 5;

@interface NoshiShiroShimmerLabel () {
    CAGradientLayer *_paint;
    CALayer *_cut;
    NSString *_text;
    UIFont *_font;
    CGSize _cutSize;
    BOOL _observing;
}
@end

@implementation NoshiShiroShimmerLabel

@synthesize text = _text;
@synthesize font = _font;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    /* UIAccessibilityTraitHeader is 1 << 16; the constant is not exported by the ios 5 runtime, and a reference to its symbol keeps the app from starting there */
    self.accessibilityTraits = (UIAccessibilityTraits)(1 << 16);
    _paint = [[CAGradientLayer alloc] init];
    _paint.startPoint = CGPointMake(0, 0.5);
    _paint.endPoint = CGPointMake(1, 0.5);
    _paint.actions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNull null], @"bounds", [NSNull null], @"position", [NSNull null], @"colors", nil];
    [self.layer addSublayer:_paint];
    _cut = [[CALayer alloc] init];
    self.layer.mask = _cut;
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_paint release];
    [_cut release];
    [_text release];
    [_font release];
    [super dealloc];
}

- (void)setText:(NSString *)text {
    if (text == _text || [text isEqualToString:_text]) return;
    [_text release];
    _text = [text copy];
    self.accessibilityLabel = _text;
    _cutSize = CGSizeZero;
    [self setNeedsLayout];
}

- (void)setFont:(UIFont *)font {
    if (font == _font) return;
    [_font release];
    _font = [font retain];
    _cutSize = CGSizeZero;
    [self setNeedsLayout];
}

/* the colors run through one lap and start again with the first, over a layer of two laps, so the visible half can slide by one lap without a seam */
- (void)applyTheme {
    NSArray *lap = NoshiShiroShimmerColors();
    NSMutableArray *colors = [NSMutableArray array];
    for (int round = 0; round < 2; ++round) {
        for (UIColor *color in lap) [colors addObject:(id)color.CGColor];
    }
    [colors addObject:(id)[[lap objectAtIndex:0] CGColor]];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _paint.colors = colors;
    [CATransaction commit];
}

/* the text as an alpha picture: the mask takes only the coverage of the glyphs */
- (void)cutText {
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _cutSize) || size.width < 1 || size.height < 1) return;
    _cutSize = size;
    UIImage *image = nil;
    if (_text.length && _font) {
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        [[UIColor blackColor] set];
        CGFloat line = NoshiStringSize(_text, _font).height;
        CGRect rect = CGRectMake(0, floor((size.height - line) / 2), size.width, line);
        NoshiDrawStringIn(_text, _font, rect, NoshiStringTailTruncate, NoshiTextAlignmentCenter);
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cut.frame = self.bounds;
    _cut.contents = (id)image.CGImage;
    _cut.contentsScale = image.scale > 0 ? image.scale : [UIScreen mainScreen].scale;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _paint.bounds = CGRectMake(0, 0, size.width * 2, size.height);
    _paint.position = CGPointMake(size.width, size.height / 2);
    [CATransaction commit];
    [self cutText];
    [self syncSlide];
}

/* backgrounding drops running animations, so they start again when the app is active; a system that asks for reduced motion gets the colors standing still */
- (void)syncSlide {
    CGFloat width = self.bounds.size.width;
    if (!self.window || NoshiReduceMotionEnabled() || width < 1) {
        [_paint removeAnimationForKey:NoshiShimmerSlideKey];
        return;
    }
    if ([_paint animationForKey:NoshiShimmerSlideKey]) return;
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position.x"];
    slide.fromValue = [NSNumber numberWithFloat:(float)width];
    slide.toValue = [NSNumber numberWithFloat:0];
    slide.duration = NoshiShimmerLapSeconds;
    slide.repeatCount = HUGE_VALF;
    slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_paint addAnimation:slide forKey:NoshiShimmerSlideKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_observing) [center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    _observing = NO;
    if (self.window) {
        [center addObserver:self selector:@selector(syncSlide) name:UIApplicationDidBecomeActiveNotification object:nil];
        _observing = YES;
    }
    [self syncSlide];
}

@end

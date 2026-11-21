#import "noshi_shiro_power_button.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>

#import "noshi_platform.h"
#import "noshi_shiro_style.h"
#import "noshi_theme.h"

/* every outline has this many points, because core animation only interpolates two paths that are built the same way */
#define OUTLINE_POINTS 144
#define FRONT_RADIUS 0.32
#define BLOOM_RADIUS 0.46

static NSString *const NoshiShiroSpinKey = @"shiro.spin";
static NSString *const NoshiShiroCycleKey = @"shiro.cycle";
static NSString *const NoshiShiroMorphKey = @"shiro.morph";
static NSString *const NoshiShiroSettleKey = @"shiro.settle";
static NSString *const NoshiShiroWiggleKey = @"shiro.wiggle";
static NSString *const NoshiShiroBounceKey = @"shiro.bounce";
static NSString *const NoshiShiroBloomKey = @"shiro.bloom";
static const CFTimeInterval NoshiShiroMorphTime = 0.55;

/* a lobed circle: lobes bumps of the given depth around the radius, the first one at the top */
static UIBezierPath *NoshiShiroOutline(CGPoint center, CGFloat radius, int lobes, CGFloat depth) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (int i = 0; i < OUTLINE_POINTS; ++i) {
        CGFloat angle = (CGFloat)(2 * M_PI * i / OUTLINE_POINTS);
        CGFloat r = radius * (1 + depth * cos(lobes * angle));
        CGPoint point = CGPointMake(center.x + r * sin(angle), center.y - r * cos(angle));
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [path closePath];
    return path;
}

/* the shapes the loading cycle passes through, then back to the first */
static const struct { int lobes; CGFloat depth; } NoshiShiroCycle[] = {{8, 0.08}, {5, 0.1}, {10, 0.06}, {6, 0.11}};
#define CYCLE_COUNT (sizeof(NoshiShiroCycle) / sizeof(NoshiShiroCycle[0]))

/* a quick rise past the target and a settle back, the spring of the Material expressive motion scheme */
static CAMediaTimingFunction *NoshiShiroSpring(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f];
}

@interface NoshiShiroPowerButton () {
    /* holds every layer of the shape, so the press scales it and the view itself keeps its size */
    CALayer *_body;
    CALayer *_bloom;
    CAShapeLayer *_back;
    CAShapeLayer *_front;
    CAShapeLayer *_glyph;
    NoshiShiroPowerState _powerState;
    CGSize _laidSize;
    BOOL _observing;
}
- (void)syncMotion;
- (void)syncMotionRestart:(BOOL)restart;
- (void)showBloom:(BOOL)show animated:(BOOL)animated;
- (void)wiggle;
@end

@implementation NoshiShiroPowerButton

@synthesize powerState = _powerState;

static CAShapeLayer *NoshiShiroShapeLayer(CALayer *parent) {
    CAShapeLayer *layer = [[[CAShapeLayer alloc] init] autorelease];
    [parent addSublayer:layer];
    return layer;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.exclusiveTouch = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    _body = [[CALayer alloc] init];
    [self.layer addSublayer:_body];
    _bloom = [[CALayer alloc] init];
    [_body addSublayer:_bloom];
    _back = [NoshiShiroShapeLayer(_bloom) retain];
    _front = [NoshiShiroShapeLayer(_body) retain];
    _glyph = [NoshiShiroShapeLayer(_body) retain];
    _glyph.fillColor = [UIColor clearColor].CGColor;
    _glyph.lineCap = kCALineCapRound;
    _bloom.opacity = 0;
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_body release];
    [_bloom release];
    [_back release];
    [_front release];
    [_glyph release];
    [super dealloc];
}

#pragma mark geometry

- (CGFloat)side {
    return MIN(self.bounds.size.width, self.bounds.size.height);
}

- (CGPoint)middle {
    return CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
}

/* the outline the front shape rests in for a state; the loading cycle starts from the first shape of its list */
- (UIBezierPath *)frontOutlineForState:(NoshiShiroPowerState)state {
    CGFloat radius = [self side] * FRONT_RADIUS;
    switch (state) {
    /* off keeps the scallop of the lit state, so switching off only drops the color and the motion */
    case NoshiShiroPowerOff:
    case NoshiShiroPowerOn: return NoshiShiroOutline([self middle], radius, 12, 0.045);
    case NoshiShiroPowerWorking: return NoshiShiroOutline([self middle], radius, NoshiShiroCycle[0].lobes, NoshiShiroCycle[0].depth);
    case NoshiShiroPowerFailed: return NoshiShiroOutline([self middle], radius, 5, 0.09);
    }
    return NoshiShiroOutline([self middle], radius, 12, 0.045);
}

- (UIBezierPath *)glyphPath {
    CGPoint center = [self middle];
    CGFloat gap = [self side] * FRONT_RADIUS * 0.4;
    UIBezierPath *power = [UIBezierPath bezierPathWithArcCenter:center radius:gap startAngle:(CGFloat)(-M_PI_2 + 0.62)
                                                       endAngle:(CGFloat)(-M_PI_2 - 0.62 + M_PI * 2) clockwise:YES];
    [power moveToPoint:CGPointMake(center.x, center.y - gap * 1.25)];
    [power addLineToPoint:CGPointMake(center.x, center.y - gap * 0.25)];
    return power;
}

- (BOOL)lit {
    return _powerState == NoshiShiroPowerWorking || _powerState == NoshiShiroPowerOn;
}

/* the round hit area: the corners of the bounds are empty plate */
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    CGPoint middle = [self middle];
    CGFloat reach = [self side] / 2;
    return hypot(point.x - middle.x, point.y - middle.y) <= reach;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1 || CGSizeEqualToSize(size, _laidSize)) return;
    _laidSize = size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    /* bounds and position, never frame: the frame of a layer that is rotated or scaled is its bounding box, and assigning it shrinks the layer, which
       moved the pivot away from the middle of the outline */
    for (CALayer *layer in [NSArray arrayWithObjects:_body, _bloom, _back, _front, _glyph, nil]) {
        layer.bounds = CGRectMake(0, 0, size.width, size.height);
        layer.position = layer == _body ? [self middle] : CGPointMake(size.width / 2, size.height / 2);
    }
    _front.path = [self frontOutlineForState:_powerState].CGPath;
    _back.path = NoshiShiroOutline([self middle], [self side] * BLOOM_RADIUS, 6, 0.07).CGPath;
    _glyph.path = [self glyphPath].CGPath;
    _glyph.lineWidth = MAX(3, [self side] * FRONT_RADIUS * 0.11);
    [CATransaction commit];
    [self syncMotion];
}

#pragma mark colors

- (void)applyColorsAnimated:(BOOL)animated {
    UIColor *front, *glyph;
    switch (_powerState) {
    case NoshiShiroPowerOff: front = NoshiShiroColorSurfaceHighest(); glyph = NoshiShiroColorOnSurfaceVariant(); break;
    case NoshiShiroPowerFailed: front = NoshiShiroColorErrorContainer(); glyph = NoshiShiroColorOnErrorContainer(); break;
    default: front = NoshiShiroColorPrimary(); glyph = NoshiShiroColorOnPrimary(); break;
    }
    [CATransaction begin];
    if (animated) [CATransaction setAnimationDuration:0.4];
    else [CATransaction setDisableActions:YES];
    _front.fillColor = front.CGColor;
    _glyph.strokeColor = glyph.CGColor;
    _back.fillColor = NoshiShiroColorPrimaryContainer().CGColor;
    [CATransaction commit];
}

- (void)applyTheme {
    [self applyColorsAnimated:NO];
}

#pragma mark motion

static double NoshiShiroShownAngle(CALayer *layer) {
    CALayer *shown = [layer presentationLayer];
    return [[(shown ? shown : layer) valueForKeyPath:@"transform.rotation.z"] doubleValue];
}

/* a layer that stops spinning keeps the angle it has on screen, and the model takes that angle so removing the
   spin does not snap it back to zero */
static void NoshiShiroSettle(CALayer *layer, int lobes, BOOL animated) {
    double angle = NoshiShiroShownAngle(layer);
    double target = angle;
    if (lobes > 0) {
        double lobe = M_PI * 2 / lobes;
        target = round(angle / lobe) * lobe;
    }
    [layer removeAnimationForKey:NoshiShiroSpinKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.transform = CATransform3DMakeRotation((CGFloat)target, 0, 0, 1);
    [CATransaction commit];
    if (!animated || fabs(angle - target) < 0.001) return;
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithDouble:angle];
    turn.toValue = [NSNumber numberWithDouble:target];
    turn.duration = 0.25;
    turn.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layer addAnimation:turn forKey:NoshiShiroSettleKey];
}

static void NoshiShiroSpin(CALayer *layer, double direction, CFTimeInterval seconds, BOOL restart) {
    if (!restart && [layer animationForKey:NoshiShiroSpinKey]) return;
    double angle = NoshiShiroShownAngle(layer);
    [layer removeAnimationForKey:NoshiShiroSpinKey];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = [NSNumber numberWithDouble:angle];
    spin.toValue = [NSNumber numberWithDouble:angle + direction * M_PI * 2];
    spin.duration = seconds;
    spin.repeatCount = HUGE_VALF;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:spin forKey:NoshiShiroSpinKey];
}

/* the front shape goes from where it is on screen to its resting outline for the state */
- (void)morphFrontAnimated:(BOOL)animated {
    CAShapeLayer *shown = (CAShapeLayer *)[_front presentationLayer];
    CGPathRef from = shown && shown.path ? shown.path : _front.path;
    /* the path is still empty before the first layout, and CGPathRetain(NULL) crashes on ios 5 and 6 */
    if (from) CGPathRetain(from);
    [_front removeAnimationForKey:NoshiShiroCycleKey];
    [_front removeAnimationForKey:NoshiShiroMorphKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _front.path = [self frontOutlineForState:_powerState].CGPath;
    [CATransaction commit];
    if (animated && from) {
        CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
        morph.fromValue = (id)from;
        morph.toValue = (id)_front.path;
        morph.duration = NoshiShiroMorphTime;
        morph.timingFunction = NoshiShiroSpring();
        [_front addAnimation:morph forKey:NoshiShiroMorphKey];
    }
    if (from) CGPathRelease(from);
}

/* the loading cycle: the shape flows through the others and comes back */
- (void)startCycleAfter:(CFTimeInterval)delay {
    if ([_front animationForKey:NoshiShiroCycleKey]) return;
    NSMutableArray *values = [NSMutableArray array];
    NSMutableArray *easing = [NSMutableArray array];
    CGFloat radius = [self side] * FRONT_RADIUS;
    for (size_t i = 0; i <= CYCLE_COUNT; ++i) {
        size_t shape = i % CYCLE_COUNT;
        [values addObject:(id)NoshiShiroOutline([self middle], radius, NoshiShiroCycle[shape].lobes, NoshiShiroCycle[shape].depth).CGPath];
        if (i < CYCLE_COUNT) [easing addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    }
    CAKeyframeAnimation *cycle = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    cycle.values = values;
    cycle.timingFunctions = easing;
    cycle.duration = 1.0 * CYCLE_COUNT;
    cycle.repeatCount = HUGE_VALF;
    if (delay > 0) cycle.beginTime = [_front convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
    [_front addAnimation:cycle forKey:NoshiShiroCycleKey];
}

/* core animation drops running animations while the app is in the background, so every state write and every return to the screen puts back the
   ones the state needs */
- (void)syncMotion {
    [self syncMotionRestart:NO];
}

- (void)syncMotionRestart:(BOOL)restart {
    BOOL moving = self.window != nil && !NoshiReduceMotionEnabled() && _laidSize.width > 0;
    if (!moving) {
        [_front removeAnimationForKey:NoshiShiroCycleKey];
        [_front removeAnimationForKey:NoshiShiroSpinKey];
        [_back removeAnimationForKey:NoshiShiroSpinKey];
        return;
    }
    switch (_powerState) {
    case NoshiShiroPowerWorking:
        [self startCycleAfter:0];
        NoshiShiroSpin(_front, 1, 5, restart);
        NoshiShiroSpin(_back, -1, 9, restart);
        break;
    case NoshiShiroPowerOn:
        NoshiShiroSpin(_front, 1, 32, restart);
        NoshiShiroSpin(_back, -1, 48, restart);
        break;
    default:
        break;
    }
}

- (void)setPowerState:(NoshiShiroPowerState)powerState {
    if (powerState == _powerState) {
        [self syncMotion];
        return;
    }
    _powerState = powerState;
    BOOL animated = self.window != nil && !NoshiReduceMotionEnabled() && _laidSize.width > 0;
    [self applyColorsAnimated:animated];
    if (_laidSize.width > 0) {
        [self morphFrontAnimated:animated];
        if (powerState == NoshiShiroPowerWorking && animated) [self startCycleAfter:NoshiShiroMorphTime];
        if (powerState != NoshiShiroPowerWorking && powerState != NoshiShiroPowerOn) {
            NoshiShiroSettle(_front, powerState == NoshiShiroPowerFailed ? 5 : 0, animated);
            NoshiShiroSettle(_back, 0, animated);
        }
        [self showBloom:[self lit] animated:animated];
        if (powerState == NoshiShiroPowerFailed && animated) [self wiggle];
    }
    [self syncMotionRestart:YES];
}

/* the bloom behind the front shape grows in with a spring when the tunnel starts and shrinks away when it ends */
- (void)showBloom:(BOOL)show animated:(BOOL)animated {
    CALayer *shown = [_bloom presentationLayer];
    float opacityFrom = (shown ? shown : _bloom).opacity;
    CATransform3D scaleFrom = (shown ? shown : _bloom).transform;
    CATransform3D scaleTo = show ? CATransform3DIdentity : CATransform3DMakeScale(0.6f, 0.6f, 1);
    [_bloom removeAnimationForKey:NoshiShiroBloomKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bloom.opacity = show ? 1 : 0;
    _bloom.transform = scaleTo;
    [CATransaction commit];
    if (!animated) return;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:opacityFrom];
    fade.toValue = [NSNumber numberWithFloat:_bloom.opacity];
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform"];
    grow.fromValue = [NSValue valueWithCATransform3D:scaleFrom];
    grow.toValue = [NSValue valueWithCATransform3D:scaleTo];
    grow.timingFunction = NoshiShiroSpring();
    group.animations = [NSArray arrayWithObjects:fade, grow, nil];
    group.duration = 0.6;
    [_bloom addAnimation:group forKey:NoshiShiroBloomKey];
}

/* a failure shakes the shape once, like a refused input */
- (void)wiggle {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    shake.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.16f], [NSNumber numberWithFloat:-0.14f],
                    [NSNumber numberWithFloat:0.08f], [NSNumber numberWithFloat:-0.04f], [NSNumber numberWithFloat:0], nil];
    shake.duration = 0.5;
    /* the model keeps the angle the shape stopped at, so the shake adds to it */
    shake.additive = YES;
    [_front addAnimation:shake forKey:NoshiShiroWiggleKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_observing) [center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    _observing = NO;
    if (self.window) {
        [center addObserver:self selector:@selector(syncMotion) name:UIApplicationDidBecomeActiveNotification object:nil];
        _observing = YES;
    }
    [self syncMotion];
}

#pragma mark touch

/* the shape sinks under the finger and springs past its size on release */
- (void)setHighlighted:(BOOL)highlighted {
    BOOL was = self.highlighted;
    [super setHighlighted:highlighted];
    if (was == highlighted) return;
    CALayer *shown = [_body presentationLayer];
    CGFloat from = [[(shown ? shown : _body) valueForKeyPath:@"transform.scale"] floatValue];
    [_body removeAnimationForKey:NoshiShiroBounceKey];
    CGFloat to = highlighted ? 0.9f : 1;
    /* a plain layer animates its own property changes, which would run beside the animation added below */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _body.transform = CATransform3DMakeScale(to, to, 1);
    [CATransaction commit];
    if (self.window == nil || NoshiReduceMotionEnabled()) return;
    if (highlighted) {
        CABasicAnimation *press = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        press.fromValue = [NSNumber numberWithFloat:from];
        press.toValue = [NSNumber numberWithFloat:to];
        press.duration = 0.12;
        press.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_body addAnimation:press forKey:NoshiShiroBounceKey];
        return;
    }
    CAKeyframeAnimation *release = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    release.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:from], [NSNumber numberWithFloat:1.08f], [NSNumber numberWithFloat:0.97f],
                      [NSNumber numberWithFloat:1], nil];
    release.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.4f], [NSNumber numberWithFloat:0.72f],
                        [NSNumber numberWithFloat:1], nil];
    release.duration = 0.5;
    [_body addAnimation:release forKey:NoshiShiroBounceKey];
}

@end

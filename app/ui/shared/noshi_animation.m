#import "noshi_animation.h"

#import "noshi_theme.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "noshi_platform.h"

/* a sample every 8 ms or less at the longest motion, so the spring is smooth on a 120 Hz screen too */
#define MOTION_SAMPLES 121

@interface NoshiMotionCompletion : NSObject {
    void (^_completion)(BOOL);
}
- (id)initWithCompletion:(void (^)(BOOL))completion;
@end

@implementation NoshiMotionCompletion
- (id)initWithCompletion:(void (^)(BOOL))completion {
    self = [super init];
    if (self) _completion = [completion copy];
    return self;
}
- (void)dealloc {
    [_completion release];
    [super dealloc];
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    if (_completion) _completion(finished);
}
@end

void NoshiAnimateView(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        noshi_motion_curve curve, void (^completion)(BOOL finished)) {
    NoshiAnimateViewAfter(view, transform, alpha, curve, 0, completion);
}

void NoshiAnimateViewAfter(UIView *view, CGAffineTransform transform, CGFloat alpha,
                             noshi_motion_curve curve, NSTimeInterval delay, void (^completion)(BOOL finished)) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:@"noshigram.motion"] ? [layer presentationLayer] : nil;
    CGAffineTransform from = visible ? CATransform3DGetAffineTransform(visible.transform) : view.transform;
    CGFloat fromAlpha = visible ? visible.opacity : view.alpha;
    [layer removeAnimationForKey:@"noshigram.motion"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.transform = transform;
    view.alpha = alpha;
    [CATransaction commit];
    BOOL reduced = NoshiReduceMotionEnabled();
    if (!view.window || ![UIView areAnimationsEnabled] || (reduced && !(delay > 0 && alpha < fromAlpha))) {
        if (completion) completion(YES);
        return;
    }
    if (reduced) {
        /* keep delayed notices readable when reduce motion disables their fade */
        CABasicAnimation *hold = [CABasicAnimation animationWithKeyPath:@"opacity"];
        hold.fromValue = hold.toValue = [NSNumber numberWithDouble:fromAlpha];
        hold.duration = delay;
        if (completion) hold.delegate = (id)[[[NoshiMotionCompletion alloc] initWithCompletion:completion] autorelease];
        [layer addAnimation:hold forKey:@"noshigram.motion"];
        return;
    }
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)noshi_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (transform.a - from.a) * progress, from.b + (transform.b - from.b) * progress,
            from.c + (transform.c - from.c) * progress, from.d + (transform.d - from.d) * progress,
            from.tx + (transform.tx - from.tx) * progress, from.ty + (transform.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        CGFloat opacity = fromAlpha + (alpha - fromAlpha) * MIN(1, MAX(0, progress));
        [opacities addObject:[NSNumber numberWithDouble:opacity]];
    }
    /* sampled springs keep the same motion on ios 5, where CASpringAnimation is absent */
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = noshi_motion_duration(curve);
    movement.duration = fade.duration = group.duration;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    if (delay > 0) {
        group.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
        group.fillMode = kCAFillModeBackwards;
    }
    if (completion) group.delegate = (id)[[[NoshiMotionCompletion alloc] initWithCompletion:completion] autorelease];
    [layer addAnimation:group forKey:@"noshigram.motion"];
}

void NoshiCacheForMotion(UIView *view) {
    if (NoshiReduceMotionEnabled()) return;
    view.layer.rasterizationScale = NoshiScreenScale();
    view.layer.shouldRasterize = YES;
}

void NoshiUncacheAfterMotion(UIView *view) {
    view.layer.shouldRasterize = NO;
}

void NoshiPlaceView(UIView *view, CGRect frame) {
    CGPoint anchor = view.layer.anchorPoint;
    view.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    view.center = CGPointMake(frame.origin.x + frame.size.width * anchor.x, frame.origin.y + frame.size.height * anchor.y);
}

void NoshiSetShadowPath(UIView *card, CGFloat radius) {
    card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:card.bounds cornerRadius:radius].CGPath;
}

void NoshiAnimatePosition(UIView *view, CGPoint position, noshi_motion_curve curve) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:@"noshigram.position"] ? [layer presentationLayer] : nil;
    CGPoint from = visible ? visible.position : layer.position;
    [layer removeAnimationForKey:@"noshigram.position"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.position = position;
    [CATransaction commit];
    if (NoshiReduceMotionEnabled() || !view.window || ![UIView areAnimationsEnabled]) return;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)noshi_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        [values addObject:[NSValue valueWithCGPoint:CGPointMake(from.x + (position.x - from.x) * progress,
                                                               from.y + (position.y - from.y) * progress)]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    movement.values = values;
    movement.duration = noshi_motion_duration(curve);
    movement.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:movement forKey:@"noshigram.position"];
}

void NoshiAnimateEnter(UIView *view, CGAffineTransform from, CGFloat fromAlpha, noshi_motion_curve curve) {
    CALayer *layer = view.layer;
    CGAffineTransform to = view.transform;
    CGFloat toAlpha = view.alpha;
    [layer removeAnimationForKey:@"noshigram.enter"];
    if (!(view.window || view.superview) || ![UIView areAnimationsEnabled] || NoshiReduceMotionEnabled()) return;
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        CGFloat progress = (CGFloat)noshi_motion_progress(curve, (double)i / (MOTION_SAMPLES - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (to.a - from.a) * progress, from.b + (to.b - from.b) * progress,
            from.c + (to.c - from.c) * progress, from.d + (to.d - from.d) * progress,
            from.tx + (to.tx - from.tx) * progress, from.ty + (to.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        /* a spring overshoots, and an opacity past one is clamped by the layer anyway */
        [opacities addObject:[NSNumber numberWithDouble:fromAlpha + (toAlpha - fromAlpha) * MIN(1, MAX(0, progress))]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = noshi_motion_duration(curve);
    movement.duration = fade.duration = group.duration;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:group forKey:@"noshigram.enter"];
}

void NoshiCancelEnter(UIView *view) {
    [view.layer removeAnimationForKey:@"noshigram.enter"];
}

#define BOUNCE_PRESS_SECONDS 0.06
#define BOUNCE_RELEASE_SECONDS 0.35
#define BOUNCE_OVERSHOOT 5.0
static NSString *const NoshiBounceKey = @"noshigram.bounce";

@interface NoshiBounceTarget : NSObject
+ (NoshiBounceTarget *)shared;
- (void)press:(UIControl *)control;
- (void)lift:(UIControl *)control;
@end

/* the scale the layer shows at this moment, which is where a new bounce starts from */
static CGFloat NoshiBounceShownScale(CALayer *layer) {
    CALayer *shown = [layer animationForKey:NoshiBounceKey] ? [layer presentationLayer] : nil;
    NSNumber *scale = shown ? [shown valueForKeyPath:@"transform.scale"] : nil;
    return scale ? (CGFloat)scale.doubleValue : 1;
}

@implementation NoshiBounceTarget

+ (NoshiBounceTarget *)shared {
    static NoshiBounceTarget *target;
    if (!target) target = [[NoshiBounceTarget alloc] init];
    return target;
}

- (BOOL)animates:(UIControl *)control {
    return control.window && [UIView areAnimationsEnabled] && !NoshiReduceMotionEnabled();
}

- (void)press:(UIControl *)control {
    if (![self animates:control]) return;
    CALayer *layer = control.layer;
    CGFloat depth = [objc_getAssociatedObject(control, &NoshiBounceKey) doubleValue];
    CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    shrink.fromValue = [NSNumber numberWithDouble:NoshiBounceShownScale(layer)];
    shrink.toValue = [NSNumber numberWithDouble:1 - depth];
    shrink.duration = BOUNCE_PRESS_SECONDS;
    shrink.fillMode = kCAFillModeForwards;
    shrink.removedOnCompletion = NO;
    /* CubicBezierInterpolator.DEFAULT */
    shrink.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.25f:0.1f:0.25f:1];
    [layer addAnimation:shrink forKey:NoshiBounceKey];
}

- (void)lift:(UIControl *)control {
    CALayer *layer = control.layer;
    if (![layer animationForKey:NoshiBounceKey]) return;
    CGFloat from = NoshiBounceShownScale(layer);
    if (![self animates:control]) {
        [layer removeAnimationForKey:NoshiBounceKey];
        return;
    }
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:MOTION_SAMPLES];
    for (NSUInteger i = 0; i < MOTION_SAMPLES; ++i) {
        double t = (double)i / (MOTION_SAMPLES - 1) - 1;
        double overshoot = t * t * ((BOUNCE_OVERSHOOT + 1) * t + BOUNCE_OVERSHOOT) + 1;
        [values addObject:[NSNumber numberWithDouble:from + (1 - from) * overshoot]];
    }
    CAKeyframeAnimation *spring = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    spring.values = values;
    spring.duration = BOUNCE_RELEASE_SECONDS;
    spring.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:spring forKey:NoshiBounceKey];
}

@end

void NoshiAttachBounce(UIControl *control, CGFloat depth) {
    NoshiBounceTarget *target = [NoshiBounceTarget shared];
    objc_setAssociatedObject(control, &NoshiBounceKey, [NSNumber numberWithDouble:depth], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control addTarget:target action:@selector(press:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:target action:@selector(lift:)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

void NoshiSetFrameRate(CADisplayLink *link, NSInteger framesPerSecond) {
    if (!link || framesPerSecond <= 0) return;
    SEL preferred = NSSelectorFromString(@"setPreferredFramesPerSecond:");
    if ([link respondsToSelector:preferred]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(link, preferred, framesPerSecond);
        return;
    }
    if ([link respondsToSelector:@selector(setFrameInterval:)]) link.frameInterval = (NSUInteger)MAX(1, 60 / framesPerSecond);
}

noshi_motion_curve NoshiPopupCurve(BOOL entering) {
    return entering ? NOSHI_MOTION_POPUP_CLASSIC_ENTER : NOSHI_MOTION_POPUP_CLASSIC_EXIT;
}

CGFloat NoshiPopupScale(void) {
    return 0.95;
}

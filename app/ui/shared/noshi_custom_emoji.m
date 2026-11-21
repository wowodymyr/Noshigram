#import "noshi_custom_emoji.h"

#import "noshi_platform.h"
#import "noshi_image_decoder.h"
#import "noshi_animation.h"
#import <QuartzCore/QuartzCore.h>

#define PICTURE_POINTS 24.0
#define BADGE_POINTS 48.0
#define PICTURE_COUNT_MAX 400

NSString *const NoshiCustomEmojiDidLoadNotification = @"NoshiCustomEmojiDidLoad";

static NSCache *NoshiCustomPictures(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = PICTURE_COUNT_MAX;
        cache.totalCostLimit = 16 * 1024 * 1024;
    });
    return cache;
}

static NSMutableSet *NoshiCustomSet(NSMutableSet **slot) {
    if (!*slot) *slot = [[NSMutableSet alloc] init];
    return *slot;
}

static NSMutableSet *NoshiLoading;
/* the documents that did not come, with the time they failed: a lost packet, a flood wait or a dead connection looks the same as a document the server does not have,
   and a failure that stayed for the whole run left emoji blank until the app was restarted */
static NSMutableDictionary *NoshiFailed;
#define FAILED_RETRY_SECONDS 60.0

static UIImage *NoshiTelegramVerifiedImage(void) {
    static UIImage *image;
    if (image) return image;
    CGFloat side = PICTURE_POINTS, center = side / 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, NoshiScreenScale());
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextMoveToPoint(context, center, center - side * 0.46);
    for (int i = 1; i <= 24; ++i) {
        CGFloat angle = -M_PI_2 + (CGFloat)i * (CGFloat)M_PI / 12;
        CGFloat radius = side * (i % 2 ? 0.40 : 0.46);
        CGContextAddLineToPoint(context, center + cos(angle) * radius, center + sin(angle) * radius);
    }
    CGContextClosePath(context);
    CGContextSetRGBFillColor(context, 0.20, 0.65, 0.91, 1);
    CGContextFillPath(context);
    CGContextSetRGBStrokeColor(context, 1, 1, 1, 1);
    CGContextSetLineWidth(context, side * 0.10);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextMoveToPoint(context, side * 0.29, side * 0.50);
    CGContextAddLineToPoint(context, side * 0.43, side * 0.64);
    CGContextAddLineToPoint(context, side * 0.71, side * 0.36);
    CGContextStrokePath(context);
    image = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return image;
}

/* the Premium star of Telegram for Android (the white shape of its list star), filled with the blue to violet of the Premium mark and drawn once at the size the pictures use */
static UIImage *NoshiPremiumStarImage(void) {
    static UIImage *star;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"badge_premium_star" ofType:@"png"];
        UIImage *shape = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (!shape) {
            NSLog(@"noshigram: the premium star picture is missing from the bundle");
            return;
        }
        CGFloat side = PICTURE_POINTS;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, NoshiScreenScale());
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        /* the shape goes down first, and the gradient is drawn over it where it already has paint */
        CGFloat width = side * 0.86, height = width * shape.size.height / shape.size.width;
        [shape drawInRect:CGRectMake((side - width) / 2, (side - height) / 2, width, height)];
        CGContextSetBlendMode(context, kCGBlendModeSourceIn);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat colors[8] = {0.33, 0.62, 1.0, 1.0, 0.74, 0.36, 1.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(side * 0.2, 0), CGPointMake(side * 0.8, side), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        star = [UIGraphicsGetImageFromCurrentImageContext() retain];
        UIGraphicsEndImageContext();
    });
    return star;
}

/* a bundled badge drawn once at the size the pictures use; the file is larger than any screen needs, so the
   context does the scaling */
static UIImage *NoshiBundledBadge(NSString *name, UIImage **slot) {
    if (*slot) return *slot;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) {
        NSLog(@"noshigram: the badge picture %@ is missing from the bundle", name);
        return nil;
    }
    CGFloat side = BADGE_POINTS;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, NoshiScreenScale());
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [source drawInRect:CGRectMake(0, 0, side, side)];
    *slot = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return *slot;
}

#pragma mark animation

#define ANIMATION_COST_LIMIT (12 * 1024 * 1024)
#define ANIMATION_FPS 15

@interface NoshiEmojiFrames : NSObject {
@public
    NSArray *frames;
    NSTimeInterval duration;
}
@end

@implementation NoshiEmojiFrames
- (void)dealloc {
    [frames release];
    [super dealloc];
}
@end

static NSCache *NoshiAnimations(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.totalCostLimit = ANIMATION_COST_LIMIT;
    });
    return cache;
}

static NSUInteger sAnimatedDraws;

NSUInteger NoshiCustomEmojiAnimatedDraws(void) { return sAnimatedDraws; }

/* one display link for every animated emoji on screen: it runs while views are waiting for a tick and stops when none is */
@interface NoshiEmojiClock : NSObject {
    CADisplayLink *_link;
    NSMutableSet *_views;
}
+ (NoshiEmojiClock *)shared;
- (void)keep:(UIView *)view;
@end

@implementation NoshiEmojiClock

+ (NoshiEmojiClock *)shared {
    static NoshiEmojiClock *clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ clock = [[NoshiEmojiClock alloc] init]; });
    return clock;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _views = [[NSMutableSet alloc] init];
    return self;
}

- (void)keep:(UIView *)view {
    [_views addObject:view];
    if (_link) return;
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
    NoshiSetFrameRate(_link, ANIMATION_FPS);
    /* not in the common modes: while a finger drags or a list decelerates the run loop is in the tracking mode, and every row with an animated emoji drawing again fifteen times a second
       is what an iPhone 5 could not keep up with while scrolling the chat list; the emoji stand still for the scroll and go on after it */
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    NSSet *waiting = [[_views copy] autorelease];
    [_views removeAllObjects];
    for (UIView *view in waiting) {
        if (view.window && !view.hidden && view.alpha > 0.01) [view setNeedsDisplay];
    }
    /* a view that drew an emoji again has put itself back by now only if it was drawn, which happens after this tick; the link stays for the next one and ends when nobody came back */
    if (!waiting.count) {
        [_link invalidate];
        [_link release];
        _link = nil;
    }
}

@end

@implementation NoshiCustomEmoji

+ (void)setAnimationFrames:(NSArray *)frames duration:(NSTimeInterval)duration forDocument:(long long)document {
    if (frames.count < 2 || duration <= 0) return;
    NoshiEmojiFrames *holder = [[[NoshiEmojiFrames alloc] init] autorelease];
    holder->frames = [frames copy];
    holder->duration = duration;
    NSUInteger cost = 0;
    for (UIImage *frame in frames) cost += CGImageGetBytesPerRow(frame.CGImage) * CGImageGetHeight(frame.CGImage);
    [NoshiAnimations() setObject:holder forKey:[NSNumber numberWithLongLong:document] cost:cost];
}

+ (BOOL)hasAnimationForDocument:(long long)document {
    return [NoshiAnimations() objectForKey:[NSNumber numberWithLongLong:document]] != nil;
}

+ (void)keepAnimatingView:(UIView *)view {
    [[NoshiEmojiClock shared] keep:view];
}

+ (UIImage *)imageForDocument:(long long)document {
    if (document == NOSHI_TELEGRAM_VERIFIED_DOCUMENT) return NoshiTelegramVerifiedImage();
    if (document == NOSHI_PREMIUM_STAR_DOCUMENT) return NoshiPremiumStarImage();
    static UIImage *hammer, *fox, *net, *hammers, *promotion, *bugHunter, *officialTester, *manager, *videoFix, *flawSeer;
    if (document == NOSHI_BUG_HUNTER_DOCUMENT) {
        if (!bugHunter) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"badge_bug_hunter" ofType:@"png"];
            if (path) bugHunter = [NoshiDecodeImageAtURL([NSURL fileURLWithPath:path], BADGE_POINTS * NoshiScreenScale()) retain];
            if (!bugHunter) NSLog(@"noshigram: the bug hunter badge picture could not be decoded");
        }
        return bugHunter;
    }
    if (document == NOSHI_OFFICIAL_TESTER_DOCUMENT) return NoshiBundledBadge(@"badge_official_tester", &officialTester);
    if (document == NOSHI_FLAW_SEER_DOCUMENT) return NoshiBundledBadge(@"badge_flaw_seer", &flawSeer);
    if (document == NOSHI_MANAGER_DOCUMENT) return NoshiBundledBadge(@"badge_manager", &manager);
    if (document == NOSHI_VIDEO_FIX_DOCUMENT) return NoshiBundledBadge(@"badge_videofix", &videoFix);
    if (document == NOSHI_PROMOTION_DOCUMENT) return NoshiBundledBadge(@"badge_promotion", &promotion);
    if (document == NOSHI_DEVELOPER_DOCUMENT) return NoshiBundledBadge(@"badge_developer", &hammer);
    if (document == NOSHI_LEAD_DOCUMENT) return NoshiBundledBadge(@"badge_lead", &hammers);
    if (document == NOSHI_TESTER_DOCUMENT) return NoshiBundledBadge(@"badge_tester", &net);
    if (document == NOSHI_SENKO_DOCUMENT) return NoshiBundledBadge(@"badge_senko", &fox);
    NoshiEmojiFrames *animated = [NoshiAnimations() objectForKey:[NSNumber numberWithLongLong:document]];
    if (animated && !NoshiReduceMotionEnabled()) {
        /* every emoji of a document shows the same frame at the same moment, which is what the clock of the process gives */
        double phase = fmod(CACurrentMediaTime(), animated->duration) / animated->duration;
        NSUInteger index = MIN(animated->frames.count - 1, (NSUInteger)(phase * (double)animated->frames.count));
        ++sAnimatedDraws;
        return [animated->frames objectAtIndex:index];
    }
    return [NoshiCustomPictures() objectForKey:[NSNumber numberWithLongLong:document]];
}

+ (UIImage *)stillImageForDocument:(long long)document {
    UIImage *still = [NoshiCustomPictures() objectForKey:[NSNumber numberWithLongLong:document]];
    return still ? still : [self imageForDocument:document];
}

+ (void)replaceStillImage:(UIImage *)image forDocument:(long long)document {
    CGImageRef bitmap = image.CGImage;
    if (!bitmap) return;
    NSUInteger cost = CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap);
    [NoshiCustomPictures() setObject:image forKey:[NSNumber numberWithLongLong:document] cost:cost];
}

+ (BOOL)needsLoad:(long long)document {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    if ([NoshiCustomPictures() objectForKey:key] || [NoshiCustomSet(&NoshiLoading) containsObject:key]) return NO;
    NSDate *failed = [NoshiFailed objectForKey:key];
    if (!failed) return YES;
    if (-[failed timeIntervalSinceNow] < FAILED_RETRY_SECONDS) return NO;
    [NoshiFailed removeObjectForKey:key];
    return YES;
}

+ (void)abandonLoad:(long long)document {
    [NoshiCustomSet(&NoshiLoading) removeObject:[NSNumber numberWithLongLong:document]];
}

+ (void)beginLoad:(long long)document {
    [NoshiCustomSet(&NoshiLoading) addObject:[NSNumber numberWithLongLong:document]];
}

+ (void)finishLoad:(long long)document image:(UIImage *)image {
    NSNumber *key = [NSNumber numberWithLongLong:document];
    [NoshiCustomSet(&NoshiLoading) removeObject:key];
    /* custom documents have unrelated transparent canvas margins */
    if (image) {
        UIImage *fitted = NoshiFitEmojiImage(image);
        CGImageRef bitmap = fitted.CGImage;
        NSUInteger cost = bitmap ? CGImageGetBytesPerRow(bitmap) * CGImageGetHeight(bitmap) : 0;
        [NoshiCustomPictures() setObject:fitted forKey:key cost:cost];
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiCustomEmojiDidLoadNotification object:key];
    }
    else {
        if (!NoshiFailed) NoshiFailed = [[NSMutableDictionary alloc] init];
        [NoshiFailed setObject:[NSDate date] forKey:key];
    }
}

+ (CGFloat)pictureSide {
    /* NoshiFitEmojiImage trims the empty margin and enlarges what is left, up to a third, and a topic icon is drawn 48 points wide: the extra decoded
       pixels are what that enlargement and the row use */
    return 64.0 * NoshiScreenScale();
}

@end

#import "noshi_classic_bubble.h"

#import "noshi_theme.h"

/* the corners and the tail of the cut pictures, in points: the side with the tail holds the tail and a corner, the others a corner */
#define CAP_CORNER NOSHI_CLASSIC_BUBBLE_CORNER
#define CAP_PLAIN 13.0
/* lightness of the grey template at which the body color sits; the edge goes dark below it, and everything above it is the body */
#define BODY_LIGHTNESS_OUT 0.72
#define BODY_LIGHTNESS_IN 0.84
/* the cache holds a few colors; a change of accent or look makes a new one and the old ones go when it is full */
#define CACHE_MAX 12

static void NoshiBubbleRGB(UIColor *color, CGFloat rgb[3]) {
    CGFloat alpha;
    if (![color getRed:&rgb[0] green:&rgb[1] blue:&rgb[2] alpha:&alpha]) {
        CGFloat white;
        [color getWhite:&white alpha:&alpha];
        rgb[0] = rgb[1] = rgb[2] = white;
    }
}

static void NoshiBubbleMix(const CGFloat from[3], const CGFloat to[3], CGFloat share, CGFloat out[3]) {
    for (int i = 0; i < 3; ++i) out[i] = from[i] + (to[i] - from[i]) * share;
}

/* the grey of a pixel picks a point on a ramp from the outline to the body color, so the bubble is the body color with its rim; the template's gloss is not used */
static UIImage *NoshiMakeBubble(BOOL outgoing, BOOL tail) {
    NSString *name = [NSString stringWithFormat:@"classic_bubble_%@%@.png", outgoing ? @"out" : @"in", tail ? @"" : @"_plain"];
    UIImage *template = [UIImage imageNamed:name];
    CGImageRef source = template.CGImage;
    if (!source) {
        NSLog(@"noshigram: the bubble picture %@ is missing from the bundle", name);
        return nil;
    }
    UIColor *top, *bottom, *outline;
    NoshiClassicBubbleColors(outgoing, &top, &bottom, &outline);
    (void)top;
    CGFloat edge[3], body[3];
    NoshiBubbleRGB(outline, edge);
    NoshiBubbleRGB(bottom, body);
    CGFloat bodyAt = outgoing ? BODY_LIGHTNESS_OUT : BODY_LIGHTNESS_IN;

    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        NSLog(@"noshigram: no bitmap for the bubble picture %@", name);
        return nil;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);
    uint8_t *pixels = CGBitmapContextGetData(context);
    for (size_t i = 0; i < width * height; ++i) {
        uint8_t *px = pixels + i * 4;
        if (!px[3]) continue;
        /* the template has no hue, so the red channel is its grey once the alpha is divided out of it */
        CGFloat grey = MIN(1.0, (CGFloat)px[0] / (CGFloat)px[3]);
        CGFloat color[3];
        if (grey < bodyAt) NoshiBubbleMix(edge, body, grey / bodyAt, color);
        else memcpy(color, body, sizeof color);
        for (int c = 0; c < 3; ++c) px[c] = (uint8_t)(color[c] * (CGFloat)px[3] + 0.5);
    }
    CGImageRef tinted = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!tinted) return nil;
    UIImage *image = [UIImage imageWithCGImage:tinted scale:template.scale orientation:UIImageOrientationUp];
    CGImageRelease(tinted);
    UIEdgeInsets caps;
    if (!tail) caps = UIEdgeInsetsMake(CAP_CORNER, CAP_PLAIN, CAP_CORNER, CAP_PLAIN);
    else if (outgoing) caps = UIEdgeInsetsMake(CAP_CORNER, CAP_CORNER, CAP_CORNER, CAP_CORNER + NOSHI_CLASSIC_BUBBLE_TAIL);
    else caps = UIEdgeInsetsMake(CAP_CORNER, CAP_CORNER + NOSHI_CLASSIC_BUBBLE_TAIL, CAP_CORNER, CAP_CORNER);
    return [image resizableImageWithCapInsets:caps];
}

UIImage *NoshiClassicBubbleImage(BOOL outgoing, BOOL tail) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    UIColor *top, *bottom, *outline;
    NoshiClassicBubbleColors(outgoing, &top, &bottom, &outline);
    CGFloat key[3];
    NoshiBubbleRGB(bottom, key);
    NSString *id = [NSString stringWithFormat:@"%d%d%d:%.3f:%.3f:%.3f", outgoing, tail, NoshiThemeIsDark(), key[0], key[1], key[2]];
    UIImage *image = [cache objectForKey:id];
    if (image) return image;
    image = NoshiMakeBubble(outgoing, tail);
    if (!image) return nil;
    if (cache.count >= CACHE_MAX) [cache removeAllObjects];
    [cache setObject:image forKey:id];
    return image;
}

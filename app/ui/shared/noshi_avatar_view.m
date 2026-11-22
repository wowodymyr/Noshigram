#import "noshi_image_decoder.h"
#import "noshi_avatar_view.h"

#import "noshi_emoji_label.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_wave.h"

#define AVATAR_COLORS 7
/* the corner radius is the percent the person chose, in avatar sizes: 64 percent are the rounded squares of the official apps, 100 a circle */

@interface NoshiAvatarView () {
    NoshiEmojiLabel *_label;
    UIImage *_image;
    BOOL _imageHasAlpha;
    NSString *_photoKey;
}
@end

@implementation NoshiAvatarView

@synthesize initials = _initials;
@synthesize showsSymbol = _showsSymbol;
@synthesize symbol = _symbol;
@synthesize accent = _accent;
@synthesize seed = _seed;
@synthesize transparentPhoto = _transparentPhoto;
@synthesize deleted = _deleted;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    _label = [[NoshiEmojiLabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = NoshiTextAlignmentCenter;
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_image release];
    [_photoKey release];
    [_label release];
    [_initials release];
    [super dealloc];
}

- (void)setInitials:(NSString *)initials {
    if (initials == _initials || [initials isEqualToString:_initials]) return;
    [_initials release];
    _initials = [initials copy];
    _label.text = _initials;
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    /* the text layout uses at least 20 points, so center that width on small avatars */
    CGFloat labelWidth = MAX(20, self.bounds.size.width);
    _label.frame = CGRectMake((self.bounds.size.width - labelWidth) / 2, 0, labelWidth, self.bounds.size.height);
    UIFont *font = NoshiFontSemibold(MIN(self.bounds.size.width, self.bounds.size.height) * 0.38);
    if (font != _label.font) _label.font = font;
    _label.hidden = _showsSymbol || _image != nil;
}

- (void)setShowsSymbol:(BOOL)showsSymbol { if (showsSymbol == _showsSymbol) return; _showsSymbol = showsSymbol; _label.hidden = showsSymbol || _image != nil; [self setNeedsDisplay]; }

- (void)showImage:(UIImage *)image {
    if (image == _image) return;
    [_image release];
    _image = [image retain];
    CGImageAlphaInfo alpha = image.CGImage ? CGImageGetAlphaInfo(image.CGImage) : kCGImageAlphaNone;
    _imageHasAlpha = alpha != kCGImageAlphaNone && alpha != kCGImageAlphaNoneSkipFirst && alpha != kCGImageAlphaNoneSkipLast;
    _label.hidden = _showsSymbol || _image != nil;
    [self setNeedsDisplay];
}

- (void)setPhoto:(NoshiPhoto *)photo cache:(NoshiAvatarCache *)cache {
    NSString *key = photo.key;
    if (key == _photoKey || [key isEqualToString:_photoKey]) return;
    [_photoKey release];
    _photoKey = [key copy];
    [self showImage:nil];
    if (!photo || !cache) return;
    UIImage *cached = [cache cachedImageForPhoto:photo];
    if (cached) {
        [self showImage:cached];
        return;
    }
    /* the view can be released while the download runs, when a screen is rebuilt or a cell is dropped */
    [self retain];
    [cache loadImageForPhoto:photo completion:^(UIImage *image) {
        [self autorelease];
        if (!image || ![key isEqualToString:_photoKey]) return;
        /* a photo that came after the row was shown fades over the initials; one the cache already held was there with the row and appears with it */
        if (self.window && !NoshiReduceMotionEnabled()) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = 0.2;
            [self.layer addAnimation:fade forKey:@"photo"];
        }
        [self showImage:image];
    }];
}
- (void)setSymbol:(NoshiSymbol)symbol { if (symbol == _symbol) return; _symbol = symbol; [self setNeedsDisplay]; }
- (void)setAccent:(BOOL)accent { if (accent == _accent) return; _accent = accent; [self setNeedsDisplay]; }
- (void)setSeed:(NSUInteger)seed { if (seed == _seed) return; _seed = seed; [self setNeedsDisplay]; }
- (void)setDeleted:(BOOL)deleted { if (deleted == _deleted) return; _deleted = deleted; [self setNeedsDisplay]; }
- (void)setTransparentPhoto:(BOOL)transparentPhoto { if (transparentPhoto == _transparentPhoto) return; _transparentPhoto = transparentPhoto; [self setNeedsDisplay]; }

/* the accent color of the app as the two ends of the gradient: a lighter top over the color itself */
static void NoshiAccentGradient(CGFloat out[8]) {
    CGColorRef color = NoshiColorAccent().CGColor;
    const CGFloat *c = CGColorGetComponents(color);
    size_t count = CGColorGetNumberOfComponents(color);
    CGFloat r = c[0], g = count >= 3 ? c[1] : c[0], b = count >= 3 ? c[2] : c[0];
    out[0] = r + (1 - r) * 0.28f; out[1] = g + (1 - g) * 0.28f; out[2] = b + (1 - b) * 0.28f; out[3] = 1;
    out[4] = r; out[5] = g; out[6] = b; out[7] = 1;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    static const CGFloat palette[AVATAR_COLORS][8] = {
        {1.00, 0.52, 0.39, 1, 1.00, 0.32, 0.42, 1},
        {1.00, 0.74, 0.37, 1, 1.00, 0.62, 0.04, 1},
        {0.63, 0.52, 1.00, 1, 0.49, 0.36, 0.89, 1},
        {0.50, 0.84, 0.50, 1, 0.29, 0.71, 0.41, 1},
        {0.42, 0.80, 0.86, 1, 0.24, 0.66, 0.78, 1},
        {0.43, 0.69, 1.00, 1, 0.26, 0.52, 0.96, 1},
        {1.00, 0.49, 0.78, 1, 0.86, 0.33, 0.67, 1},
    };
    /* the gradient of the special avatars is the accent of the app, lighter at the top */
    CGFloat accent[8];
    NoshiAccentGradient(accent);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat side = MIN(bounds.size.width, bounds.size.height);
    /* every picture is a circle, as in telegram; a view that is not square is a capsule */
    CGFloat radius = side * 0.5;
    CGContextSaveGState(context);
    if (bounds.size.width == bounds.size.height) {
        CGContextAddEllipseInRect(context, bounds);
    } else {
        CGContextMoveToPoint(context, CGRectGetMinX(bounds) + radius, CGRectGetMinY(bounds));
        CGContextAddArcToPoint(context, CGRectGetMaxX(bounds), CGRectGetMinY(bounds), CGRectGetMaxX(bounds), CGRectGetMaxY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds), CGRectGetMinX(bounds), CGRectGetMaxY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds), CGRectGetMinX(bounds), CGRectGetMinY(bounds), radius);
        CGContextAddArcToPoint(context, CGRectGetMinX(bounds), CGRectGetMinY(bounds), CGRectGetMaxX(bounds), CGRectGetMinY(bounds), radius);
        CGContextClosePath(context);
    }
    CGContextClip(context);
    if (_image) {
        if (_imageHasAlpha && !_transparentPhoto) {
            NoshiFillGradient(context, CGPointMake(0, 0), CGPointMake(0, bounds.size.height), _accent ? accent : palette[_seed % AVATAR_COLORS], 2);
        }
        /* the photo fills the square, cropped to its middle */
        CGSize size = _image.size;
        CGFloat scale = MAX(bounds.size.width / size.width, bounds.size.height / size.height);
        CGSize drawn = CGSizeMake(size.width * scale, size.height * scale);
        [_image drawInRect:CGRectMake((bounds.size.width - drawn.width) / 2, (bounds.size.height - drawn.height) / 2, drawn.width, drawn.height)];
    } else {
        NoshiFillGradient(context, CGPointMake(0, 0), CGPointMake(0, bounds.size.height),
                            _accent ? accent : palette[_seed % AVATAR_COLORS], 2);
    }
    CGContextRestoreGState(context);

    if (_showsSymbol && !_image) {
        CGFloat glyph = side * 0.46;
        UIImage *image = NoshiSymbolImage(_symbol, glyph, [UIColor whiteColor]);
        [image drawInRect:CGRectMake((bounds.size.width - image.size.width) / 2, (bounds.size.height - image.size.height) / 2,
                                     image.size.width, image.size.height)];
    } else if (_deleted && !_image) {
        /* the mask is the ghost.webp canv, 32 units drawn on a 54 unit avatar */
        UIImage *ghost = NoshiSymbolImage(NoshiSymbolGhost, side * 0.6, [UIColor whiteColor]);
        [ghost drawInRect:CGRectMake((bounds.size.width - ghost.size.width) / 2, (bounds.size.height - ghost.size.height) / 2,
                                     ghost.size.width, ghost.size.height)];
    }
}

@end

@implementation NoshiOnlineDotView
@synthesize inverted = _inverted;
- (void)setInverted:(BOOL)inverted {
    if (inverted == _inverted) return;
    _inverted = inverted;
    [self setNeedsDisplay];
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.userInteractionEnabled = NO; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    [(_inverted ? [UIColor whiteColor] : [UIColor colorWithRed:0.30f green:0.78f blue:0.37f alpha:1]) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}
@end

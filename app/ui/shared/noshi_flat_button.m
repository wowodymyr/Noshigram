#import "noshi_flat_button.h"
#import "noshi_animation.h"

#import "noshi_theme.h"

@interface NoshiFlatButton () {
    UILabel *_label;
    NSString *_title;
    CGFloat _cornerRadius;
    CGFloat _titleSize;
}
@end

@implementation NoshiFlatButton

@synthesize cornerRadius = _cornerRadius;
@synthesize titleSize = _titleSize;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    NoshiAttachBounce(self, 0.06);
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = NoshiTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    _label.font = NoshiFontBold(19);
    [self addSubview:_label];
    return self;
}

- (void)dealloc {
    [_label release];
    [_title release];
    [super dealloc];
}

- (NSString *)title {
    return _title;
}

- (void)setTitle:(NSString *)title {
    if (title == _title || [title isEqualToString:_title]) return;
    [_title release];
    _title = [title copy];
    _label.text = _title;
    self.accessibilityLabel = _title;
}

- (void)setTitleSize:(CGFloat)titleSize {
    _titleSize = titleSize;
    _label.font = NoshiFontBold(titleSize);
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect box = self.bounds;
    CGFloat radius = MIN(_cornerRadius, box.size.height / 2);
    CGFloat minX = CGRectGetMinX(box), maxX = CGRectGetMaxX(box);
    CGFloat minY = CGRectGetMinY(box), maxY = CGRectGetMaxY(box);
    /* the path is drawn by hand: the rounded rect of UIBezierPath bends wrong on ios 7 when the radius is half the height */
    CGContextMoveToPoint(context, minX + radius, minY);
    CGContextAddArcToPoint(context, maxX, minY, maxX, maxY, radius);
    CGContextAddArcToPoint(context, maxX, maxY, minX, maxY, radius);
    CGContextAddArcToPoint(context, minX, maxY, minX, minY, radius);
    CGContextAddArcToPoint(context, minX, minY, maxX, minY, radius);
    CGContextClosePath(context);
    [(self.highlighted ? NoshiColorAccentDark() : NoshiColorAccent()) setFill];
    CGContextFillPath(context);
}

@end

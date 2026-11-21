#import "noshi_bar_button.h"
#import "noshi_animation.h"

#import "noshi_symbol.h"
#import "noshi_theme.h"

/* the arrow glyph fills 0.8 of its square, the width the label has to clear */
#define NOSHI_CHEVRON_SIDE 22.0
#define NOSHI_CHEVRON_WIDTH 17.6
#define NOSHI_CHEVRON_GAP 6.0
#define NOSHI_BAR_PADDING 14.0

@interface NoshiBarButton () {
    NSString *_title;
    BOOL _chevron;
    BOOL _bold;
    BOOL _dimmed;
    CGFloat _titleSize;
    UILabel *_label;
    UIColor *_inkColor;
}
@end

@implementation NoshiBarButton

@synthesize chevron = _chevron;
@synthesize bold = _bold;
@synthesize titleSize = _titleSize;
@synthesize dimmed = _dimmed;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    NoshiAttachBounce(self, 0.08);
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    _titleSize = 17;
    _label = [[UILabel alloc] init];
    _label.backgroundColor = [UIColor clearColor];
    _label.userInteractionEnabled = NO;
    _label.adjustsFontSizeToFitWidth = YES;
    _label.minimumFontSize = 10;
    [self addSubview:_label];
    [self refreshLabel];
    return self;
}

- (void)dealloc {
    [_title release];
    [_label release];
    [_inkColor release];
    [super dealloc];
}

- (NSString *)title {
    return _title;
}

- (void)refreshLabel {
    _label.text = _title;
    _label.font = _bold ? NoshiFontSemibold(_titleSize) : NoshiFontRegular(_titleSize);
    _label.textColor = _inkColor ? _inkColor : NoshiColorAccent();
    _label.alpha = _dimmed ? 0.4 : (self.highlighted ? 0.5 : 1.0);
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setTitle:(NSString *)title {
    if (title == _title || [title isEqualToString:_title]) return;
    [_title release];
    _title = [title copy];
    self.accessibilityLabel = _title;
    [self refreshLabel];
}

- (UIColor *)inkColor { return _inkColor; }
- (void)setInkColor:(UIColor *)color {
    if (_inkColor == color) return;
    [_inkColor release];
    _inkColor = [color retain];
    [self refreshLabel];
}

- (void)setChevron:(BOOL)chevron { _chevron = chevron; [self refreshLabel]; }
- (void)setBold:(BOOL)bold { _bold = bold; [self refreshLabel]; }
- (void)setTitleSize:(CGFloat)titleSize { _titleSize = titleSize; [self refreshLabel]; }
- (void)setDimmed:(BOOL)dimmed { _dimmed = dimmed; [self refreshLabel]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self refreshLabel]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    [_label sizeToFit];
    CGFloat inset = NOSHI_BAR_PADDING + (_chevron ? NOSHI_CHEVRON_WIDTH + NOSHI_CHEVRON_GAP : 0);
    CGRect frame = _label.frame;
    frame.size.width = MIN(frame.size.width, MAX(0, self.bounds.size.width - inset));
    /* the back button hugs the left edge and the forward one the right edge */
    frame.origin.x = _chevron ? inset : MAX(0, self.bounds.size.width - NOSHI_BAR_PADDING - frame.size.width);
    frame.origin.y = (self.bounds.size.height - frame.size.height) / 2;
    _label.frame = CGRectIntegral(frame);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    if (!_chevron) return;
    UIImage *arrow = NoshiSymbolImage(NoshiSymbolBack, NOSHI_CHEVRON_SIDE, _inkColor ? _inkColor : NoshiColorAccent());
    CGFloat margin = (NOSHI_CHEVRON_SIDE - NOSHI_CHEVRON_WIDTH) / 2;
    CGRect box = CGRectMake(NOSHI_BAR_PADDING - margin, (self.bounds.size.height - NOSHI_CHEVRON_SIDE) / 2, NOSHI_CHEVRON_SIDE, NOSHI_CHEVRON_SIDE);
    [arrow drawInRect:box blendMode:kCGBlendModeNormal alpha:_dimmed ? 0.4 : (self.highlighted ? 0.5 : 1.0)];
}

@end

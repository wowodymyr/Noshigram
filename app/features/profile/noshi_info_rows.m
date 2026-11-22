#import "noshi_info_rows.h"

#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define TEXT_INSET 15.0
#define TOP_LINE 100
#define BOTTOM_LINE 101

UIColor *NoshiInfoLineColor(void) { return [UIColor colorWithWhite:NoshiThemeIsDark() ? 1 : 0 alpha:NoshiThemeIsDark() ? 0.12 : 0.2]; }

static UIView *NoshiInfoHairline(NSInteger tag) {
    UIView *line = [[[UIView alloc] init] autorelease];
    line.tag = tag;
    line.backgroundColor = NoshiInfoLineColor();
    line.userInteractionEnabled = NO;
    return line;
}

UIView *NoshiNewInfoGroup(void) {
    UIView *group = [[UIView alloc] init];
    group.backgroundColor = NoshiColorCard();
    [group addSubview:NoshiInfoHairline(TOP_LINE)];
    [group addSubview:NoshiInfoHairline(BOTTOM_LINE)];
    return group;
}

void NoshiFitInfoGroupLines(UIView *group, BOOL top) {
    CGFloat pixel = 1.0f / NoshiScreenScale(), width = group.bounds.size.width, height = group.bounds.size.height;
    UIView *topLine = [group viewWithTag:TOP_LINE], *bottomLine = [group viewWithTag:BOTTOM_LINE];
    topLine.hidden = !top;
    topLine.frame = CGRectMake(0, 0, width, pixel);
    bottomLine.frame = CGRectMake(0, height - pixel, width, pixel);
    [group bringSubviewToFront:topLine];
    [group bringSubviewToFront:bottomLine];
}

CGFloat NoshiLayoutInfoGroup(UIView *group, NSArray *rows, CGFloat y, CGFloat width) {
    CGFloat rowY = 0;
    for (UIView *row in group.subviews) {
        if ([row isKindOfClass:[NoshiInfoRow class]]) row.hidden = ![rows containsObject:row];
    }
    for (UIView *row in rows) {
        row.frame = CGRectMake(0, rowY, width, NOSHI_INFO_ROW_HEIGHT);
        [row viewWithTag:11].hidden = row == [rows objectAtIndex:0];
        rowY += NOSHI_INFO_ROW_HEIGHT;
    }
    group.hidden = !rows.count;
    group.frame = CGRectMake(0, y, width, rowY);
    NoshiFitInfoGroupLines(group, YES);
    return rowY;
}

@interface NoshiInfoRow () {
    UILabel *_titleLabel;
    UILabel *_valueLabel;
    UIImageView *_arrow;
}
@end

@implementation NoshiInfoRow

static UILabel *NoshiInfoRowLabel(UIColor *color, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:17];
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    return label;
}

- (id)initWithTitle:(NSString *)title accent:(BOOL)accent chevron:(BOOL)chevron target:(id)target action:(SEL)action {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _titleLabel = NoshiInfoRowLabel(accent ? NoshiColorAccent() : NoshiColorTitle(), NoshiTextAlignmentLeft);
    _titleLabel.text = title;
    [self addSubview:_titleLabel];
    _valueLabel = NoshiInfoRowLabel(NoshiColorSecondary(), NoshiTextAlignmentRight);
    [self addSubview:_valueLabel];
    if (chevron) {
        _arrow = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolChevronRight, 13, [UIColor colorWithRed:0.78 green:0.78 blue:0.8 alpha:1])];
        _arrow.contentMode = UIViewContentModeCenter;
        [self addSubview:_arrow];
    }
    UIView *line = NoshiInfoHairline(11);
    [self addSubview:line];
    if (action) [self addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    else self.userInteractionEnabled = NO;
    self.accessibilityLabel = title;
    return self;
}

- (void)dealloc {
    [_titleLabel release];
    [_valueLabel release];
    [_arrow release];
    [super dealloc];
}

- (NSString *)title { return _titleLabel.text; }

- (void)setTitle:(NSString *)title {
    _titleLabel.text = title;
    self.accessibilityLabel = title;
}

- (NSString *)value { return _valueLabel.text; }

- (void)setValue:(NSString *)value {
    _valueLabel.text = value;
    self.accessibilityValue = value;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) {
        self.backgroundColor = NoshiThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0.85 alpha:1];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor = [UIColor clearColor]; }];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat right = _arrow ? 34 : TEXT_INSET;
    CGFloat valueWidth = _valueLabel.text.length ? MIN(ceil([_valueLabel sizeThatFits:CGSizeMake(size.width / 2, size.height)].width), size.width / 2) : 0;
    _titleLabel.frame = CGRectMake(TEXT_INSET, 0, MAX(0, size.width - TEXT_INSET - right - valueWidth - 8), size.height);
    _valueLabel.frame = CGRectMake(size.width - right - valueWidth, 0, valueWidth, size.height);
    _arrow.frame = CGRectMake(size.width - TEXT_INSET - 8, (size.height - 13) / 2, 8, 13);
    [self viewWithTag:11].frame = CGRectMake(TEXT_INSET, 0, size.width - TEXT_INSET, 1.0f / NoshiScreenScale());
}

@end

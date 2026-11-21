#import "noshi_rating_view.h"
#import <QuartzCore/QuartzCore.h>
#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_settings_kit.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define RATING_DIM 0.55

@implementation NoshiRatingBadge {
    int32_t _level;
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (int32_t)level { return _level; }
- (void)setLevel:(int32_t)level { _level = level; [self setNeedsDisplay]; }
static void NoshiAddShield(CGContextRef c, CGFloat w, CGFloat h) {
    CGContextMoveToPoint(c, 3, 2);
    CGContextAddLineToPoint(c, w - 3, 2);
    CGContextAddLineToPoint(c, w - 3, h * 0.55);
    CGContextAddQuadCurveToPoint(c, w - 3, h * 0.8, w / 2, h - 2);
    CGContextAddQuadCurveToPoint(c, 3, h * 0.8, 3, h * 0.55);
    CGContextClosePath(c);
}

/* the shield of the classic theme is a glossy plate like the badges of the old system: a vertical shade, a pale cap on the upper half and a dark rim */
static void NoshiDrawGlossShield(CGContextRef c, CGFloat w, CGFloat h, UIColor *base) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![base getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0;
        [base getWhite:&white alpha:&alpha];
        red = green = blue = white;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat shade[8] = {MIN(1, red + (1 - red) * 0.35f), MIN(1, green + (1 - green) * 0.35f), MIN(1, blue + (1 - blue) * 0.35f), 1,
                        red * 0.7f, green * 0.7f, blue * 0.7f, 1};
    CGFloat cap[8] = {1, 1, 1, 0.75f, 1, 1, 1, 0.12f};
    CGGradientRef body = CGGradientCreateWithColorComponents(space, shade, NULL, 2);
    CGGradientRef gloss = CGGradientCreateWithColorComponents(space, cap, NULL, 2);
    CGContextSaveGState(c);
    NoshiAddShield(c, w, h);
    CGContextClip(c);
    CGContextDrawLinearGradient(c, body, CGPointMake(0, 2), CGPointMake(0, h - 2), 0);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(-w * 0.25f, -h * 0.62f, w * 1.5f, h * 1.12f));
    CGContextClip(c);
    CGContextDrawLinearGradient(c, gloss, CGPointMake(0, 2), CGPointMake(0, h * 0.5f), 0);
    CGContextRestoreGState(c);
    /* the rim is stroked double wide inside the clip, so only the inner half shows and the plate keeps its size */
    NoshiAddShield(c, w, h);
    CGContextSetLineWidth(c, 2);
    CGContextSetRGBStrokeColor(c, 0, 0, 0, 0.4f);
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
    CGGradientRelease(body);
    CGGradientRelease(gloss);
    CGColorSpaceRelease(space);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    NoshiDrawGlossShield(c, w, h, NoshiColorTitle());
    NSString *text = [NSString stringWithFormat:@"%d", (int)_level];
    UIFont *font = NoshiFontBold(10);
    CGSize size = [text sizeWithFont:font];
    CGContextSaveGState(c);
    /* the digit is pressed into the plate: a light edge under it */
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 0, [UIColor colorWithWhite:1 alpha:0.6f].CGColor);
    [NoshiColorScreen() setFill];
    [text drawAtPoint:CGPointMake(floor((w - size.width) / 2), floor((h - size.height) / 2) - 1) withFont:font];
    CGContextRestoreGState(c);
}
@end

/* "2.7K" for 2700 and "5K" for 5000: the thousands with one decimal, dropped when it is zero */
static NSString *NoshiStarsShort(long long stars) {
    if (stars < 1000) return [NSString stringWithFormat:@"%lld", stars];
    long long tenths = (stars + 50) / 100;
    if (tenths % 10 == 0) return [NSString stringWithFormat:@"%lldK", tenths / 10];
    return [NSString stringWithFormat:@"%lld.%lldK", tenths / 10, tenths % 10];
}

/* the plate over the bar that tells the stars: a pill in the accent color with a crown, the amount and the goal, and a small tail that points at the bar */
@interface NoshiRatingPill : UIView {
    NSString *_amount;
    NSString *_goal;
}
- (void)setAmount:(NSString *)amount goal:(NSString *)goal;
- (CGSize)fittingSize;
@end

@implementation NoshiRatingPill
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.45f;
    self.layer.shadowRadius = 3;
    self.layer.shadowOffset = CGSizeMake(0, 1.5);
    return self;
}
- (void)dealloc { [_amount release]; [_goal release]; [super dealloc]; }
- (void)setAmount:(NSString *)amount goal:(NSString *)goal {
    [_amount release]; _amount = [amount copy];
    [_goal release]; _goal = [goal copy];
    [self setNeedsDisplay];
}
#define PILL_HEIGHT 40.0
#define PILL_TAIL 8.0
#define PILL_CROWN 26.0
- (CGSize)fittingSize {
    CGFloat amount = ceil([_amount sizeWithFont:NoshiFontBold(22)].width);
    CGFloat goal = _goal.length ? ceil([_goal sizeWithFont:NoshiFontMedium(15)].width) + 2 : 0;
    return CGSizeMake(16 + PILL_CROWN + 6 + amount + goal + 16, PILL_HEIGHT + PILL_TAIL);
}
static void NoshiAddCrown(CGContextRef c, CGRect box) {
    CGFloat x = box.origin.x, y = box.origin.y, w = box.size.width, h = box.size.height;
    /* three points and a band: the peaks stand on a base that is a little wider than the points */
    CGContextMoveToPoint(c, x, y + h * 0.88);
    CGContextAddLineToPoint(c, x, y + h * 0.22);
    CGContextAddLineToPoint(c, x + w * 0.27, y + h * 0.52);
    CGContextAddLineToPoint(c, x + w * 0.5, y);
    CGContextAddLineToPoint(c, x + w * 0.73, y + h * 0.52);
    CGContextAddLineToPoint(c, x + w, y + h * 0.22);
    CGContextAddLineToPoint(c, x + w, y + h * 0.88);
    CGContextClosePath(c);
    CGContextFillPath(c);
    CGContextFillRect(c, CGRectMake(x, y + h * 0.95, w, h * 0.05 + 1));
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width;
    CGRect body = CGRectMake(0, 0, w, PILL_HEIGHT);
    /* the plate is a glossy capsule, as the badges of the old home screen are; its shadow is the layer's */
    [NoshiClassicTintedGlossImage(NoshiColorAccent(), PILL_HEIGHT / 2 - 2, NO) drawInRect:body];
    CGFloat r = 0, g = 0, b = 0;
    [NoshiColorAccent() getRed:&r green:&g blue:&b alpha:NULL];
    [[UIColor colorWithRed:r * 0.74 green:g * 0.74 blue:b * 0.74 alpha:1] setFill];
    CGContextMoveToPoint(c, w / 2 - 9, PILL_HEIGHT - 1);
    CGContextAddLineToPoint(c, w / 2, PILL_HEIGHT + PILL_TAIL);
    CGContextAddLineToPoint(c, w / 2 + 9, PILL_HEIGHT - 1);
    CGContextClosePath(c);
    CGContextFillPath(c);
    [[UIColor whiteColor] setFill];
    CGContextSetShadowWithColor(c, CGSizeMake(0, -1), 0, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
    CGFloat x = 16;
    NoshiAddCrown(c, CGRectMake(x, (PILL_HEIGHT - PILL_CROWN * 0.8) / 2, PILL_CROWN, PILL_CROWN * 0.8));
    x += PILL_CROWN + 6;
    UIFont *big = NoshiFontBold(22);
    CGSize size = [_amount sizeWithFont:big];
    [_amount drawAtPoint:CGPointMake(x, floor((PILL_HEIGHT - size.height) / 2)) withFont:big];
    if (_goal.length) {
        [[UIColor colorWithWhite:1 alpha:0.78] setFill];
        UIFont *small = NoshiFontMedium(15);
        [_goal drawAtPoint:CGPointMake(x + ceil(size.width) + 2, floor((PILL_HEIGHT - [_goal sizeWithFont:small].height) / 2) + 2) withFont:small];
    }
}
@end

/* the card of the sheet, its top corners round, as a picture that stretches in its middle */
static UIImage *NoshiRatingSheetImage(void) {
    CGFloat radius = 24, side = radius * 2 + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [NoshiColorCard() setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side + radius) byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight cornerRadii:CGSizeMake(radius, radius)] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
    return [image stretchableImageWithLeftCapWidth:(NSInteger)radius topCapHeight:(NSInteger)radius];
}

@interface NoshiRatingView : UIView {
    NoshiFullUser *_user;
    UIView *_panel;
    UIImageView *_panelBack;
    UIScrollView *_scroll;
    NoshiRatingPill *_pill;
    UILabel *_level;
    UILabel *_nextLevel;
    UIView *_track;
    UIView *_fill;
    UILabel *_pending;
    UIButton *_preview;
    UIButton *_close;
    NSMutableArray *_rows;
    BOOL _showPending;
    BOOL _closing;
}
- (id)initWithUser:(NoshiFullUser *)user;
/* the dim comes in and the sheet rises; the plate with the crowns then swings a little on its tail */
- (void)enter;
@end

@implementation NoshiRatingView
static UILabel *ratingLabel(NSString *text, UIFont *font, UIColor *color, NSInteger alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}
/* one reason in the list: its picture, its title, and the words after a small mark of what it does to the rating */
static NSMutableDictionary *NoshiRatingRow(NoshiSymbol symbol, NSString *titleKey, NSString *bodyKey, BOOL adds) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:symbol], @"symbol", titleKey, @"title", bodyKey, @"body", [NSNumber numberWithBool:adds], @"adds", nil];
}
- (id)initWithUser:(NoshiFullUser *)user {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _user = [user retain];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:RATING_DIM];
    _panel = [[UIView alloc] init];
    /* the rounded top is a stretched picture and not a mask of the layer: a masked layer is drawn off screen at every frame of its move, which made the sheet judder when it left */
    _panel.backgroundColor = [UIColor clearColor];
    _panelBack = [[UIImageView alloc] initWithImage:NoshiRatingSheetImage()];
    /* the classic sheet is a plate of polished metal, as the menus are, and runs below the screen so that its lower corners are not seen */
    _panelBack.hidden = YES;
    NoshiClassicApplyMenuPlate(_panel, 10);
    [_panel addSubview:_panelBack];
    [self addSubview:_panel];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    [_panel addSubview:_scroll];
    _track = [[UIView alloc] init];
    /* the bar is a groove cut into the plate, with a dark line along its upper edge and a lit one along its lower, and the fill is a glossy accent capsule */
    _track.backgroundColor = [UIColor colorWithWhite:0 alpha:NoshiThemeIsDark() ? 0.40 : 0.16];
    _track.layer.cornerRadius = 20;
    _track.layer.borderWidth = 1;
    _track.layer.borderColor = [UIColor colorWithWhite:0 alpha:NoshiThemeIsDark() ? 0.7 : 0.3].CGColor;
    _track.clipsToBounds = YES;
    [_scroll addSubview:_track];
    _fill = [[UIImageView alloc] initWithImage:NoshiClassicTintedGlossImage(NoshiColorAccent(), 18, NO)];
    [_track addSubview:_fill];
    _level = [ratingLabel(@"", NoshiFontSemibold(16), [UIColor whiteColor], NoshiTextAlignmentLeft) retain];
    _level.numberOfLines = 1;
    [_track addSubview:_level];
    _nextLevel = [ratingLabel(@"", NoshiFontSemibold(16), NoshiClassicMenuTextColor(), NoshiTextAlignmentRight) retain];
    _nextLevel.numberOfLines = 1;
    [_track addSubview:_nextLevel];
    _pill = [[NoshiRatingPill alloc] init];
    [_scroll addSubview:_pill];
    _pending = [ratingLabel(@"", NoshiFontRegular(14), NoshiColorSecondary(), NoshiTextAlignmentCenter) retain];
    [_scroll addSubview:_pending];
    _preview = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_preview setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    _preview.titleLabel.font = NoshiFontSemibold(14);
    [_preview addTarget:self action:@selector(togglePreview) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_preview];
    UIColor *ink = NoshiClassicMenuTextColor();
    UILabel *title = ratingLabel(NSLocalizedString(@"rating.title", nil), [UIFont boldSystemFontOfSize:23], ink, NoshiTextAlignmentCenter);
    /* the letters are cut into the plate: a light edge under them on the pale plate, a dark one on the charcoal */
    title.shadowColor = NoshiThemeIsDark() ? [UIColor colorWithWhite:0 alpha:0.6] : [UIColor colorWithWhite:1 alpha:0.9];
    title.shadowOffset = CGSizeMake(0, NoshiThemeIsDark() ? -1 : 1);
    title.tag = 100;
    [_scroll addSubview:title];
    UILabel *about = ratingLabel(NSLocalizedString(@"rating.about", nil), [UIFont systemFontOfSize:15], ink, NoshiTextAlignmentCenter);
    about.tag = 101;
    [_scroll addSubview:about];
    _rows = [[NSMutableArray alloc] initWithObjects:NoshiRatingRow(NoshiSymbolGift, @"rating.gifts.title", @"rating.gifts.body", YES),
             NoshiRatingRow(NoshiSymbolMember, @"rating.users.title", @"rating.users.body", YES),
             NoshiRatingRow(NoshiSymbolRotate, @"rating.refunds.title", @"rating.refunds.body", NO), nil];
    NSInteger tag = 200;
    for (NSMutableDictionary *row in _rows) {
        NoshiSymbol symbol = (NoshiSymbol)[[row objectForKey:@"symbol"] intValue];
        /* the classic row has the colored glossy tile with a white sign of the settings lists and of the old messaging apps */
        UIImageView *icon = [[[UIImageView alloc] initWithImage:NoshiSettingsTileImage(symbol, tag == 200 ? NoshiSettingsTonePurple : (tag == 210 ? NoshiSettingsToneBlue : NoshiSettingsToneOrange), 32)] autorelease];
        icon.contentMode = UIViewContentModeCenter;
        icon.tag = tag;
        [_scroll addSubview:icon];
        UILabel *name = ratingLabel(NSLocalizedString([row objectForKey:@"title"], nil), [UIFont boldSystemFontOfSize:17], ink, NoshiTextAlignmentLeft);
        name.tag = tag + 1;
        [_scroll addSubview:name];
        BOOL adds = [[row objectForKey:@"adds"] boolValue];
        UILabel *mark = ratingLabel(NSLocalizedString(adds ? @"rating.plus" : @"rating.minus", nil), NoshiFontSemibold(12), adds ? [UIColor whiteColor] : NoshiColorTitle(), NoshiTextAlignmentCenter);
        mark.numberOfLines = 1;
        mark.backgroundColor = adds ? NoshiColorAccent() : [NoshiColorSecondary() colorWithAlphaComponent:0.35];
        mark.textColor = [UIColor whiteColor];
        mark.backgroundColor = adds ? [UIColor colorWithRed:0.25 green:0.62 blue:0.22 alpha:1] : [UIColor colorWithRed:0.78 green:0.20 blue:0.16 alpha:1];
        mark.layer.borderWidth = 1;
        mark.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.35].CGColor;
        mark.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        mark.shadowOffset = CGSizeMake(0, -1);
        mark.layer.cornerRadius = 5;
        mark.clipsToBounds = YES;
        mark.tag = tag + 2;
        [_scroll addSubview:mark];
        UILabel *body = ratingLabel(@"", [UIFont systemFontOfSize:15], [ink colorWithAlphaComponent:0.72], NoshiTextAlignmentLeft);
        body.tag = tag + 3;
        [_scroll addSubview:body];
        tag += 10;
    }
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setTitle:NSLocalizedString(@"rating.ok", nil) forState:UIControlStateNormal];
    [_close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    /* the blue key of the old messaging apps, in the accent: a glossy plate with a white word on it */
    _close.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    _close.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [_close setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
    [_close setBackgroundImage:NoshiClassicTintedGlossImage(NoshiColorAccent(), 10, NO) forState:UIControlStateNormal];
    [_close setBackgroundImage:NoshiClassicTintedGlossImage(NoshiColorAccent(), 10, YES) forState:UIControlStateHighlighted];
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_close];
    [self updateRating];
    return self;
}
- (void)dealloc {
    [_user release]; [_panelBack release]; [_panel release]; [_scroll release]; [_pill release]; [_level release]; [_nextLevel release]; [_track release]; [_fill release];
    [_pending release]; [_preview release]; [_close release]; [_rows release]; [super dealloc];
}
- (void)togglePreview { _showPending = !_showPending; [self updateRating]; }
- (void)enter {
    [self layoutIfNeeded];
    BOOL motion = !NoshiReduceMotionEnabled();
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:motion ? 0 : RATING_DIM];
    if (!motion) return;
    CGFloat rise = _panel.frame.size.height;
    _panel.transform = CGAffineTransformMakeTranslation(0, rise);
    [UIView animateWithDuration:0.22 animations:^{ self.backgroundColor = [UIColor colorWithWhite:0 alpha:RATING_DIM]; }];
    NoshiAnimateView(_panel, CGAffineTransformIdentity, 1, NOSHI_MOTION_SPRING, nil);
    /* the plate hangs by its tail and swings out, each swing smaller than the one before */
    CAKeyframeAnimation *swing = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    swing.values = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:0.16], [NSNumber numberWithDouble:-0.12],
                    [NSNumber numberWithDouble:0.08], [NSNumber numberWithDouble:-0.04], [NSNumber numberWithDouble:0.015], [NSNumber numberWithDouble:0], nil];
    swing.duration = 1.1;
    swing.beginTime = CACurrentMediaTime() + 0.28;
    swing.fillMode = kCAFillModeBackwards;
    swing.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_pill.layer addAnimation:swing forKey:@"noshigram.swing"];
}
- (void)close {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    NoshiCacheForMotion(_panel);
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.2 animations:^{ self.backgroundColor = [UIColor colorWithWhite:0 alpha:0]; }];
    NoshiAnimateView(_panel, CGAffineTransformMakeTranslation(0, _panel.frame.size.height), 1, NOSHI_MOTION_DISMISS, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}
- (void)updateRating {
    noshi_star_rating rating = _showPending ? _user.pendingRating : _user.rating;
    _level.text = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)rating.level];
    _nextLevel.text = rating.has_next ? [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)rating.level + 1] : @"";
    [_pill setAmount:NoshiStarsShort((long long)rating.stars) goal:rating.has_next ? [@"/" stringByAppendingString:NoshiStarsShort((long long)rating.next_level_stars)] : nil];
    if (_user.hasPendingRating) {
        NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
        format.dateStyle = NSDateFormatterMediumStyle;
        _pending.text = [NSString stringWithFormat:NSLocalizedString(@"rating.pending", nil), [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:_user.pendingRatingDate]]];
    } else _pending.text = @"";
    _preview.hidden = !_user.hasPendingRating;
    [_preview setTitle:NSLocalizedString(_showPending ? @"rating.current" : @"rating.preview", nil) forState:UIControlStateNormal];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = NoshiSafeInsets(self);
    CGFloat width = MIN(520, self.bounds.size.width - safe.left - safe.right);
    CGFloat inner = width - 40;
    /* the sheet is as tall as what it says, up to the screen */
    noshi_star_rating rating = _showPending ? _user.pendingRating : _user.rating;
    CGSize pill = [_pill fittingSize];
    double fraction = rating.has_next ? ((double)rating.stars - (double)rating.current_level_stars) / ((double)rating.next_level_stars - (double)rating.current_level_stars) : 1;
    fraction = MAX(0, MIN(1, fraction));
    CGFloat trackY = 20 + pill.height + 6;
    _track.frame = CGRectMake(20, trackY, inner, 40);
    CGFloat levelWidth = ceil([_level.text sizeWithFont:_level.font].width) + 28;
    CGFloat filled = MAX(levelWidth, floor(inner * fraction));
    _fill.frame = CGRectMake(0, 0, filled, 40);
    _level.frame = CGRectMake(14, 0, filled - 14, 40);
    _nextLevel.frame = CGRectMake(inner - 14 - MAX(0, inner - filled - 28), 0, MAX(0, inner - filled - 28), 40);
    _pill.frame = CGRectMake(MAX(20, MIN(20 + inner - pill.width, 20 + filled - pill.width / 2)), 20, pill.width, pill.height);
    CGFloat y = trackY + 40 + 26;
    if (_user.hasPendingRating) {
        /* the line wraps, so it has the height its words need: a fixed 34 points cut the date off with dots */
        CGFloat pendingHeight = MAX(34, ceil([_pending sizeThatFits:CGSizeMake(inner, 1000)].height));
        _pending.frame = CGRectMake(20, y, inner, pendingHeight);
        y += pendingHeight;
        _preview.frame = CGRectMake(20, y, inner, 30);
        y += 38;
    }
    for (NSInteger i = 0; i < 2; ++i) {
        UILabel *label = (UILabel *)[_scroll viewWithTag:100 + i];
        CGSize size = [label sizeThatFits:CGSizeMake(inner, 1000)];
        label.frame = CGRectMake(20, y, inner, ceil(size.height));
        y += ceil(size.height) + (i == 0 ? 8 : 24);
    }
    NSInteger tag = 200;
    CGFloat textLeft = 68, textWidth = width - textLeft - 20;
    for (NSMutableDictionary *row in _rows) {
        UIView *icon = [_scroll viewWithTag:tag];
        UILabel *name = (UILabel *)[_scroll viewWithTag:tag + 1], *mark = (UILabel *)[_scroll viewWithTag:tag + 2], *body = (UILabel *)[_scroll viewWithTag:tag + 3];
        CGSize nameSize = [name sizeThatFits:CGSizeMake(textWidth, 100)];
        name.frame = CGRectMake(textLeft, y, textWidth, ceil(nameSize.height));
        icon.frame = CGRectMake(20, y, 32, 32);
        CGFloat markWidth = ceil([mark.text sizeWithFont:mark.font].width) + 12;
        /* the words begin after the mark: the mark stands over a run of blanks the width of itself */
        CGFloat blank = [@" " sizeWithFont:body.font].width;
        NSMutableString *lead = [NSMutableString string];
        for (NSUInteger n = 0; n < (NSUInteger)ceil((markWidth + 6) / MAX(1, blank)); ++n) [lead appendString:@" "];
        body.text = [lead stringByAppendingString:NSLocalizedString([row objectForKey:@"body"], nil)];
        CGSize bodySize = [body sizeThatFits:CGSizeMake(textWidth, 1000)];
        CGFloat bodyY = y + ceil(nameSize.height) + 3;
        body.frame = CGRectMake(textLeft, bodyY, textWidth, ceil(bodySize.height));
        mark.frame = CGRectMake(textLeft, bodyY + 2, markWidth, 20);
        y = CGRectGetMaxY(body.frame) + 22;
        tag += 10;
    }
    CGFloat closeRoom = 44 + 16 + 16 + safe.bottom;
    CGFloat height = MIN(y + closeRoom, self.bounds.size.height - safe.top - 24);
    /* the sheet is moved by a transform while it rises and leaves, and a frame written over that put it back on the screen for a frame */
    NoshiPlaceView(_panel, CGRectMake(floor((self.bounds.size.width - width) / 2), self.bounds.size.height - height, width, height));
    _panelBack.frame = _panel.bounds;
    /* the plate of the classic sheet is a layer of its own, sized by hand and taller than the panel, so the rounded lower corners stay under the screen */
    NoshiClassicFitPlate(_panel, 14);
    _close.frame = CGRectMake(16, height - 16 - safe.bottom - 44, width - 32, 44);
    _scroll.frame = CGRectMake(0, 0, width, height - closeRoom + 8);
    _scroll.contentSize = CGSizeMake(width, y);
}
@end

void NoshiShowRating(UIView *host, NoshiFullUser *user) {
    if (!host || !user.hasRating) return;
    /* not the window: before ios 8 a view in the window keeps the turn of the device, and the card lay on its side on an ipad held sideways */
    if ([host isKindOfClass:[UIWindow class]] && NoshiOverlayHost()) host = NoshiOverlayHost();
    NoshiRatingView *view = [[[NoshiRatingView alloc] initWithUser:user] autorelease];
    view.frame = host.bounds;
    [host addSubview:view];
    [view enter];
}

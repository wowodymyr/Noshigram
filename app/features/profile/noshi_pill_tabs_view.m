#import "noshi_pill_tabs_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_classic_chrome.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

#define TABS_HEIGHT 40.0

@interface NoshiPillTabsView () {
    NSMutableArray *_labels;
    UIScrollView *_scroll;
    UIView *_chosen;
    NSUInteger _selectedIndex;
    void (^_changeHandler)(NSUInteger);
}
@end

@implementation NoshiPillTabsView

@synthesize changeHandler = _changeHandler;
@synthesize selectedIndex = _selectedIndex;

- (id)initWithTitles:(NSArray *)titles {
    self = [super initWithFrame:CGRectMake(0, 0, 320, TABS_HEIGHT)];
    if (!self) return nil;
    /* the tabs are the plate of the menus with a key in the accent under the chosen one */
    NoshiClassicApplyMenuPlate(self, 10);
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_scroll];
    _chosen = [[UIImageView alloc] initWithImage:NoshiClassicKeyImage(NoshiClassicKeyAccent, NO)];
    [_scroll addSubview:_chosen];
    _labels = [[NSMutableArray alloc] init];
    for (NSString *title in titles) {
        UILabel *label = [[[UILabel alloc] init] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.textAlignment = NoshiTextAlignmentCenter;
        label.font = NoshiFontMedium(15);
        label.adjustsFontSizeToFitWidth = NO;
        label.text = title;
        label.isAccessibilityElement = YES;
        label.accessibilityTraits = UIAccessibilityTraitButton;
        [_scroll addSubview:label];
        [_labels addObject:label];
    }
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [_scroll addGestureRecognizer:tap];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_labels release];
    [_scroll release];
    [_chosen release];
    [_changeHandler release];
    [super dealloc];
}

- (void)refresh {
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        label.textColor = (i == _selectedIndex ? [UIColor whiteColor] : NoshiColorSecondary());
    }
    [self setNeedsLayout];
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (index >= _labels.count) return;
    _selectedIndex = index;
    [self refresh];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    NoshiClassicFitPlate(self, 0);
    /* the classic key sits 2 points inside the plate, so its radius of 8 stays concentric with the plate's 10; the modern pill is 4 inside */
    CGFloat inset = 2;
    CGFloat natural = 0;
    for (UILabel *label in _labels) natural += ceil(NoshiStringSize(label.text, NoshiFontMedium(15)).width) + 28;
    /* two tabs always fit the width, since a scroll of two keys leaves the chosen one cut off by the plate (the testers tab on a 320 point screen); more tabs scroll */
    BOOL fit = _labels.count <= 2 && natural > width && width > 0;
    CGFloat extra = _labels.count && natural < width ? (width - natural) / _labels.count : 0;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        CGFloat textWidth = ceil(NoshiStringSize(label.text, NoshiFontMedium(15)).width);
        CGFloat item = textWidth + 28 + extra;
        if (fit) {
            item = width / _labels.count;
            CGFloat room = item - 2 * inset - 12;
            /* the text shrinks to the key, down to 11 points, and is cut with an ellipsis below that */
            label.font = NoshiFontMedium(textWidth > room ? MAX(11, floor(15 * room / textWidth)) : 15);
        } else {
            label.font = NoshiFontMedium(15);
        }
        label.frame = CGRectMake(x + inset, 0, MAX(0, item - 2 * inset), height);
        if (i == _selectedIndex) _chosen.frame = CGRectMake(x + inset, inset, MAX(0, item - 2 * inset), height - 2 * inset);
        x += item;
    }
    _scroll.contentSize = CGSizeMake(MAX(width, x), height);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (!_labels.count || self.bounds.size.width <= 0) return;
    CGPoint point = [tap locationInView:_scroll];
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _labels.count; ++i) {
        UILabel *label = [_labels objectAtIndex:i];
        if (CGRectContainsPoint(CGRectInset(label.frame, -4, 0), point)) { index = i; break; }
    }
    if (index >= _labels.count || index == _selectedIndex) return;
    [self layoutIfNeeded];
    CGPoint from = _chosen.layer.presentationLayer ? [(CALayer *)_chosen.layer.presentationLayer position] : _chosen.center;
    self.selectedIndex = index;
    [self layoutIfNeeded];
    CGPoint target = _chosen.center;
    _chosen.center = from;
    NoshiAnimatePosition(_chosen, target, NOSHI_MOTION_ENTER);
    [_scroll scrollRectToVisible:CGRectInset([[_labels objectAtIndex:index] frame], -4, 0) animated:YES];
    if (_changeHandler) _changeHandler(index);
}

@end

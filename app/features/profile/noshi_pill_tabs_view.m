#import "noshi_pill_tabs_view.h"

#import "noshi_classic_chrome.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"

#define TABS_HEIGHT 40.0
#define SEGMENT_HEIGHT 29.0
#define SIDE 8.0

@interface NoshiPillTabsView () {
    UIScrollView *_scroll;
    UISegmentedControl *_segments;
    NSArray *_titles;
    void (^_changeHandler)(NSUInteger);
}
@end

@implementation NoshiPillTabsView

@synthesize changeHandler = _changeHandler;

- (id)initWithTitles:(NSArray *)titles {
    self = [super initWithFrame:CGRectMake(0, 0, 320, TABS_HEIGHT)];
    if (!self) return nil;
    /* the segments of the system on a strip of the list's own white, as the shared media of telegram for ios 4 had them; many tabs scroll sideways */
    self.backgroundColor = NoshiColorCard();
    _titles = [titles copy];
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.scrollsToTop = NO;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_scroll];
    _segments = [[UISegmentedControl alloc] initWithItems:titles];
    NoshiClassicStyleSegmented(_segments);
    _segments.selectedSegmentIndex = titles.count ? 0 : UISegmentedControlNoSegment;
    [_segments addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    [_scroll addSubview:_segments];
    return self;
}

- (void)dealloc {
    [_scroll release];
    [_segments release];
    [_titles release];
    [_changeHandler release];
    [super dealloc];
}

- (NSUInteger)selectedIndex {
    return _segments.selectedSegmentIndex == UISegmentedControlNoSegment ? 0 : (NSUInteger)_segments.selectedSegmentIndex;
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (index >= _titles.count) return;
    _segments.selectedSegmentIndex = (NSInteger)index;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    if (!_titles.count || width <= 0) return;
    /* the segments share the width while every title fits its share, and take the width of their titles otherwise */
    UIFont *font = [UIFont systemFontOfSize:13];
    CGFloat widest = 0;
    for (NSString *title in _titles) widest = MAX(widest, ceil(NoshiStringSize(title, font).width) + 20);
    CGFloat room = width - 2 * SIDE;
    BOOL share = widest * _titles.count <= room;
    CGFloat total = 0;
    for (NSUInteger i = 0; i < _titles.count; ++i) {
        CGFloat item = share ? floor(room / _titles.count) : ceil(NoshiStringSize([_titles objectAtIndex:i], font).width) + 24;
        [_segments setWidth:item forSegmentAtIndex:i];
        total += item;
    }
    _segments.frame = CGRectMake(SIDE, floor((height - SEGMENT_HEIGHT) / 2), total, SEGMENT_HEIGHT);
    _scroll.contentSize = CGSizeMake(total + 2 * SIDE, height);
}

- (void)changed {
    NSUInteger index = self.selectedIndex;
    if (_scroll.contentSize.width > _scroll.bounds.size.width) {
        /* the chosen segment comes into view with a little of its neighbours */
        CGFloat x = SIDE;
        for (NSUInteger i = 0; i < index; ++i) x += [_segments widthForSegmentAtIndex:i];
        [_scroll scrollRectToVisible:CGRectMake(x - 40, 0, [_segments widthForSegmentAtIndex:index] + 80, 1) animated:YES];
    }
    if (_changeHandler) _changeHandler(index);
}

@end

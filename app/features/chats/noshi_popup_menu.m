#import "noshi_popup_menu.h"

#import "noshi_alert.h"

@interface NoshiPopupMenu () {
    NSArray *_titles;
    void (^_handler)(NSUInteger index);
}
@end

@implementation NoshiPopupMenu

@synthesize bottomInset = _bottomInset;
@synthesize destructiveIndex = _destructiveIndex;

- (id)initWithTitles:(NSArray *)titles symbols:(const NoshiSymbol *)symbols handler:(void (^)(NSUInteger index))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    (void)symbols;
    _titles = [titles copy];
    _handler = [handler copy];
    _destructiveIndex = -1;
    return self;
}

- (void)dealloc {
    [_titles release];
    [_handler release];
    [super dealloc];
}

- (void)showInView:(UIView *)host anchor:(CGPoint)anchor {
    /* a small view at the anchor gives the popover of an ipad the place to point at */
    self.frame = CGRectMake(anchor.x - 1, anchor.y - 1, 2, 2);
    self.userInteractionEnabled = NO;
    [host addSubview:self];
    void (^handler)(NSUInteger) = [[_handler copy] autorelease];
    NoshiPopupMenu *menu = [self retain];
    NoshiChooseFromView(self, nil, _titles, _destructiveIndex, ^(NSInteger index) {
        [menu removeFromSuperview];
        [menu release];
        if (index >= 0 && handler) handler((NSUInteger)index);
    });
}

- (void)dismiss {
    [self removeFromSuperview];
}

@end

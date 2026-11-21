#import "noshi_slider.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

@implementation NoshiSlider
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    /* the stock slider of the classic theme keeps its own look, and only the filled part of the track takes the accent, which it showed in the system blue */
    else self.minimumTrackTintColor = NoshiColorAccent();
    return self;
}

- (void)setTrackColor:(UIColor *)color {
}

/* the track runs the full width and the thumb travels inside it by its own radius: with the track inset to the thumb's centre the filled part has no
   width at value 0, and the stretched cap image shows there as a thin bar as tall as the slider */
- (CGRect)trackRectForBounds:(CGRect)bounds {
    return [super trackRectForBounds:bounds];
}

- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value {
    return [super thumbRectForBounds:bounds trackRect:rect value:value];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event];
}
@end

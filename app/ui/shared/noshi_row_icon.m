#import "noshi_row_icon.h"

#import <QuartzCore/QuartzCore.h>

#define ICON_SIDE 32.0

static UIImageView *NoshiIconSquare(UIImage *glyph, UIColor *color) {
    UIImageView *view = [[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, ICON_SIDE, ICON_SIDE)] autorelease];
    view.backgroundColor = color;
    view.layer.cornerRadius = 8;
    view.contentMode = UIViewContentModeCenter;
    view.image = glyph;
    return view;
}

UIImageView *NoshiRowIcon(NoshiSymbol symbol, UIColor *color) {
    return NoshiIconSquare(NoshiSymbolImage(symbol, 20, [UIColor whiteColor]), color);
}

#import "noshi_customization_views.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_view.h"
#import "noshi_chat_settings.h"
#import "noshi_dialog.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_shape.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_wallpaper.h"

#define CLASSIC_BAR 44.0
#define CLASSIC_STRIP 76.0
#define CLASSIC_ROW 40.0

/* the two rows of the preview, drawn with the separator the person chose */
@interface NoshiClassicRowsView : UIView
@end

@implementation NoshiClassicRowsView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) self.contentMode = UIViewContentModeRedraw;
    return self;
}
- (void)drawRect:(CGRect)dirty {
    (void)dirty;
    CGFloat width = self.bounds.size.width, pixel = 1.0 / NoshiScreenScale();
    [NoshiColorCard() setFill];
    UIRectFill(self.bounds);
    UIFont *font = [UIFont boldSystemFontOfSize:15];
    [NoshiColorTitle() set];
    [NSLocalizedString(@"custom.classic.row1", nil) drawAtPoint:CGPointMake(16, 11) withFont:font];
    [NSLocalizedString(@"custom.classic.row2", nil) drawAtPoint:CGPointMake(16, CLASSIC_ROW + 11) withFont:font];
    NSInteger style = NoshiClassicSeparators();
    if (style == 2) return;
    BOOL dark = NoshiThemeIsDark();
    CGFloat y = CLASSIC_ROW - pixel;
    [(dark ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor colorWithWhite:0 alpha:0.2]) setFill];
    UIRectFill(CGRectMake(style == 1 ? 0 : 10, y, width - (style == 1 ? 0 : 10), pixel));
    /* the etched line has a lit line under the dark one */
    if (style == 1) {
        [(dark ? [UIColor colorWithWhite:1 alpha:0.06] : [UIColor colorWithWhite:1 alpha:0.9]) setFill];
        UIRectFill(CGRectMake(0, y + pixel, width, pixel));
    }
}
@end

@interface NoshiClassicPreviewView () {
    UIImageView *_bar;
    UILabel *_title;
    UIView *_strip;
    UIImageView *_button;
    UILabel *_buttonText;
    NoshiAvatarView *_avatar;
    NoshiClassicRowsView *_rows;
}
@end

@implementation NoshiClassicPreviewView

+ (CGFloat)height {
    return CLASSIC_BAR + CLASSIC_STRIP + 2 * CLASSIC_ROW;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    _strip = [[UIView alloc] init];
    [self addSubview:_strip];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.initials = @"s";
    _avatar.seed = 3;
    [_strip addSubview:_avatar];
    _button = [[UIImageView alloc] init];
    [_strip addSubview:_button];
    _buttonText = [[UILabel alloc] init];
    _buttonText.backgroundColor = [UIColor clearColor];
    _buttonText.textColor = [UIColor whiteColor];
    _buttonText.font = [UIFont boldSystemFontOfSize:14];
    _buttonText.textAlignment = NoshiTextAlignmentCenter;
    _buttonText.text = NSLocalizedString(@"chat.send", nil);
    [_button addSubview:_buttonText];
    _rows = [[NoshiClassicRowsView alloc] init];
    [self addSubview:_rows];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = [UIColor whiteColor];
    _title.font = [UIFont boldSystemFontOfSize:18];
    _title.textAlignment = NoshiTextAlignmentCenter;
    _title.text = @"sqmrak";
    _title.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    _title.shadowOffset = CGSizeMake(0, -1);
    [self addSubview:_title];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_bar release];
    [_title release];
    [_strip release];
    [_button release];
    [_buttonText release];
    [_avatar release];
    [_rows release];
    [super dealloc];
}

- (void)setPicture:(UIImage *)picture {
    [_avatar showImage:picture];
}

- (void)refresh {
    [_bar removeFromSuperview];
    [_bar release];
    _bar = [NoshiClassicStripBackdrop() retain];
    [self insertSubview:_bar atIndex:0];
    _strip.backgroundColor = NoshiClassicLinenColor(NoshiThemeIsDark());
    _button.image = NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, NO);
    [_avatar setNeedsDisplay];
    [_avatar setNeedsLayout];
    [_rows setNeedsDisplay];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _bar.frame = CGRectMake(0, 0, width, CLASSIC_BAR);
    _title.frame = CGRectMake(40, 0, width - 80, CLASSIC_BAR);
    _strip.frame = CGRectMake(0, CLASSIC_BAR, width, CLASSIC_STRIP);
    _avatar.frame = CGRectMake(16, (CLASSIC_STRIP - 48) / 2, 48, 48);
    _button.frame = CGRectMake(width - 16 - 90, (CLASSIC_STRIP - 34) / 2, 90, 34);
    _buttonText.frame = _button.bounds;
    _rows.frame = CGRectMake(0, CLASSIC_BAR + CLASSIC_STRIP, width, 2 * CLASSIC_ROW);
}

@end

#import "noshi_selection_bar.h"

#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define HEIGHT 48.0
#define BUTTON_WIDTH 40.0
#define CANCEL_WIDTH 78.0

@interface NoshiSelectionBar () {
    UIButton *_cancel;
    UILabel *_count;
    UIButton *_forward;
    UIButton *_copy;
    UIButton *_delete;
    UIButton *_range;
    UIView *_line;
    UIImageView *_backdrop;
    void (^_cancelHandler)(void);
    void (^_forwardHandler)(void);
    void (^_copyHandler)(void);
    void (^_deleteHandler)(void);
    void (^_rangeHandler)(void);
}
@end

@implementation NoshiSelectionBar

@synthesize cancelHandler = _cancelHandler;
@synthesize forwardHandler = _forwardHandler;
@synthesize copyHandler = _copyHandler;
@synthesize deleteHandler = _deleteHandler;
@synthesize rangeHandler = _rangeHandler;

+ (CGFloat)height {
    return HEIGHT;
}

- (UIButton *)iconButton:(NoshiSymbol)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    BOOL classic = NoshiThemeIsClassic();
    [button setImage:NoshiSymbolImage(symbol, 24, classic ? [UIColor whiteColor] : NoshiColorAccent()) forState:UIControlStateNormal];
    [button setImage:NoshiSymbolImage(symbol, 24, classic ? [UIColor colorWithWhite:1 alpha:0.35] : NoshiColorMuted()) forState:UIControlStateDisabled];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = label;
    [self addSubview:button];
    return button;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BOOL classic = NoshiThemeIsClassic();
    if (classic) {
        _backdrop = [NoshiClassicStripBackdrop() retain];
        [self addSubview:_backdrop];
    } else {
        self.backgroundColor = NoshiColorBar();
    }
    _cancel = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_cancel setTitle:NSLocalizedString(@"chat.msg.cancel", nil) forState:UIControlStateNormal];
    [_cancel setTitleColor:classic ? [UIColor whiteColor] : NoshiColorAccent() forState:UIControlStateNormal];
    _cancel.titleLabel.font = classic ? [UIFont boldSystemFontOfSize:16] : NoshiFontMedium(16);
    if (classic) {
        [_cancel setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, NO) forState:UIControlStateNormal];
        [_cancel setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, YES) forState:UIControlStateHighlighted];
    }
    [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_cancel];
    _count = [[UILabel alloc] init];
    _count.backgroundColor = [UIColor clearColor];
    _count.textColor = classic ? [UIColor whiteColor] : NoshiColorTitle();
    _count.font = classic ? [UIFont boldSystemFontOfSize:15] : NoshiFontSemibold(15);
    if (classic) {
        _count.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        _count.shadowOffset = CGSizeMake(0, -1);
    }
    _count.textAlignment = NoshiTextAlignmentCenter;
    _count.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_count];
    _forward = [[self iconButton:NoshiSymbolForward label:NSLocalizedString(@"chat.msg.forward", nil) action:@selector(forwardTapped)] retain];
    _copy = [[self iconButton:NoshiSymbolCopy label:NSLocalizedString(@"chat.msg.copy", nil) action:@selector(copyTapped)] retain];
    _delete = [[self iconButton:NoshiSymbolTrash label:NSLocalizedString(@"chat.msg.delete", nil) action:@selector(deleteTapped)] retain];
    _range = [[self iconButton:NoshiSymbolCheckDouble label:NSLocalizedString(@"chat.select.range", nil) action:@selector(rangeTapped)] retain];
    _line = [[UIView alloc] init];
    _line.backgroundColor = classic ? [UIColor colorWithWhite:0 alpha:0.55] : NoshiColorHairline();
    [self addSubview:_line];
    return self;
}

- (void)dealloc {
    [_cancel release];
    [_count release];
    [_forward release];
    [_copy release];
    [_delete release];
    [_range release];
    [_line release];
    [_backdrop release];
    [_cancelHandler release];
    [_forwardHandler release];
    [_copyHandler release];
    [_deleteHandler release];
    [_rangeHandler release];
    [super dealloc];
}

- (void)setCount:(NSUInteger)count forward:(BOOL)forward copy:(BOOL)copy delete:(BOOL)delete range:(BOOL)range {
    _count.text = [NSString stringWithFormat:NSLocalizedString(@"chat.select.count", nil), (long)count];
    _forward.enabled = forward;
    _copy.enabled = copy;
    _delete.enabled = delete;
    _range.enabled = range;
}

- (void)cancelTapped { if (_cancelHandler) _cancelHandler(); }
- (void)forwardTapped { if (_forwardHandler) _forwardHandler(); }
- (void)copyTapped { if (_copyHandler) _copyHandler(); }
- (void)deleteTapped { if (_deleteHandler) _deleteHandler(); }
- (void)rangeTapped { if (_rangeHandler) _rangeHandler(); }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* the bar may be taller than its content by the bottom safe area, which the buttons stay above */
    CGFloat row = MIN(HEIGHT, size.height);
    _backdrop.frame = self.bounds;
    _line.frame = CGRectMake(0, 0, size.width, 1.0 / NoshiScreenScale());
    _cancel.frame = NoshiThemeIsClassic() ? CGRectMake(8, (row - 30) / 2, CANCEL_WIDTH - 8, 30) : CGRectMake(4, 0, CANCEL_WIDTH, row);
    CGFloat right = size.width - 4;
    _delete.frame = CGRectMake(right - BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _copy.frame = CGRectMake(right - 2 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _forward.frame = CGRectMake(right - 3 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    _range.frame = CGRectMake(right - 4 * BUTTON_WIDTH, 0, BUTTON_WIDTH, row);
    CGFloat from = 4 + CANCEL_WIDTH;
    _count.frame = CGRectMake(from, 0, MAX(0, right - 4 * BUTTON_WIDTH - from), row);
}

@end

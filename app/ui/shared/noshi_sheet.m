#import "noshi_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_classic_chrome.h"
#import "noshi_animation.h"
#import "noshi_dismiss_pan.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define CARD_RADIUS 14.0
#define ROW_HEIGHT 54.0
#define GAP 8.0
#define SIDE 10.0
#define TEXT_PAD 18.0

@interface NoshiSheet () {
    UIView *_dim;
    UIView *_stack;
    void (^_handler)(NSUInteger index);
    BOOL _closing;
    CGFloat _bottomInset;
}
@end

@implementation NoshiSheet

- (void)dealloc {
    [_dim release];
    [_stack release];
    [_handler release];
    [super dealloc];
}

#define CLASSIC_RADIUS 10.0

static UIView *NoshiSheetCard(void) {
    UIView *card = [[[UIView alloc] init] autorelease];
    /* the classic card is a plate of polished metal, which is put on once the card has its size, and its shadow must not be clipped */
    return card;
}

static UIColor *NoshiSheetText(void) { return NoshiClassicMenuTextColor(); }

static UILabel *NoshiSheetLabel(UIFont *font, UIColor *color) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.textAlignment = NoshiTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title color:(UIColor *)color font:(UIFont *)font tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.titleLabel.font = font;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.tag = tag;
    [button addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

- (void)rowDown:(UIButton *)row {
    /* the cancel key is a picture and shows its own pressed one */
    if (row.tag >= 0) row.backgroundColor = NoshiClassicMenuPressColor();
}
- (void)rowUp:(UIButton *)row { row.backgroundColor = [UIColor clearColor]; }

+ (void)presentInView:(UIView *)host title:(NSString *)title message:(NSString *)message options:(NSArray *)options destructive:(NSIndexSet *)destructive
          cancelTitle:(NSString *)cancelTitle handler:(void (^)(NSUInteger))handler {
    /* a view put in the window itself keeps the turn of the device before ios 8, and on an ipad held sideways the sheet lay on its side: the screen on top turns with the interface */
    if ([host isKindOfClass:[UIWindow class]] && NoshiOverlayHost()) host = NoshiOverlayHost();
    NoshiSheet *sheet = [[[NoshiSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sheet->_handler = [handler copy];
    /* the sheet is built before it is in the window, so the home indicator is read from the host */
    sheet->_bottomInset = NoshiSafeInsets(host).bottom;
    [sheet buildWithTitle:title message:message options:options destructive:destructive cancelTitle:cancelTitle];
    [host addSubview:sheet];
    [sheet enter];
}

- (void)buildWithTitle:(NSString *)title message:(NSString *)message options:(NSArray *)options destructive:(NSIndexSet *)destructive cancelTitle:(NSString *)cancelTitle {
    CGSize size = self.bounds.size;
    CGFloat width = MIN(size.width - 2 * SIDE, 420);
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancel)] autorelease]];
    [self addSubview:_dim];

    UIView *card = NoshiSheetCard();
    CGFloat y = 0;
    CGFloat textWidth = width - 2 * TEXT_PAD;
    if (title.length) {
        UILabel *label = NoshiSheetLabel([UIFont boldSystemFontOfSize:16], NoshiSheetText());
        label.text = title;
        CGSize fit = [label sizeThatFits:CGSizeMake(textWidth, 200)];
        label.frame = CGRectMake(TEXT_PAD, y + 16, textWidth, fit.height);
        [card addSubview:label];
        y += 16 + fit.height + (message.length ? 4 : 12);
    }
    if (message.length) {
        UILabel *label = NoshiSheetLabel([UIFont systemFontOfSize:14], [NoshiClassicMenuTextColor() colorWithAlphaComponent:0.7]);
        label.text = message;
        CGSize fit = [label sizeThatFits:CGSizeMake(textWidth, 300)];
        label.frame = CGRectMake(TEXT_PAD, y + (title.length ? 0 : 16), textWidth, fit.height);
        [card addSubview:label];
        y += (title.length ? 0 : 16) + fit.height + 14;
    }
    CGFloat head = y;
    /* a long list scrolls inside the card, which keeps its room above the cancel card */
    CGFloat cancelHeight = ROW_HEIGHT;
    CGFloat limit = MAX(ROW_HEIGHT * 2, size.height - 120 - cancelHeight - GAP);
    CGFloat rows = ROW_HEIGHT * (CGFloat)options.count;
    CGFloat cardHeight = MIN(head + rows, limit);
    UIScrollView *list = [[[UIScrollView alloc] initWithFrame:CGRectMake(0, head, width, cardHeight - head)] autorelease];
    list.contentSize = CGSizeMake(width, rows);
    list.showsVerticalScrollIndicator = NO;
    list.bounces = rows > list.bounds.size.height;
    /* the bottom rows follow the round corners of the plate under them */
    list.layer.cornerRadius = CLASSIC_RADIUS;
    list.layer.masksToBounds = YES;
    for (NSUInteger i = 0; i < options.count; ++i) {
        UIColor *color = [destructive containsIndex:i] ? (NoshiClassicMenuRedColor()) : NoshiSheetText();
        UIButton *button = [self buttonWithTitle:[options objectAtIndex:i] color:color font:[UIFont boldSystemFontOfSize:17] tag:(NSInteger)i];
        button.frame = CGRectMake(0, ROW_HEIGHT * (CGFloat)i, width, ROW_HEIGHT);
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        /* a dark groove over a lit line, the way the old menus split their rows */
        BOOL charcoal = NoshiThemeIsDark();
        UIView *groove = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)] autorelease];
        groove.backgroundColor = [UIColor colorWithWhite:0 alpha:charcoal ? 0.45 : 0.14];
        groove.userInteractionEnabled = NO;
        [button addSubview:groove];
        UIView *lit = [[[UIView alloc] initWithFrame:CGRectMake(0, 1, width, 1)] autorelease];
        lit.backgroundColor = [UIColor colorWithWhite:1 alpha:charcoal ? 0.08 : 0.85];
        lit.userInteractionEnabled = NO;
        [button addSubview:lit];
        [list addSubview:button];
    }
    [card addSubview:list];
    card.frame = CGRectMake(0, 0, width, cardHeight);
    NoshiClassicApplyMenuPlate(card, CLASSIC_RADIUS);

    UIView *cancel = NoshiSheetCard();
    cancel.frame = CGRectMake(0, cardHeight + GAP, width, cancelHeight);
    UIButton *cancelButton = [self buttonWithTitle:cancelTitle color:[UIColor whiteColor] font:[UIFont boldSystemFontOfSize:17] tag:-1];
    cancelButton.frame = cancel.bounds;
    /* the cancel key is a glossy slate key of its own, apart from the plate, as on the old action sheets */
    [cancelButton setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, NO) forState:UIControlStateNormal];
    [cancelButton setBackgroundImage:NoshiClassicGlossButtonImage(NoshiClassicGlossSlate, YES) forState:UIControlStateHighlighted];
    cancelButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [cancelButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
    [cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [cancel addSubview:cancelButton];

    CGFloat total = cardHeight + GAP + cancelHeight;
    _stack = [[UIView alloc] initWithFrame:CGRectMake((size.width - width) / 2, size.height - total - MAX(GAP + 4, _bottomInset + GAP), width, total)];
    _stack.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    NoshiAddDismissPan(_stack, self, @selector(cancel));
    [_stack addSubview:card];
    [_stack addSubview:cancel];
    [self addSubview:_stack];
}

- (void)enter {
    CGFloat shift = _stack.frame.size.height + 40;
    _stack.transform = CGAffineTransformMakeTranslation(0, shift);
    /* the two cards clip their rows with rounded corners, which is drawn off screen on every frame of the slide; as a bitmap it slides as a picture */
    NoshiCacheForMotion(_stack);
    UIView *stack = _stack;
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0.42, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(_stack, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), ^(BOOL finished) {
        (void)finished;
        NoshiUncacheAfterMotion(stack);
    });
}

- (void)leaveThen:(void (^)(void))after {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    void (^next)(void) = [after copy];
    [self retain];
    NoshiCacheForMotion(_stack);
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_stack, CGAffineTransformMakeTranslation(0, _stack.frame.size.height + 40), 1, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
        [self release];
    });
}

- (void)cancel {
    [self leaveThen:nil];
}

- (void)picked:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    void (^handler)(NSUInteger) = [_handler retain];
    [self leaveThen:^{
        if (handler) handler(index);
        [handler release];
    }];
}

@end

void NoshiConfirmAction(UIViewController *host, NSString *message, NSString *actionTitle, void (^confirmed)(void)) {
    /* the classic style keeps the system alert it always had */
    NoshiConfirm(nil, message, actionTitle, confirmed);
}

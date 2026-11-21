#import "noshi_emoji_label.h"
#import "noshi_alert_view.h"
#import "noshi_gift_screen.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_bar_button.h"
#import "noshi_classic_chrome.h"
#import "noshi_platform.h"
#import "noshi_split_controller.h"
#import "noshi_theme.h"

#define BAR_HEIGHT 44.0

static NSString *NoshiGroupedNumber(long long value) {
    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter stringFromNumber:[NSNumber numberWithLongLong:value]];
}

NSString *NoshiStarsText(long long stars) {
    NSString *language = [[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : @"en";
    long long ones = stars % 10, tens = stars % 100;
    NSString *key;
    if ([language hasPrefix:@"ru"]) {
        if (ones == 1 && tens != 11) key = @"gifts.stars.one";
        else if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) key = @"gifts.stars.few";
        else key = @"gifts.stars.many";
    } else {
        key = stars == 1 ? @"gifts.stars.one" : @"gifts.stars.many";
    }
    return [NSString stringWithFormat:NSLocalizedString(key, nil), NoshiGroupedNumber(stars)];
}

UIImage *NoshiStarsImage(NSString *prefix, long long stars, UIFont *font, UIColor *color) {
    NSString *count = NoshiGroupedNumber(stars);
    NSString *lead = prefix.length ? [prefix stringByAppendingString:@" "] : @"";
    CGSize leadSize = lead.length ? [lead sizeWithFont:font] : CGSizeZero;
    CGSize countSize = [count sizeWithFont:font];
    CGFloat side = ceil(font.pointSize * 1.05);
    UIImage *star = NoshiStarsGlyph(side);
    CGFloat gap = 3;
    CGFloat width = ceil(leadSize.width + side + gap + countSize.width);
    CGFloat height = ceil(MAX(side, countSize.height));
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0);
    [color set];
    if (lead.length) [lead drawAtPoint:CGPointMake(0, (height - leadSize.height) / 2) withFont:font];
    [star drawInRect:CGRectMake(leadSize.width, (height - side) / 2, side, side)];
    [count drawAtPoint:CGPointMake(leadSize.width + side + gap, (height - countSize.height) / 2) withFont:font];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

NSString *NoshiGiftErrorText(NSString *errorName) {
    if ([errorName isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([errorName isEqualToString:@"BALANCE_LOW"] || [errorName isEqualToString:@"BALANCE_TOO_LOW"]) return NSLocalizedString(@"gifts.error.balance", nil);
    if ([errorName isEqualToString:@"STARS_UNSUPPORTED"]) return NSLocalizedString(@"gifts.error.unsupported", nil);
    if ([errorName isEqualToString:@"STARGIFT_USAGE_LIMITED"]) return NSLocalizedString(@"gifts.error.limited", nil);
    if ([errorName isEqualToString:@"USER_PRIVACY_RESTRICTED"] || [errorName isEqualToString:@"PRIVACY_PREMIUM_REQUIRED"]) return NSLocalizedString(@"gifts.error.privacy", nil);
    if ([errorName isEqualToString:@"PEER_ID_INVALID"] || [errorName isEqualToString:@"USER_BOT"]) return NSLocalizedString(@"gifts.error.peer", nil);
    if ([errorName isEqualToString:@"JOIN_WEBVIEW"]) return NSLocalizedString(@"channel.join.webview", nil);
    if ([errorName isEqualToString:@"CHANNELS_TOO_MUCH"]) return NSLocalizedString(@"channel.join.toomuch", nil);
    if ([errorName isEqualToString:@"USER_BANNED_IN_CHANNEL"] || [errorName isEqualToString:@"CHANNEL_PRIVATE"]) return NSLocalizedString(@"channel.join.denied", nil);
    if ([errorName isEqualToString:@"NOT_REPORTED"]) return NSLocalizedString(@"report.refused", nil);
    if ([errorName isEqualToString:@"SHARE_FILE_UNREADABLE"]) return NSLocalizedString(@"share.error.unreadable", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
}

void NoshiGiftAlert(NSString *title, NSString *message) {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

@interface NoshiGiftScreen () {
    UIView *_header;
    UIView *_headerLine;
    NoshiBarButton *_back;
    NoshiEmojiLabel *_titleLabel;
    NoshiBarButton *_action;
    UIButton *_actionIcon;
    NoshiSymbol _actionSymbol;
    NSString *_actionLabel;
    NSString *_screenTitle;
    NSString *_classicTitleText;
    NSArray *_classicTitleEntities;
    NSString *_actionTitle;
    void (^_actionHandler)(void);
    BOOL _clearBar;
    UIColor *_barTint;
    BOOL _barShaded;
    BOOL _barOverPhoto;
    BOOL _symbolAction;
}
@end

@implementation NoshiGiftScreen

@synthesize session = _session;
@synthesize avatars = _avatars;
@synthesize media = _media;
@synthesize screenTitle = _screenTitle;
@synthesize clearBar = _clearBar;
@synthesize barTint = _barTint;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_screenTitle release];
    [_classicTitleText release];
    [_classicTitleEntities release];
    [_actionTitle release];
    [_actionHandler release];
    [_header release];
    [_headerLine release];
    [_back release];
    [_barTint release];
    [_titleLabel release];
    [_action release];
    [_actionIcon release];
    [_actionLabel release];
    [super dealloc];
}

/* the look of the bar for the tint and the shade it is in; set inside an animation block it moves there */
- (void)refreshBarLook {
    if (!_header) return;
    if (_barOverPhoto) {
        _header.backgroundColor = [UIColor clearColor];
        _headerLine.hidden = YES;
        _titleLabel.alpha = 0;
        _back.inkColor = [UIColor whiteColor];
        return;
    }
    BOOL tinted = _barTint != nil;
    UIColor *plain = _clearBar ? [UIColor clearColor] : NoshiColorBar();
    _header.backgroundColor = tinted ? (_barShaded ? _barTint : [UIColor clearColor]) : plain;
    _headerLine.hidden = _clearBar || tinted;
    _titleLabel.alpha = tinted && !_barShaded ? 0 : 1;
    _titleLabel.textColor = tinted ? [UIColor whiteColor] : NoshiColorTitle();
    /* the arrow has the ink of the dots at the other end of the bar, whatever picture a clear bar lies over */
    _back.inkColor = tinted ? [UIColor whiteColor] : (_clearBar ? NoshiColorTitle() : nil);
}

- (void)setBarTint:(UIColor *)tint {
    if (tint == _barTint || (tint && [tint isEqual:_barTint])) return;
    [_barTint release];
    _barTint = [tint retain];
}

- (void)setBarOverPhoto:(BOOL)over {
    if (over == _barOverPhoto) return;
    _barOverPhoto = over;
}

- (void)setBarShaded:(BOOL)shaded animated:(BOOL)animated {
    if (shaded == _barShaded) return;
    _barShaded = shaded;
}

- (void)setScreenTitle:(NSString *)title {
    if (title == _screenTitle) return;
    [_screenTitle release];
    _screenTitle = [title copy];
    self.title = _screenTitle;
    _titleLabel.text = _screenTitle;
    [self showClassicTitle];
}

/* the name in the classic bar is drawn by the app's own label: the system title shows boxes for the letters of a styled nick and has no emoji of the app. the bar centers the view
   between its buttons, so on a phone it is as wide as what is left beside them */
- (void)showClassicTitle {
    if (!self.isViewLoaded) return;
    NSString *text = _classicTitleText.length ? _classicTitleText : _screenTitle;
    UIView *title = nil;
    if (text.length) {
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat width = NoshiIsPad() ? 420 : MIN(190, MIN(screen.width, screen.height) - 2 * 92);
        title = NoshiClassicTitleViewWithStatusWidth(text, nil, 0, width);
        if (_classicTitleText.length) {
            for (UIView *view in title.subviews) {
                if (![view isKindOfClass:[NoshiEmojiLabel class]]) continue;
                NoshiEmojiLabel *label = (NoshiEmojiLabel *)view;
                label.entities = _classicTitleEntities;
                /* the name in the body keeps every character it has a font for, so the title does not cut them either */
                label.dropsUndrawable = NO;
            }
        }
    }
    self.navigationItem.titleView = title;
}

- (void)setClassicTitleText:(NSString *)text entities:(NSArray *)entities {
    [_classicTitleText release];
    _classicTitleText = [text copy];
    [_classicTitleEntities release];
    _classicTitleEntities = [entities copy];
    [self showClassicTitle];
}

- (void)refreshClassicTitle {
    for (UIView *view in self.navigationItem.titleView.subviews) [view setNeedsDisplay];
}

- (void)setActionTitle:(NSString *)title handler:(void (^)(void))handler {
    /* the classic load path passes these ivars back into the setter */
    NSString *copiedTitle = [title copy];
    void (^copiedHandler)(void) = [handler copy];
    [_actionTitle release];
    _actionTitle = copiedTitle;
    [_actionHandler release];
    _actionHandler = copiedHandler;
    _symbolAction = NO;
    self.navigationItem.rightBarButtonItem = title ? [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered
                                                                                      target:self action:@selector(actionTapped)] autorelease] : nil;
}

- (void)setActionSymbol:(NoshiSymbol)symbol label:(NSString *)label handler:(void (^)(void))handler {
    void (^copiedHandler)(void) = [handler copy];
    NSString *copiedLabel = [label copy];
    [_actionHandler release];
    _actionHandler = copiedHandler;
    _symbolAction = handler != nil;
    [_actionTitle release]; _actionTitle = nil;
    _action.hidden = YES;
    [_actionLabel release];
    _actionLabel = copiedLabel;
    _actionSymbol = symbol;
    self.navigationItem.rightBarButtonItem = handler ? [[[UIBarButtonItem alloc] initWithImage:NoshiSymbolImage(symbol, 22, [UIColor whiteColor])
                                                                                          style:UIBarButtonItemStyleBordered target:self
                                                                                         action:@selector(actionTapped)] autorelease] : nil;
    self.navigationItem.rightBarButtonItem.accessibilityLabel = label;
}

/* the bar is built in loadView, so a symbol set before it waits there */
- (void)refreshActionIcon {
    if (!_header) return;
    if (!_symbolAction || !_actionHandler) {
        [_actionIcon removeFromSuperview];
        [_actionIcon release];
        _actionIcon = nil;
        return;
    }
    if (!_actionIcon) {
        _actionIcon = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _actionIcon.contentMode = UIViewContentModeCenter;
        [_actionIcon addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_actionIcon];
    }
    [_actionIcon setImage:NoshiSymbolImage(_actionSymbol, 24, _barOverPhoto || (_barTint && !_barShaded) ? [UIColor whiteColor] : NoshiColorTitle()) forState:UIControlStateNormal];
    _actionIcon.accessibilityLabel = _actionLabel;
    [self.view setNeedsLayout];
}

- (CGPoint)actionSymbolAnchor {
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    /* the classic style has its bar above the screen, so its insets already end under it; the modern bar is drawn inside */
    return CGPointMake(self.view.bounds.size.width - insets.right - 8, insets.top + 4);
}

- (void)actionTapped {
    if (_actionHandler) _actionHandler();
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    [self buildBodyInView:root];
    self.title = _screenTitle;
    [self showClassicTitle];
    if (_actionTitle) [self setActionTitle:_actionTitle handler:_actionHandler];
}

- (void)buildBodyInView:(UIView *)root {
    (void)root;
}

- (void)layoutBody:(CGRect)body {
    (void)body;
}

- (CGRect)bodyFrame {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    CGFloat top = insets.top;
    /* the body stands in one column; a layoutBody: places what is not inside its own scroll view or grid from the body's origin, not from zero */
    CGRect column = NoshiContentColumn(size, insets, NOSHI_COLUMN_PAGE);
    return CGRectMake(column.origin.x, top, column.size.width, size.height - top);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutBody:[self bodyFrame]];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return NoshiAllowsOrientation(orientation); }
- (BOOL)shouldAutorotate { return YES; }

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return NoshiOrientationMask(); }
#pragma clang diagnostic pop

@end

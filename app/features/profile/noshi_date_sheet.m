#import "noshi_date_sheet.h"

#import "noshi_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_dismiss_pan.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

#define PANEL_HEIGHT 330.0

@interface NoshiDateSheet () {
    UIView *_dim;
    UIView *_panel;
    UIDatePicker *_picker;
    UISwitch *_hideYear;
    UILabel *_hideLabel;
    UIButton *_cancel;
    UIButton *_remove;
    UIButton *_done;
    BOOL _canRemove;
    void (^_doneHandler)(int32_t, int32_t, int32_t);
    void (^_removeHandler)(void);
}
@end

@implementation NoshiDateSheet

@synthesize doneHandler = _doneHandler;
@synthesize removeHandler = _removeHandler;
@synthesize canRemove = _canRemove;

static UIButton *NoshiSheetButton(NSString *title, UIColor *color, BOOL bold) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.titleLabel.font = bold ? NoshiFontSemibold(17) : NoshiFontRegular(17);
    return button;
}

- (id)initWithDay:(int32_t)day month:(int32_t)month year:(int32_t)year {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [self addSubview:_dim];
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelTapped)] autorelease]];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = NoshiColorCard();
    [self addSubview:_panel];
    NoshiAddDismissPan(_panel, self, @selector(cancelTapped));
    _picker = [[UIDatePicker alloc] init];
    _picker.datePickerMode = UIDatePickerModeDate;
    _picker.maximumDate = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
    parts.day = day > 0 ? day : 1;
    parts.month = month > 0 ? month : 1;
    parts.year = year > 0 ? year : 2000;
    NSDate *start = [calendar dateFromComponents:parts];
    if (start) _picker.date = start;
    [_panel addSubview:_picker];
    _hideLabel = [[UILabel alloc] init];
    _hideLabel.backgroundColor = [UIColor clearColor];
    _hideLabel.font = NoshiFontRegular(16);
    _hideLabel.textColor = NoshiColorTitle();
    _hideLabel.text = NSLocalizedString(@"profile.birthday.noyear", nil);
    [_panel addSubview:_hideLabel];
    _hideYear = [[UISwitch alloc] init];
    _hideYear.on = year == 0;
    [_panel addSubview:_hideYear];
    _cancel = [NoshiSheetButton(NSLocalizedString(@"picker.cancel", nil), NoshiColorAccent(), NO) retain];
    [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_cancel];
    _remove = [NoshiSheetButton(NSLocalizedString(@"profile.birthday.remove", nil), NoshiColorBadgeRed(), NO) retain];
    [_remove addTarget:self action:@selector(removeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_remove];
    _done = [NoshiSheetButton(NSLocalizedString(@"profile.edit.save", nil), NoshiColorAccent(), YES) retain];
    [_done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:_done];
    return self;
}

- (void)dealloc {
    [_dim release];
    [_panel release];
    [_picker release];
    [_hideYear release];
    [_hideLabel release];
    [_cancel release];
    [_remove release];
    [_done release];
    [_doneHandler release];
    [_removeHandler release];
    [super dealloc];
}

- (void)setCanRemove:(BOOL)canRemove {
    _canRemove = canRemove;
    _remove.hidden = !canRemove;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets safe = NoshiSafeInsets(self);
    /* the panel stands in a column of a page on a tablet and clear of the notch in landscape, and runs under the home indicator with its controls above it */
    CGRect column = NoshiContentColumn(size, safe, NOSHI_COLUMN_PAGE);
    CGFloat width = column.size.width;
    _dim.frame = self.bounds;
    CGFloat height = PANEL_HEIGHT + safe.bottom;
    /* frame changes under a transform shift the panel while ios 6 lays out the closing sheet */
    _panel.bounds = CGRectMake(0, 0, width, height);
    _panel.center = CGPointMake(column.origin.x + width / 2, size.height - height / 2);
    _cancel.frame = CGRectMake(8, 6, 90, 44);
    _remove.frame = CGRectMake((width - 110) / 2, 6, 110, 44);
    _remove.hidden = !_canRemove;
    _done.frame = CGRectMake(width - 98, 6, 90, 44);
    _picker.frame = CGRectMake(0, 54, width, 216);
    _hideLabel.frame = CGRectMake(16, 276, width - 100, 44);
    _hideYear.center = CGPointMake(width - 16 - _hideYear.bounds.size.width / 2, 298);
}

- (void)showInView:(UIView *)host {
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    _panel.transform = CGAffineTransformMakeTranslation(0, _panel.bounds.size.height);
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0.4, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(_panel, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}

- (void)leaveThen:(void (^)(void))after {
    void (^next)(void) = [after copy];
    self.userInteractionEnabled = NO;
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_panel, CGAffineTransformMakeTranslation(0, _panel.bounds.size.height), 1, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (next) next();
        [next release];
    });
}

- (void)cancelTapped {
    [self leaveThen:nil];
}

- (void)removeTapped {
    void (^handler)(void) = [_removeHandler retain];
    [self leaveThen:^{ if (handler) handler(); [handler release]; }];
}

- (void)doneTapped {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit fromDate:_picker.date];
    int32_t day = (int32_t)parts.day, month = (int32_t)parts.month, year = _hideYear.on ? 0 : (int32_t)parts.year;
    void (^handler)(int32_t, int32_t, int32_t) = [_doneHandler retain];
    [self leaveThen:^{ if (handler) handler(day, month, year); [handler release]; }];
}

@end

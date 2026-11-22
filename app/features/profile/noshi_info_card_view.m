#import "noshi_info_card_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_classic_chrome.h"
#import "noshi_emoji_label.h"
#import "noshi_link_router.h"
#import "noshi_platform.h"
#include "noshi_links.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define ROW_MIN 62.0
#define STARS_ROW 56.0
#define CODE_SIDE 48.0

@interface NoshiInfoCardView () {
    NSMutableArray *_rows;
    UIView *_starsRow;
    UIImageView *_starsPicture;
    void (^_copyHandler)(void);
    NSString *_codeCaption;
    void (^_codeHandler)(void);
}
@end

@implementation NoshiInfoCardView

@synthesize copyHandler = _copyHandler;
@synthesize codeCaption = _codeCaption;
@synthesize codeHandler = _codeHandler;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    /* the card is the plate of the menus, with a hairline between its rows */
    NoshiClassicApplyMenuPlate(self, 10);
    _rows = [[NSMutableArray alloc] init];
    self.hidden = YES;
    return self;
}

- (void)dealloc {
    [_rows release];
    [_starsRow release];
    [_starsPicture release];
    [_copyHandler release];
    [_codeCaption release];
    [_codeHandler release];
    [super dealloc];
}

static NoshiEmojiLabel *NoshiInfoLabel(UIColor *color, CGFloat size) {
    NoshiEmojiLabel *label = [[[NoshiEmojiLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = NoshiFontRegular(size);
    return label;
}

NSArray *NoshiInfoMentions(NSString *text) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [[NSRegularExpression alloc] initWithPattern:@"(?<![A-Za-z0-9_@])@[A-Za-z0-9_]{1,32}(?![A-Za-z0-9_])" options:0 error:NULL];
    });
    NSMutableArray *entities = [NSMutableArray array];
    for (NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *name = [text substringWithRange:match.range];
        char checked[NOSHI_LINK_NAME_MAX];
        if (noshi_mention_name(name.UTF8String, checked, sizeof(checked)) != NOSHI_OK) continue;
        NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleMention range:match.range url:nil] autorelease];
        [entities addObject:entity];
    }
    return entities;
}

- (void)setRows:(NSArray *)rows {
    for (UIView *row in _rows) [row removeFromSuperview];
    [_rows removeAllObjects];
    for (NSArray *pair in rows) {
        NSString *caption = [pair objectAtIndex:0], *text = [pair objectAtIndex:1];
        if (!text.length) continue;
        UIControl *row = [[[UIControl alloc] init] autorelease];
        NoshiEmojiLabel *value = NoshiInfoLabel(NoshiColorTitle(), 17);
        value.numberOfLines = 0;
        value.text = text;
        if ([caption isEqualToString:NSLocalizedString(@"profile.about", nil)] || [caption isEqualToString:NSLocalizedString(@"channel.description", nil)]) {
            value.entities = NoshiInfoMentions(text);
            value.linkColor = NoshiColorAccent();
        }
        value.tag = 1;
        NoshiEmojiLabel *small = NoshiInfoLabel(NoshiColorSecondary(), 13);
        small.text = caption;
        small.tag = 2;
        [row addSubview:value];
        [row addSubview:small];
        [row addTarget:self action:@selector(copyRow:event:) forControlEvents:UIControlEventTouchUpInside];
        if (_rows.count) {
            /* a hairline between the rows */
            UIView *line = [[[UIView alloc] init] autorelease];
            line.tag = 11;
            line.userInteractionEnabled = NO;
            line.backgroundColor = [UIColor colorWithWhite:NoshiThemeIsDark() ? 1 : 0 alpha:NoshiThemeIsDark() ? 0.12 : 0.15];
            [row addSubview:line];
        }
        if (_codeHandler && [caption isEqualToString:_codeCaption]) {
            UIButton *code = [UIButton buttonWithType:UIButtonTypeCustom];
            code.tag = 3;
            [code setImage:NoshiSymbolImage(NoshiSymbolQr, 26, NoshiColorTitle()) forState:UIControlStateNormal];
            code.accessibilityLabel = NSLocalizedString(@"profile.qr", nil);
            [code addTarget:self action:@selector(openCode) forControlEvents:UIControlEventTouchUpInside];
            [row addSubview:code];
        }
        [self addSubview:row];
        [_rows addObject:row];
    }
    self.hidden = _rows.count == 0 && !_starsRow;
    [self setNeedsLayout];
}

- (void)setStarsBalance:(UIImage *)balance caption:(NSString *)caption {
    [_starsRow removeFromSuperview];
    [_starsRow release];
    _starsRow = nil;
    [_starsPicture release];
    _starsPicture = nil;
    if (balance) {
        _starsRow = [[UIView alloc] init];
        NoshiEmojiLabel *title = NoshiInfoLabel(NoshiColorTitle(), 17);
        title.tag = 2;
        title.text = caption;
        _starsPicture = [[UIImageView alloc] initWithImage:balance];
        [_starsRow addSubview:title];
        [_starsRow addSubview:_starsPicture];
        [self addSubview:_starsRow];
    }
    self.hidden = _rows.count == 0 && !_starsRow;
    [self setNeedsLayout];
}

/* the text of a row with a QR button stops short of it */
- (CGFloat)textWidthOfRow:(UIView *)row card:(CGFloat)width {
    return width - 32 - ([row viewWithTag:3] ? CODE_SIDE : 0);
}

- (CGFloat)rowHeight:(UIView *)row width:(CGFloat)width {
    NoshiEmojiLabel *value = (NoshiEmojiLabel *)[row viewWithTag:1];
    CGSize fit = [value sizeThatFits:CGSizeMake([self textWidthOfRow:row card:width], 400)];
    return MAX(ROW_MIN, fit.height + 38);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat total = 0;
    for (UIView *row in _rows) total += [self rowHeight:row width:width];
    return total + (_starsRow ? STARS_ROW : 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, y = 0;
    /* the plate of the classic card is a layer of its own, sized by hand */
    NoshiClassicFitPlate(self, 0);
    for (UIView *row in _rows) {
        NoshiEmojiLabel *value = (NoshiEmojiLabel *)[row viewWithTag:1], *caption = (NoshiEmojiLabel *)[row viewWithTag:2];
        CGFloat textWidth = [self textWidthOfRow:row card:width];
        CGSize fit = [value sizeThatFits:CGSizeMake(textWidth, 400)];
        CGFloat height = [self rowHeight:row width:width];
        row.frame = CGRectMake(0, y, width, height);
        value.frame = CGRectMake(16, 10, textWidth, fit.height);
        caption.frame = CGRectMake(16, 10 + fit.height + 2, textWidth, 16);
        [row viewWithTag:3].frame = CGRectMake(width - CODE_SIDE - 4, (height - CODE_SIDE) / 2, CODE_SIDE, CODE_SIDE);
        [row viewWithTag:11].frame = CGRectMake(0, 0, width, 1.0f / NoshiScreenScale());
        y += height;
    }
    if (_starsRow) {
        _starsRow.frame = CGRectMake(0, y, width, STARS_ROW);
        [_starsRow viewWithTag:2].frame = CGRectMake(16, 0, width - 16 - 100, STARS_ROW);
        CGSize balance = _starsPicture.bounds.size;
        _starsPicture.frame = CGRectMake(width - 16 - balance.width, (STARS_ROW - balance.height) / 2, balance.width, balance.height);
    }
}

- (void)openCode {
    if (_codeHandler) _codeHandler();
}

- (void)copyRow:(UIControl *)row event:(UIEvent *)event {
    NoshiEmojiLabel *value = (NoshiEmojiLabel *)[row viewWithTag:1];
    UITouch *touch = [[event allTouches] anyObject];
    NSString *link = touch ? [value linkAtPoint:[touch locationInView:value]] : nil;
    if (link.length) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenLinkNotification object:self userInfo:[NSDictionary dictionaryWithObject:link forKey:@"url"]];
        return;
    }
    NoshiEmojiLabel *caption = (NoshiEmojiLabel *)[row viewWithTag:2];
    if ([caption.text isEqualToString:NSLocalizedString(@"profile.about", nil)] ||
        [caption.text isEqualToString:NSLocalizedString(@"channel.description", nil)]) return;
    [UIPasteboard generalPasteboard].string = value.text;
    if (_copyHandler) _copyHandler();
}

@end

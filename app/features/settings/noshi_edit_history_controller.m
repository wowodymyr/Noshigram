#import "noshi_edit_history_controller.h"

#import "noshi_message.h"
#import "noshi_theme.h"
#import "noshi_time.h"

#define PAD 16.0
#define GAP 6.0

/* one text in a card: a small line over it that says which it is, and the text, which takes as many lines as it needs */
@interface NoshiEditTextView : UIView {
    UILabel *_caption;
    UILabel *_text;
}
- (id)initWithCaption:(NSString *)caption text:(NSString *)text;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation NoshiEditTextView

- (id)initWithCaption:(NSString *)caption text:(NSString *)text {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textColor = NoshiColorAccent();
    _caption.font = NoshiFontSemibold(13);
    _caption.text = caption;
    [self addSubview:_caption];
    _text = [[UILabel alloc] init];
    _text.backgroundColor = [UIColor clearColor];
    _text.textColor = NoshiColorTitle();
    _text.font = NoshiFontRegular(16);
    _text.numberOfLines = 0;
    _text.text = text.length ? text : @"—";
    [self addSubview:_text];
    return self;
}

- (void)dealloc {
    [_caption release];
    [_text release];
    [super dealloc];
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGSize fit = [_text sizeThatFits:CGSizeMake(MAX(0, width - 2 * PAD), CGFLOAT_MAX)];
    return PAD + ceil(_caption.font.lineHeight) + GAP + ceil(fit.height) + PAD;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width - 2 * PAD;
    _caption.frame = CGRectMake(PAD, PAD, width, ceil(_caption.font.lineHeight));
    CGSize fit = [_text sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    _text.frame = CGRectMake(PAD, CGRectGetMaxY(_caption.frame) + GAP, width, ceil(fit.height));
}

@end

@interface NoshiEditHistoryController () {
    NSArray *_versions;
    NSString *_current;
    int32_t _date;
}
@end

@implementation NoshiEditHistoryController

- (id)initWithVersions:(NSArray *)versions current:(NSString *)current date:(int32_t)date {
    self = [super init];
    if (!self) return nil;
    _versions = [versions copy];
    _current = [current copy];
    _date = date;
    self.pageTitle = NSLocalizedString(@"chat.edithistory.title", nil);
    return self;
}

- (void)dealloc {
    [_versions release];
    [_current release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiEditHistoryController alloc] initWithVersions:_versions current:_current date:_date] autorelease];
}

static NoshiSettingsRow *NoshiEditRow(NSString *caption, NSString *text) {
    NoshiEditTextView *view = [[[NoshiEditTextView alloc] initWithCaption:caption text:text] autorelease];
    return [NoshiSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { return [view heightForWidth:width]; }];
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:NoshiEditRow(NSLocalizedString(@"chat.edithistory.now", nil), _current)];
    /* the newest version is the one just before the present text */
    NSUInteger number = _versions.count;
    for (NoshiMessage *version in [_versions reverseObjectEnumerator]) {
        [rows addObject:NoshiEditRow([NSString stringWithFormat:NSLocalizedString(@"chat.edithistory.version", nil), (unsigned long)number], version.text)];
        --number;
    }
    self.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"chat.edithistory.info", nil) rows:rows]];
    [self reloadSettings];
}

@end

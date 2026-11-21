#import "noshi_bot_markup.h"

static NSString *NoshiUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiMarkupButton

@synthesize row = _row;
@synthesize text = _text;
@synthesize argument = _argument;
@synthesize data = _data;

+ (NoshiMarkupButton *)buttonWithRow:(const noshi_markup_button *)row markup:(const noshi_markup *)markup {
    NoshiMarkupButton *button = [[[NoshiMarkupButton alloc] init] autorelease];
    button->_row = *row;
    button->_text = [NoshiUtf8(row->text) copy];
    button->_argument = [NoshiUtf8(noshi_markup_arg(markup, row)) copy];
    if (row->kind == NOSHI_BUTTON_CALLBACK) button->_data = [[NSData alloc] initWithBytes:row->data length:row->data_len];
    return button;
}

- (void)dealloc {
    [_text release];
    [_argument release];
    [_data release];
    [super dealloc];
}

- (noshi_button_kind)kind { return (noshi_button_kind)_row.kind; }
- (noshi_button_style)style { return (noshi_button_style)_row.style; }
- (BOOL)enabled { return _row.kind != NOSHI_BUTTON_DISABLED; }

@end

@implementation NoshiMarkup

@synthesize kind = _kind;
@synthesize resize = _resize;
@synthesize singleUse = _singleUse;
@synthesize persistent = _persistent;
@synthesize selective = _selective;
@synthesize placeholder = _placeholder;
@synthesize rows = _rows;
@synthesize buttonCount = _buttonCount;

+ (NoshiMarkup *)markupWithValue:(const noshi_tl_value *)value {
    if (!value) return nil;
    /* about 22 KB, so it lives on the heap and not on the worker's stack */
    noshi_markup *raw = calloc(1, sizeof(*raw));
    if (!raw) return nil;
    noshi_status status = noshi_markup_read(value, raw);
    if (status != NOSHI_OK || raw->kind == NOSHI_MARKUP_NONE) {
        if (status != NOSHI_OK && status != NOSHI_E_UNSUPPORTED) NSLog(@"noshigram: reply markup rejected: %s", noshi_status_name(status));
        free(raw);
        return nil;
    }
    NoshiMarkup *markup = [[[NoshiMarkup alloc] init] autorelease];
    markup->_kind = (noshi_markup_kind)raw->kind;
    markup->_resize = raw->resize;
    markup->_singleUse = raw->single_use;
    markup->_persistent = raw->persistent;
    markup->_selective = raw->selective;
    markup->_placeholder = [NoshiUtf8(raw->placeholder) copy];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:raw->row_count];
    NSUInteger at = 0;
    for (unsigned r = 0; r < raw->row_count; ++r) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:raw->row_size[r]];
        for (unsigned k = 0; k < raw->row_size[r]; ++k) [row addObject:[NoshiMarkupButton buttonWithRow:&raw->buttons[at++] markup:raw]];
        [rows addObject:row];
    }
    markup->_rows = [rows copy];
    markup->_rowSizes = [[NSData alloc] initWithBytes:raw->row_size length:raw->row_count];
    markup->_buttonCount = at;
    free(raw);
    return markup;
}

- (void)dealloc {
    [_placeholder release];
    [_rows release];
    [_rowSizes release];
    [super dealloc];
}

- (NSData *)framesForWidth:(CGFloat)width rowHeight:(CGFloat)rowHeight gap:(CGFloat)gap height:(CGFloat *)height {
    if (height) *height = 0;
    if (!_buttonCount) return [NSData data];
    noshi_rect *frames = calloc(_buttonCount, sizeof(*frames));
    if (!frames) return nil;
    double total = 0;
    noshi_status status = noshi_markup_layout(_rowSizes.bytes, _rowSizes.length, width, rowHeight, gap, frames, _buttonCount, &total);
    if (status != NOSHI_OK) {
        free(frames);
        return nil;
    }
    CGRect *rects = calloc(_buttonCount, sizeof(CGRect));
    if (!rects) {
        free(frames);
        return nil;
    }
    for (NSUInteger i = 0; i < _buttonCount; ++i) rects[i] = CGRectMake((CGFloat)frames[i].x, (CGFloat)frames[i].y, (CGFloat)frames[i].width, (CGFloat)frames[i].height);
    free(frames);
    if (height) *height = (CGFloat)total;
    return [NSData dataWithBytesNoCopy:rects length:_buttonCount * sizeof(CGRect) freeWhenDone:YES];
}

- (BOOL)isEqualMarkup:(NoshiMarkup *)other {
    if (self == other) return YES;
    if (!other || _kind != other->_kind || _buttonCount != other->_buttonCount || ![_rowSizes isEqualToData:other->_rowSizes]) return NO;
    for (NSUInteger r = 0; r < _rows.count; ++r) {
        NSArray *a = [_rows objectAtIndex:r], *b = [other->_rows objectAtIndex:r];
        for (NSUInteger k = 0; k < a.count; ++k) {
            NoshiMarkupButton *x = [a objectAtIndex:k], *y = [b objectAtIndex:k];
            if (x.kind != y.kind || x.style != y.style || ![x.text isEqualToString:y.text] || ![x.argument isEqualToString:y.argument] ||
                (x.data != y.data && ![x.data isEqualToData:y.data])) return NO;
        }
    }
    return YES;
}

@end

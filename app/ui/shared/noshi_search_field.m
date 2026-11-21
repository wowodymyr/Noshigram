#import "noshi_search_field.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_string_drawing.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

static const CGFloat NoshiSearchIconWidth = 38.0;

@implementation NoshiSearchField

+ (NoshiSearchField *)fieldWithPlaceholder:(NSString *)placeholder height:(CGFloat)height {
    NoshiSearchField *field = [[[NoshiSearchField alloc] init] autorelease];
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.backgroundColor = NoshiColorField();
    field.layer.cornerRadius = height / 2;
    field.placeholder = placeholder;
    field.font = NoshiFontRegular(16);
    field.textColor = NoshiColorTitle();
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolMagnifier, 16, NoshiColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, NoshiSearchIconWidth, height);
    field.leftView = glass;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

- (CGRect)textRectForBounds:(CGRect)bounds {
    return CGRectMake(NoshiSearchIconWidth, 0, MAX(0, bounds.size.width - NoshiSearchIconWidth - 30), bounds.size.height);
}

- (CGRect)editingRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [(NoshiColorSecondary()) set];
    CGFloat height = ceil(self.font.lineHeight);
    rect.origin.y += floor((rect.size.height - height) / 2);
    rect.size.height = height;
    NoshiDrawStringIn(self.placeholder, self.font, rect, NoshiStringTailTruncate, NoshiTextAlignmentLeft);
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    return CGRectMake(0, 0, NoshiSearchIconWidth, bounds.size.height);
}

- (CGRect)clearButtonRectForBounds:(CGRect)bounds {
    return CGRectMake(bounds.size.width - 30, 0, 30, bounds.size.height);
}

@end


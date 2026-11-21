#import "noshi_input_format.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_date_time_picker.h"
#import "noshi_person.h"
#import "noshi_session.h"
#import "noshi_session_bots.h"
#import "noshi_sheet.h"
#import "noshi_theme.h"
#import "noshi_translate_config.h"
#import "noshi_translator.h"
#import "noshi_weak_reference.h"

/* what a pick in the menu does, in the order of the menu */
typedef enum {
    NoshiFormatTranslate,
    NoshiFormatBold,
    NoshiFormatItalic,
    NoshiFormatMono,
    NoshiFormatCode,
    NoshiFormatStrike,
    NoshiFormatUnderline,
    NoshiFormatQuote,
    NoshiFormatSpoiler,
    NoshiFormatLink,
    NoshiFormatMention,
    NoshiFormatDate,
    NoshiFormatRegular
} NoshiFormatAction;

#define STYLE_BIT(style) (1u << (unsigned)(style))
#define INLINE_STYLES (STYLE_BIT(NoshiTextStyleBold) | STYLE_BIT(NoshiTextStyleItalic) | STYLE_BIT(NoshiTextStyleUnderline) | \
                       STYLE_BIT(NoshiTextStyleStrike) | STYLE_BIT(NoshiTextStyleSpoiler))
#define MONO_STYLES (STYLE_BIT(NoshiTextStyleCode) | STYLE_BIT(NoshiTextStylePre))
#define TARGET_STYLES (STYLE_BIT(NoshiTextStyleLink) | STYLE_BIT(NoshiTextStyleMentionName) | STYLE_BIT(NoshiTextStyleDate))
/* every style a person can pick; the custom emoji are not theirs to remove with "regular" */
#define PICKED_STYLES (INLINE_STYLES | MONO_STYLES | TARGET_STYLES | STYLE_BIT(NoshiTextStyleQuote))

static NoshiTextEntity *NoshiRunLike(NoshiTextEntity *base, NSRange range) {
    NoshiTextEntity *run = [[[NoshiTextEntity alloc] initWithStyle:base.style range:range url:base.url] autorelease];
    run.userId = base.userId;
    run.accessHash = base.accessHash;
    run.date = base.date;
    run.flags = base.flags;
    return run;
}

#pragma mark runs

@implementation NoshiInputFormat

@synthesize session = _session;
@synthesize host = _host;
@synthesize changed = _changed;
@synthesize replace = _replace;

- (id)initWithTextView:(UITextView *)view {
    self = [super init];
    if (!self) return nil;
    _view = view;
    _runs = [[NSMutableArray alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_job cancel];
    [_job release];
    [_runs release];
    [_changed release];
    [_replace release];
    [super dealloc];
}

- (void)reset {
    [_runs removeAllObjects];
    [self refreshAppearance];
}

- (void)restoreEntities:(NSArray *)entities {
    NSUInteger length = _view.text.length;
    [_runs removeAllObjects];
    for (NoshiTextEntity *entity in entities) {
        if (NSMaxRange(entity.range) > length || !entity.range.length) continue;
        switch (entity.style) {
        case NoshiTextStyleBold:
        case NoshiTextStyleItalic:
        case NoshiTextStyleUnderline:
        case NoshiTextStyleStrike:
        case NoshiTextStyleCode:
        case NoshiTextStylePre:
        case NoshiTextStyleSpoiler:
        case NoshiTextStyleQuote:
        case NoshiTextStyleDate:
            [_runs addObject:entity];
            break;
        case NoshiTextStyleLink:
            if (entity.url.length) [_runs addObject:entity];
            break;
        case NoshiTextStyleMentionName:
            /* the server wants the access hash of the user in a sent message, and a draft does not bring it back */
            if (entity.userId && entity.accessHash) [_runs addObject:entity];
            break;
        default:
            break;
        }
    }
    [self refreshAppearance];
}

- (void)shiftForRange:(NSRange)range replacementLength:(NSUInteger)length {
    if (!_runs.count) return;
    NSInteger delta = (NSInteger)length - (NSInteger)range.length;
    NSUInteger editEnd = NSMaxRange(range);
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_runs.count];
    for (NoshiTextEntity *run in _runs) {
        NSRange at = run.range;
        NSUInteger end = NSMaxRange(at);
        if (end <= range.location) {
            [kept addObject:run];
        } else if (at.location >= editEnd && !(range.length == 0 && at.location == range.location && length == 0)) {
            [kept addObject:NoshiRunLike(run, NSMakeRange((NSUInteger)((NSInteger)at.location + delta), at.length))];
        } else if (range.location >= at.location && editEnd <= end && !(range.length == 0 && (range.location == at.location || range.location == end))) {
            NSInteger grown = (NSInteger)at.length + delta;
            if (grown > 0) [kept addObject:NoshiRunLike(run, NSMakeRange(at.location, (NSUInteger)grown))];
        } else if (range.location <= at.location && editEnd >= end) {
            /* replaced whole */
        } else if (range.location <= at.location) {
            [kept addObject:NoshiRunLike(run, NSMakeRange(range.location + length, end - editEnd))];
        } else {
            [kept addObject:NoshiRunLike(run, NSMakeRange(at.location, range.location - at.location))];
        }
    }
    [_runs setArray:kept];
}

/* what is left of the runs of these styles once the range is cut out of them */
- (void)cutRange:(NSRange)range styles:(unsigned)styles {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_runs.count + 2];
    NSUInteger rangeEnd = NSMaxRange(range);
    for (NoshiTextEntity *run in _runs) {
        NSRange at = run.range;
        NSUInteger end = NSMaxRange(at);
        if (!(STYLE_BIT(run.style) & styles) || end <= range.location || at.location >= rangeEnd) {
            [kept addObject:run];
            continue;
        }
        if (at.location < range.location) [kept addObject:NoshiRunLike(run, NSMakeRange(at.location, range.location - at.location))];
        if (end > rangeEnd) [kept addObject:NoshiRunLike(run, NSMakeRange(rangeEnd, end - rangeEnd))];
    }
    [_runs setArray:kept];
}

/* whether runs of the style together cover every character of the range */
- (BOOL)style:(NoshiTextStyle)style coversRange:(NSRange)range {
    NSUInteger position = range.location, end = NSMaxRange(range);
    BOOL moved = YES;
    while (position < end && moved) {
        moved = NO;
        for (NoshiTextEntity *run in _runs) {
            if (run.style != style || run.range.location > position || NSMaxRange(run.range) <= position) continue;
            position = NSMaxRange(run.range);
            moved = YES;
        }
    }
    return position >= end;
}

- (void)add:(NoshiTextEntity *)entity {
    [_runs addObject:entity];
    [self refreshAppearance];
    if (_changed) _changed();
}

- (void)applyStyle:(NoshiTextStyle)style toRange:(NSRange)range {
    if ([self style:style coversRange:range]) {
        [self cutRange:range styles:STYLE_BIT(style)];
        [self refreshAppearance];
        if (_changed) _changed();
        return;
    }
    /* mono text keeps no other inline style and no other inline style keeps mono it */
    unsigned clear = STYLE_BIT(style);
    if (style == NoshiTextStyleCode || style == NoshiTextStylePre) clear |= INLINE_STYLES | MONO_STYLES;
    else if (STYLE_BIT(style) & INLINE_STYLES) clear |= MONO_STYLES;
    [self cutRange:range styles:clear];
    [self add:[[[NoshiTextEntity alloc] initWithStyle:style range:range url:nil] autorelease]];
}

- (void)applyTarget:(NoshiTextEntity *)entity {
    /* a link, a name and a date all say what a tap on the words does, so one replaces another */
    [self cutRange:entity.range styles:TARGET_STYLES];
    [self add:entity];
}

#pragma mark entities

- (NSArray *)entitiesAfterLead:(NSUInteger)lead length:(NSUInteger)length {
    NSMutableArray *entities = [NSMutableArray arrayWithCapacity:_runs.count];
    for (NoshiTextEntity *run in _runs) {
        NSRange at = run.range;
        if (at.location >= lead + length || NSMaxRange(at) <= lead) continue;
        NSUInteger from = MAX(at.location, lead), to = MIN(NSMaxRange(at), lead + length);
        [entities addObject:NoshiRunLike(run, NSMakeRange(from - lead, to - from))];
    }
    return entities;
}

#pragma mark appearance

/* the attribute names of NSAttributedString from ios 6 and 7 by their values: a constant the old runtime lacks would not load, and the text
   storage that takes them only exists from ios 7 */
- (void)refreshAppearance {
    if (![_view respondsToSelector:@selector(textStorage)] || _view.markedTextRange) return;
    if (!_runs.count && !_appearanceApplied) return;
    /* the ios 6.1 headers of the armv7 slice do not declare the storage, so it is sent to as an id */
    id storage = [_view performSelector:@selector(textStorage)];
    NSUInteger length = [[storage string] length];
    if (!length) { _appearanceApplied = NO; return; }
    UIFont *base = _view.font ? _view.font : NoshiFontRegular(16);
    UIColor *ink = _view.textColor ? _view.textColor : NoshiColorTitle();
    CGFloat size = base.pointSize;
    [storage beginEditing];
    [storage setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:base, @"NSFont", ink, @"NSColor", nil] range:NSMakeRange(0, length)];
    for (NoshiTextEntity *run in _runs) {
        NSRange range = run.range;
        if (NSMaxRange(range) > length) continue;
        switch (run.style) {
        case NoshiTextStyleBold: [storage addAttribute:@"NSFont" value:NoshiFontBold(size) range:range]; break;
        case NoshiTextStyleItalic: [storage addAttribute:@"NSObliqueness" value:[NSNumber numberWithFloat:0.2f] range:range]; break;
        case NoshiTextStyleUnderline: [storage addAttribute:@"NSUnderline" value:[NSNumber numberWithInt:1] range:range]; break;
        case NoshiTextStyleStrike: [storage addAttribute:@"NSStrikethrough" value:[NSNumber numberWithInt:1] range:range]; break;
        case NoshiTextStyleCode:
        case NoshiTextStylePre: {
            UIFont *mono = [UIFont fontWithName:@"Courier" size:size - 1];
            if (mono) [storage addAttribute:@"NSFont" value:mono range:range];
            [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.12] range:range];
            break;
        }
        case NoshiTextStyleSpoiler: [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.3] range:range]; break;
        case NoshiTextStyleQuote: [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.08] range:range]; break;
        case NoshiTextStyleLink:
        case NoshiTextStyleMentionName:
        case NoshiTextStyleDate:
            [storage addAttribute:@"NSColor" value:NoshiColorAccent() range:range];
            if (run.style != NoshiTextStyleMentionName) [storage addAttribute:@"NSUnderline" value:[NSNumber numberWithInt:1] range:range];
            break;
        default: break;
        }
    }
    [storage endEditing];
    _appearanceApplied = _runs.count > 0;
}

#pragma mark menu

- (void)presentMenu {
    if (!_host || !_view.text.length) return;
    BOOL selected = _view.selectedRange.length > 0;
    static const NoshiFormatAction all[] = {NoshiFormatTranslate, NoshiFormatBold, NoshiFormatItalic, NoshiFormatMono, NoshiFormatCode,
        NoshiFormatStrike, NoshiFormatUnderline, NoshiFormatQuote, NoshiFormatSpoiler, NoshiFormatLink, NoshiFormatMention, NoshiFormatDate,
        NoshiFormatRegular};
    static NSString *const keys[] = {@"fmt.translate", @"fmt.bold", @"fmt.italic", @"fmt.mono", @"fmt.code", @"fmt.strike", @"fmt.underline", @"fmt.quote",
        @"fmt.spoiler", @"fmt.link", @"fmt.mention", @"fmt.date", @"fmt.regular"};
    NSMutableArray *options = [NSMutableArray array], *actions = [NSMutableArray array];
    /* with nothing selected only the translation of the whole text makes sense */
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); ++i) {
        if (!selected && all[i] != NoshiFormatTranslate) continue;
        [options addObject:NSLocalizedString(keys[i], nil)];
        [actions addObject:[NSNumber numberWithInt:all[i]]];
    }
    NSRange range = selected ? _view.selectedRange : NSMakeRange(0, _view.text.length);
    NoshiWeakReference *weak = _weak;
    /* the sheet stands on the bottom edge of the screen, where the keyboard is; the keyboard goes while the choice is made and comes back with the answer */
    BOOL hadKeyboard = [_view isFirstResponder];
    if (hadKeyboard) [_view resignFirstResponder];
    [NoshiSheet presentInView:_host title:nil message:nil options:options destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                        handler:^(NSUInteger index) {
        NoshiInputFormat *format = weak.target;
        if (!format || index >= actions.count) return;
        NoshiFormatAction action = (NoshiFormatAction)[[actions objectAtIndex:index] intValue];
        /* the questions that follow (a link, a language, a date) ask for the keyboard themselves or have none, so only the plain styles take it back at once */
        if (hadKeyboard && action != NoshiFormatTranslate && action != NoshiFormatCode && action != NoshiFormatLink && action != NoshiFormatMention && action != NoshiFormatDate) {
            [format->_view becomeFirstResponder];
            if (NSMaxRange(range) <= format->_view.text.length) format->_view.selectedRange = range;
        }
        [format perform:action range:range];
    }];
}

- (void)perform:(NoshiFormatAction)action range:(NSRange)range {
    if (NSMaxRange(range) > _view.text.length) return;
    switch (action) {
    case NoshiFormatTranslate: [self translateRange:range]; break;
    case NoshiFormatBold: [self applyStyle:NoshiTextStyleBold toRange:range]; break;
    case NoshiFormatItalic: [self applyStyle:NoshiTextStyleItalic toRange:range]; break;
    case NoshiFormatMono: [self applyStyle:NoshiTextStyleCode toRange:range]; break;
    case NoshiFormatStrike: [self applyStyle:NoshiTextStyleStrike toRange:range]; break;
    case NoshiFormatUnderline: [self applyStyle:NoshiTextStyleUnderline toRange:range]; break;
    case NoshiFormatQuote: [self applyStyle:NoshiTextStyleQuote toRange:range]; break;
    case NoshiFormatSpoiler: [self applyStyle:NoshiTextStyleSpoiler toRange:range]; break;
    case NoshiFormatCode: [self askCodeInRange:range]; break;
    case NoshiFormatLink: [self askLinkInRange:range]; break;
    case NoshiFormatMention: [self askMentionInRange:range]; break;
    case NoshiFormatDate: [self askDateInRange:range]; break;
    case NoshiFormatRegular:
        [self cutRange:range styles:PICKED_STYLES];
        [self refreshAppearance];
        if (_changed) _changed();
        break;
    }
}

- (BOOL)stillHolds:(NSRange)range {
    return NSMaxRange(range) <= _view.text.length;
}

- (void)askCodeInRange:(NSRange)range {
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"fmt.code.title", nil), nil, nil, NSLocalizedString(@"fmt.code.language", nil), ^(NSString *language) {
        NoshiInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        [format cutRange:range styles:INLINE_STYLES | MONO_STYLES];
        NSString *name = [language stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [format add:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStylePre range:range url:name.length ? name : nil] autorelease]];
    });
}

- (void)askLinkInRange:(NSRange)range {
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"fmt.link.title", nil), nil, @"http://", NSLocalizedString(@"fmt.link.address", nil), ^(NSString *address) {
        NoshiInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        NSString *url = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        /* nothing typed after the scheme is no link; the run that was there stays as it was */
        if (!url.length || [url isEqualToString:@"http://"]) return;
        if ([url rangeOfString:@"://"].location == NSNotFound && ![url hasPrefix:@"tg:"] && ![url hasPrefix:@"mailto:"]) url = [@"http://" stringByAppendingString:url];
        [format applyTarget:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleLink range:range url:url] autorelease]];
    });
}

- (void)askMentionInRange:(NSRange)range {
    NoshiWeakReference *weak = _weak;
    NoshiPromptText(NSLocalizedString(@"fmt.mention.title", nil), nil, nil, NSLocalizedString(@"fmt.mention.name", nil), ^(NSString *text) {
        NoshiInputFormat *format = weak.target;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name hasPrefix:@"@"]) name = [name substringFromIndex:1];
        if (!format || !name.length || !format->_session || ![format stillHolds:range]) return;
        [format->_session resolveUsername:name completion:^(NoshiDialog *resolved, NoshiPerson *person, NSString *errorName) {
            (void)resolved;
            NoshiInputFormat *again = weak.target;
            if (!again) return;
            /* a name needs a person with a hash the server will accept; a channel or a group has none to point at */
            if (!person || person.userId <= 0 || person.accessHash == 0) {
                if (errorName) NSLog(@"noshigram: the mention was not resolved: %@", errorName);
                NoshiShowNotice(nil, NSLocalizedString(@"fmt.mention.failed", nil));
                return;
            }
            if (![again stillHolds:range]) return;
            NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleMentionName range:range url:nil] autorelease];
            entity.userId = person.userId;
            entity.accessHash = person.accessHash;
            [again applyTarget:entity];
        }];
    });
}

- (void)askDateInRange:(NSRange)range {
    NoshiWeakReference *weak = _weak;
    NoshiDateTimePicker *picker = [[[NoshiDateTimePicker alloc] initWithFrame:_host.bounds mode:UIDatePickerModeDateAndTime initialDate:nil minimumDate:nil done:^(NSDate *date) {
        NoshiInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        NoshiTextEntity *entity = [[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleDate range:range url:nil] autorelease];
        entity.date = (int32_t)[date timeIntervalSince1970];
        [format applyTarget:entity];
    } cancelled:nil] autorelease];
    [_host addSubview:picker];
}

- (void)translateRange:(NSRange)range {
    NSString *text = [_view.text substringWithRange:range];
    if (!text.length || !_replace) return;
    NoshiWeakReference *weak = _weak;
    [_job cancel];
    [_job release];
    _job = [[NoshiTranslateJob translateText:text entities:nil to:NoshiTranslateTargetLanguage() context:nil session:_session
                                      completion:^(NoshiTranslation *translation, NSString *failure) {
        NoshiInputFormat *format = weak.target;
        if (!format) return;
        if (!translation) {
            NoshiShowNotice(nil, failure.length ? failure : NSLocalizedString(@"fmt.translate.failed", nil));
            return;
        }
        /* the text moved under the request; replacing a different range would eat words the person typed since */
        if (![format stillHolds:range] || ![[format->_view.text substringWithRange:range] isEqualToString:text]) return;
        format->_replace(range, translation.text);
    }] retain];
}

@end

#import "noshi_text_parts.h"

#import "noshi_message.h"

#include "noshi_text_split.h"

/* a piece of text never needs more messages than the units it holds, but a bound keeps a hostile paste from asking for thousands */
#define TEXT_PARTS_MAX 256

@implementation NoshiTextPart
@synthesize text = _text;
@synthesize entities = _entities;

- (id)initWithText:(NSString *)text entities:(NSArray *)entities {
    self = [super init];
    if (!self) return nil;
    _text = [text copy];
    _entities = [entities copy];
    return self;
}

- (void)dealloc {
    [_text release];
    [_entities release];
    [super dealloc];
}
@end

static NoshiTextEntity *entity_in_part(NoshiTextEntity *entity, NSUInteger begin, NSUInteger end) {
    NSRange range = entity.range;
    NSUInteger from = MAX(range.location, begin), to = MIN(NSMaxRange(range), end);
    if (to <= from) return nil;
    BOOL whole = from == range.location && to == NSMaxRange(range);
    if (!whole && (entity.style == NoshiTextStyleCustomEmoji || entity.style == NoshiTextStyleMentionName)) return nil;
    NoshiTextEntity *cut = [[[NoshiTextEntity alloc] initWithStyle:entity.style range:NSMakeRange(from - begin, to - from) url:entity.url] autorelease];
    cut.documentId = entity.documentId;
    cut.userId = entity.userId;
    cut.accessHash = entity.accessHash;
    cut.date = entity.date;
    cut.flags = entity.flags;
    return cut;
}

NSArray *NoshiTextPartsForLimit(NSString *text, NSArray *entities, NSUInteger limit) {
    NSUInteger length = text.length;
    if (!length) return [NSArray array];
    uint16_t *units = malloc(length * sizeof(uint16_t));
    if (!units) return nil;
    for (NSUInteger i = 0; i < length; ++i) units[i] = [text characterAtIndex:i];
    noshi_text_part *parts = malloc(TEXT_PARTS_MAX * sizeof(noshi_text_part));
    if (!parts) {
        free(units);
        return nil;
    }
    size_t written = 0;
    size_t needed = noshi_text_split(units, length, limit, parts, TEXT_PARTS_MAX, &written);
    free(units);
    NSMutableArray *result = nil;
    /* a text that would need more pieces than the bound is refused whole, instead of sending its first part and losing the rest */
    if (needed <= TEXT_PARTS_MAX) {
        result = [NSMutableArray arrayWithCapacity:written];
        for (size_t i = 0; i < written; ++i) {
            NSUInteger begin = parts[i].begin, end = parts[i].end;
            NSMutableArray *inside = [NSMutableArray array];
            for (NoshiTextEntity *entity in entities) {
                NoshiTextEntity *cut = entity_in_part(entity, begin, end);
                if (cut) [inside addObject:cut];
            }
            NoshiTextPart *part = [[NoshiTextPart alloc] initWithText:[text substringWithRange:NSMakeRange(begin, end - begin)] entities:inside];
            [result addObject:part];
            [part release];
        }
    }
    free(parts);
    return result;
}

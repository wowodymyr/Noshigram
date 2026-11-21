#import "noshi_ayu.h"

#import "noshi_chat_settings.h"

static NSString *const NoshiAyuRegexKey = @"noshigram.ayu.regexlist";
#define PATTERNS_MAX 50
#define PATTERN_LENGTH_MAX 200

NSArray *NoshiAyuRegexList(void) {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:NoshiAyuRegexKey];
    NSMutableArray *list = [NSMutableArray array];
    for (id item in stored) if ([item isKindOfClass:[NSString class]] && [(NSString *)item length]) [list addObject:item];
    return list;
}

/* the compiled expressions are kept with the list they came from, so a change of the list builds them again */
static NSArray *NoshiAyuCompiledFrom;
static NSArray *NoshiAyuCompiled;
/* what the list said of a text. the chat asks for every loaded message at every rebuild, and running up to fifty expressions over each of thousands of texts took the main
   thread; the list is only written by NoshiAyuSetRegexList, which empties this */
static NSCache *NoshiAyuVerdicts;
#define VERDICTS_MAX 8192

void NoshiAyuSetRegexList(NSArray *patterns) {
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *pattern in patterns) {
        if (pattern.length && pattern.length <= PATTERN_LENGTH_MAX && list.count < PATTERNS_MAX) [list addObject:pattern];
    }
    [NoshiAyuVerdicts removeAllObjects];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:NoshiAyuRegexKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"noshigram: the filters were not saved");
}

NSString *NoshiAyuRegexProblem(NSString *pattern) {
    if (!pattern.length) return NSLocalizedString(@"ayu.regex.empty", nil);
    if (pattern.length > PATTERN_LENGTH_MAX) return NSLocalizedString(@"ayu.regex.long", nil);
    NSError *error = nil;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    return expression ? nil : NSLocalizedString(@"ayu.regex.bad", nil);
}

BOOL NoshiAyuHidesText(NSString *text) {
    if (!text.length || !NoshiChatFlagGet(NoshiChatFlagAyuRegex)) return NO;
    if (!NoshiAyuVerdicts) {
        NoshiAyuVerdicts = [[NSCache alloc] init];
        NoshiAyuVerdicts.countLimit = VERDICTS_MAX;
    }
    NSNumber *known = [NoshiAyuVerdicts objectForKey:text];
    if (known) return known.boolValue;
    NSArray *list = NoshiAyuRegexList();
    if (!list.count) return NO;
    if (!NoshiAyuCompiled || ![NoshiAyuCompiledFrom isEqualToArray:list]) {
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSString *pattern in list) {
            NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
            if (expression) [compiled addObject:expression];
        }
        [NoshiAyuCompiledFrom release];
        [NoshiAyuCompiled release];
        NoshiAyuCompiledFrom = [list copy];
        NoshiAyuCompiled = [compiled retain];
    }
    NSRange all = NSMakeRange(0, text.length);
    BOOL hides = NO;
    for (NSRegularExpression *expression in NoshiAyuCompiled) {
        if ([expression firstMatchInString:text options:0 range:all]) { hides = YES; break; }
    }
    [NoshiAyuVerdicts setObject:[NSNumber numberWithBool:hides] forKey:text];
    return hides;
}

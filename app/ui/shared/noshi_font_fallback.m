#import "noshi_font_fallback.h"

#include "noshi_text_class.h"

#define FALLBACK_COUNT 5
/* what a lookup answers: the base font or the system draws the character, a bundled font does (its index plus one), or nothing does */
#define FALLBACK_NONE 0
#define FALLBACK_MISSING 255
/* the coverage of a bundled font is read at this size, which is only a handle for the lookup */
#define PROBE_SIZE 12.0

/* in the order they are tried: math letters, symbols of the basic plane, symbols of the other planes */
static NSString *const NoshiFallbackFiles[FALLBACK_COUNT] = {
    @"NotoSansMath-Regular.ttf", @"NotoSansSymbols-Regular.ttf", @"NotoSansSymbols2-Regular.ttf", @"Unifont.otf", @"UnifontUpper.otf",
};

static CGFontRef NoshiFallbackGraphics[FALLBACK_COUNT];
static CTFontRef NoshiFallbackProbes[FALLBACK_COUNT];
static BOOL NoshiFallbackTried[FALLBACK_COUNT];
/* base font family -> (code point -> lookup answer), and "index@size" -> font of a bundled file at a size */
static NSMutableDictionary *NoshiCoverage;
static NSMutableDictionary *NoshiSizedFonts;
static BOOL NoshiCoverageDirty;

/* a lookup of a character that no base font has opens the bundled fonts and asks each of them, which took seconds
   on the main thread for a name in an unusual script */
static NSString *NoshiCoveragePath(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [caches stringByAppendingPathComponent:@"noshigram-glyph-coverage.plist"];
}

static NSString *NoshiCoverageSignature(void) {
    id build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    /* the revision of the bundled fonts: Unifont lost the ideographs and the rare scripts of the upper planes, and an answer saved before that names glyphs it no longer has */
    return [NSString stringWithFormat:@"%@|%@|%@|fonts3", build ? build : @"", [[NSProcessInfo processInfo] operatingSystemVersionString],
            [[NSArray arrayWithObjects:NoshiFallbackFiles count:FALLBACK_COUNT] componentsJoinedByString:@","]];
}

static void NoshiLoadCoverage(void) {
    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:NoshiCoveragePath()];
    if (![[file objectForKey:@"signature"] isEqual:NoshiCoverageSignature()]) return;
    NSDictionary *families = [file objectForKey:@"families"];
    if (![families isKindOfClass:[NSDictionary class]]) return;
    for (NSString *family in families) {
        NSDictionary *stored = [families objectForKey:family];
        if (![stored isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *answers = [NSMutableDictionary dictionaryWithCapacity:stored.count];
        for (NSString *key in stored) {
            NSNumber *answer = [stored objectForKey:key];
            if ([answer isKindOfClass:[NSNumber class]]) [answers setObject:answer forKey:[NSNumber numberWithUnsignedInt:(unsigned)[key intValue]]];
        }
        [NoshiCoverage setObject:answers forKey:family];
    }
}

static NSObject *NoshiFallbackLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSObject alloc] init];
        NoshiCoverage = [[NSMutableDictionary alloc] init];
        NoshiSizedFonts = [[NSMutableDictionary alloc] init];
        NoshiLoadCoverage();
    });
    return lock;
}

/* the new answers are written a few seconds after the first of them, in one file, off the thread that asked; the caller holds the lock */
static void NoshiCoverageChanged(void) {
    if (NoshiCoverageDirty) return;
    NoshiCoverageDirty = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableDictionary *families = [NSMutableDictionary dictionary];
        @synchronized (NoshiFallbackLock()) {
            NoshiCoverageDirty = NO;
            for (NSString *family in NoshiCoverage) {
                NSDictionary *answers = [NoshiCoverage objectForKey:family];
                NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithCapacity:answers.count];
                for (NSNumber *cp in answers) [stored setObject:[answers objectForKey:cp] forKey:[NSString stringWithFormat:@"%u", [cp unsignedIntValue]]];
                [families setObject:stored forKey:family];
            }
        }
        NSDictionary *file = [NSDictionary dictionaryWithObjectsAndKeys:NoshiCoverageSignature(), @"signature", families, @"families", nil];
        if (![file writeToFile:NoshiCoveragePath() atomically:YES]) NSLog(@"noshigram: the glyph coverage was not saved");
    });
}

/* a bundled file is loaded once, from the file itself, so the 11 MB of Unifont are not held in memory */
static CTFontRef NoshiFallbackProbe(NSUInteger index) {
    if (!NoshiFallbackTried[index]) {
        NoshiFallbackTried[index] = YES;
        NSString *path = [[NSBundle mainBundle] pathForResource:NoshiFallbackFiles[index] ofType:nil];
        CGDataProviderRef provider = path ? CGDataProviderCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path]) : NULL;
        CGFontRef graphics = provider ? CGFontCreateWithDataProvider(provider) : NULL;
        if (provider) CGDataProviderRelease(provider);
        if (graphics) {
            NoshiFallbackGraphics[index] = graphics;
            NoshiFallbackProbes[index] = CTFontCreateWithGraphicsFont(graphics, PROBE_SIZE, NULL, NULL);
        }
        if (!NoshiFallbackProbes[index]) NSLog(@"noshigram: fallback font %@ did not load", NoshiFallbackFiles[index]);
    }
    return NoshiFallbackProbes[index];
}

/* before ios 6 the system had no fonts for the letters of the upper planes (the math alphabets, the fancy names built of them), and its answers for a pair of units were not
   to be trusted: it named a glyph, which was the box of the missing ones, and the name was drawn in boxes. the answer there is the call's own, and a font is taken to draw such
   a character only when it says that all of it is mapped */
static BOOL NoshiSystemIsOld(void) {
    return kCFCoreFoundationVersionNumber < 793.0;
}

static BOOL NoshiFontHasGlyph(CTFontRef font, const UniChar *chars, CFIndex count) {
    CGGlyph glyphs[2] = {0, 0};
    BOOL mapped = CTFontGetGlyphsForCharacters(font, chars, glyphs, count);
    /* a pair of units maps to one glyph, kept at the first of them */
    if (count > 1 && NoshiSystemIsOld() && !mapped) return NO;
    return glyphs[0] != 0;
}

/* the font the system would substitute is the box font when it has nothing for the character, and the box font maps every code
   point, so its name has to be told apart */
static BOOL NoshiSystemDraws(CTFontRef base, const UniChar *chars, CFIndex count) {
    /* the only letters of the upper planes that the old system draws are the emoji, which the labels have taken out of the text before this */
    if (count > 1 && NoshiSystemIsOld()) return NO;
    CFStringRef text = CFStringCreateWithCharacters(NULL, chars, count);
    CTFontRef substitute = text ? CTFontCreateForString(base, text, CFRangeMake(0, count)) : NULL;
    BOOL draws = NO;
    if (substitute) {
        CFStringRef name = CTFontCopyPostScriptName(substitute);
        BOOL box = name && CFStringFind(name, CFSTR("LastResort"), 0).length > 0;
        if (name) CFRelease(name);
        draws = !box && NoshiFontHasGlyph(substitute, chars, count);
        CFRelease(substitute);
    }
    if (text) CFRelease(text);
    return draws;
}

static NSUInteger NoshiLookup(uint32_t cp, CTFontRef base, NSMutableDictionary *answers) {
    NSNumber *key = [NSNumber numberWithUnsignedInt:cp];
    NSNumber *known = [answers objectForKey:key];
    if (known) return [known unsignedIntegerValue];
    UniChar chars[2];
    CFIndex count = 1;
    if (cp > 0xFFFF) {
        chars[0] = (UniChar)(0xD800 + ((cp - 0x10000) >> 10));
        chars[1] = (UniChar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
        count = 2;
    } else {
        chars[0] = (UniChar)cp;
    }
    NSUInteger answer = FALLBACK_MISSING;
    if (NoshiFontHasGlyph(base, chars, count) || NoshiSystemDraws(base, chars, count)) {
        answer = FALLBACK_NONE;
    } else {
        for (NSUInteger i = 0; i < FALLBACK_COUNT; ++i) {
            CTFontRef probe = NoshiFallbackProbe(i);
            if (probe && NoshiFontHasGlyph(probe, chars, count)) {
                answer = i + 1;
                break;
            }
        }
    }
    [answers setObject:[NSNumber numberWithUnsignedInteger:answer] forKey:key];
    NoshiCoverageChanged();
    return answer;
}

static CTFontRef NoshiSizedFallback(NSUInteger index, CGFloat size) {
    NSString *key = [NSString stringWithFormat:@"%lu@%.2f", (unsigned long)index, size];
    CTFontRef font = (CTFontRef)[NoshiSizedFonts objectForKey:key];
    if (font) return font;
    if (!NoshiFallbackProbe(index)) return NULL;
    font = CTFontCreateWithGraphicsFont(NoshiFallbackGraphics[index], size, NULL, NULL);
    if (!font) return NULL;
    [NoshiSizedFonts setObject:(id)font forKey:key];
    CFRelease(font);
    return font;
}

static void NoshiSetFallbackRun(NSMutableAttributedString *string, NSUInteger from, NSUInteger to, NSUInteger answer, CGFloat size) {
    if (answer == FALLBACK_NONE || answer == FALLBACK_MISSING || to <= from) return;
    CTFontRef font = NoshiSizedFallback(answer - 1, size);
    if (font) [string addAttribute:(id)kCTFontAttributeName value:(id)font range:NSMakeRange(from, to - from)];
}

/* the answers of one base font family; the caller holds the lock; the weights of a family cover the same
   characters, and a name set in the regular */
static NSMutableDictionary *NoshiAnswersFor(CTFontRef base) {
    CFStringRef name = CTFontCopyFamilyName(base);
    NSString *baseName = name ? [NSString stringWithString:(NSString *)name] : @"";
    if (name) CFRelease(name);
    NSMutableDictionary *answers = [NoshiCoverage objectForKey:baseName];
    if (!answers) {
        answers = [NSMutableDictionary dictionary];
        [NoshiCoverage setObject:answers forKey:baseName];
    }
    return answers;
}

void NoshiApplyFontFallback(NSMutableAttributedString *string, CTFontRef base, CGFloat size) {
    NSUInteger length = string.length;
    if (!length || !base) return;
    uint16_t *units = malloc(sizeof(uint16_t) * length);
    if (!units) {
        NSLog(@"noshigram: no room to look for fallback fonts in %lu units of text", (unsigned long)length);
        return;
    }
    [string.string getCharacters:units range:NSMakeRange(0, length)];
    @synchronized (NoshiFallbackLock()) {
        NSMutableDictionary *answers = NoshiAnswersFor(base);
        NSUInteger runStart = 0, runAnswer = FALLBACK_NONE;
        size_t at = 0;
        while (at < length) {
            uint32_t cp;
            size_t used = noshi_utf16_next(units, length, at, &cp);
            NSUInteger want = FALLBACK_NONE;
            switch (noshi_cp_class_of(cp)) {
            case NOSHI_CP_CHECK: want = NoshiLookup(cp, base, answers); break;
            /* a joiner or a selector has no shape of its own and stays in the font of the character before it */
            case NOSHI_CP_ATTACH: want = runAnswer; break;
            case NOSHI_CP_PLAIN: break;
            }
            if (want != runAnswer) {
                NoshiSetFallbackRun(string, runStart, at, runAnswer, size);
                runStart = at;
                runAnswer = want;
            }
            at += used;
        }
        NoshiSetFallbackRun(string, runStart, length, runAnswer, size);
    }
    free(units);
}

/* marks that take room in no font and say nothing in a name; the joiner and the selectors stay, since emoji sequences are built with them */
static BOOL NoshiIsInvisibleMark(uint32_t cp) {
    return cp == 0x00AD || cp == 0x061C || cp == 0x180E || cp == 0x200B || cp == 0x200C || (cp >= 0x200E && cp <= 0x200F) ||
           (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2060 && cp <= 0x2064) || (cp >= 0x2066 && cp <= 0x206F) || cp == 0xFEFF ||
           (cp >= 0xE0000 && cp <= 0xE007F);
}

void NoshiDropUndrawableCharacters(NSMutableAttributedString *string, CTFontRef base) {
    NSUInteger length = string.length;
    if (!length || !base) return;
    uint16_t *units = malloc(sizeof(uint16_t) * length);
    if (!units) {
        NSLog(@"noshigram: no room to look for undrawable characters in %lu units of text", (unsigned long)length);
        return;
    }
    [string.string getCharacters:units range:NSMakeRange(0, length)];
    NSMutableArray *dropped = [NSMutableArray array];
    NSMutableArray *replacements = [NSMutableArray array];
    @synchronized (NoshiFallbackLock()) {
        NSMutableDictionary *answers = NoshiAnswersFor(base);
        static NSMutableSet *logged;
        if (!logged) logged = [[NSMutableSet alloc] init];
        size_t at = 0;
        while (at < length) {
            uint32_t cp;
            size_t used = noshi_utf16_next(units, length, at, &cp);
            BOOL invisible = NoshiIsInvisibleMark(cp);
            BOOL missing = !invisible && noshi_cp_class_of(cp) == NOSHI_CP_CHECK && NoshiLookup(cp, base, answers) == FALLBACK_MISSING;
            if (invisible || missing) {
                NSRange range = NSMakeRange(at, used);
                [dropped addObject:[NSValue valueWithRange:range]];
                /* a letter no font has may still be a styled form of plain ones (the math alphabets, the full width and circled letters), and then those are drawn in its place */
                NSString *plain = nil;
                if (missing) {
                    NSString *one = [NSString stringWithCharacters:units + at length:used];
                    NSString *folded = [one decomposedStringWithCompatibilityMapping];
                    BOOL drawable = folded.length && ![folded isEqualToString:one];
                    for (NSUInteger i = 0; drawable && i < folded.length; ++i) {
                        unichar unit = [folded characterAtIndex:i];
                        drawable = unit >= 0x20 && !(unit >= 0xD800 && unit <= 0xDFFF) && NoshiFontHasGlyph(base, &unit, 1);
                    }
                    if (drawable) plain = folded;
                }
                [replacements addObject:plain ? (id)plain : (id)[NSNull null]];
                NSNumber *key = [NSNumber numberWithUnsignedInt:cp];
                if (![logged containsObject:key]) {
                    [logged addObject:key];
                    NSLog(@"noshigram: a name is drawn without U+%04X (%@)", cp, invisible ? @"invisible mark" : @"no font has a glyph");
                }
            }
            at += used;
        }
    }
    free(units);
    for (NSUInteger i = dropped.count; i-- > 0;) {
        NSRange range = [[dropped objectAtIndex:i] rangeValue];
        id plain = [replacements objectAtIndex:i];
        if ([plain isKindOfClass:[NSString class]]) [string replaceCharactersInRange:range withString:plain];
        else [string deleteCharactersInRange:range];
    }
}

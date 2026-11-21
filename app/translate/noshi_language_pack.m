#import "noshi_language_pack.h"

#import "noshi_language.h"

#include "noshi_langpack.h"

NSString *NoshiInterfaceLanguageForPackCode(NSString *packCode) {
    NSString *wanted = NoshiNormalizedLanguageCode(packCode);
    if (!wanted.length) return nil;
    for (NSString *code in NoshiInterfaceLanguageCodes()) {
        if (NoshiIsCustomLanguage(code)) continue;
        if ([NoshiNormalizedLanguageCode(code) isEqualToString:wanted]) return code;
    }
    return nil;
}

static NSDictionary *NoshiStringsOf(NSString *code) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:code];
    NSDictionary *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    if (path && !strings) NSLog(@"noshigram: the texts of %@ could not be read from %@", code, path);
    return strings;
}

int NoshiInterfaceLanguageCompleteness(NSString *code) {
    NSDictionary *english = NoshiStringsOf(@"en"), *own = NoshiStringsOf(code);
    if (!english.count || !own.count) return 0;
    if ([code isEqualToString:@"en"]) return 100;
    NSUInteger translated = 0;
    for (NSString *key in english) {
        NSString *text = [own objectForKey:key];
        if ([text isKindOfClass:[NSString class]] && text.length) ++translated;
    }
    return noshi_langpack_percent((int32_t)translated, (int32_t)english.count);
}

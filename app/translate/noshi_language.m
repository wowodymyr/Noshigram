#import "noshi_language.h"

#import <objc/runtime.h>

#include <string.h>

NSString *const NoshiLanguageDidChangeNotification = @"NoshiLanguageDidChange";

static NSString *const NoshiLanguageKey = @"noshigram.language";

static NSString *const NoshiCustomLanguagesKey = @"noshigram.language.custom";
#define CUSTOM_FILE_BYTES_MAX (2 * 1024 * 1024)
#define CUSTOM_KEYS_MAX 20000
#define CUSTOM_LANGUAGES_MAX 12

static NSString *NoshiCustomDirectory(void) {
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [[support stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"Languages"];
}

static NSString *NoshiCustomBundlePath(NSString *code) {
    return [[NoshiCustomDirectory() stringByAppendingPathComponent:code] stringByAppendingPathExtension:@"lproj"];
}

/* code -> {name, english, base} */
static NSDictionary *NoshiCustomLanguages(void) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiCustomLanguagesKey];
    return all ? all : [NSDictionary dictionary];
}

NSArray *NoshiCustomLanguageCodes(void) {
    return [[NoshiCustomLanguages() allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

BOOL NoshiIsCustomLanguage(NSString *code) {
    return code && [NoshiCustomLanguages() objectForKey:code] != nil;
}

NSArray *NoshiInterfaceLanguageCodes(void) {
    return [[NSArray arrayWithObjects:@"en", @"ru", nil] arrayByAddingObjectsFromArray:NoshiCustomLanguageCodes()];
}

NSString *NoshiInterfaceLanguageChoice(void) {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiLanguageKey];
    return [NoshiInterfaceLanguageCodes() containsObject:code] ? code : @"";
}

NSString *NoshiInterfaceLanguage(void) {
    NSString *choice = NoshiInterfaceLanguageChoice();
    if (NoshiIsCustomLanguage(choice)) {
        NSString *base = [[NoshiCustomLanguages() objectForKey:choice] objectForKey:@"base"];
        return base.length ? base : @"en";
    }
    if (choice.length) return choice;
    for (NSString *language in [NSLocale preferredLanguages]) {
        NSString *base = [[language componentsSeparatedByString:@"-"] objectAtIndex:0];
        if ([NoshiInterfaceLanguageCodes() containsObject:base]) return base;
    }
    return @"en";
}

/* the main bundle answers the texts of the chosen lproj; its class is swapped once for this one, which is how NSLocalizedString can follow a choice made
   while the app runs */
static NSBundle *NoshiChosenBundle;

@interface NoshiLocalizedBundle : NSBundle
@end

static NSBundle *NoshiEnglishBundle;

@implementation NoshiLocalizedBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    NSBundle *chosen = NoshiChosenBundle;
    NSString *text = chosen ? [chosen localizedStringForKey:key value:value table:table] : [super localizedStringForKey:key value:value table:table];
    /* a text the language of the bundle or of the phone lacks (a custom pack translates what it can, an lproj of another build may lack a newer key, an lproj that
       does not parse has none) is the English one, never the bare key */
    if ((!text.length || [text isEqualToString:key]) && NoshiEnglishBundle && chosen != NoshiEnglishBundle) {
        NSString *english = [NoshiEnglishBundle localizedStringForKey:key value:value table:table];
        if (english.length) return english;
    }
    return text;
}
@end

NSString *NoshiInterfaceLanguageVariant(void) {
    NSString *choice = NoshiInterfaceLanguageChoice();
    return choice.length ? choice : NoshiInterfaceLanguage();
}

void NoshiApplyInterfaceLanguage(void) {
    NSString *choice = NoshiInterfaceLanguageChoice();
    NSBundle *main = [NSBundle mainBundle];
    if (!NoshiEnglishBundle) {
        NSString *english = [main pathForResource:@"en" ofType:@"lproj"];
        NoshiEnglishBundle = english ? [[NSBundle bundleWithPath:english] retain] : nil;
        if (!NoshiEnglishBundle) NSLog(@"noshigram: the bundle has no en.lproj, texts that are missing show as their keys");
    }
    /* the fallback to English works with no choice made too, so the swap is made at every launch */
    if (object_getClass(main) != [NoshiLocalizedBundle class]) object_setClass(main, [NoshiLocalizedBundle class]);
    [NoshiChosenBundle release];
    NoshiChosenBundle = nil;
    if (!choice.length) return;
    NSString *path = NoshiIsCustomLanguage(choice) ? NoshiCustomBundlePath(choice) : [main pathForResource:choice ofType:@"lproj"];
    NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : nil;
    /* a stored choice whose texts are gone (a pack deleted by hand, an lproj this build does not ship) must not keep the app on keys: the choice is dropped */
    if (!bundle || ![bundle pathForResource:@"Localizable" ofType:@"strings"]) {
        NSLog(@"noshigram: no texts for the language %@, back to the language of the phone", choice);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiLanguageKey];
        return;
    }
    NoshiChosenBundle = [bundle retain];
}

void NoshiSetInterfaceLanguage(NSString *code) {
    NSString *kept = [NoshiInterfaceLanguageCodes() containsObject:code] ? code : @"";
    [[NSUserDefaults standardUserDefaults] setObject:kept forKey:NoshiLanguageKey];
    NoshiApplyInterfaceLanguage();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiLanguageDidChangeNotification object:nil];
}

/* the placeholders of a text in order, as the letters that end each: "%@ of %lld" gives "@", "d" */
static NSString *NoshiPlaceholders(NSString *text) {
    NSMutableString *kinds = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; ++i) {
        if ([text characterAtIndex:i] != '%') continue;
        ++i;
        while (i < text.length && strchr("-+ #0123456789.$lhqLzjt", (int)[text characterAtIndex:i]) && [text characterAtIndex:i] < 128) ++i;
        if (i >= text.length) return nil;
        unichar kind = [text characterAtIndex:i];
        if (kind == '%') continue;
        [kinds appendFormat:@"%C", kind];
    }
    return kinds;
}

static NSDictionary *NoshiEnglishTexts(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
    return path ? [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Localizable.strings"]] : nil;
}

NSString *NoshiInstallCustomLanguage(NSString *path, NSUInteger *accepted, NSUInteger *skipped) {
    if (accepted) *accepted = 0;
    if (skipped) *skipped = 0;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (!attributes) return NSLocalizedString(@"language.custom.unreadable", nil);
    if ([attributes fileSize] > CUSTOM_FILE_BYTES_MAX) return NSLocalizedString(@"language.custom.large", nil);
    NSDictionary *texts = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![texts isKindOfClass:[NSDictionary class]] || !texts.count) return NSLocalizedString(@"language.custom.unreadable", nil);
    if (texts.count > CUSTOM_KEYS_MAX) return NSLocalizedString(@"language.custom.large", nil);
    NSDictionary *english = NoshiEnglishTexts();
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-_"];
    NSString *stem = [[path lastPathComponent] stringByDeletingPathExtension];
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < stem.length && name.length < 32; ++i) {
        unichar c = [stem characterAtIndex:i];
        if (c < 128 && [allowed characterIsMember:c]) [name appendFormat:@"%C", c];
    }
    if (!name.length) return NSLocalizedString(@"language.custom.name", nil);
    NSString *code = [@"x-" stringByAppendingString:[name lowercaseString]];
    BOOL replacing = NoshiIsCustomLanguage(code);
    if (!replacing && NoshiCustomLanguageCodes().count >= CUSTOM_LANGUAGES_MAX) return NSLocalizedString(@"language.custom.many", nil);
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    NSUInteger skippedCount = 0;
    for (id key in texts) {
        id value = [texts objectForKey:key];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) continue;
        NSString *original = [english objectForKey:key];
        if (!original) continue;
        if (![NoshiPlaceholders(value) isEqualToString:NoshiPlaceholders(original)]) { ++skippedCount; continue; }
        [kept setObject:value forKey:key];
    }
    if (!kept.count) return NSLocalizedString(@"language.custom.empty", nil);
    NSString *own = [texts objectForKey:@"language.name"], *englishName = [texts objectForKey:@"language.english"], *base = [texts objectForKey:@"language.base"];
    if (![own isKindOfClass:[NSString class]] || !own.length) own = stem;
    if (![englishName isKindOfClass:[NSString class]] || !englishName.length) englishName = own;
    base = [base isKindOfClass:[NSString class]] && [NoshiTranslationLanguageCodes() containsObject:base] ? base : @"en";
    NSString *bundlePath = NoshiCustomBundlePath(code);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:bundlePath withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: custom language directory: %@", error);
        return NSLocalizedString(@"language.custom.save", nil);
    }
    if (![kept writeToFile:[bundlePath stringByAppendingPathComponent:@"Localizable.strings"] atomically:YES]) return NSLocalizedString(@"language.custom.save", nil);
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:NoshiCustomLanguages()];
    [all setObject:[NSDictionary dictionaryWithObjectsAndKeys:own, @"name", englishName, @"english", base, @"base", nil] forKey:code];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiCustomLanguagesKey];
    if (accepted) *accepted = kept.count;
    if (skipped) *skipped = skippedCount;
    /* a pack that is in force again is read again from its new file */
    if ([NoshiInterfaceLanguageChoice() isEqualToString:code]) NoshiApplyInterfaceLanguage();
    return nil;
}

void NoshiRemoveCustomLanguage(NSString *code) {
    if (!NoshiIsCustomLanguage(code)) return;
    BOOL inForce = [NoshiInterfaceLanguageChoice() isEqualToString:code];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:NoshiCustomLanguages()];
    [all removeObjectForKey:code];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:NoshiCustomLanguagesKey];
    [[NSFileManager defaultManager] removeItemAtPath:NoshiCustomBundlePath(code) error:NULL];
    if (inForce) NoshiSetInterfaceLanguage(@"");
}

NSString *NoshiCustomLanguageTemplatePath(NSString *language) {
    NSString *source = [[[NSBundle mainBundle] pathForResource:language ofType:@"lproj"] stringByAppendingPathComponent:@"Localizable.strings"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:source]) return nil;
    NSString *target = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"noshigram-template-%@.strings", language]];
    [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:source toPath:target error:&error]) {
        NSLog(@"noshigram: language template: %@", error);
        return nil;
    }
    return target;
}

NSLocale *NoshiFormattingLocale(void) {
    NSArray *languages = [NSLocale preferredLanguages];
    NSString *system = languages.count ? [[[languages objectAtIndex:0] componentsSeparatedByString:@"-"] objectAtIndex:0] : @"en";
    NSString *own = NoshiInterfaceLanguage();
    if ([system isEqualToString:own]) return [NSLocale currentLocale];
    return [[[NSLocale alloc] initWithLocaleIdentifier:own] autorelease];
}

NSArray *NoshiTranslationLanguageCodes(void) {
    static NSArray *codes;
    if (!codes) {
        codes = [[@"sq ar am az ga et eu be bg is pl bs fa af da de ru fr tl fi fy km ka gu kk ht ko ha nl ky gl ca cs kn co hr ku la lv lo lt lb ro mg mt mr ml ms mk mi mn "
                   "bn my hmn xh zu ne no pa pt ps ny ja sv sm sr st si eo sk sl sw gd ceb so tg te ta th tr cy ur uk uz es iw el haw sd hu sn hy ig it yi hi su id jw en yo vi "
                   "zh-TW zh-CN zh" componentsSeparatedByString:@" "] retain];
    }
    return codes;
}

NSString *NoshiNormalizedLanguageCode(NSString *code) {
    return [[code stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
}

static NSString *NoshiCapitalized(NSString *name) {
    if (!name.length) return name;
    return [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]];
}

static NSString *NoshiNameIn(NSString *code, NSString *inLanguage) {
    NSString *fixed = [code stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    /* "iw" and "jw" are the old codes of Hebrew and Javanese that the translators still use */
    if ([fixed isEqualToString:@"iw"]) fixed = @"he";
    if ([fixed isEqualToString:@"jw"]) fixed = @"jv";
    NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:inLanguage] autorelease];
    NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:[fixed stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
    return name.length ? NoshiCapitalized(name) : code;
}

NSString *NoshiLanguageName(NSString *code) {
    return NoshiNameIn(code, NoshiInterfaceLanguage());
}

NSString *NoshiNativeLanguageName(NSString *code) {
    if (NoshiIsCustomLanguage(code)) return [[NoshiCustomLanguages() objectForKey:code] objectForKey:@"name"];
    return NoshiNameIn(code, code);
}

NSString *NoshiEnglishLanguageName(NSString *code) {
    if (NoshiIsCustomLanguage(code)) return [[NoshiCustomLanguages() objectForKey:code] objectForKey:@"english"];
    return NoshiNameIn(code, @"en");
}

NSString *NoshiGuessLanguageOfText(NSString *text) {
    NSUInteger cyrillic = 0, latin = 0, greek = 0, hebrew = 0, arabic = 0, thai = 0, hangul = 0, kana = 0, han = 0, ukrainian = 0;
    NSUInteger length = MIN(text.length, 400);
    for (NSUInteger i = 0; i < length; ++i) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= 0xC0 && c <= 0x24F)) ++latin;
        else if (c >= 0x400 && c <= 0x4FF) { ++cyrillic; if (c == 0x456 || c == 0x457 || c == 0x454 || c == 0x491 || c == 0x406 || c == 0x407 || c == 0x404 || c == 0x490) ++ukrainian; }
        else if (c >= 0x370 && c <= 0x3FF) ++greek;
        else if (c >= 0x590 && c <= 0x5FF) ++hebrew;
        else if (c >= 0x600 && c <= 0x6FF) ++arabic;
        else if (c >= 0xE00 && c <= 0xE7F) ++thai;
        else if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF)) ++hangul;
        else if (c >= 0x3040 && c <= 0x30FF) ++kana;
        else if (c >= 0x4E00 && c <= 0x9FFF) ++han;
    }
    NSUInteger total = cyrillic + latin + greek + hebrew + arabic + thai + hangul + kana + han;
    if (total < 2) return nil;
    NSUInteger best = MAX(MAX(MAX(cyrillic, latin), MAX(greek, hebrew)), MAX(MAX(arabic, thai), MAX(hangul, MAX(kana, han))));
    /* a text of no clear majority is a mix, which no guess can serve */
    if (best * 10 < total * 6) return nil;
    if (best == cyrillic) return ukrainian > 0 ? @"uk" : @"ru";
    if (best == latin) return @"en";
    if (best == greek) return @"el";
    if (best == hebrew) return @"iw";
    if (best == arabic) return @"ar";
    if (best == thai) return @"th";
    if (best == hangul) return @"ko";
    if (kana > 0) return @"ja";
    return @"zh";
}

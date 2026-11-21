#import "noshi_translate_config.h"

#import "noshi_language.h"

#include "noshi_translate_llm.h"

static NSString *const NoshiTrPrefix = @"noshigram.tr.";

static NSUserDefaults *NoshiTrDefaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static NSString *NoshiTrKey(NSString *name) {
    return [NoshiTrPrefix stringByAppendingString:name];
}

static NSString *NoshiTrString(NSString *name) {
    NSString *value = [NoshiTrDefaults() stringForKey:NoshiTrKey(name)];
    return value ? value : @"";
}

static void NoshiTrSetString(NSString *name, NSString *value) {
    NSString *kept = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (kept.length) [NoshiTrDefaults() setObject:kept forKey:NoshiTrKey(name)];
    else [NoshiTrDefaults() removeObjectForKey:NoshiTrKey(name)];
}

static BOOL NoshiTrBool(NSString *name, BOOL fallback) {
    id value = [NoshiTrDefaults() objectForKey:NoshiTrKey(name)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static void NoshiTrSetBool(NSString *name, BOOL value) {
    [NoshiTrDefaults() setBool:value forKey:NoshiTrKey(name)];
}

static int NoshiTrInt(NSString *name, int fallback) {
    id value = [NoshiTrDefaults() objectForKey:NoshiTrKey(name)];
    return [value isKindOfClass:[NSNumber class]] ? [value intValue] : fallback;
}

static void NoshiTrSetInt(NSString *name, int value) {
    [NoshiTrDefaults() setInteger:value forKey:NoshiTrKey(name)];
}

#pragma mark providers

NSArray *NoshiTranslateProviderList(void) {
    return [NSArray arrayWithObjects:[NSNumber numberWithInt:NoshiTranslateProviderGoogle], [NSNumber numberWithInt:NoshiTranslateProviderYandex],
            [NSNumber numberWithInt:NoshiTranslateProviderLingo], [NSNumber numberWithInt:NoshiTranslateProviderBing],
            [NSNumber numberWithInt:NoshiTranslateProviderDeepL],
            [NSNumber numberWithInt:NoshiTranslateProviderTelegram], [NSNumber numberWithInt:NoshiTranslateProviderTranSmart],
            [NSNumber numberWithInt:NoshiTranslateProviderLLM], nil];
}

NSString *NoshiTranslateProviderName(int provider) {
    switch (provider) {
    case NoshiTranslateProviderYandex: return NSLocalizedString(@"tr.provider.yandex", nil);
    case NoshiTranslateProviderLingo: return NSLocalizedString(@"tr.provider.lingo", nil);
    case NoshiTranslateProviderBing: return NSLocalizedString(@"tr.provider.bing", nil);
    case NoshiTranslateProviderDeepL: return NSLocalizedString(@"tr.provider.deepl", nil);
    case NoshiTranslateProviderTelegram: return NSLocalizedString(@"tr.provider.telegram", nil);
    case NoshiTranslateProviderTranSmart: return NSLocalizedString(@"tr.provider.transmart", nil);
    case NoshiTranslateProviderLLM: return NSLocalizedString(@"tr.provider.llm", nil);
    default: return NSLocalizedString(@"tr.provider.google", nil);
    }
}

BOOL NoshiTranslateButtonEnabled(void) { return NoshiTrBool(@"show", NO); }
void NoshiTranslateSetButtonEnabled(BOOL on) { NoshiTrSetBool(@"show", on); }

int NoshiTranslateProviderChoice(void) {
    int stored = NoshiTrInt(@"provider", NoshiTranslateProviderGoogle);
    return [NoshiTranslateProviderList() containsObject:[NSNumber numberWithInt:stored]] ? stored : NoshiTranslateProviderGoogle;
}

void NoshiTranslateSetProviderChoice(int provider) { NoshiTrSetInt(@"provider", provider); }

int NoshiTranslateOriginalMode(void) {
    int mode = NoshiTrInt(@"original", 0);
    return mode >= 0 && mode <= 2 ? mode : 0;
}

void NoshiTranslateSetOriginalMode(int mode) { NoshiTrSetInt(@"original", mode); }

#pragma mark languages

NSString *NoshiTranslateTargetChoice(void) { return NoshiTrString(@"target"); }
void NoshiTranslateSetTargetChoice(NSString *code) { NoshiTrSetString(@"target", code); }

NSString *NoshiTranslateTargetLanguage(void) {
    NSString *choice = NoshiTranslateTargetChoice();
    return choice.length ? choice : NoshiInterfaceLanguage();
}

NSArray *NoshiTranslateSkippedLanguages(void) {
    NSArray *stored = [NoshiTrDefaults() arrayForKey:NoshiTrKey(@"skipped")];
    if (!stored) return [NSArray arrayWithObject:NoshiInterfaceLanguage()];
    NSMutableArray *codes = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]] && [item length]) [codes addObject:[item lowercaseString]];
    }
    return codes;
}

void NoshiTranslateSetSkippedLanguages(NSArray *codes) {
    /* the language of the interface alone is what no choice at all means, so it is not stored */
    if (codes.count == 1 && [[codes objectAtIndex:0] isEqualToString:NoshiInterfaceLanguage()]) {
        [NoshiTrDefaults() removeObjectForKey:NoshiTrKey(@"skipped")];
        return;
    }
    [NoshiTrDefaults() setObject:codes forKey:NoshiTrKey(@"skipped")];
}

BOOL NoshiTranslateSkips(NSString *code) {
    if (!code.length) return NO;
    NSString *wanted = NoshiNormalizedLanguageCode(code);
    for (NSString *skipped in NoshiTranslateSkippedLanguages()) {
        if ([NoshiNormalizedLanguageCode(skipped) isEqualToString:wanted]) return YES;
    }
    return NO;
}

NSString *NoshiTranslatePreferredText(void) { return NoshiTrString(@"preferred"); }
void NoshiTranslateSetPreferredText(NSString *text) { NoshiTrSetString(@"preferred", text); }

NSArray *NoshiTranslatePreferredLanguages(void) {
    NSMutableArray *codes = [NSMutableArray array];
    for (NSString *part in [NoshiTranslatePreferredText() componentsSeparatedByString:@","]) {
        NSString *code = NoshiNormalizedLanguageCode([part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
        if (code.length && ![codes containsObject:code]) [codes addObject:code];
    }
    return codes;
}

BOOL NoshiTranslateKeepsPreferences(void) { return NoshiTrBool(@"keep", NO); }
void NoshiTranslateSetKeepsPreferences(BOOL on) { NoshiTrSetBool(@"keep", on); }

void NoshiTranslateInterfaceLanguageChanged(NSString *previous, NSString *current) {
    if (NoshiTranslateKeepsPreferences() || [previous isEqualToString:current]) return;
    /* the list is read with the old language of the interface as its default before the new one is stored */
    NSMutableArray *codes = [NSMutableArray array];
    BOOL stored = [NoshiTrDefaults() arrayForKey:NoshiTrKey(@"skipped")] != nil;
    if (stored) [codes addObjectsFromArray:NoshiTranslateSkippedLanguages()];
    else if (previous.length) [codes addObject:previous];
    if (previous.length && current.length && [codes containsObject:previous] && ![codes containsObject:current]) [codes removeObject:previous];
    if (current.length && ![codes containsObject:current]) [codes addObject:current];
    NoshiTranslateSetSkippedLanguages(codes);
}

#pragma mark google and deepl

NSString *NoshiTranslateGoogleKey(void) { return NoshiTrString(@"google.key"); }
void NoshiTranslateSetGoogleKey(NSString *key) { NoshiTrSetString(@"google.key", key); }
BOOL NoshiTranslateGoogleNew(void) { return NoshiTrBool(@"google.new", YES); }
void NoshiTranslateSetGoogleNew(BOOL on) { NoshiTrSetBool(@"google.new", on); }

NSString *NoshiTranslateDeepLKey(void) { return NoshiTrString(@"deepl.key"); }
void NoshiTranslateSetDeepLKey(NSString *key) { NoshiTrSetString(@"deepl.key", key); }

int NoshiTranslateDeepLFormality(void) {
    int value = NoshiTrInt(@"deepl.formality", 0);
    return value >= 0 && value <= 2 ? value : 0;
}

void NoshiTranslateSetDeepLFormality(int formality) { NoshiTrSetInt(@"deepl.formality", formality); }

#pragma mark ai translator

NSArray *NoshiLlmPresetList(void) {
    int order[] = {NoshiLlmPresetCustom, NoshiLlmPresetOpenAI, NoshiLlmPresetGoogleAIStudio, NoshiLlmPresetVertex, NoshiLlmPresetGroq,
                   NoshiLlmPresetDeepSeek, NoshiLlmPresetXAI, NoshiLlmPresetCerebras, NoshiLlmPresetOllamaCloud, NoshiLlmPresetOpenRouter,
                   NoshiLlmPresetVercelGateway};
    NSMutableArray *list = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(order) / sizeof(order[0]); ++i) [list addObject:[NSNumber numberWithInt:order[i]]];
    return list;
}

NSString *NoshiLlmPresetName(int preset) {
    switch (preset) {
    case NoshiLlmPresetOpenAI: return @"OpenAI";
    case NoshiLlmPresetGoogleAIStudio: return @"Google AI Studio";
    case NoshiLlmPresetVertex: return @"Google Vertex";
    case NoshiLlmPresetGroq: return @"Groq";
    case NoshiLlmPresetDeepSeek: return @"DeepSeek";
    case NoshiLlmPresetXAI: return @"SpaceXAI";
    case NoshiLlmPresetCerebras: return @"Cerebras";
    case NoshiLlmPresetOllamaCloud: return @"Ollama";
    case NoshiLlmPresetOpenRouter: return @"OpenRouter";
    case NoshiLlmPresetVercelGateway: return @"Vercel AI Gateway";
    default: return NSLocalizedString(@"tr.llm.custom", nil);
    }
}

int NoshiLlmPresetChoice(void) {
    int stored = NoshiTrInt(@"llm.preset", NoshiLlmPresetCustom);
    return [NoshiLlmPresetList() containsObject:[NSNumber numberWithInt:stored]] ? stored : NoshiLlmPresetCustom;
}

void NoshiLlmSetPresetChoice(int preset) { NoshiTrSetInt(@"llm.preset", preset); }

NSString *NoshiLlmKey(int preset) { return NoshiTrString([NSString stringWithFormat:@"llm.key.%d", preset]); }
void NoshiLlmSetKey(int preset, NSString *key) { NoshiTrSetString([NSString stringWithFormat:@"llm.key.%d", preset], key); }

NSString *NoshiLlmSavedModel(int preset) { return NoshiTrString([NSString stringWithFormat:@"llm.model.%d", preset]); }
void NoshiLlmSetModel(int preset, NSString *model) { NoshiTrSetString([NSString stringWithFormat:@"llm.model.%d", preset], model); }

NSString *NoshiLlmDefaultModel(int preset) {
    switch (preset) {
    case NoshiLlmPresetOpenAI: return @"gpt-5.6-luna";
    case NoshiLlmPresetGoogleAIStudio: return @"gemini-flash-lite-latest";
    case NoshiLlmPresetVertex: return @"gemini-3.5-flash-lite";
    case NoshiLlmPresetGroq: return @"openai/gpt-oss-120b";
    case NoshiLlmPresetDeepSeek: return @"deepseek-v4-flash";
    case NoshiLlmPresetXAI: return @"";
    case NoshiLlmPresetCerebras: return @"gpt-oss-120b";
    case NoshiLlmPresetOllamaCloud: return @"gemma4:31b";
    case NoshiLlmPresetOpenRouter: return @"openrouter/free";
    case NoshiLlmPresetVercelGateway: return @"google/gemma-4-31b-it";
    default: return NSLocalizedString(@"tr.llm.model.default", nil);
    }
}

NSString *NoshiLlmModel(int preset) {
    NSString *saved = NoshiLlmSavedModel(preset);
    return saved.length ? saved : NoshiLlmDefaultModel(preset);
}

NSString *NoshiLlmCustomURL(void) { return NoshiTrString(@"llm.url"); }
void NoshiLlmSetCustomURL(NSString *url) { NoshiTrSetString(@"llm.url", NoshiLlmNormalizedURL(url)); }

NSString *NoshiLlmNormalizedURL(NSString *text) {
    NSString *url = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!url.length) return @"";
    NSString *lower = [url lowercaseString];
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) url = [@"https://" stringByAppendingString:url];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    NSString *tail = @"/chat/completions";
    if ([[url lowercaseString] hasSuffix:tail]) {
        url = [url substringToIndex:url.length - tail.length];
        while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    }
    /* a host is required; a text with spaces or no name after the scheme is no address */
    NSURL *parsed = [NSURL URLWithString:url];
    if (!parsed || !parsed.host.length) return @"";
    return url;
}

NSString *NoshiLlmBaseURL(int preset) {
    switch (preset) {
    case NoshiLlmPresetOpenAI: return @"https://api.openai.com/v1";
    case NoshiLlmPresetGoogleAIStudio: return @"https://generativelanguage.googleapis.com/v1beta/openai";
    case NoshiLlmPresetGroq: return @"https://api.groq.com/openai/v1";
    case NoshiLlmPresetDeepSeek: return @"https://api.deepseek.com/v1";
    case NoshiLlmPresetXAI: return @"https://api.x.ai/v1";
    case NoshiLlmPresetCerebras: return @"https://api.cerebras.ai/v1";
    case NoshiLlmPresetOllamaCloud: return @"https://ollama.com/v1";
    case NoshiLlmPresetOpenRouter: return @"https://openrouter.ai/api/v1";
    case NoshiLlmPresetVercelGateway: return @"https://ai-gateway.vercel.sh/v1";
    case NoshiLlmPresetVertex: return @"https://aiplatform.googleapis.com/v1";
    default: {
        NSString *typed = NoshiLlmCustomURL();
        return typed.length ? typed : @"https://generativelanguage.googleapis.com/v1beta/openai";
    }
    }
}

NSString *NoshiLlmSystemPrompt(void) { return NoshiTrString(@"llm.system"); }
void NoshiLlmSetSystemPrompt(NSString *text) { NoshiTrSetString(@"llm.system", text); }
NSString *NoshiLlmUserPrompt(void) { return NoshiTrString(@"llm.user"); }
void NoshiLlmSetUserPrompt(NSString *text) { NoshiTrSetString(@"llm.user", text); }

float NoshiLlmTemperature(void) {
    id value = [NoshiTrDefaults() objectForKey:NoshiTrKey(@"llm.temperature")];
    float temperature = [value isKindOfClass:[NSNumber class]] ? [value floatValue] : 0.7f;
    return temperature < 0 ? 0 : (temperature > 2 ? 2 : temperature);
}

void NoshiLlmSetTemperature(float value) {
    [NoshiTrDefaults() setFloat:value forKey:NoshiTrKey(@"llm.temperature")];
}

BOOL NoshiLlmUsesContext(void) { return NoshiTrBool(@"llm.context", NO); }
void NoshiLlmSetUsesContext(BOOL on) { NoshiTrSetBool(@"llm.context", on); }

NSArray *NoshiLlmContextCounts(void) {
    return [NSArray arrayWithObjects:[NSNumber numberWithInt:1], [NSNumber numberWithInt:3], [NSNumber numberWithInt:5], [NSNumber numberWithInt:7],
            [NSNumber numberWithInt:10], nil];
}

int NoshiLlmContextIndex(void) {
    int index = NoshiTrInt(@"llm.context.size", 2);
    return index >= 0 && index < (int)NoshiLlmContextCounts().count ? index : 2;
}

void NoshiLlmSetContextIndex(int index) { NoshiTrSetInt(@"llm.context.size", index); }

int NoshiLlmContextCount(void) {
    return [[NoshiLlmContextCounts() objectAtIndex:(NSUInteger)NoshiLlmContextIndex()] intValue];
}

BOOL NoshiLlmSupportsTemperature(int preset, NSString *model) {
    if (preset == NoshiLlmPresetVertex) return NO;
    return noshi_llm_supports_temperature(model.UTF8String) != 0;
}

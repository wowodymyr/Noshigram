#import <Foundation/Foundation.h>

/* the settings of the translator; the numbers of the providers and of the model providers are those, so a stored
   choice means the same there */

typedef enum {
    NoshiTranslateProviderGoogle = 1,
    NoshiTranslateProviderYandex = 3,
    NoshiTranslateProviderLingo = 4,
    NoshiTranslateProviderBing = 5,
    NoshiTranslateProviderDeepL = 7,
    NoshiTranslateProviderTelegram = 8,
    NoshiTranslateProviderTranSmart = 9,
    NoshiTranslateProviderLLM = 10
} NoshiTranslateProviderId;

typedef enum {
    NoshiLlmPresetCustom = 0,
    NoshiLlmPresetOpenAI = 1,
    NoshiLlmPresetGoogleAIStudio = 2,
    NoshiLlmPresetGroq = 3,
    NoshiLlmPresetDeepSeek = 4,
    NoshiLlmPresetXAI = 5,
    NoshiLlmPresetCerebras = 6,
    NoshiLlmPresetOllamaCloud = 7,
    NoshiLlmPresetOpenRouter = 8,
    NoshiLlmPresetVercelGateway = 9,
    NoshiLlmPresetVertex = 10
} NoshiLlmPreset;

/* the providers in the order of the list, as NSNumbers of NoshiTranslateProviderId */
NSArray *NoshiTranslateProviderList(void);
NSString *NoshiTranslateProviderName(int provider);

/* the Translate button in the menu of a message, off until it is switched on */
BOOL NoshiTranslateButtonEnabled(void);
void NoshiTranslateSetButtonEnabled(BOOL on);

int NoshiTranslateProviderChoice(void);
void NoshiTranslateSetProviderChoice(int provider);

/* whether the original goes with the translation: 0 off, 1 manual only, 2 on */
int NoshiTranslateOriginalMode(void);
void NoshiTranslateSetOriginalMode(int mode);

/* the language to translate into: a code, or an empty string for the language of the app */
NSString *NoshiTranslateTargetChoice(void);
void NoshiTranslateSetTargetChoice(NSString *code);
/* the code in force: the choice, or else the language of the interface */
NSString *NoshiTranslateTargetLanguage(void);

/* the codes of the languages that get no Translate button, lowercase; until the person picks some it is the
   language of the interface alone */
NSArray *NoshiTranslateSkippedLanguages(void);
void NoshiTranslateSetSkippedLanguages(NSArray *codes);
BOOL NoshiTranslateSkips(NSString *code);

/* the languages offered first in the list of targets, as the person typed them ("ja, zh_cn") and as codes */
NSString *NoshiTranslatePreferredText(void);
void NoshiTranslateSetPreferredText(NSString *text);
NSArray *NoshiTranslatePreferredLanguages(void);

/* keep the choices above when the language of the app changes; off, the new language of the app replaces the old one among the skipped languages */
BOOL NoshiTranslateKeepsPreferences(void);
void NoshiTranslateSetKeepsPreferences(BOOL on);
/* the app language changed from previous to current: moves the language of the interface among the skipped ones unless the preferences are kept */
void NoshiTranslateInterfaceLanguageChanged(NSString *previous, NSString *current);

/* Google: a Cloud key sends the text to the cloud API, and the experimental switch picks the translate-pa endpoint over the one of the Google app */
NSString *NoshiTranslateGoogleKey(void);
void NoshiTranslateSetGoogleKey(NSString *key);
BOOL NoshiTranslateGoogleNew(void);
void NoshiTranslateSetGoogleNew(BOOL on);

/* DeepL: an own key, and the tone: 0 as it comes, 1 informal, 2 formal */
NSString *NoshiTranslateDeepLKey(void);
void NoshiTranslateSetDeepLKey(NSString *key);
int NoshiTranslateDeepLFormality(void);
void NoshiTranslateSetDeepLFormality(int formality);

/* the AI translator */
NSArray *NoshiLlmPresetList(void);
NSString *NoshiLlmPresetName(int preset);
int NoshiLlmPresetChoice(void);
void NoshiLlmSetPresetChoice(int preset);
/* the keys are kept apart for each provider; several keys may stand in one string, separated by commas */
NSString *NoshiLlmKey(int preset);
void NoshiLlmSetKey(int preset, NSString *key);
/* the model the person typed for the provider, empty for the default one */
NSString *NoshiLlmSavedModel(int preset);
void NoshiLlmSetModel(int preset, NSString *model);
NSString *NoshiLlmDefaultModel(int preset);
NSString *NoshiLlmModel(int preset);
/* the base address of the chat completions API: the one typed for a custom provider (the Gemini one when empty), the fixed one of a named provider */
NSString *NoshiLlmCustomURL(void);
void NoshiLlmSetCustomURL(NSString *url);
NSString *NoshiLlmBaseURL(int preset);
/* "https://host/v1/" with the scheme added, the tail slashes and a trailing /chat/completions cut, or an empty string for text that is no address */
NSString *NoshiLlmNormalizedURL(NSString *text);
NSString *NoshiLlmSystemPrompt(void);
void NoshiLlmSetSystemPrompt(NSString *text);
NSString *NoshiLlmUserPrompt(void);
void NoshiLlmSetUserPrompt(NSString *text);
float NoshiLlmTemperature(void);
void NoshiLlmSetTemperature(float value);
BOOL NoshiLlmUsesContext(void);
void NoshiLlmSetUsesContext(BOOL on);
/* the index in the list 1, 3, 5, 7, 10 of messages sent as context */
int NoshiLlmContextIndex(void);
void NoshiLlmSetContextIndex(int index);
int NoshiLlmContextCount(void);
NSArray *NoshiLlmContextCounts(void);
/* whether the model takes a temperature: not the GPT-5 family and not the newer Gemini models, which reject the
   field */
BOOL NoshiLlmSupportsTemperature(int preset, NSString *model);

#import "noshi_translator_controller.h"

#import "noshi_alert.h"
#import "noshi_language.h"
#import "noshi_translate_config.h"
#import "noshi_translate_languages_controller.h"
#import "noshi_weak_reference.h"

@interface NoshiTranslatorSettingsController () {
    NoshiWeakReference *_weak;
    int _openedWith;
}
@end

@implementation NoshiTranslatorSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _openedWith = NoshiTranslateProviderChoice();
    self.pageTitle = NSLocalizedString(@"tr.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

/* the AI translator without a key cannot translate, so a choice of it left without one goes back to the service the screen was opened with, or to Google
   when that was the AI translator itself */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (![self isMovingFromParentViewController]) return;
    if (NoshiTranslateProviderChoice() != NoshiTranslateProviderLLM || NoshiLlmKey(NoshiLlmPresetChoice()).length) return;
    NoshiTranslateSetProviderChoice(_openedWith == NoshiTranslateProviderLLM ? NoshiTranslateProviderGoogle : _openedWith);
}

static NSString *NoshiSecretText(NSString *key) {
    if (!key.length) return NSLocalizedString(@"tr.none.value", nil);
    return key.length <= 4 ? @"••••" : [@"••••" stringByAppendingString:[key substringFromIndex:key.length - 4]];
}

static NSString *NoshiPlainText(NSString *text, NSString *empty) {
    if (!text.length) return empty;
    NSString *line = [[text componentsSeparatedByString:@"\n"] objectAtIndex:0];
    return line.length > 60 ? [[line substringToIndex:60] stringByAppendingString:@"…"] : line;
}

- (NSString *)skippedSummary {
    NSArray *codes = NoshiTranslateSkippedLanguages();
    if (!codes.count) return NSLocalizedString(@"tr.none.value", nil);
    if (codes.count < 3) {
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *code in codes) [names addObject:NoshiLanguageName(code)];
        return [names componentsJoinedByString:@", "];
    }
    NSString *form = codes.count == 1 ? @"one" : @"other";
    return [NSString stringWithFormat:NSLocalizedString([@"tr.languages." stringByAppendingString:form], nil), (int)codes.count];
}

- (NSString *)targetSummary {
    NSString *choice = NoshiTranslateTargetChoice();
    return choice.length ? NoshiLanguageName(choice) : NSLocalizedString(@"tr.target.app", nil);
}

/* the sheet for a key or a prompt: the notice as the message, the stored text in the field, an empty field clears it */
- (void)edit:(NSString *)title notice:(NSString *)notice initial:(NSString *)initial placeholder:(NSString *)placeholder save:(void (^)(NSString *text))save {
    NoshiWeakReference *weak = _weak;
    void (^store)(NSString *) = [save copy];
    NoshiPromptText(title, notice, initial, placeholder, ^(NSString *text) {
        store(text);
        [(NoshiTranslatorSettingsController *)weak.target rebuild];
    });
    [store release];
}

- (NSArray *)optionTitles:(NSArray *)ids name:(NSString *(*)(int))name {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *item in ids) [titles addObject:name([item intValue])];
    return titles;
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiTranslatorSettingsController *(^me)(void) = ^NoshiTranslatorSettingsController *{ return weak.target; };
    NSMutableArray *sections = [NSMutableArray array];

    NoshiSettingsRow *show = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.show", nil) subtitle:nil on:NoshiTranslateButtonEnabled()
                                                              toggle:^(BOOL on) { NoshiTranslateSetButtonEnabled(on); }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tr.options", nil) footer:NSLocalizedString(@"tr.messages.info", nil)
                                                             rows:[NSArray arrayWithObject:show]]];

    NSMutableArray *translate = [NSMutableArray array];
    int provider = NoshiTranslateProviderChoice();
    [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.provider", nil) value:NoshiTranslateProviderName(provider) tap:^{
        NoshiTranslatorSettingsController *screen = me();
        NSArray *ids = NoshiTranslateProviderList();
        NoshiSettingsChoose(screen, NSLocalizedString(@"tr.provider", nil), [screen optionTitles:ids name:NoshiTranslateProviderName], ^(NSUInteger index) {
            NoshiTranslateSetProviderChoice([[ids objectAtIndex:index] intValue]);
            [me() rebuild];
        });
    }]];
    NSArray *modes = [NSArray arrayWithObjects:NSLocalizedString(@"tr.original.off", nil), NSLocalizedString(@"tr.original.manual", nil), NSLocalizedString(@"tr.original.on", nil), nil];
    [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.original", nil) value:[modes objectAtIndex:(NSUInteger)NoshiTranslateOriginalMode()] tap:^{
        NoshiSettingsChoose(me(), NSLocalizedString(@"tr.original", nil), modes, ^(NSUInteger index) {
            NoshiTranslateSetOriginalMode((int)index);
            [me() rebuild];
        });
    }]];
    [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.target", nil) value:[self targetSummary] tap:^{
        NoshiTranslatorSettingsController *screen = me();
        [screen.navigationController pushViewController:[[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesTarget] autorelease] animated:YES];
    }]];
    [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.skip", nil) value:[self skippedSummary] tap:^{
        NoshiTranslatorSettingsController *screen = me();
        [screen.navigationController pushViewController:[[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesSkipped] autorelease] animated:YES];
    }]];
    [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.preferred", nil) subtitle:NoshiPlainText(NoshiTranslatePreferredText(), NSLocalizedString(@"tr.none.value", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.preferred.title", nil) notice:NSLocalizedString(@"tr.preferred.example", nil) initial:NoshiTranslatePreferredText()
       placeholder:NSLocalizedString(@"tr.preferred.example", nil) save:^(NSString *text) { NoshiTranslateSetPreferredText(text); }];
    }]];
    if (provider == NoshiTranslateProviderGoogle && !NoshiTranslateGoogleNew()) {
        [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.google.key", nil) subtitle:NoshiSecretText(NoshiTranslateGoogleKey()) value:nil tap:^{
            [me() edit:NSLocalizedString(@"tr.google.key", nil) notice:NSLocalizedString(@"tr.google.key.notice", nil) initial:NoshiTranslateGoogleKey()
           placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { NoshiTranslateSetGoogleKey(text); }];
        }]];
    } else if (provider == NoshiTranslateProviderDeepL) {
        [translate addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.deepl.key", nil) subtitle:NoshiSecretText(NoshiTranslateDeepLKey()) value:nil tap:^{
            [me() edit:NSLocalizedString(@"tr.deepl.key", nil) notice:NSLocalizedString(@"tr.deepl.key.notice", nil) initial:NoshiTranslateDeepLKey()
           placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { NoshiTranslateSetDeepLKey(text); }];
        }]];
        NSArray *tones = [NSArray arrayWithObjects:NSLocalizedString(@"tr.deepl.formality.default", nil), NSLocalizedString(@"tr.deepl.formality.informal", nil),
                          NSLocalizedString(@"tr.deepl.formality.formal", nil), nil];
        [translate addObject:[NoshiSettingsRow rowWithTitle:[tones objectAtIndex:(NSUInteger)NoshiTranslateDeepLFormality()] value:nil tap:^{
            NoshiSettingsChoose(me(), nil, tones, ^(NSUInteger index) {
                NoshiTranslateSetDeepLFormality((int)index);
                [me() rebuild];
            });
        }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tr.translate", nil) footer:nil rows:translate]];
    [sections addObject:[self aiSection]];

    NoshiSettingsRow *fresh = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.google.new", nil) subtitle:nil on:NoshiTranslateGoogleNew() toggle:^(BOOL on) {
        NoshiTranslateSetGoogleNew(on);
        [me() rebuild];
    }];
    NoshiSettingsRow *keep = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.keep", nil) subtitle:NSLocalizedString(@"tr.keep.notice", nil) on:NoshiTranslateKeepsPreferences()
                                                              toggle:^(BOOL on) { NoshiTranslateSetKeepsPreferences(on); }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tr.experimental", nil) footer:nil rows:[NSArray arrayWithObjects:fresh, keep, nil]]];
    self.sections = sections;
}

- (NoshiSettingsSection *)aiSection {
    NoshiWeakReference *weak = _weak;
    NoshiTranslatorSettingsController *(^me)(void) = ^NoshiTranslatorSettingsController *{ return weak.target; };
    int preset = NoshiLlmPresetChoice();
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.preset", nil) value:NoshiLlmPresetName(preset) tap:^{
        NoshiTranslatorSettingsController *screen = me();
        NSArray *ids = NoshiLlmPresetList();
        NoshiSettingsChoose(screen, NSLocalizedString(@"tr.llm.preset", nil), [screen optionTitles:ids name:NoshiLlmPresetName], ^(NSUInteger index) {
            NoshiLlmSetPresetChoice([[ids objectAtIndex:index] intValue]);
            [me() rebuild];
        });
    }]];
    NSString *model = NoshiLlmModel(preset);
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.model", nil) subtitle:NoshiPlainText(model, NSLocalizedString(@"tr.none.value", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.model", nil) notice:nil initial:NoshiLlmSavedModel(preset) placeholder:NoshiLlmDefaultModel(preset)
              save:^(NSString *text) { NoshiLlmSetModel(preset, text); }];
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.key", nil) subtitle:NoshiSecretText(NoshiLlmKey(preset)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.key", nil) notice:NSLocalizedString(@"tr.llm.key.notice", nil) initial:NoshiLlmKey(preset)
       placeholder:NSLocalizedString(@"tr.llm.key", nil) save:^(NSString *text) { NoshiLlmSetKey(preset, text); }];
    }]];
    if (preset == NoshiLlmPresetCustom) {
        NSString *url = NoshiLlmCustomURL();
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.url", nil) subtitle:url.length ? url : NoshiLlmBaseURL(NoshiLlmPresetCustom) value:nil tap:^{
            NoshiWeakReference *inner = weak;
            NoshiPromptText(NSLocalizedString(@"tr.llm.url", nil), NSLocalizedString(@"tr.llm.url.notice", nil), NoshiLlmCustomURL(), NSLocalizedString(@"tr.llm.url.hint", nil),
                              ^(NSString *text) {
                NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (trimmed.length && !NoshiLlmNormalizedURL(trimmed).length) {
                    NoshiShowNotice(nil, NSLocalizedString(@"tr.url.invalid", nil));
                    return;
                }
                NoshiLlmSetCustomURL(trimmed);
                [(NoshiTranslatorSettingsController *)inner.target rebuild];
            });
        }]];
    }
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.system", nil) subtitle:NoshiPlainText(NoshiLlmSystemPrompt(), NSLocalizedString(@"tr.default", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.system", nil) notice:NSLocalizedString(@"tr.llm.system.notice", nil) initial:NoshiLlmSystemPrompt()
       placeholder:NSLocalizedString(@"tr.llm.system.hint", nil) save:^(NSString *text) { NoshiLlmSetSystemPrompt(text); }];
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.user", nil) subtitle:NoshiPlainText(NoshiLlmUserPrompt(), NSLocalizedString(@"tr.default", nil)) value:nil tap:^{
        [me() edit:NSLocalizedString(@"tr.llm.user", nil) notice:NSLocalizedString(@"tr.llm.user.notice", nil) initial:NoshiLlmUserPrompt()
       placeholder:NSLocalizedString(@"tr.llm.user.hint", nil) save:^(NSString *text) { NoshiLlmSetUserPrompt(text); }];
    }]];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"tr.llm.context", nil) subtitle:NSLocalizedString(@"tr.llm.context.notice", nil) on:NoshiLlmUsesContext() toggle:^(BOOL on) {
        NoshiLlmSetUsesContext(on);
        [me() rebuild];
    }]];
    if (NoshiLlmUsesContext()) {
        NSArray *counts = NoshiLlmContextCounts();
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.llm.context.size", nil) value:[NSString stringWithFormat:@"%d", NoshiLlmContextCount()] tap:^{
            NSMutableArray *titles = [NSMutableArray array];
            for (NSNumber *count in counts) [titles addObject:[count stringValue]];
            NoshiSettingsChoose(me(), NSLocalizedString(@"tr.llm.context.title", nil), titles, ^(NSUInteger index) {
                NoshiLlmSetContextIndex((int)index);
                [me() rebuild];
            });
        }]];
    }
    if (NoshiLlmSupportsTemperature(preset, model)) {
        [rows addObject:[NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"tr.llm.temperature", nil) format:@"%.1f" value:NoshiLlmTemperature() minimum:0 maximum:2
                                                        change:^(float value) { NoshiLlmSetTemperature(roundf(value * 10) / 10); }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tr.ai", nil) footer:nil rows:rows];
}

@end

#import "noshi_language_controller.h"

#import "noshi_language.h"
#import "noshi_alert.h"
#import "noshi_classic_chrome.h"
#import "noshi_file_picker.h"
#import "noshi_logs_controller.h"
#import "noshi_theme.h"
#import "noshi_translate_config.h"
#import "noshi_translator_controller.h"
#import "noshi_weak_reference.h"

@interface NoshiLanguageSettingsController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiLanguageSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"language.title", nil);
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged) name:NoshiLanguageDidChangeNotification object:nil];
    [self rebuild];
}

/* the provider shown on the translator row may have changed on the screen above */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

/* the title and every row are read again in the new language, and a search in the old words is closed closes it */
- (void)languageChanged {
    self.pageTitle = NSLocalizedString(@"language.title", nil);
    [self endSearch];
    [self rebuild];
}

- (NoshiSettingsRow *)rowForCode:(NSString *)code {
    NoshiWeakReference *weak = _weak;
    BOOL custom = NoshiIsCustomLanguage(code);
    return [NoshiSettingsRow checkRowWithTitle:NoshiNativeLanguageName(code) subtitle:NoshiEnglishLanguageName(code)
                                         checked:[code isEqualToString:NoshiInterfaceLanguageVariant()]
                                             tap:^{
        NoshiLanguageSettingsController *me = weak.target;
        if (!me) return;
        if (!custom) {
            [me choose:code];
            return;
        }
        /* a language that came from a file can also be taken away */
        NoshiSettingsChoose(me, NoshiNativeLanguageName(code), [NSArray arrayWithObjects:NSLocalizedString(@"language.custom.use", nil), NSLocalizedString(@"language.custom.remove", nil), nil], ^(NSUInteger index) {
            NoshiLanguageSettingsController *screen = weak.target;
            if (!screen) return;
            if (index == 0) [screen choose:code];
            else {
                NoshiRemoveCustomLanguage(code);
                [screen rebuild];
            }
        });
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *translator = [NoshiSettingsRow rowWithSymbol:NoshiSymbolTranslate tone:NoshiSettingsTonePurple title:NSLocalizedString(@"tr.title", nil) subtitle:nil
                                                                 value:NoshiTranslateProviderName(NoshiTranslateProviderChoice()) tap:^{
        NoshiLanguageSettingsController *screen = weak.target;
        [screen.navigationController pushViewController:[[[NoshiTranslatorSettingsController alloc] init] autorelease] animated:YES];
    }];
    NSMutableArray *languages = [NSMutableArray array];
    for (NSString *code in NoshiInterfaceLanguageCodes()) [languages addObject:[self rowForCode:code]];
    NoshiSettingsRow *import = [NoshiSettingsRow rowWithSymbol:NoshiSymbolDocument tone:NoshiSettingsToneBlue title:NSLocalizedString(@"language.custom.import", nil)
                                                          subtitle:NSLocalizedString(@"language.custom.import.info", nil) value:nil tap:^{ [(NoshiLanguageSettingsController *)weak.target importLanguageFile]; }];
    NSMutableArray *templates = [NSMutableArray arrayWithObject:import];
    static NSString *const sources[] = {@"en", @"ru"};
    static NSString *const titles[] = {@"language.custom.template", @"language.custom.template.ru"};
    for (size_t i = 0; i < 2; ++i) {
        NSString *source = sources[i];
        [templates addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolShare tone:NoshiSettingsToneBlue title:NSLocalizedString(titles[i], nil)
                                                      subtitle:NSLocalizedString(@"language.custom.template.info", nil) value:nil tap:^{
            NoshiLanguageSettingsController *me = weak.target;
            if (!me) return;
            NSString *path = NoshiCustomLanguageTemplatePath(source);
            if (path) NoshiShareFile(me, path);
            else NoshiShowNotice(nil, NSLocalizedString(@"language.custom.unreadable", nil));
        }]];
    }
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"tr.messages", nil) footer:nil rows:[NSArray arrayWithObject:translator]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"language.title", nil) footer:nil rows:languages],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"language.custom.header", nil) footer:nil rows:templates], nil];
    [self reloadSearchResults];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *code in NoshiInterfaceLanguageCodes()) {
        if ([[NoshiNativeLanguageName(code) lowercaseString] hasPrefix:wanted] || [[NoshiEnglishLanguageName(code) lowercaseString] hasPrefix:wanted]) {
            [rows addObject:[self rowForCode:code]];
        }
    }
    return rows.count ? [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:rows]] : [NSArray array];
}

/* a .strings file with the texts of the app in another language: the same browser as the one that picks a file to send, asking for a language */
- (void)importLanguageFile {
    NoshiWeakReference *weak = _weak;
    NoshiFilePicker *picker = [[[NoshiFilePicker alloc] initWithDirectory:nil handler:^(NSString *path) {
        NoshiLanguageSettingsController *me = weak.target;
        if (!me) return;
        NSUInteger accepted = 0, skipped = 0;
        NSString *error = NoshiInstallCustomLanguage(path, &accepted, &skipped);
        if (error) {
            NoshiShowNotice(NSLocalizedString(@"language.custom.import", nil), error);
            return;
        }
        [me rebuild];
        NoshiShowNotice(NSLocalizedString(@"language.custom.import", nil), [NSString stringWithFormat:NSLocalizedString(@"language.custom.done", nil), (long)accepted, (long)skipped]);
    } cancel:nil] autorelease];
    picker.extensions = [NSArray arrayWithObject:@"strings"];
    picker.rootTitle = NSLocalizedString(@"language.custom.pick", nil);
    picker.searchPlaceholder = NSLocalizedString(@"language.custom.search", nil);
    picker.emptyText = NSLocalizedString(@"language.custom.empty.files", nil);
    picker.fileSymbol = NoshiSymbolSettingsLanguage;
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:picker] autorelease];
    NoshiClassicStyleNavigationBar(navigation.navigationBar);
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)choose:(NSString *)code {
    if ([NoshiInterfaceLanguageVariant() isEqualToString:code]) return;
    NSString *previous = NoshiInterfaceLanguage();
    NoshiSetInterfaceLanguage(code);
    NoshiTranslateInterfaceLanguageChanged(previous, NoshiInterfaceLanguage());
}

@end

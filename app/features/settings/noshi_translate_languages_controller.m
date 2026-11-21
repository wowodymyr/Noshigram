#import "noshi_translate_languages_controller.h"

#import "noshi_language.h"
#import "noshi_translate_config.h"
#import "noshi_weak_reference.h"

@interface NoshiTranslateLanguagesController () {
    NoshiTranslateLanguagesMode _mode;
    NoshiWeakReference *_weak;
    NSArray *_order;
    NSMutableArray *_chosen;
}
@end

@implementation NoshiTranslateLanguagesController

- (id)initWithMode:(NoshiTranslateLanguagesMode)mode {
    self = [super init];
    if (!self) return nil;
    _mode = mode;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(mode == NoshiTranslateLanguagesTarget ? @"tr.target.title" : @"tr.skip.title", nil);
    self.searchable = YES;
    _chosen = [[NSMutableArray alloc] initWithArray:NoshiTranslateSkippedLanguages()];
    _order = [[self orderedCodes] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_order release];
    [_chosen release];
    [super dealloc];
}

/* the display name is looked up once for the sort, which asks for it many times */
- (NSArray *)sortedByName:(NSArray *)codes {
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *code in codes) [names setObject:NoshiLanguageName(code) forKey:code];
    return [codes sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [[names objectForKey:a] localizedCaseInsensitiveCompare:[names objectForKey:b]];
    }];
}

/* target mode: the preferred languages first, then the rest by name */
- (NSArray *)orderedCodes {
    NSMutableArray *all = [NSMutableArray arrayWithArray:NoshiTranslationLanguageCodes()];
    NSMutableArray *front = [NSMutableArray array];
    if (_mode == NoshiTranslateLanguagesTarget) {
        for (NSString *code in NoshiTranslatePreferredLanguages()) {
            NSString *match = nil;
            for (NSString *known in all) {
                if ([NoshiNormalizedLanguageCode(known) isEqualToString:code]) { match = known; break; }
            }
            if (match && ![front containsObject:match]) [front addObject:match];
        }
    } else {
        NSString *own = NoshiInterfaceLanguage();
        for (NSString *code in _chosen) {
            if ([NoshiNormalizedLanguageCode(code) isEqualToString:own]) { [front insertObject:code atIndex:0]; continue; }
            [front addObject:code];
        }
    }
    NSMutableSet *taken = [NSMutableSet set];
    for (NSString *code in front) [taken addObject:NoshiNormalizedLanguageCode(code)];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSString *code in all) {
        if (![taken containsObject:NoshiNormalizedLanguageCode(code)]) [rest addObject:code];
    }
    all = rest;
    NSMutableArray *ordered = [NSMutableArray arrayWithArray:front];
    [ordered addObjectsFromArray:[self sortedByName:all]];
    return ordered;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (BOOL)isChosen:(NSString *)code {
    if (_mode == NoshiTranslateLanguagesTarget) {
        NSString *choice = NoshiTranslateTargetChoice();
        return choice.length && [NoshiNormalizedLanguageCode(choice) isEqualToString:NoshiNormalizedLanguageCode(code)];
    }
    NSString *wanted = NoshiNormalizedLanguageCode(code);
    for (NSString *chosen in _chosen) {
        if ([NoshiNormalizedLanguageCode(chosen) isEqualToString:wanted]) return YES;
    }
    return NO;
}

- (NoshiSettingsRow *)rowForCode:(NSString *)code {
    NoshiWeakReference *weak = _weak;
    NSString *own = NoshiNativeLanguageName(code);
    NSString *name = NoshiLanguageName(code);
    NSString *line = [own isEqualToString:name] ? nil : own;
    BOOL star = _mode == NoshiTranslateLanguagesTarget && [NoshiTranslatePreferredLanguages() containsObject:NoshiNormalizedLanguageCode(code)];
    NSString *title = star ? [@"⭐ " stringByAppendingString:name] : name;
    return [NoshiSettingsRow checkRowWithTitle:title subtitle:line checked:[self isChosen:code] tap:^{
        [(NoshiTranslateLanguagesController *)weak.target pick:code];
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    if (_mode == NoshiTranslateLanguagesTarget) {
        NSString *app = NoshiLanguageName(NoshiInterfaceLanguage());
        NoshiSettingsRow *follow = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"tr.target.app", nil) subtitle:app
                                                                   checked:NoshiTranslateTargetChoice().length == 0
                                                                       tap:^{ [(NoshiTranslateLanguagesController *)weak.target pick:@""]; }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:follow]]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *code in _order) [rows addObject:[self rowForCode:code]];
    NSString *footer = _mode == NoshiTranslateLanguagesSkipped ? NSLocalizedString(@"tr.skip.info", nil) : nil;
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    self.sections = sections;
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *starts = [NSMutableArray array], *contains = [NSMutableArray array];
    for (NSString *code in _order) {
        NSString *name = [NoshiLanguageName(code) lowercaseString];
        NSString *own = [NoshiNativeLanguageName(code) lowercaseString];
        NSString *english = [NoshiEnglishLanguageName(code) lowercaseString];
        if ([name hasPrefix:wanted] || [own hasPrefix:wanted] || [english hasPrefix:wanted] || [[code lowercaseString] hasPrefix:wanted]) [starts addObject:[self rowForCode:code]];
        else if ([name rangeOfString:wanted].location != NSNotFound || [own rangeOfString:wanted].location != NSNotFound
                 || [english rangeOfString:wanted].location != NSNotFound) [contains addObject:[self rowForCode:code]];
    }
    [starts addObjectsFromArray:contains];
    return starts.count ? [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:starts]] : [NSArray array];
}

- (void)pick:(NSString *)code {
    if (_mode == NoshiTranslateLanguagesTarget) {
        NoshiTranslateSetTargetChoice(code);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *wanted = NoshiNormalizedLanguageCode(code);
    NSString *found = nil;
    for (NSString *chosen in _chosen) {
        if ([NoshiNormalizedLanguageCode(chosen) isEqualToString:wanted]) { found = chosen; break; }
    }
    if (found) [_chosen removeObject:found];
    else [_chosen addObject:[code lowercaseString]];
    NoshiTranslateSetSkippedLanguages(_chosen);
    [self rebuild];
    /* the search results hold rows made before the toggle, so they are asked for again */
    [self reloadSearchResults];
}

@end

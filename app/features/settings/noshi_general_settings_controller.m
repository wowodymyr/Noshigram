#import "noshi_general_settings_controller.h"

#import "noshi_browser_settings.h"
#import "noshi_chat_settings.h"
#import "noshi_language.h"
#import "noshi_translate_config.h"
#import "noshi_translate_languages_controller.h"
#import "noshi_translator_controller.h"
#import "noshi_symbol.h"
#import "noshi_weak_reference.h"
#import "noshi_time.h"
#import "noshi_time_zone_controller.h"

/* a switch that sets a flag of the chat settings and tells what listens (the chat list, the demo dialog) */
static NoshiSettingsRow *NoshiGeneralFlagRow(NSString *titleKey, NSString *infoKey, NoshiChatFlag flag) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil
                                               on:NoshiChatFlagGet(flag) toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }];
}

@interface NoshiGeneralSettingsController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiGeneralSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"about.main", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* the translator page and the language lists change what the first section shows */
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiGeneralSettingsController alloc] init] autorelease];
}

- (NSString *)targetSummary {
    NSString *choice = NoshiTranslateTargetChoice();
    return choice.length ? NoshiLanguageName(choice) : NSLocalizedString(@"tr.target.app", nil);
}

- (NSString *)skippedSummary {
    NSUInteger count = NoshiTranslateSkippedLanguages().count;
    return count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil;
}

- (NoshiSettingsSection *)translateSection {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"general.translate.button", nil) subtitle:nil on:NoshiTranslateButtonEnabled()
                                                    toggle:^(BOOL on) { NoshiTranslateSetButtonEnabled(on); }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.provider", nil) value:NoshiTranslateProviderName(NoshiTranslateProviderChoice()) tap:^{
        NoshiGeneralSettingsController *me = weak.target;
        if (!me) return;
        NSArray *ids = NoshiTranslateProviderList();
        NSMutableArray *titles = [NSMutableArray array];
        for (NSNumber *provider in ids) [titles addObject:NoshiTranslateProviderName(provider.intValue)];
        NoshiSettingsChoose(me, NSLocalizedString(@"tr.provider", nil), titles, ^(NSUInteger index) {
            NoshiTranslateSetProviderChoice([[ids objectAtIndex:index] intValue]);
            [(NoshiGeneralSettingsController *)weak.target rebuild];
        });
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.target", nil) value:[self targetSummary] tap:^{
        [[(NoshiGeneralSettingsController *)weak.target navigationController] pushViewController:[[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesTarget] autorelease] animated:YES];
    }]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"tr.skip", nil) value:[self skippedSummary] tap:^{
        [[(NoshiGeneralSettingsController *)weak.target navigationController] pushViewController:[[[NoshiTranslateLanguagesController alloc] initWithMode:NoshiTranslateLanguagesSkipped] autorelease] animated:YES];
    }]];
    [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolTranslate tone:NoshiSettingsTonePurple title:NSLocalizedString(@"tr.title", nil) subtitle:nil value:nil tap:^{
        [[(NoshiGeneralSettingsController *)weak.target navigationController] pushViewController:[[[NoshiTranslatorSettingsController alloc] init] autorelease] animated:YES];
    }]];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.translate.header", nil) footer:NSLocalizedString(@"general.translate.info", nil) rows:rows];
}

- (void)rebuild {
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self translateSection]];

    NSMutableArray *general = [NSMutableArray array];
    [general addObject:NoshiGeneralFlagRow(@"general.exactnumbers", @"general.exactnumbers.value", NoshiChatFlagExactNumbers)];
    [general addObject:NoshiGeneralFlagRow(@"general.seconds", @"general.seconds.value", NoshiChatFlagSeconds)];
    NoshiWeakReference *weak = _weak;
    [general addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"time.zone.title", nil) value:NoshiTimeZoneChoiceText() tap:^{
        [[(NoshiGeneralSettingsController *)weak.target navigationController] pushViewController:[[[NoshiTimeZoneController alloc] init] autorelease] animated:YES];
    }]];
    [general addObject:NoshiGeneralFlagRow(@"general.zalgo", nil, NoshiChatFlagFilterZalgo)];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.header", nil) footer:NSLocalizedString(@"general.zalgo.info", nil) rows:general]];

    [sections addObject:NoshiBrowserChoiceSection(^{ [(NoshiGeneralSettingsController *)weak.target rebuild]; })];

    NSMutableArray *profile = [NSMutableArray array];
    [profile addObject:NoshiGeneralFlagRow(@"general.hidephone", nil, NoshiChatFlagHidePhone)];
    [profile addObject:NoshiGeneralFlagRow(@"general.showids", nil, NoshiChatFlagShowIds)];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.profile.header", nil) footer:NSLocalizedString(@"general.showids.info", nil) rows:profile]];

    NSMutableArray *archive = [NSMutableArray array];
    [archive addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"general.hidearchive", nil) subtitle:nil on:NoshiArchiveHidden() toggle:^(BOOL on) {
        NoshiArchiveSetHidden(on);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
    }]];
    [archive addObject:NoshiGeneralFlagRow(@"general.nounarchive", nil, NoshiChatFlagNoUnarchiveSwipe)];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"general.archive.header", nil) footer:NSLocalizedString(@"general.nounarchive.info", nil) rows:archive]];

    self.sections = sections;
    [self reloadSettings];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

@end

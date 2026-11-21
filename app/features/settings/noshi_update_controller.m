#import "noshi_update_controller.h"
#import "noshi_release_check.h"
#import "noshi_updater.h"
#import "noshi_wave_progress.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#include "noshi_release.h"

@interface NoshiUpdateController () {
    NoshiWeakReference *_weak;
    NSDictionary *_release;
    NSString *_error;
    NoshiUpdater *_updater;
    UIView *_progressCard;
    NoshiWaveProgress *_wave;
    UILabel *_progressText;
    BOOL _checking;
    BOOL _newer;
    NSUInteger _generation;
}
@end

@implementation NoshiUpdateController
- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"update.page.title", nil);
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    _updater.onChange = nil;
    [_updater cancel];
    [_updater release];
    [_release release];
    [_error release];
    [_progressCard release];
    [_wave release];
    [_progressText release];
    [super dealloc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self check];
}
- (void)themeDidChange { [self rebuild]; }
- (void)check {
    if (_checking || _updater.state == NoshiUpdaterWorking) return;
    _checking = YES;
    NSUInteger generation = ++_generation;
    [_error release]; _error = nil;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    NoshiFetchLatestRelease(^(NSDictionary *release, NSString *error) {
        NoshiUpdateController *controller = weak.target;
        if (!controller || generation != controller->_generation) return;
        controller->_checking = NO;
        [controller->_release release];
        controller->_release = [release retain];
        [controller->_error release];
        controller->_error = [error copy];
        controller->_newer = NO;
        if (release) {
            NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            int newer = 0;
            noshi_status status = noshi_release_compare([[release objectForKey:@"tag"] UTF8String], version.UTF8String, &newer);
            if (status != NOSHI_OK) controller->_error = [[NSString stringWithUTF8String:noshi_status_name(status)] copy];
            else controller->_newer = newer != 0;
        }
        [controller rebuild];
    });
}
- (void)startUpdate {
    if (!_newer || !_release) return;
    NSString *ipa = [_release objectForKey:@"ipa"], *digest = [_release objectForKey:@"digest"];
    if (!ipa.length || !digest.length || ![NoshiUpdater canInstallInPlace]) return;
    _updater.onChange = nil;
    [_updater release];
    _updater = [[NoshiUpdater alloc] initWithIpaURL:ipa digestURL:digest size:[[_release objectForKey:@"size"] unsignedLongLongValue]];
    NoshiWeakReference *weak = _weak;
    _updater.onChange = ^{ [(NoshiUpdateController *)weak.target updateChanged]; };
    _wave.value = 0;
    [_updater start];
    [self rebuild];
    [self updateChanged];
}
- (void)updateChanged {
    if (_updater.state == NoshiUpdaterWorking) {
        _progressText.text = _updater.installing ? NSLocalizedString(@"release.installing", nil) :
            [NSString stringWithFormat:NSLocalizedString(@"release.progress", nil),
             [NSString stringWithFormat:@"%.1f", (double)_updater.downloaded / 1048576.0],
             [NSString stringWithFormat:@"%.1f", (double)_updater.expected / 1048576.0]];
        [_wave setValue:_updater.fraction gliding:YES];
    } else [self rebuild];
}
- (UIView *)progressCard {
    if (_progressCard) return _progressCard;
    _progressCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 76)];
    _progressText = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 248, 24)];
    _progressText.backgroundColor = [UIColor clearColor];
    _progressText.textColor = NoshiColorSecondary();
    _progressText.font = NoshiFontMedium(14);
    _progressText.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressText.text = NSLocalizedString(@"release.preparing", nil);
    [_progressCard addSubview:_progressText];
    _wave = [[NoshiWaveProgress alloc] initWithFrame:CGRectMake(10, 36, 260, NoshiWaveProgressHeight)];
    _wave.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _wave.userInteractionEnabled = NO;
    _wave.waving = !NoshiThemeIsClassic();
    [_progressCard addSubview:_wave];
    return _progressCard;
}
- (void)rebuild {
    NSString *installed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *latest = [_release objectForKey:@"tag"];
    /* the release tag carries a leading v that the bundle version does not, so the two rows would read differently for the same build */
    if (latest.length > 1 && ([latest hasPrefix:@"v"] || [latest hasPrefix:@"V"])) latest = [latest substringFromIndex:1];
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"update.page.installed", nil) value:installed tap:nil]];
    [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"update.page.latest", nil)
                                             value:latest ? latest : (_checking ? NSLocalizedString(@"update.page.checking", nil) : @"—") tap:nil]];
    NSMutableArray *sections = [NSMutableArray array];
    NSString *message = nil;
    if (_error) message = [NSString stringWithFormat:NSLocalizedString(@"update.page.error", nil), _error];
    else if (_release && !_newer) message = NSLocalizedString(@"update.page.current", nil);
    else if (_newer && (![[_release objectForKey:@"ipa"] length] || ![[_release objectForKey:@"digest"] length])) message = NSLocalizedString(@"release.noasset", nil);
    else if (_newer && ![NoshiUpdater canInstallInPlace]) message = NSLocalizedString(@"release.readonly", nil);
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:message rows:rows]];
    if (_updater.state == NoshiUpdaterWorking) {
        NoshiSettingsRow *progress = [NoshiSettingsRow viewRowWithView:[self progressCard] height:^CGFloat(CGFloat width) { (void)width; return 76; }];
        NoshiSettingsRow *cancel = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCloseMark() title:NSLocalizedString(@"release.cancel", nil) destructive:NO tap:^{
            NoshiUpdateController *controller = weak.target;
            if (controller) [controller->_updater cancel];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:progress, cancel, nil]]];
    } else if (_updater.state == NoshiUpdaterDone) {
        NoshiSettingsRow *restart = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCheckMark() title:NSLocalizedString(@"release.restart", nil) destructive:NO tap:^{ exit(0); }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"release.restart.note", nil) rows:[NSArray arrayWithObject:restart]]];
    } else {
        if (_updater.state == NoshiUpdaterFailed) {
            NSString *failure = [NSString stringWithFormat:@"%s", noshi_status_name(_updater.failure)];
            [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:failure rows:[NSArray array]]];
        }
        NSMutableArray *actions = [NSMutableArray array];
        if (_newer && [[_release objectForKey:@"ipa"] length] && [[_release objectForKey:@"digest"] length] && [NoshiUpdater canInstallInPlace])
            [actions addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolArrowDown title:NSLocalizedString(@"release.update", nil) destructive:NO tap:^{ [(NoshiUpdateController *)weak.target startUpdate]; }]];
        else if (_newer)
            [actions addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolArrowDown title:NSLocalizedString(@"release.open", nil) destructive:NO tap:^{
                NoshiUpdateController *controller = weak.target;
                if (controller) [NoshiUpdater openDownloadOfIpaURL:[controller->_release objectForKey:@"ipa"]];
            }]];
        [actions addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolRotate title:NSLocalizedString(@"update.page.check", nil) destructive:NO tap:^{ [(NoshiUpdateController *)weak.target check]; }]];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:actions]];
    }
    self.sections = sections;
}
@end

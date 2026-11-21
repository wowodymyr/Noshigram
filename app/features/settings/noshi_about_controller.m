#import "noshi_about_controller.h"
#import "noshi_general_settings_controller.h"
#import "noshi_more_settings_controller.h"
#import "noshi_link_router.h"

#import "noshi_chat_extras_controller.h"
#import "noshi_platform.h"
#import "noshi_settings_pages.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define ICON_SIDE 72.0
#define HEADER_HEIGHT 172.0

static NSString *const NoshiSourceAddress = @"https://github.com/wowodymyr/Noshigram";
static NSString *const NoshiUpstreamAddress = @"https://github.com/sqmrak/exteria";

/* the developers of exteria, which noshigram is a fork of; its license asks every fork to name them */
static NSString *const NoshiUpstreamDevelopers[] = {
    @"sqmrak", @"QWERTYU1OPZ", @"LimeDev", @"menstry", @"anazerka", @"loveiOS6", @"nestorvashenko", @"svcayon4ik",
};

/* the slice the running code was built for, which the version line shows */
static NSString *NoshiSliceName(void) {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__arm__)
    return @"armv7";
#else
    return @"host";
#endif
}

/* the icon of the app with the rounded corners of the home screen */
static UIImage *NoshiAppIcon(CGFloat side) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Icon-83.5@2x" ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.2237] addClip];
    [source drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface NoshiAboutController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiAboutController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.noshigram", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_avatars release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiAboutController alloc] initWithSession:_session avatars:_avatars] autorelease];
}

#pragma mark header

- (UIView *)makeHeader {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, HEADER_HEIGHT)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIImageView *icon = [[[UIImageView alloc] initWithImage:NoshiAppIcon(ICON_SIDE)] autorelease];
    icon.frame = CGRectMake(floor((width - ICON_SIDE) / 2), 24, ICON_SIDE, ICON_SIDE);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [header addSubview:icon];
    UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(icon.frame) + 10, width, 28)] autorelease];
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.backgroundColor = [UIColor clearColor];
    name.textAlignment = NoshiTextAlignmentCenter;
    name.font = NoshiFontBold(22);
    name.textColor = NoshiColorTitle();
    name.text = NSLocalizedString(@"about.name", nil);
    [header addSubview:name];
    UILabel *version = [[[UILabel alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(name.frame) + 2, width, 20)] autorelease];
    version.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    version.backgroundColor = [UIColor clearColor];
    version.textAlignment = NoshiTextAlignmentCenter;
    version.font = NoshiFontRegular(14);
    version.textColor = NoshiColorSecondary();
    NSString *number = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"";
    version.text = [NSString stringWithFormat:@"v%@ (%@)", number, NoshiSliceName()];
    [header addSubview:version];
    return header;
}

#pragma mark rows

- (void)open:(NSString *)address {
    NSURL *url = [NSURL URLWithString:address];
    /* t.me addresses open as chats and profiles inside the app, through the main screen */
    if (url && NoshiIsTelegramLink(url)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenLinkNotification object:self userInfo:[NSDictionary dictionaryWithObject:address forKey:@"url"]];
        return;
    }
    if (url && ![[UIApplication sharedApplication] openURL:url]) NSLog(@"noshigram: the system did not open %@", address);
}

- (NoshiSettingsRow *)categoryRow:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone key:(NSString *)key page:(UIViewController *(^)(void))page {
    NoshiWeakReference *weak = _weak;
    return [NoshiSettingsRow rowWithSymbol:symbol tone:tone title:NSLocalizedString(key, nil) subtitle:nil value:nil tap:^{
        NoshiAboutController *me = weak.target;
        if (me) [me.navigationController pushViewController:page() animated:YES];
    }];
}

- (void)rebuild {
    self.headerView = [self makeHeader];
    [self rebuildSections];
}

- (void)rebuildSections {
    NoshiWeakReference *weak = _weak;
    NoshiSession *session = _session;

    NSArray *categories = [NSArray arrayWithObjects:
        [self categoryRow:NoshiSymbolGear tone:NoshiSettingsToneBlue key:@"about.main" page:^UIViewController *{
            return [[[NoshiGeneralSettingsController alloc] init] autorelease];
        }],
        [self categoryRow:NoshiSymbolBackground tone:NoshiSettingsToneOrange key:@"about.look" page:^UIViewController *{
            return [[[NoshiAppearanceSettingsController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:NoshiSymbolSettingsChat tone:NoshiSettingsToneGreen key:@"about.chats" page:^UIViewController *{
            return [[[NoshiChatExtrasController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:NoshiSymbolEllipsis tone:NoshiSettingsToneGray key:@"about.more" page:^UIViewController *{
            return [[[NoshiMoreSettingsController alloc] initWithSession:session] autorelease];
        }], nil];

    NoshiSettingsRow *source = [NoshiSettingsRow rowWithSymbol:NoshiSymbolExternalLink tone:NoshiSettingsTonePurple title:NSLocalizedString(@"about.source", nil)
                                                          subtitle:[NoshiSourceAddress substringFromIndex:[@"https://" length]] value:nil
                                                               tap:^{ [(NoshiAboutController *)weak.target open:NoshiSourceAddress]; }];
    NoshiSettingsRow *upstream = [NoshiSettingsRow rowWithSymbol:NoshiSymbolExternalLink tone:NoshiSettingsToneGray title:NSLocalizedString(@"about.upstream", nil)
                                                            subtitle:[NoshiUpstreamAddress substringFromIndex:[@"https://" length]] value:nil
                                                                 tap:^{ [(NoshiAboutController *)weak.target open:NoshiUpstreamAddress]; }];

    NSMutableArray *credits = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(NoshiUpstreamDevelopers) / sizeof(NoshiUpstreamDevelopers[0]); ++i) {
        NSString *username = NoshiUpstreamDevelopers[i];
        NSString *address = [@"https://t.me/" stringByAppendingString:username];
        [credits addObject:[NoshiSettingsRow rowWithTitle:[@"@" stringByAppendingString:username] value:nil
                                                      tap:^{ [(NoshiAboutController *)weak.target open:address]; }]];
    }

    NoshiSettingsSection *creditSection = [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.credits", nil)
                                                                           footer:NSLocalizedString(@"about.credits.info", nil) rows:credits];
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.categories", nil) footer:nil rows:categories],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.links", nil) footer:nil rows:[NSArray arrayWithObjects:source, upstream, nil]],
        creditSection, nil];
}

@end

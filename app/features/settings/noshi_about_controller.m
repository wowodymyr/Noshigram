#import "noshi_about_controller.h"
#import "noshi_link_router.h"

#import "noshi_platform.h"
#import "noshi_string_drawing.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define ICON_SIDE 72.0
#define HEADER_HEIGHT 172.0

static NSString *const NoshiSourceAddress = @"https://github.com/wowodymyr/Noshigram";
static NSString *const NoshiUpstreamAddress = @"https://github.com/sqmrak/exteria";
static NSString *const NoshiClaudeAddress = @"https://www.anthropic.com/claude";

/* the people who made noshigram out of exteria, by their telegram names */
static NSString *const NoshiAuthors[] = {
    @"wowodymyr", @"BOP_COCICOK",
};

/* the developers of exteria, which noshigram is a fork of; its license asks every fork to name them */
static NSString *const NoshiUpstreamDevelopers[] = {
    @"sqmrak", @"QWERTYU1OPZ", @"LimeDev", @"menstry", @"anazerka", @"loveiOS6", @"nestorvashenko", @"svcayon4ik", @"illyagif",
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
    self.pageTitle = NSLocalizedString(@"settings.about", nil);
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

/* a person of the credits by the @name, which opens their profile in the app */
- (NoshiSettingsRow *)personRow:(NSString *)username {
    NoshiWeakReference *weak = _weak;
    NSString *address = [@"https://t.me/" stringByAppendingString:username];
    return [NoshiSettingsRow rowWithTitle:[@"@" stringByAppendingString:username] value:nil tap:^{ [(NoshiAboutController *)weak.target open:address]; }];
}

- (void)rebuild {
    self.headerView = [self makeHeader];
    [self rebuildSections];
}

- (void)rebuildSections {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *source = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"about.source", nil) value:nil
                                                          tap:^{ [(NoshiAboutController *)weak.target open:NoshiSourceAddress]; }];
    NoshiSettingsRow *upstream = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"about.upstream", nil) value:nil
                                                            tap:^{ [(NoshiAboutController *)weak.target open:NoshiUpstreamAddress]; }];
    source.link = YES;
    upstream.link = YES;

    NSMutableArray *authors = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(NoshiAuthors) / sizeof(NoshiAuthors[0]); ++i) [authors addObject:[self personRow:NoshiAuthors[i]]];
    /* claude has no telegram name, so its row opens the page of the model */
    [authors addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"about.claude", nil) value:nil
                                                  tap:^{ [(NoshiAboutController *)weak.target open:NoshiClaudeAddress]; }]];
    NSMutableArray *credits = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(NoshiUpstreamDevelopers) / sizeof(NoshiUpstreamDevelopers[0]); ++i) [credits addObject:[self personRow:NoshiUpstreamDevelopers[i]]];

    self.sections = [NSArray arrayWithObjects:
        /* the addresses stand under the links in plain words, so the rows stay one line high */
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.links", nil)
                                         footer:[NSString stringWithFormat:@"%@\n%@", [NoshiSourceAddress substringFromIndex:[@"https://" length]], [NoshiUpstreamAddress substringFromIndex:[@"https://" length]]]
                                           rows:[NSArray arrayWithObjects:source, upstream, nil]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.authors", nil) footer:nil rows:authors],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.credits", nil) footer:NSLocalizedString(@"about.credits.info", nil) rows:credits], nil];
}

@end

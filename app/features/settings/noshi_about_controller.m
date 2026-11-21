#import "noshi_ayu_controller.h"
#import "noshi_about_controller.h"
#import "noshi_general_settings_controller.h"
#import "noshi_more_settings_controller.h"
#import "noshi_link_router.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_chat_extras_controller.h"
#import "noshi_developers.h"
#import "noshi_developer_settings.h"
#import "noshi_alert.h"
#import "noshi_classic_chrome.h"
#import "noshi_gift_screen.h"
#import "noshi_custom_emoji.h"
#import "noshi_pill_tabs_view.h"
#import "noshi_platform.h"
#import "noshi_shape.h"
#import "noshi_person.h"
#import "noshi_session_bots.h"
#import "noshi_settings_pages.h"
#import "noshi_string_drawing.h"
#import "noshi_team_picture.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define ICON_SIDE 88.0
#define HEADER_HEIGHT 196.0
#define PILL_HEIGHT 20.0
#define PERSON_TILE 36.0
#define LEAD_TILE 42.0

static NSString *const NoshiChannelAddress = @"https://t.me/sqmrakdev";
static NSString *const NoshiSourceAddress = @"https://github.com/wowodymyr/Noshigram";

typedef struct {
    long long userId;
    NSString *role;
    /* the outline of the picture: a circle pressed in by lobes dents of the given depth, as the shapes of the material 3 expressive set are */
    int lobes;
    CGFloat depth;
    /* the app this person made, with the picture of its icon, or nil */
    NSString *app;
    NSString *appIcon;
} NoshiCredit;

static const NoshiCredit NoshiCredits[] = {
    {8202789099LL, @"about.lead", 9, 0.10, @"Senko", @"app_senko"},
    {5435278149LL, @"about.backend", 4, 0.14, @"LegacyGram", @"app_legacygram"},
    {8510741400LL, @"about.frontend", 8, 0.16, @"MintAI", @"app_mintai"},
    {588487063LL, @"about.backend", 12, 0.08, @"TeleGloss", @"app_telegloss"},
    {8796163695LL, @"about.backend", 5, 0.12, @"Twelve", @"app_twelve"},
    {5191291829LL, @"about.frontend", 6, 0.14, @"iChatter", @"app_ichatter"},
    {5390055485LL, @"about.frontend", 7, 0.12, @"iKlassika", @"app_iklassika"},
    {6233584668LL, @"about.backend", 10, 0.10, @"FlowGram", @"app_flowgram"},
};

/* the slice the running code was built for, which is what the version line shows */
static NSString *NoshiSliceName(void) {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__arm__)
    return @"armv7";
#else
    return @"host";
#endif
}

/* the picture drawn inside a wavy circle (a plain circle with no depth: the classic style has no wavy shapes), r = R (1 - depth / 2 + depth / 2 cos(lobes angle)), so the outline touches the square at every lobe */
static UIImage *NoshiShapedPicture(UIImage *source, int lobes, CGFloat depth, CGFloat side) {
    if (!source) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGFloat radius = side / 2;
    UIBezierPath *outline = [UIBezierPath bezierPath];
    const int steps = 180;
    for (int i = 0; i <= steps; ++i) {
        CGFloat angle = (CGFloat)i * 2 * (CGFloat)M_PI / steps;
        CGFloat reach = radius * (1 - depth / 2 + depth / 2 * cos(lobes * angle));
        CGPoint point = CGPointMake(radius + reach * cos(angle), radius + reach * sin(angle));
        if (i == 0) [outline moveToPoint:point];
        else [outline addLineToPoint:point];
    }
    [outline closePath];
    [outline addClip];
    [source drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the people that were loaded in this run, with the time, so a page opened again does not ask the server for all of them once more */
static NSMutableDictionary *NoshiTeamPeopleMemory(void) {
    static NSMutableDictionary *people;
    if (!people) people = [[NSMutableDictionary alloc] init];
    return people;
}
#define TEAM_PERSON_FRESH_SECONDS 900.0

/* the wavy picture of a person, made once for a source picture and kept with it: the source is held, so its address cannot come back for another picture */
static UIImage *NoshiCachedShapedPicture(NSNumber *identifier, UIImage *source, int lobes, CGFloat depth, CGFloat side) {
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
    }
    NSString *key = [NSString stringWithFormat:@"%@/%d/%g/%g", identifier, lobes, (double)depth, (double)side];
    NSArray *kept = [cache objectForKey:key];
    if (kept && [kept objectAtIndex:0] == source) return [kept objectAtIndex:1];
    UIImage *shaped = NoshiShapedPicture(source, lobes, depth, side);
    if (shaped) [cache setObject:[NSArray arrayWithObjects:source, shaped, nil] forKey:key];
    return shaped;
}

static UIImage *NoshiBundledPicture(NSString *name) {
    static NSMutableDictionary *kept;
    if (!kept) kept = [[NSMutableDictionary alloc] init];
    UIImage *cached = [kept objectForKey:name];
    if (cached) return cached;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!image) NSLog(@"noshigram: about picture %@ is missing from the bundle", name);
    else [kept setObject:image forKey:name];
    return image;
}

/* the picture a person stands behind until the server's one arrives: a colored square with the first letter of the name, drawn here, since no picture of a person
   is kept in the app */
static UIImage *NoshiInitialPicture(NSString *name, CGFloat side) {
    static NSMutableDictionary *kept;
    if (!kept) kept = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%@/%g", name, (double)side];
    UIImage *cached = [kept objectForKey:key];
    if (cached) return cached;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat hue = (CGFloat)(name.hash % 360) / 360;
    [[UIColor colorWithHue:hue saturation:0.45 brightness:0.78 alpha:1] setFill];
    CGContextFillRect(context, CGRectMake(0, 0, side, side));
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    UIFont *font = NoshiFontBold(side * 0.5);
    [[UIColor whiteColor] set];
    CGSize size = NoshiStringSize(letter, font);
    NoshiDrawStringIn(letter, font, CGRectMake(0, (side - size.height) / 2, side, size.height), NoshiStringTailTruncate, NoshiTextAlignmentCenter);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [kept setObject:image forKey:key];
    return image;
}

/* the icon of the app in a circle */
static UIImage *NoshiRoundIcon(CGFloat side) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Icon-83.5@2x" ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) return NoshiSettingsMarkTile(side);
    /* the classic style sets the icon in a chrome rim, as the logo of the QR code is */
    if (NoshiThemeIsClassic()) return NoshiClassicMetalDisc(source, side);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] addClip];
    [source drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface NoshiCreditView : UIControl {
    UIImageView *_picture;
    UILabel *_name;
    UILabel *_role;
    UILabel *_made;
    UIImageView *_appIcon;
    NSMutableArray *_marks;
    long long _userId;
    CAShapeLayer *_morphMask;
}
@property (nonatomic, assign) long long userId;
/* the picture of the lead takes the outlines of the Material shapes one after another, as the power button of Shiro does: it holds one, springs into the next and turns slowly;
   picture is the square one, not cut to any shape */
- (void)morphPicture:(UIImage *)picture;
- (id)initWithName:(NSString *)name role:(NSString *)role made:(NSString *)made picture:(UIImage *)picture appIcon:(UIImage *)icon marks:(NSUInteger)marks;
@end

@implementation NoshiCreditView
@synthesize userId = _userId;

- (id)initWithName:(NSString *)name role:(NSString *)role made:(NSString *)made picture:(UIImage *)picture appIcon:(UIImage *)icon marks:(NSUInteger)marks {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = NoshiColorCard();
    self.layer.cornerRadius = 12;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = role.length ? [NSString stringWithFormat:@"@%@, %@", name, role] : [@"@" stringByAppendingString:name];
    _picture = [[UIImageView alloc] initWithImage:picture];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_picture];
    _name = [[UILabel alloc] init];
    _name.backgroundColor = [UIColor clearColor];
    _name.font = NoshiFontSemibold(16);
    _name.textColor = NoshiColorTitle();
    _name.text = [@"@" stringByAppendingString:name];
    _name.adjustsFontSizeToFitWidth = YES;
    _name.minimumFontSize = 10;
    [self addSubview:_name];
    _role = [[UILabel alloc] init];
    _role.backgroundColor = [UIColor clearColor];
    _role.font = NoshiFontRegular(13);
    _role.textColor = NoshiColorSecondary();
    _role.text = role;
    [self addSubview:_role];
    _made = [[UILabel alloc] init];
    _made.backgroundColor = [UIColor clearColor];
    _made.font = NoshiFontRegular(13);
    _made.textColor = NoshiColorAccent();
    _made.text = made;
    [self addSubview:_made];
    _appIcon = [[UIImageView alloc] initWithImage:icon];
    _appIcon.contentMode = UIViewContentModeScaleAspectFit;
    _appIcon.layer.cornerRadius = 5;
    _appIcon.clipsToBounds = YES;
    [self addSubview:_appIcon];
    _marks = [[NSMutableArray alloc] init];
    const NSUInteger bits[] = {NoshiMarkDeveloper, NoshiMarkLead, NoshiMarkSenko, NoshiMarkOfficialTester, NoshiMarkBugHunter, NoshiMarkFlawSeer, NoshiMarkManager, NoshiMarkPromotion};
    const long long documents[] = {NOSHI_DEVELOPER_DOCUMENT, NOSHI_LEAD_DOCUMENT, NOSHI_SENKO_DOCUMENT, NOSHI_OFFICIAL_TESTER_DOCUMENT, NOSHI_BUG_HUNTER_DOCUMENT, NOSHI_FLAW_SEER_DOCUMENT, NOSHI_MANAGER_DOCUMENT, NOSHI_PROMOTION_DOCUMENT};
    for (NSUInteger i = 0; i < sizeof(bits) / sizeof(bits[0]); ++i) {
        if (!(marks & bits[i])) continue;
        UIImage *image = [NoshiCustomEmoji imageForDocument:documents[i]];
        if (!image) continue;
        UIImageView *badge = [[[UIImageView alloc] initWithImage:image] autorelease];
        badge.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:badge];
        [_marks addObject:badge];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _picture.frame = CGRectMake(12, (height - LEAD_TILE) / 2, LEAD_TILE, LEAD_TILE);
    CGFloat right = width - 12;
    _appIcon.frame = CGRectMake(right - 26, (height - 26) / 2, 26, 26);
    if (_appIcon.image) right -= 34;
    CGFloat badges = _marks.count * 20;
    CGFloat left = 12 + LEAD_TILE + 10;
    CGFloat titleWidth = MAX(0, right - left - badges - 4);
    CGFloat measured = ceil(NoshiStringSize(_name.text, _name.font).width);
    _name.frame = CGRectMake(left, _role.text.length ? (_made.text.length ? 9 : 11) : (height - 22) / 2, MIN(titleWidth, measured), 22);
    CGFloat x = CGRectGetMaxX(_name.frame) + 4;
    for (UIImageView *badge in _marks) {
        badge.frame = CGRectMake(x, _name.frame.origin.y + 2, 18, 18);
        x += 20;
    }
    _role.frame = CGRectMake(left, CGRectGetMaxY(_name.frame), MAX(0, right - left), 18);
    _made.frame = CGRectMake(left, CGRectGetMaxY(_role.frame), MAX(0, right - left), 18);
}

/* the shapes the picture passes through; they are the ones with 240 points, because core animation only interpolates two paths that are built the same way */
static const NoshiShape NoshiMorphShapes[] = {NoshiShapeCookie, NoshiShapeFlower, NoshiShapeClover, NoshiShapeSunny, NoshiShapeBurst};
#define MORPH_COUNT (sizeof(NoshiMorphShapes) / sizeof(NoshiMorphShapes[0]))
#define MORPH_HOLD 1.45
#define MORPH_MOVE 0.55
#define MORPH_TURN 14.0
static NSString *const NoshiMorphPathKey = @"about.morph";
static NSString *const NoshiMorphTurnKey = @"about.turn";

- (CGPathRef)morphOutline:(size_t)index {
    return NoshiShapePath(NoshiMorphShapes[index % MORPH_COUNT], CGRectMake(0, 0, LEAD_TILE, LEAD_TILE), 0).CGPath;
}

- (void)morphPicture:(UIImage *)picture {
    _picture.image = picture;
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    if (!_morphMask) {
        _morphMask = [[CAShapeLayer layer] retain];
        _morphMask.frame = CGRectMake(0, 0, LEAD_TILE, LEAD_TILE);
        _picture.layer.mask = _morphMask;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncMorph) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    _morphMask.path = [self morphOutline:0];
    [self syncMorph];
}

/* core animation drops running animations while the app is in the background, so they are put back when the view comes on a screen and when the app returns */
- (void)syncMorph {
    if (!_morphMask) return;
    if (!self.window || NoshiReduceMotionEnabled()) {
        [_morphMask removeAnimationForKey:NoshiMorphPathKey];
        [_morphMask removeAnimationForKey:NoshiMorphTurnKey];
        return;
    }
    if ([_morphMask animationForKey:NoshiMorphPathKey]) return;
    /* one hold and one spring into the next shape for each of the shapes, round to the first again */
    CFTimeInterval period = MORPH_HOLD + MORPH_MOVE, total = period * MORPH_COUNT;
    NSMutableArray *values = [NSMutableArray array], *times = [NSMutableArray array], *easing = [NSMutableArray array];
    CAMediaTimingFunction *spring = [CAMediaTimingFunction functionWithControlPoints:0.34f:1.45f:0.64f:1.0f];
    CAMediaTimingFunction *linear = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    for (size_t i = 0; i < MORPH_COUNT; ++i) {
        [values addObject:(id)[self morphOutline:i]];
        [times addObject:[NSNumber numberWithDouble:period * i / total]];
        [values addObject:(id)[self morphOutline:i]];
        [times addObject:[NSNumber numberWithDouble:(period * i + MORPH_HOLD) / total]];
        [easing addObject:linear];
        [easing addObject:spring];
    }
    [values addObject:(id)[self morphOutline:0]];
    [times addObject:[NSNumber numberWithDouble:1]];
    CAKeyframeAnimation *morph = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    morph.values = values;
    morph.keyTimes = times;
    morph.timingFunctions = easing;
    morph.duration = total;
    morph.repeatCount = HUGE_VALF;
    /* the phase follows the clock, so the page made again at the arrival of a name or a photo carries on where the shape was, and not from the first one */
    morph.timeOffset = fmod(CACurrentMediaTime(), total);
    [_morphMask addAnimation:morph forKey:NoshiMorphPathKey];
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithDouble:0];
    turn.toValue = [NSNumber numberWithDouble:M_PI * 2];
    turn.duration = MORPH_TURN;
    turn.repeatCount = HUGE_VALF;
    turn.timingFunction = linear;
    turn.timeOffset = fmod(CACurrentMediaTime(), MORPH_TURN);
    [_morphMask addAnimation:turn forKey:NoshiMorphTurnKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self syncMorph];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_morphMask release];
    [_picture release];
    [_name release];
    [_role release];
    [_made release];
    [_appIcon release];
    [_marks release];
    [super dealloc];
}
@end

@interface NoshiAboutController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiWeakReference *_weak;
    /* photos and people by their stable account id */
    NSMutableDictionary *_fresh;
    NSMutableDictionary *_people;
    NSMutableSet *_requested;
    NSUInteger _teamTab;
    /* presses of the lead's picture in a row; the fifth opens the developer settings */
    NSUInteger _leadTaps;
    BOOL _rebuildScheduled;
    NSTimeInterval _leadTapTime;
}
@end

@implementation NoshiAboutController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _fresh = [[NSMutableDictionary alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _requested = [[NSMutableSet alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.noshigram", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(developerModeChanged:) name:NoshiDeveloperModeDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    [_fresh release];
    [_people release];
    [_requested release];
    [_avatars release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self fetchPhotos];
}

/* the id stays with the account when its username changes */
- (void)fetchPhotos {
    NSMutableArray *ids = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(NoshiCredits) / sizeof(NoshiCredits[0]); ++i)
        [ids addObject:[NSNumber numberWithLongLong:NoshiCredits[i].userId]];
    if (_teamTab == 1) [ids addObjectsFromArray:NoshiOfficialTesterIds()];
    for (NSNumber *identifier in ids) {
        if ([_requested containsObject:identifier]) continue;
        [_requested addObject:identifier];
        /* a person loaded a moment ago is taken as it was, with the picture kept for it */
        NSDictionary *held = [NoshiTeamPeopleMemory() objectForKey:identifier];
        if (held && -[[held objectForKey:@"date"] timeIntervalSinceNow] < TEAM_PERSON_FRESH_SECONDS) {
            [_people setObject:[held objectForKey:@"person"] forKey:identifier];
            continue;
        }
        NoshiWeakReference *weak = _weak;
        NoshiLoadTeamPerson(_session, identifier.longLongValue, ^(NoshiPerson *person, NSString *error) {
            NoshiAboutController *me = weak.target;
            if (!me) return;
            if (!person) {
                NSLog(@"noshigram: team user %@ could not be loaded: %@", identifier, error);
                return;
            }
            [NoshiTeamPeopleMemory() setObject:[NSDictionary dictionaryWithObjectsAndKeys:person, @"person", [NSDate date], @"date", nil] forKey:identifier];
            [me->_people setObject:person forKey:identifier];
            [me scheduleRebuild];
            if (!person.photo) return;
            [me->_avatars loadImageForPhoto:person.photo completion:^(UIImage *image) {
                if (!image) return;
                /* kept even when the page is gone: the next one opens with it */
                NoshiKeepTeamImage(identifier, image);
                NoshiAboutController *again = weak.target;
                if (!again) return;
                [again->_fresh setObject:image forKey:identifier];
                [again scheduleRebuild];
            }];
        });
    }
    [self scheduleRebuild];
}

/* the names and the photos arrive one by one, and a page of the whole team was built again at each; one build after a short wait takes them all */
- (void)scheduleRebuild {
    if (_rebuildScheduled) return;
    _rebuildScheduled = YES;
    [self performSelector:@selector(runScheduledRebuild) withObject:nil afterDelay:0.12];
}

- (void)runScheduledRebuild {
    _rebuildScheduled = NO;
    [self rebuildSections];
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
    UIImageView *icon = [[[UIImageView alloc] initWithImage:NoshiRoundIcon(ICON_SIDE)] autorelease];
    icon.frame = CGRectMake(0, 24, ICON_SIDE, ICON_SIDE);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    icon.center = CGPointMake(width / 2, icon.center.y);
    [header addSubview:icon];
    UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake(0, 24 + ICON_SIDE + 10, width, 30)] autorelease];
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.backgroundColor = [UIColor clearColor];
    name.textAlignment = NoshiTextAlignmentCenter;
    name.font = NoshiFontBold(24);
    name.textColor = NoshiColorTitle();
    name.text = NSLocalizedString(@"about.name", nil);
    [header addSubview:name];

    NSString *version = [@"v" stringByAppendingString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @""];
    UILabel *versionLabel = [[[UILabel alloc] init] autorelease];
    versionLabel.backgroundColor = [UIColor clearColor];
    versionLabel.font = NoshiFontRegular(15);
    versionLabel.textColor = NoshiColorSecondary();
    versionLabel.text = version;
    UILabel *pill = [[[UILabel alloc] init] autorelease];
    pill.backgroundColor = [NoshiColorAccent() colorWithAlphaComponent:0.18];
    pill.textColor = NoshiColorAccent();
    pill.font = NoshiFontSemibold(12);
    pill.textAlignment = NoshiTextAlignmentCenter;
    pill.text = NoshiSliceName();
    pill.layer.cornerRadius = PILL_HEIGHT / 2;
    pill.layer.masksToBounds = YES;
    /* the widths are the ones the labels themselves ask for: the measure of the string alone came out a point or two short, and the pill sat on the last letter */
    [versionLabel sizeToFit];
    [pill sizeToFit];
    CGFloat versionWidth = ceil(versionLabel.frame.size.width) + 2;
    CGFloat pillWidth = MAX(ceil(pill.frame.size.width), ceil(NoshiStringSize(pill.text, pill.font).width)) + 18;
    CGFloat gap = 10;
    CGFloat y = CGRectGetMaxY(name.frame) + 4;
    /* the two stand in one view, which is the one that keeps to the middle: with a flexible margin on each, the header changing its width (a tablet turned upright) moved the version and
       the pill by different amounts, and the pill came to stand on the last letters of the version */
    CGFloat lineWidth = versionWidth + gap + pillWidth;
    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(floor((width - lineWidth) / 2), y, lineWidth, PILL_HEIGHT)] autorelease];
    line.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    versionLabel.frame = CGRectMake(0, 0, versionWidth, PILL_HEIGHT);
    pill.frame = CGRectMake(versionWidth + gap, 0, pillWidth, PILL_HEIGHT);
    [line addSubview:versionLabel];
    [line addSubview:pill];
    [header addSubview:line];
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
    NSString *title = NSLocalizedString(key, nil);
    return [NoshiSettingsRow rowWithSymbol:symbol tone:tone title:title subtitle:nil value:nil tap:^{
        NoshiAboutController *me = weak.target;
        if (me) [me.navigationController pushViewController:page() animated:YES];
    }];
}

- (NoshiSettingsRow *)personRow:(const NoshiCredit *)person {
    NSNumber *identifier = [NSNumber numberWithLongLong:person->userId];
    NoshiPerson *known = [_people objectForKey:identifier];
    NSString *name = known.username.length ? known.username : NoshiTeamUsername(person->userId);
    NSString *role = person->role ? NSLocalizedString(person->role, nil) : nil;
    BOOL lead = person == &NoshiCredits[0];
    NSString *made = lead && person->app ? [NSString stringWithFormat:NSLocalizedString(@"about.made", nil), person->app] : nil;
    UIImage *picture = [_fresh objectForKey:identifier] ?: NoshiStoredTeamImage(identifier) ?: NoshiInitialPicture(name, 2 * LEAD_TILE);
    UIImage *icon = lead && person->appIcon ? NoshiBundledPicture(person->appIcon) : nil;
    NoshiCreditView *view = [[[NoshiCreditView alloc] initWithName:name role:role made:made picture:NoshiCachedShapedPicture(identifier, picture, NoshiThemeIsClassic() ? 0 : person->lobes, NoshiThemeIsClassic() ? 0 : person->depth, LEAD_TILE)
                                                                  appIcon:icon marks:NoshiMarksOfId(person->userId)] autorelease];
    /* the lead's picture is not one wavy outline but all of the Material shapes in turn; the classic style has no such shapes */
    if (lead && !NoshiThemeIsClassic()) [view morphPicture:picture];
    [view addTarget:self action:@selector(creditTapped:) forControlEvents:UIControlEventTouchUpInside];
    view.userId = person->userId;
    return [NoshiSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return made ? 80 : 62; }];
}

- (void)developerModeChanged:(NSNotification *)note {
    (void)note;
    [self rebuildSections];
}

/* the lead's row opens the profile after a short wait, which a second press in a row cancels: five presses are the way to the developer settings, and the
   profile is for the single one */
- (void)creditTapped:(NoshiCreditView *)view {
    if (view.userId != NOSHI_TEAM_LEAD_ID) {
        [self openCredit:view.userId];
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(openLead) object:nil];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _leadTapTime > 1.5) _leadTaps = 0;
    _leadTapTime = now;
    if (++_leadTaps >= 5) {
        _leadTaps = 0;
        if (NoshiDeveloperModeEnabled()) {
            NoshiShowNotice(nil, NSLocalizedString(@"developer.already", nil));
            return;
        }
        NoshiDeveloperModeSet(YES);
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDeveloperModeDidChangeNotification object:nil];
        NoshiShowNotice(nil, NSLocalizedString(@"developer.unlocked", nil));
        return;
    }
    [self performSelector:@selector(openLead) withObject:nil afterDelay:0.45];
}

- (void)openLead {
    [self openCredit:NOSHI_TEAM_LEAD_ID];
}

- (void)openCredit:(long long)userId {
    NoshiPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:userId]];
    if (!person || !person.accessHash) {
        NoshiGiftAlert(nil, NSLocalizedString(@"about.person.unavailable", nil));
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenTeamPersonNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:person forKey:@"person"]];
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
        /* the theme and the dark mode live on this page, so it is the one category that has something in it */
        [self categoryRow:NoshiSymbolBackground tone:NoshiSettingsToneOrange key:@"about.look" page:^UIViewController *{
            return [[[NoshiAppearanceSettingsController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:NoshiSymbolSettingsChat tone:NoshiSettingsToneGreen key:@"about.chats" page:^UIViewController *{
            return [[[NoshiChatExtrasController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:NoshiSymbolEyeSlash tone:NoshiSettingsTonePurplePastel key:@"ayu.title" page:^UIViewController *{
            return [[[NoshiAyuController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:NoshiSymbolEllipsis tone:NoshiSettingsToneGray key:@"about.more" page:^UIViewController *{
            return [[[NoshiMoreSettingsController alloc] initWithSession:session] autorelease];
        }], nil];
    /* what only the developers see: a black tile with a hammer, after the others */
    if (NoshiDeveloperModeEnabled()) {
        categories = [categories arrayByAddingObject:[self categoryRow:NoshiSymbolHammer tone:NoshiSettingsToneBlack key:@"developer.settings" page:^UIViewController *{
            return [[[NoshiDeveloperSettingsController alloc] initWithSession:session] autorelease];
        }]];
    }

    NoshiSettingsRow *channel = [NoshiSettingsRow rowWithSymbol:NoshiSymbolMegaphone tone:NoshiSettingsToneCyan title:NSLocalizedString(@"about.channel", nil)
                                                           subtitle:@"@sqmrakdev" value:nil tap:^{ [(NoshiAboutController *)weak.target open:NoshiChannelAddress]; }];
    NoshiSettingsRow *source = [NoshiSettingsRow rowWithSymbol:NoshiSymbolExternalLink tone:NoshiSettingsTonePurple title:NSLocalizedString(@"about.source", nil)
                                                          subtitle:[NoshiSourceAddress substringFromIndex:[@"https://" length]] value:nil tap:^{ [(NoshiAboutController *)weak.target open:NoshiSourceAddress]; }];

    NoshiPillTabsView *tabs = [[[NoshiPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"about.developers", nil), NSLocalizedString(@"about.testers", nil), nil]] autorelease];
    tabs.selectedIndex = _teamTab;
    tabs.changeHandler = ^(NSUInteger index) {
        NoshiAboutController *me = weak.target;
        if (!me) return;
        me->_teamTab = index;
        [me rebuildSections];
        [me fetchPhotos];
    };
    NSMutableArray *people = [NSMutableArray array];
    if (_teamTab == 0) {
        for (size_t i = 1; i < sizeof(NoshiCredits) / sizeof(NoshiCredits[0]); ++i) [people addObject:[self personRow:&NoshiCredits[i]]];
    } else {
        for (NSNumber *identifier in NoshiOfficialTesterIds()) {
            NoshiCredit tester = {identifier.longLongValue, nil, 8, 0.12, nil, nil};
            [people addObject:[self personRow:&tester]];
        }
    }

    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.categories", nil) footer:nil rows:categories],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.links", nil) footer:nil rows:[NSArray arrayWithObjects:channel, source, nil]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"about.team", nil) footer:nil rows:[NSArray arrayWithObject:[self personRow:&NoshiCredits[0]]]],
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:[NoshiSettingsRow viewRowWithView:tabs height:^CGFloat(CGFloat width) { (void)width; return 40; }]]],
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:people], nil];
}

@end

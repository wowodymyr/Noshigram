#import "noshi_developer_badges_controller.h"

#import "noshi_animation.h"
#import "noshi_custom_emoji.h"
#import "noshi_developers.h"
#import "noshi_emoji_label.h"
#import "noshi_name_badge.h"
#import "noshi_person.h"
#import "noshi_session.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* one badge: its bit, its picture and the words of its row */
typedef struct {
    NSUInteger mark;
    long long document;
    NSString *title;
    NSString *info;
} NoshiBadgeEntry;

static const NoshiBadgeEntry NoshiBadgeEntries[] = {
    {NoshiMarkLead, NOSHI_LEAD_DOCUMENT, @"developer.mark.lead", @"developer.lead"},
    {NoshiMarkDeveloper, NOSHI_DEVELOPER_DOCUMENT, @"developer.mark.developer", @"developer.notice"},
    {NoshiMarkSenko, NOSHI_SENKO_DOCUMENT, @"developer.mark.senko", @"developer.senko"},
    {NoshiMarkTester, NOSHI_TESTER_DOCUMENT, @"developer.mark.tester", @"developer.tester"},
    {NoshiMarkOfficialTester, NOSHI_OFFICIAL_TESTER_DOCUMENT, @"developer.mark.official", @"developer.official_tester"},
    {NoshiMarkBugHunter, NOSHI_BUG_HUNTER_DOCUMENT, @"developer.mark.hunter", @"developer.bug_hunter.notice"},
    {NoshiMarkFlawSeer, NOSHI_FLAW_SEER_DOCUMENT, @"developer.mark.flawseer", @"developer.flaw_seer.notice"},
    {NoshiMarkManager, NOSHI_MANAGER_DOCUMENT, @"developer.mark.manager", @"developer.manager"},
    {NoshiMarkVideoFix, NOSHI_VIDEO_FIX_DOCUMENT, @"developer.mark.videofix", @"developer.videofix"},
    {NoshiMarkPromotion, NOSHI_PROMOTION_DOCUMENT, @"developer.mark.promotion", @"developer.promotion"},
};
#define BADGE_COUNT (sizeof(NoshiBadgeEntries) / sizeof(NoshiBadgeEntries[0]))

/* the card at the top: the name of the account with the badges it wears now, large, on a ground that changes with each tap */
@interface NoshiBadgePreview : UIView {
    NoshiEmojiLabel *_name;
    UILabel *_caption;
}
- (void)showName:(NSString *)name marks:(NSUInteger)marks custom:(BOOL)custom;
@end

@implementation NoshiBadgePreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontBold(26);
    _name.textColor = NoshiColorTitle();
    _name.textAlignment = NoshiTextAlignmentCenter;
    _name.dropsUndrawable = YES;
    [self addSubview:_name];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.font = NoshiFontRegular(13);
    _caption.textColor = NoshiColorSecondary();
    _caption.textAlignment = NoshiTextAlignmentCenter;
    [self addSubview:_caption];
    return self;
}

- (void)dealloc {
    [_name release];
    [_caption release];
    [super dealloc];
}

- (void)showName:(NSString *)name marks:(NSUInteger)marks custom:(BOOL)custom {
    NSArray *entities = nil;
    _name.text = NoshiNameWithBadges(name, 0, marks, &entities);
    _name.entities = entities;
    _caption.text = NSLocalizedString(custom ? @"developer.badges.preview.local" : @"developer.badges.preview.real", nil);
    /* the name pops a little at each change, so a tap is seen where the eyes are */
    _name.transform = CGAffineTransformMakeScale(0.94, 0.94);
    NoshiAnimateView(_name, CGAffineTransformIdentity, 1, NOSHI_MOTION_SPRING, nil);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _name.frame = CGRectMake(16, 26, MAX(0, size.width - 32), 40);
    _caption.frame = CGRectMake(16, 70, MAX(0, size.width - 32), 18);
}

@end

@interface NoshiDeveloperBadgesController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    long long _userId;
    NSString *_name;
    NoshiBadgePreview *_preview;
}
@end

@implementation NoshiDeveloperBadgesController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    NoshiPerson *own = [session ownPerson];
    _userId = own.userId;
    _name = [(own.name.length ? own.name : NSLocalizedString(@"developer.popup.someone", nil)) copy];
    self.pageTitle = NSLocalizedString(@"developer.badges", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_name release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[NoshiBadgePreview alloc] initWithFrame:CGRectZero];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiDeveloperBadgesController alloc] initWithSession:_session] autorelease];
}

- (NSUInteger)marks {
    return NoshiMarksOfId(_userId);
}

/* a tap takes the badge or gives it back; the first tap sets the badges of this phone to the ones the account really has plus or minus that one */
- (void)toggle:(NSUInteger)mark {
    NSUInteger marks = [self marks];
    if (marks & mark) marks &= ~mark;
    else marks |= mark;
    NoshiSetLocalMarks(_userId, marks);
    [self rebuild];
}

- (void)setAll:(BOOL)on {
    NSUInteger all = 0;
    for (size_t i = 0; i < BADGE_COUNT; ++i) all |= NoshiBadgeEntries[i].mark;
    NoshiSetLocalMarks(_userId, on ? all : 0);
    [self rebuild];
}

- (void)restore {
    NoshiClearLocalMarks(_userId);
    [self rebuild];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSUInteger marks = [self marks];
    NSMutableArray *rows = [NSMutableArray array];
    for (size_t i = 0; i < BADGE_COUNT; ++i) {
        NSUInteger mark = NoshiBadgeEntries[i].mark;
        UIImage *picture = [NoshiCustomEmoji imageForDocument:NoshiBadgeEntries[i].document];
        BOOL on = (marks & mark) != 0;
        NoshiSettingsRow *row = [NoshiSettingsRow rowWithTileImage:picture title:NSLocalizedString(NoshiBadgeEntries[i].title, nil)
                                                              subtitle:NSLocalizedString(NoshiBadgeEntries[i].info, nil) tap:^{ [(NoshiDeveloperBadgesController *)weak.target toggle:mark]; }];
        if (on) row.trailingImage = NoshiSymbolImage(NoshiSymbolCheckMark(), 22, NoshiColorAccent());
        [rows addObject:row];
    }
    NoshiSettingsRow *previewRow = [NoshiSettingsRow viewRowWithView:_preview height:^CGFloat(CGFloat width) { (void)width; return 104; }];
    [_preview showName:_name marks:marks custom:NoshiHasLocalMarks(_userId)];
    NSMutableArray *tools = [NSMutableArray arrayWithObjects:
        [NoshiSettingsRow actionRowWithSymbol:(NoshiThemeIsClassic() ? NoshiSymbolCheckDouble : NoshiSymbolMaterialDoneAll) title:NSLocalizedString(@"developer.badges.all", nil) destructive:NO tap:^{ [(NoshiDeveloperBadgesController *)weak.target setAll:YES]; }],
        [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCloseMark() title:NSLocalizedString(@"developer.badges.none", nil) destructive:NO tap:^{ [(NoshiDeveloperBadgesController *)weak.target setAll:NO]; }], nil];
    if (NoshiHasLocalMarks(_userId)) {
        [tools addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolRotate title:NSLocalizedString(@"developer.badges.restore", nil) destructive:YES
                                                             tap:^{ [(NoshiDeveloperBadgesController *)weak.target restore]; }]];
    }
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:previewRow]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"developer.badges.header", nil) footer:NSLocalizedString(@"developer.badges.info", nil) rows:rows],
        [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:tools], nil];
}

@end

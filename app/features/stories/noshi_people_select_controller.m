#import "noshi_people_select_controller.h"

#import "noshi_person.h"
#import "noshi_weak_reference.h"
#import "noshi_alert.h"
#import "noshi_story.h"
#import "noshi_theme.h"

@interface NoshiPeopleSelectController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    NSArray *_all;
    NSMutableDictionary *_chosen;   /* user id -> person, in the order they were chosen */
    NSMutableArray *_order;
    NSString *_status;
    NSString *_title;
    void (^_done)(NSArray *);
}
@end

@implementation NoshiPeopleSelectController

- (id)initWithSession:(NoshiSession *)session title:(NSString *)title chosen:(NSArray *)chosen done:(void (^)(NSArray *))done {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _title = [title copy];
    _done = [done copy];
    _chosen = [[NSMutableDictionary alloc] init];
    _order = [[NSMutableArray alloc] init];
    for (NoshiPerson *person in chosen) {
        NSNumber *key = [NSNumber numberWithLongLong:person.userId];
        if ([_chosen objectForKey:key]) continue;
        [_chosen setObject:person forKey:key];
        [_order addObject:key];
    }
    self.searchable = YES;
    self.pageTitle = title;
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_all release];
    [_chosen release];
    [_order release];
    [_status release];
    [_title release];
    [_done release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadContacts:^(NSArray *items, NSString *errorName) {
        NoshiPeopleSelectController *me = weak.target;
        if (!me) return;
        if (!items) {
            [me->_status release];
            me->_status = [(errorName ? errorName : @"") copy];
        } else {
            [me->_all release];
            me->_all = [items retain];
            [me->_status release];
            me->_status = [(items.count ? @"" : NSLocalizedString(@"contacts.empty", nil)) copy];
        }
        [me rebuild];
    }];
}

- (void)themeDidChange { [self rebuild]; }

- (void)toggle:(NoshiPerson *)person {
    NSNumber *key = [NSNumber numberWithLongLong:person.userId];
    if ([_chosen objectForKey:key]) {
        [_chosen removeObjectForKey:key];
        [_order removeObject:key];
    } else {
        [_chosen setObject:person forKey:key];
        [_order addObject:key];
    }
    [self updateTitle];
    if (self.searching) [self reloadSearchResults]; else [self rebuild];
}

- (void)updateTitle {
    self.pageTitle = _order.count ? [NSString stringWithFormat:@"%@ (%lu)", _title, (unsigned long)_order.count] : _title;
}

- (NSArray *)sectionsForPeople:(NSArray *)people footer:(NSString *)footer {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiPerson *person in people) {
        BOOL on = [_chosen objectForKey:[NSNumber numberWithLongLong:person.userId]] != nil;
        NSString *line = person.username.length ? [@"@" stringByAppendingString:person.username] : nil;
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:person.name subtitle:line checked:on tap:^{ [(NoshiPeopleSelectController *)weak.target toggle:person]; }]];
    }
    return [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
}

- (void)rebuild {
    self.sections = [self sectionsForPeople:_all footer:_status];
    [self reloadSettings];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSMutableArray *matches = [NSMutableArray array];
    for (NoshiPerson *person in _all) {
        if ([person.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [person.username rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:person];
    }
    return [self sectionsForPeople:matches footer:matches.count ? nil : NSLocalizedString(@"chats.nothing", nil)];
}

/* the choice is handed over when the page is left */
- (void)goBack {
    if (self.searching) { [super goBack]; return; }
    if (_done) {
        NSMutableArray *people = [NSMutableArray array];
        for (NSNumber *key in _order) [people addObject:[_chosen objectForKey:key]];
        void (^done)(NSArray *) = [[_done copy] autorelease];
        /* said once: a page left twice (the arrow, then the end of its dismissal) must not apply the choice twice */
        [_done release];
        _done = nil;
        done(people);
    }
    if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (UINavigationController *)presentableNavigation {
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
    navigation.navigationBarHidden = !NoshiThemeIsClassic();
    if (NoshiThemeIsClassic()) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"story.close", nil)
            style:UIBarButtonItemStyleDone target:self action:@selector(goBack)] autorelease];
    }
    return navigation;
}

@end

/* ---- the choice of who sees a story ---- */

NSString *NoshiStoryAudienceTitle(NoshiStoryAudience *audience) {
    NSUInteger left = audience.denied.count, chosen = audience.allowed.count;
    switch (audience.base) {
    case NOSHI_STORY_CONTACTS:
        return left ? [NSString stringWithFormat:NSLocalizedString(@"story.privacy.contacts.except", nil), (unsigned long)left] : NSLocalizedString(@"story.privacy.contacts", nil);
    case NOSHI_STORY_CLOSE_FRIENDS: return NSLocalizedString(@"story.privacy.close", nil);
    case NOSHI_STORY_SELECTED: return [NSString stringWithFormat:NSLocalizedString(@"story.privacy.selected.count", nil), (unsigned long)chosen];
    default:
        return left ? [NSString stringWithFormat:NSLocalizedString(@"story.privacy.everyone.except", nil), (unsigned long)left] : NSLocalizedString(@"story.privacy.everyone", nil);
    }
}

void NoshiChooseStoryAudience(UIViewController *host, NoshiSession *session, NoshiStoryAudience *current, void (^done)(NoshiStoryAudience *), void (^cancelled)(void)) {
    if (!host || !session) { if (cancelled) cancelled(); return; }
    void (^finish)(NoshiStoryAudience *) = [[done copy] autorelease];
    void (^cancel)(void) = [[cancelled copy] autorelease];
    NoshiStoryAudience *held = [[current retain] autorelease];
    NoshiWeakReference *weakHost = [NoshiWeakReference referenceTo:host];
    NSArray *buttons = [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"story.privacy.everyone", nil),
                        NSLocalizedString(@"story.privacy.everyone.choose", nil), NSLocalizedString(@"story.privacy.contacts", nil),
                        NSLocalizedString(@"story.privacy.contacts.choose", nil), NSLocalizedString(@"story.privacy.close", nil),
                        NSLocalizedString(@"story.privacy.selected", nil), nil];
    NoshiShowAlert(NSLocalizedString(@"story.manage.privacy", nil), nil, buttons, 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index < 1 || index > 6) { if (cancel) cancel(); return; }
        noshi_story_privacy base = index <= 2 ? NOSHI_STORY_EVERYONE : (index <= 4 ? NOSHI_STORY_CONTACTS : (index == 5 ? NOSHI_STORY_CLOSE_FRIENDS : NOSHI_STORY_SELECTED));
        BOOL asksPeople = index == 2 || index == 4 || index == 6;
        if (!asksPeople) {
            if (finish) finish([NoshiStoryAudience audienceWithBase:base]);
            return;
        }
        UIViewController *top = weakHost.target;
        if (!top) { if (cancel) cancel(); return; }
        /* a list chosen before for the same kind of audience is where the page starts */
        NSArray *start = held.base == base ? (base == NOSHI_STORY_SELECTED ? held.allowed : held.denied) : nil;
        NSString *title = NSLocalizedString(base == NOSHI_STORY_SELECTED ? @"story.privacy.selected.title" : @"story.privacy.except.title", nil);
        NoshiPeopleSelectController *page = [[[NoshiPeopleSelectController alloc] initWithSession:session title:title chosen:start done:^(NSArray *people) {
            if (base == NOSHI_STORY_SELECTED && !people.count) { if (cancel) cancel(); return; }
            NoshiStoryAudience *audience = [NoshiStoryAudience audienceWithBase:base];
            if (base == NOSHI_STORY_SELECTED) audience.allowed = people; else audience.denied = people;
            if (finish) finish(audience);
        }] autorelease];
        [top presentViewController:[page presentableNavigation] animated:YES completion:nil];
    });
}


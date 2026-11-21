#import "noshi_contact_picker_controller.h"

#import "noshi_gift_screen.h"
#import "noshi_people_avatars.h"
#import "noshi_weak_reference.h"

@interface NoshiContactPickerController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiWeakReference *_weak;
    NoshiPeopleAvatars *_faces;
    NSArray *_all;
    NSString *_status;
    NoshiPerson *_selfPerson;
    void (^_pickHandler)(NoshiDialog *);
}
@end

@implementation NoshiContactPickerController

@synthesize selfPerson = _selfPerson;
@synthesize pickHandler = _pickHandler;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    (void)media;
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_all release];
    [_status release];
    [_selfPerson release];
    [_pickHandler release];
    [super dealloc];
}

- (NSString *)screenTitle {
    return self.pageTitle;
}

- (void)setScreenTitle:(NSString *)title {
    self.pageTitle = title;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadContacts:^(NSArray *items, NSString *errorName) {
        NoshiContactPickerController *me = weak.target;
        if (!me) return;
        if (!items) {
            [me->_status release];
            me->_status = [NoshiGiftErrorText(errorName) copy];
            [me rebuild];
            return;
        }
        NSMutableArray *rows = [NSMutableArray array];
        for (NoshiPerson *person in items) {
            if (!me->_selfPerson || person.userId != me->_selfPerson.userId) [rows addObject:person];
        }
        [me->_all release];
        me->_all = [rows retain];
        [me->_status release];
        me->_status = [(items.count ? @"" : NSLocalizedString(@"contacts.empty", nil)) copy];
        [me rebuild];
    }];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)choose:(NoshiPerson *)person {
    BOOL me = _selfPerson && person.userId == _selfPerson.userId;
    NoshiDialog *dialog = me ? [NoshiDialog savedMessagesWithPerson:person] : [NoshiDialog dialogWithPerson:person];
    if (!dialog) {
        NoshiGiftAlert(nil, NoshiGiftErrorText(@"PEER_ID_INVALID"));
        return;
    }
    if (_pickHandler) _pickHandler(dialog);
}

- (NoshiSettingsRow *)rowOfPerson:(NoshiPerson *)person {
    NoshiWeakReference *weak = _weak;
    if (!_faces) _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{
            NoshiContactPickerController *me = weak.target;
            if (me.searching) [me reloadSearchResults];
            else [me rebuild];
        }];
    UIImage *face = [_faces imageForKey:[NSString stringWithFormat:@"%lld", person.userId] initials:person.initials seed:(NSUInteger)(person.userId % 1000003) deleted:person.deleted photo:person.photo];
    BOOL own = _selfPerson && person.userId == _selfPerson.userId;
    return [NoshiSettingsRow rowWithTileImage:face title:person.name subtitle:own ? NSLocalizedString(@"gifts.pick.self", nil) : (person.username.length ? [@"@" stringByAppendingString:person.username] : nil)
                                            tap:^{ [(NoshiContactPickerController *)weak.target choose:person]; }];
}

- (NSArray *)sectionsForPeople:(NSArray *)people withSelf:(BOOL)withSelf footer:(NSString *)footer {
    NSMutableArray *sections = [NSMutableArray array];
    if (withSelf && _selfPerson) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:[self rowOfPerson:_selfPerson]]]];
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiPerson *person in people) [rows addObject:[self rowOfPerson:person]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    return sections;
}

- (void)rebuild {
    self.sections = [self sectionsForPeople:_all withSelf:YES footer:_status];
    [self reloadSettings];
}

- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSMutableArray *matches = [NSMutableArray array];
    NSMutableArray *pool = [NSMutableArray arrayWithArray:_all];
    if (_selfPerson) [pool insertObject:_selfPerson atIndex:0];
    for (NoshiPerson *person in pool) {
        if ([person.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [person.username rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [matches addObject:person];
    }
    return [self sectionsForPeople:matches withSelf:NO footer:matches.count ? nil : NSLocalizedString(@"chats.nothing", nil)];
}

@end

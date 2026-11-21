#import "noshi_contact_list.h"

#import "noshi_person.h"
#import "noshi_platform.h"

static NSString *const NoshiSortByNameKey = @"noshigram.contacts.sortbyname";

@interface NoshiContactList () {
    NSArray *_people;
    NSString *_query;
    BOOL _sortByName;
    NSArray *_titles;
    NSArray *_sections;
    NSUInteger _count;
}
@end

@implementation NoshiContactList

@synthesize titles = _titles;
@synthesize sections = _sections;
@synthesize count = _count;
@synthesize sortByName = _sortByName;
@synthesize people = _people;
@synthesize query = _query;

+ (BOOL)storedSortByName {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoshiSortByNameKey];
}

+ (void)storeSortByName:(BOOL)byName {
    [[NSUserDefaults standardUserDefaults] setBool:byName forKey:NoshiSortByNameKey];
    NoshiDefaultsSaveSoon();
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _sortByName = [NoshiContactList storedSortByName];
    _people = [[NSArray alloc] init];
    _titles = [[NSArray alloc] init];
    _sections = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_people release];
    [_query release];
    [_titles release];
    [_sections release];
    [super dealloc];
}

static NSComparisonResult NoshiCompareNames(NSString *a, NSString *b) {
    return [a compare:b options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch range:NSMakeRange(0, a.length) locale:[NSLocale currentLocale]];
}

/* the letter a name is filed under: its first letter in capitals, or a number sign for a name that starts with anything else */
static NSString *NoshiLetterOfName(NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return @"#";
    NSRange first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
    /* uppercaseStringWithLocale: is ios 6; the plain call capitalizes cyrillic and latin letters alike */
    NSString *letter = [[trimmed substringWithRange:first] uppercaseString];
    return [[NSCharacterSet letterCharacterSet] characterIsMember:[letter characterAtIndex:0]] ? letter : @"#";
}

/* how recently somebody was seen, as a number that grows with the time */
static int NoshiSeenRank(NoshiPerson *person) {
    switch (person.presence) {
    case NOSHI_PRESENCE_ONLINE: return 0;
    case NOSHI_PRESENCE_OFFLINE: return person.seen > 0 ? 1 : 5;
    case NOSHI_PRESENCE_RECENTLY: return 2;
    case NOSHI_PRESENCE_LAST_WEEK: return 3;
    case NOSHI_PRESENCE_LAST_MONTH: return 4;
    default: return 5;
    }
}

- (BOOL)person:(NoshiPerson *)person matches:(NSString *)query {
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if ([person.name rangeOfString:query options:options].location != NSNotFound) return YES;
    if (person.username.length && [person.username rangeOfString:query options:options].location != NSNotFound) return YES;
    return person.phone.length && [person.phone rangeOfString:query].location != NSNotFound;
}

- (void)rebuild {
    NSString *query = [_query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *shown = [NSMutableArray array];
    for (NoshiPerson *person in _people) {
        if (query.length && ![self person:person matches:query]) continue;
        [shown addObject:person];
    }
    NSArray *titles;
    NSArray *sections;
    if (_sortByName) {
        NSArray *sorted = [shown sortedArrayUsingComparator:^NSComparisonResult(NoshiPerson *a, NoshiPerson *b) { return NoshiCompareNames(a.name, b.name); }];
        NSMutableArray *letters = [NSMutableArray array];
        NSMutableDictionary *groups = [NSMutableDictionary dictionary];
        for (NoshiPerson *person in sorted) {
            NSString *letter = NoshiLetterOfName(person.name);
            NSMutableArray *group = [groups objectForKey:letter];
            if (!group) {
                group = [NSMutableArray array];
                [groups setObject:group forKey:letter];
                [letters addObject:letter];
            }
            [group addObject:person];
        }
        [letters sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            if ([a isEqualToString:@"#"]) return [b isEqualToString:@"#"] ? NSOrderedSame : NSOrderedDescending;
            if ([b isEqualToString:@"#"]) return NSOrderedAscending;
            return NoshiCompareNames(a, b);
        }];
        NSMutableArray *built = [NSMutableArray array];
        for (NSString *letter in letters) [built addObject:[groups objectForKey:letter]];
        titles = letters;
        sections = built;
    } else {
        NSArray *sorted = [shown sortedArrayUsingComparator:^NSComparisonResult(NoshiPerson *a, NoshiPerson *b) {
            int ra = NoshiSeenRank(a), rb = NoshiSeenRank(b);
            if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
            if (ra == 1 && a.seen != b.seen) return a.seen > b.seen ? NSOrderedAscending : NSOrderedDescending;
            return NoshiCompareNames(a.name, b.name);
        }];
        titles = sorted.count ? [NSArray arrayWithObject:[NSNull null]] : [NSArray array];
        sections = sorted.count ? [NSArray arrayWithObject:sorted] : [NSArray array];
    }
    [_titles release];
    _titles = [titles retain];
    [_sections release];
    _sections = [sections retain];
    _count = shown.count;
}

- (void)setPeople:(NSArray *)people {
    if (people == _people) return;
    [_people release];
    _people = [people ? people : [NSArray array] retain];
    [self rebuild];
}

- (void)setSortByName:(BOOL)byName {
    _sortByName = byName;
    [self rebuild];
}

- (void)setQuery:(NSString *)query {
    if (query == _query || [query isEqualToString:_query]) return;
    [_query release];
    _query = [query copy];
    [self rebuild];
}

- (NoshiPerson *)personAtIndexPath:(NSIndexPath *)path {
    if ((NSUInteger)path.section >= _sections.count) return nil;
    NSArray *group = [_sections objectAtIndex:(NSUInteger)path.section];
    return (NSUInteger)path.row < group.count ? [group objectAtIndex:(NSUInteger)path.row] : nil;
}

@end

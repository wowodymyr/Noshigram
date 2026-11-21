#import "noshi_cleaning.h"
#import "noshi_memory_controller.h"

#import "noshi_cache_kind.h"
#import "noshi_chat_settings.h"
#import "noshi_donut_view.h"
#import "noshi_sheet.h"
#import "noshi_storage_card_view.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* the bytes the way the cache screen writes them, with the separator of the language: 2,86 GB, 389,2 MB, 12 KB */
static NSString *NoshiMemorySize(unsigned long long bytes, int gigabyteDecimals) {
    if (!bytes) return NSLocalizedString(@"settings.cache.empty", nil);
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString localizedStringWithFormat:@"%.*f GB", gigabyteDecimals, (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString localizedStringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    return [NSString localizedStringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

/* the number and the unit apart, for the middle of the ring */
static void NoshiMemoryParts(unsigned long long bytes, NSString **amount, NSString **unit) {
    NSString *whole = bytes ? NoshiMemorySize(bytes, 1) : @"0 KB";
    NSRange space = [whole rangeOfString:@" " options:NSBackwardsSearch];
    *amount = space.location == NSNotFound ? whole : [whole substringToIndex:space.location];
    *unit = space.location == NSNotFound ? @"" : [whole substringFromIndex:space.location + 1];
}

/* the kinds as the screen lists them: the five of the media cache, and the photos of people, which live in a cache of their own */
enum { NoshiStorageAvatars = NOSHI_CACHE_KIND_COUNT, NoshiStorageKinds };

static const int NoshiStorageOrder[] = {NOSHI_CACHE_VIDEO, NOSHI_CACHE_PHOTO, NOSHI_CACHE_MUSIC, NOSHI_CACHE_STICKER, NoshiStorageAvatars, NOSHI_CACHE_OTHER};
static NSString *const NoshiStorageTitles[NoshiStorageKinds] = {
    @"memory.kind.video", @"memory.kind.photo", @"memory.kind.music", @"memory.kind.stickers", @"memory.kind.other", @"memory.avatars"};
static const uint32_t NoshiStorageColors[NoshiStorageKinds] = {0x4DA3FF, 0x2F6FE4, 0x9362E8, 0xF58A3C, 0xF2B632, 0x35B8A6};

#define HEADER_PAD 14.0
#define DONUT_SIDE 176.0

/* the days a file stays: zero is as long as the cache has room */
static const NSInteger NoshiKeepChoices[] = {3, 7, 30, 0};
static NSString *const NoshiKeepTitles[] = {@"memory.keep.3", @"memory.keep.7", @"memory.keep.30", @"memory.keep.forever"};

@interface NoshiMemoryController () {
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    unsigned long long _bytes[NoshiStorageKinds];
    BOOL _selected[NoshiStorageKinds];
    BOOL _loaded;
    /* a scan that was started before the screen was rebuilt must not fill the new one */
    NSUInteger _scan;
    UIView *_header;
    NoshiDonutView *_donut;
    UILabel *_headline;
    UILabel *_subtitle;
    NoshiStorageCardView *_card;
}
@end

@implementation NoshiMemoryController

- (id)initWithAvatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    for (int i = 0; i < NoshiStorageKinds; ++i) _selected[i] = YES;
    self.pageTitle = NSLocalizedString(@"memory.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_avatars release];
    [_media release];
    [_header release];
    [_donut release];
    [_headline release];
    [_subtitle release];
    [_card release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiMemoryController alloc] initWithAvatars:_avatars media:_media] autorelease];
}

/* the kinds that hold something, in the order of the screen */
- (NSArray *)shownKinds {
    NSMutableArray *kinds = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(NoshiStorageOrder) / sizeof(NoshiStorageOrder[0]); ++i) {
        if (_bytes[NoshiStorageOrder[i]]) [kinds addObject:[NSNumber numberWithInt:NoshiStorageOrder[i]]];
    }
    return kinds;
}

- (unsigned long long)selectedBytes {
    unsigned long long total = 0;
    for (int i = 0; i < NoshiStorageKinds; ++i) if (_selected[i]) total += _bytes[i];
    return total;
}

- (NSString *)deviceShareLine {
    NSDictionary *system = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    double capacity = [[system objectForKey:NSFileSystemSize] doubleValue];
    if (capacity <= 0) return nil;
    unsigned long long all = 0;
    for (int i = 0; i < NoshiStorageKinds; ++i) all += _bytes[i];
    double percent = (double)all * 100.0 / capacity;
    NSString *text = percent < 1 ? @"<1%" : [NSString stringWithFormat:@"%d%%", (int)floor(percent + 0.5)];
    return [NSString stringWithFormat:NSLocalizedString(@"memory.share", nil), text];
}

/* puts the numbers into the ring, the card and the line under the title; animated is for a check that was tapped */
- (void)showStorageAnimated:(BOOL)animated {
    NSArray *kinds = [self shownKinds];
    NSMutableArray *values = [NSMutableArray array], *colors = [NSMutableArray array], *titles = [NSMutableArray array], *shares = [NSMutableArray array];
    NSMutableArray *sizes = [NSMutableArray array], *checks = [NSMutableArray array];
    unsigned long long all = 0;
    for (int i = 0; i < NoshiStorageKinds; ++i) all += _bytes[i];
    for (NSNumber *number in kinds) {
        int kind = number.intValue;
        [values addObject:[NSNumber numberWithDouble:_selected[kind] ? (double)_bytes[kind] : 0]];
        [colors addObject:NoshiColorOfRGB(NoshiStorageColors[kind])];
        [titles addObject:NSLocalizedString(NoshiStorageTitles[kind], nil)];
        double share = all ? (double)_bytes[kind] * 100.0 / (double)all : 0;
        [shares addObject:share < 1 ? @"<1%" : [NSString stringWithFormat:@"%d%%", (int)floor(share + 0.5)]];
        [sizes addObject:NoshiMemorySize(_bytes[kind], 2)];
        [checks addObject:[NSNumber numberWithBool:_selected[kind]]];
    }
    unsigned long long picked = [self selectedBytes];
    NSString *amount = nil, *unit = nil;
    NoshiMemoryParts(picked, &amount, &unit);
    [_donut setValues:values colors:colors amount:amount unit:unit animated:animated];
    _subtitle.text = [self deviceShareLine];
    [_card setTitles:titles shares:shares sizes:sizes colors:colors checked:checks buttonTitle:NSLocalizedString(@"memory.clear.button", nil)
          buttonSize:picked ? NoshiMemorySize(picked, 2) : nil enabled:picked > 0];
    [_header setNeedsLayout];
}

- (void)toggleKindAtIndex:(NSUInteger)index {
    NSArray *kinds = [self shownKinds];
    if (index >= kinds.count) return;
    int kind = [[kinds objectAtIndex:index] intValue];
    _selected[kind] = !_selected[kind];
    /* the ring slides and the check moves; the rows stay where they are */
    [self showStorageAnimated:YES];
}

- (void)scanStorage {
    NoshiWeakReference *weak = _weak;
    NSUInteger scan = ++_scan;
    _bytes[NoshiStorageAvatars] = [_avatars diskBytes];
    [_media loadKindBytes:^(const unsigned long long *bytes) {
        NoshiMemoryController *me = weak.target;
        if (!me || me->_scan != scan) return;
        for (int i = 0; i < NOSHI_CACHE_KIND_COUNT; ++i) me->_bytes[i] = bytes[i];
        me->_loaded = YES;
        [me showStorageAnimated:NO];
        [me reloadSettings];
    }];
}

- (void)confirmClear {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"memory.clear.confirm", nil), NSLocalizedString(@"settings.cache.clear", nil), ^{
        NoshiMemoryController *again = weak.target;
        if (!again) return;
        NoshiMediaCache *media = again->_media;
        NoshiAvatarCache *avatars = again->_avatars;
        NSMutableArray *steps = [NSMutableArray array];
        for (NSNumber *number in [again shownKinds]) {
            int kind = number.intValue;
            if (!again->_selected[kind]) continue;
            NSString *name = NSLocalizedString(NoshiStorageTitles[kind], nil);
            if (kind == NoshiStorageAvatars) [steps addObject:[NoshiCleaningStep stepNamed:name asyncWork:^(void (^finished)(BOOL)) { [avatars clearWithCompletion:finished]; }]];
            else [steps addObject:[NoshiCleaningStep stepNamed:name asyncWork:^(void (^finished)(BOOL)) { [media clearKindsMask:1u << kind completion:finished]; }]];
        }
        if (!steps.count) return;
        NoshiRunCleaning(steps, ^{
            [(NoshiMemoryController *)weak.target rebuild];
        });
    });
}

- (UIView *)buildHeader {
    UIView *header = [[[UIView alloc] init] autorelease];
    [_donut release];
    _donut = [[NoshiDonutView alloc] initWithFrame:CGRectMake(0, 0, DONUT_SIDE, DONUT_SIDE)];
    [header addSubview:_donut];
    [_headline release];
    _headline = [[UILabel alloc] init];
    _headline.backgroundColor = [UIColor clearColor];
    _headline.font = NoshiFontBold(24);
    _headline.textColor = NoshiColorTitle();
    _headline.textAlignment = NoshiTextAlignmentCenter;
    _headline.adjustsFontSizeToFitWidth = YES;
    _headline.minimumFontSize = 16;
    _headline.text = NSLocalizedString(@"memory.title", nil);
    [header addSubview:_headline];
    [_subtitle release];
    _subtitle = [[UILabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.font = NoshiFontMedium(15);
    _subtitle.textColor = NoshiColorSecondary();
    _subtitle.textAlignment = NoshiTextAlignmentCenter;
    _subtitle.numberOfLines = 2;
    [header addSubview:_subtitle];
    [_header release];
    _header = [header retain];
    return header;
}

- (void)layoutHeader:(CGFloat)width {
    _donut.frame = CGRectMake(floor((width - DONUT_SIDE) / 2), HEADER_PAD, DONUT_SIDE, DONUT_SIDE);
    CGFloat y = HEADER_PAD + DONUT_SIDE + 18;
    _headline.frame = CGRectMake(8, y, width - 16, 30);
    CGSize line = [_subtitle.text ? _subtitle.text : @"" sizeWithFont:_subtitle.font constrainedToSize:CGSizeMake(width - 32, 40)];
    _subtitle.frame = CGRectMake(16, y + 32, width - 32, line.height);
}

- (CGFloat)headerHeight:(CGFloat)width {
    [self layoutHeader:width];
    return CGRectGetMaxY(_subtitle.frame) + 20;
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    UIView *header = [self buildHeader];
    [_card release];
    _card = [[NoshiStorageCardView alloc] init];
    _card.toggleHandler = ^(NSUInteger index) { [(NoshiMemoryController *)weak.target toggleKindAtIndex:index]; };
    _card.clearHandler = ^{ [(NoshiMemoryController *)weak.target confirmClear]; };
    /* the first frame of a screen that waits for the scan is an empty ring; the rows come in when the files are counted */
    memset(_bytes, 0, sizeof(_bytes));
    _loaded = NO;
    [self showStorageAnimated:NO];
    NoshiSettingsRow *ring = [NoshiSettingsRow viewRowWithView:header height:^CGFloat(CGFloat width) {
        NoshiMemoryController *me = weak.target;
        return me ? [me headerHeight:width] : 0;
    }];
    NoshiStorageCardView *card = _card;
    NoshiSettingsRow *rows = [NoshiSettingsRow viewRowWithView:card height:^CGFloat(CGFloat width) {
        (void)width;
        NoshiMemoryController *me = weak.target;
        return [NoshiStorageCardView heightForRows:me ? [me shownKinds].count : 0];
    }];
    NSMutableArray *keep = [NSMutableArray array];
    NSInteger days = NoshiCacheKeepDays();
    for (size_t i = 0; i < sizeof(NoshiKeepChoices) / sizeof(NoshiKeepChoices[0]); ++i) {
        NSInteger choice = NoshiKeepChoices[i];
        [keep addObject:[NoshiSettingsRow checkRowWithTitle:NSLocalizedString(NoshiKeepTitles[i], nil) subtitle:nil checked:days == choice tap:^{
            NoshiMemoryController *me = weak.target;
            if (!me) return;
            NoshiCacheSetKeepDays(choice);
            /* the files past the new limit go at once, not at the next start */
            [me->_media removeFilesOlderThanDays:choice];
            [me rebuild];
        }]];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"memory.clear.info", nil) rows:[NSArray arrayWithObjects:ring, rows, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"memory.keep", nil) footer:NSLocalizedString(@"memory.keep.info", nil) rows:keep]];
    self.sections = sections;
    [self reloadSettings];
    [self scanStorage];
}

@end

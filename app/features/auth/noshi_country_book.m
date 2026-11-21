#import "noshi_country_book.h"

#import "noshi_flag_sprite.h"
#import "noshi_phone.h"

@interface NoshiCountry () {
    NSString *_iso;
    NSString *_code;
    NSString *_name;
    NSString *_pattern;
    NSInteger _flag;
    NSUInteger _entry;
}
- (id)initWithEntry:(const noshi_country *)entry index:(NSUInteger)index flag:(NSInteger)flag;
- (NSComparisonResult)compareName:(NoshiCountry *)other;
@property (nonatomic, readonly) NSInteger flag;
@property (nonatomic, readonly) NSUInteger entry;
@end

@implementation NoshiCountry

@synthesize iso = _iso;
@synthesize code = _code;
@synthesize name = _name;
@synthesize pattern = _pattern;
@synthesize flag = _flag;
@synthesize entry = _entry;

- (id)initWithEntry:(const noshi_country *)entry index:(NSUInteger)index flag:(NSInteger)flag {
    self = [super init];
    if (!self) return nil;
    _iso = [[NSString stringWithUTF8String:entry->iso] retain];
    _code = [[NSString stringWithUTF8String:entry->code] retain];
    _pattern = [[NSString stringWithUTF8String:entry->pattern] retain];
    /* the list spells names its own way; the system knows them in every language */
    NSString *local = [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:_iso];
    NSString *listed = [NSString stringWithUTF8String:entry->name];
    _name = [(local.length && ![local isEqualToString:_iso] ? local : listed) retain];
    _flag = flag;
    _entry = index;
    return self;
}

- (NSComparisonResult)compareName:(NoshiCountry *)other {
    return [_name localizedCaseInsensitiveCompare:other.name];
}

- (void)dealloc {
    [_iso release];
    [_code release];
    [_name release];
    [_pattern release];
    [super dealloc];
}

@end

@interface NoshiCountryBook () {
    noshi_country *_table;
    size_t _tableCount;
    NSArray *_countries;
    NSMutableDictionary *_byISO;
    NSMutableDictionary *_flags;
    NSMutableArray *_entries;
    CGImageRef _sprite;
}
@end

@implementation NoshiCountryBook

@synthesize countries = _countries;

static NSString *NoshiBundleText(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
    return path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    NSString *list = NoshiBundleText(@"countries");
    NSString *flagOrder = NoshiBundleText(@"flags");
    NSData *listData = [list dataUsingEncoding:NSUTF8StringEncoding];
    _table = calloc(NOSHI_COUNTRY_MAX, sizeof(noshi_country));
    noshi_status status = listData && _table
        ? noshi_country_parse(listData.bytes, listData.length, _table, NOSHI_COUNTRY_MAX, &_tableCount)
        : NOSHI_E_NOTFOUND;
    UIImage *sprite = [UIImage imageNamed:@"flag_sprite"];
    if (status != NOSHI_OK || !flagOrder || !sprite) {
        NSLog(@"noshigram: country list did not load (%s)", noshi_status_name(status));
        [self release];
        return nil;
    }
    _sprite = CGImageRetain(sprite.CGImage);
    NSMutableDictionary *flagIndex = [NSMutableDictionary dictionary];
    NSArray *isos = [flagOrder componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSUInteger i = 0; i < isos.count; ++i) {
        [flagIndex setObject:[NSNumber numberWithUnsignedInteger:i] forKey:[isos objectAtIndex:i]];
    }
    _byISO = [[NSMutableDictionary alloc] init];
    _flags = [[NSMutableDictionary alloc] init];
    _entries = [[NSMutableArray alloc] init];
    for (size_t i = 0; i < _tableCount; ++i) {
        NSNumber *flag = [flagIndex objectForKey:[NSString stringWithUTF8String:_table[i].iso]];
        NoshiCountry *country = [[[NoshiCountry alloc] initWithEntry:&_table[i] index:i
                                                                    flag:flag ? [flag integerValue] : -1] autorelease];
        [_entries addObject:country];
        if (![_byISO objectForKey:country.iso]) [_byISO setObject:country forKey:country.iso];
    }
    _countries = [[_entries sortedArrayUsingSelector:@selector(compareName:)] retain];
    return self;
}

- (void)dealloc {
    free(_table);
    if (_sprite) CGImageRelease(_sprite);
    [_countries release];
    [_byISO release];
    [_flags release];
    [_entries release];
    [super dealloc];
}

- (NoshiCountry *)countryForISO:(NSString *)iso {
    return [_byISO objectForKey:iso];
}

- (NoshiCountry *)countryForDigits:(NSString *)digits codeLength:(NSUInteger *)codeLength {
    size_t used = 0;
    const noshi_country *hit = noshi_country_match(_table, _tableCount, digits.UTF8String, &used);
    if (codeLength) *codeLength = used;
    return hit ? [_entries objectAtIndex:(NSUInteger)(hit - _table)] : nil;
}

- (NoshiCountry *)localCountry {
    NSString *iso = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    NoshiCountry *country = iso ? [_byISO objectForKey:[iso uppercaseString]] : nil;
    return country ? country : [_byISO objectForKey:@"US"];
}

- (UIImage *)flagForCountry:(NoshiCountry *)country {
    if (!country || country.flag < 0) return nil;
    NSNumber *key = [NSNumber numberWithInteger:country.flag];
    UIImage *flag = [_flags objectForKey:key];
    if (!flag) {
        NSInteger column = country.flag % NOSHI_FLAG_COLUMNS;
        NSInteger row = country.flag / NOSHI_FLAG_COLUMNS;
        CGRect tile = CGRectMake(column * NOSHI_FLAG_TILE_WIDTH, row * NOSHI_FLAG_TILE_HEIGHT,
                                 NOSHI_FLAG_TILE_WIDTH, NOSHI_FLAG_TILE_HEIGHT);
        CGImageRef cut = CGImageCreateWithImageInRect(_sprite, tile);
        if (!cut) return nil;
        /* the tile holds twice the pixels of the largest flag on screen */
        flag = [UIImage imageWithCGImage:cut scale:2.0 orientation:UIImageOrientationUp];
        CGImageRelease(cut);
        [_flags setObject:flag forKey:key];
    }
    return flag;
}

@end

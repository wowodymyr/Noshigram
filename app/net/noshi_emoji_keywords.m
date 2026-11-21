#import "noshi_emoji_keywords.h"

#import "noshi_language.h"

@interface NoshiEmojiKeywords () {
    NSString *_language;
    NSString *_path;
    noshi_keyword_index *_index;
    NSLock *_lock;
    BOOL _updateRequested;
}
@end

@implementation NoshiEmojiKeywords

@synthesize language = _language;
@synthesize updateRequested = _updateRequested;

+ (NoshiEmojiKeywords *)keywordsForLanguage:(NSString *)language {
    static NSMutableDictionary *kept;
    @synchronized ([NoshiEmojiKeywords class]) {
        if (!kept) kept = [[NSMutableDictionary alloc] init];
        NoshiEmojiKeywords *keywords = [kept objectForKey:language];
        if (!keywords) {
            keywords = [[[NoshiEmojiKeywords alloc] initWithLanguage:language] autorelease];
            if (keywords) [kept setObject:keywords forKey:language];
        }
        return keywords;
    }
}

+ (NSArray *)searchLanguages {
    NSString *own = NoshiInterfaceLanguage();
    if (!own.length) return [NSArray arrayWithObject:@"en"];
    return [own isEqualToString:@"en"] ? [NSArray arrayWithObject:@"en"] : [NSArray arrayWithObjects:own, @"en", nil];
}

- (id)initWithLanguage:(NSString *)language {
    self = [super init];
    if (!self) return nil;
    /* the code goes into a file name, so it is checked as the core checks it: letters, digits, - and _ */
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
    if (!language.length || language.length > 15 || [language rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) {
        [self release];
        return nil;
    }
    _language = [language copy];
    _lock = [[NSLock alloc] init];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *folder = [caches stringByAppendingPathComponent:@"noshigram-emoji-keywords"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _path = [[folder stringByAppendingPathComponent:[language stringByAppendingString:@".bin"]] retain];
    NSData *file = [NSData dataWithContentsOfFile:_path];
    if (file.length) {
        noshi_status status = noshi_keyword_index_decode(file.bytes, file.length, &_index);
        if (status != NOSHI_OK) {
            /* a file that cannot be read is dropped, and the next update asks for the whole list */
            NSLog(@"noshigram: the emoji keywords of %@ were refused: %s", language, noshi_status_name(status));
            [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
        }
    }
    if (!_index) _index = noshi_keyword_index_new();
    if (!_index) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc {
    noshi_keyword_index_free(_index);
    [_language release];
    [_path release];
    [_lock release];
    [super dealloc];
}

- (int32_t)version {
    [_lock lock];
    int32_t version = noshi_keyword_index_version(_index);
    [_lock unlock];
    return version;
}

- (NSArray *)emojiForQuery:(NSString *)query {
    const char *text = query.UTF8String;
    if (!text) return [NSArray array];
    char (*found)[NOSHI_KEYWORD_EMOJI_MAX] = malloc(sizeof(*found) * NOSHI_KEYWORD_RESULTS_MAX);
    if (!found) return [NSArray array];
    [_lock lock];
    size_t count = noshi_keywords_search(_index, text, found, NOSHI_KEYWORD_RESULTS_MAX);
    [_lock unlock];
    NSMutableArray *emoji = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; ++i) {
        NSString *item = [NSString stringWithUTF8String:found[i]];
        if (item.length) [emoji addObject:item];
    }
    free(found);
    return emoji;
}

- (noshi_status)applyAnswer:(const noshi_tl_value *)answer {
    [_lock lock];
    noshi_status status = noshi_keywords_apply(_index, _language.UTF8String, answer);
    uint8_t *bytes = NULL;
    size_t length = 0;
    if (status == NOSHI_OK && noshi_keyword_index_encode(_index, &bytes, &length) == NOSHI_OK) {
        NSData *file = [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES];
        /* the index in memory is whole either way; a file that could not be written only costs the next launch a full download */
        if (![file writeToFile:_path atomically:YES]) NSLog(@"noshigram: the emoji keywords of %@ could not be written", _language);
    }
    [_lock unlock];
    return status;
}

@end

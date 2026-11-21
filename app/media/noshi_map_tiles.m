#import "noshi_map_tiles.h"
#import "noshi_image_decoder.h"
#import "noshi_shiro_network.h"
#include "noshi_https.h"

#define DISK_LIMIT (32u * 1024u * 1024u)
#define TILE_LIMIT NOSHI_MAP_TILE_BYTES_MAX

@class NoshiMapTileJob;
@interface NoshiMapTileTicket () {
@public
    NoshiMapTiles *owner;
    NoshiMapTileJob *job;
    void (^done)(UIImage *, NSString *);
}
@end

@interface NoshiMapTileJob : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, retain) NSMutableArray *tickets;
@property (nonatomic, retain) NSOperation *operation;
@property (atomic, assign) BOOL cancelled;
@end
@implementation NoshiMapTileJob
@synthesize key, tickets, operation, cancelled;
- (void)dealloc { [key release]; [tickets release]; [operation release]; [super dealloc]; }
@end

@interface NoshiMapTiles () {
    NSCache *_memory;
    NSCache *_cooldowns;
    NSMutableDictionary *_jobs;
    NSOperationQueue *_workers;
    NSString *_directory;
    NSData *_roots;
}
- (void)cancelTicket:(NoshiMapTileTicket *)ticket;
@end

@implementation NoshiMapTileTicket
- (void)cancel { [owner cancelTicket:self]; }
- (void)dealloc { [done release]; [job release]; [super dealloc]; }
@end

static int NoshiMapCancelled(void *context) {
    return [(NoshiMapTileJob *)context cancelled];
}

static UIImage *NoshiTileImage(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || !noshi_map_png_header(data.bytes,data.length)) return nil;
    return NoshiDecodeImage(data, 256);
}

static NSDictionary *NoshiTileHeaders(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [headers setObject:value forKey:name];
    }
    return headers;
}

static NSString *NoshiTileValidator(id value) {
    if (![value isKindOfClass:[NSString class]] || [value length] > 512 || [value rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) return nil;
    return value;
}

static NSDate *NoshiTileExpiry(NSDictionary *headers, BOOL *store) {
    NSTimeInterval lifetime = 7*24*60*60;
    NSString *control = [[headers objectForKey:@"cache-control"] lowercaseString];
    *store = [control rangeOfString:@"no-store"].location == NSNotFound || !control;
    BOOL hasAge = NO;
    for (NSString *piece in [control componentsSeparatedByString:@","]) {
        NSString *directive = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([directive hasPrefix:@"max-age="]) {
            NSString *value = [[directive substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
            NSScanner *scanner = [NSScanner scannerWithString:value];
            long long age = 0;
            if ([scanner scanLongLong:&age] && scanner.isAtEnd && age >= 0) { lifetime = MIN((double)age, 31536000); hasAge = YES; }
        }
    }
    if (!hasAge && [headers objectForKey:@"expires"]) {
        NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
        format.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
        format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        format.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
        NSDate *date = [format dateFromString:[headers objectForKey:@"expires"]];
        if (date) lifetime = MAX(0,[date timeIntervalSinceNow]);
    }
    if (hasAge) lifetime = MAX(0,lifetime - MAX(0,[[headers objectForKey:@"age"] doubleValue]));
    if (control && [control rangeOfString:@"no-cache"].location != NSNotFound) lifetime = 0;
    return [NSDate dateWithTimeIntervalSinceNow:lifetime];
}

@implementation NoshiMapTiles

+ (NoshiMapTiles *)sharedTiles {
    static NoshiMapTiles *tiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tiles = [[self alloc] init]; });
    return tiles;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _memory = [[NSCache alloc] init];
    _memory.countLimit = 48;
    _memory.totalCostLimit = 12*1024*1024;
    _cooldowns = [[NSCache alloc] init]; _cooldowns.countLimit=2;
    _jobs = [[NSMutableDictionary alloc] init];
    _workers = [[NSOperationQueue alloc] init];
    _workers.maxConcurrentOperationCount = 4;
    NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    _directory = [[cache stringByAppendingPathComponent:@"Noshigram/map-tiles"] copy];
    NSData *base=[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"]];
    NSData *maps=[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"map-roots" ofType:@"pem"]];
    if (base.length && maps.length) {
        NSMutableData *roots=[NSMutableData dataWithData:base];
        [roots appendData:maps]; _roots=[roots copy];
    } else NSLog(@"noshigram: map TLS roots are missing");
    [_workers addOperationWithBlock:^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        @synchronized(self) { [self trimDisk]; }
        [pool drain];
    }];
    return self;
}

- (void)dealloc {
    [_workers cancelAllOperations];
    [_workers release]; [_memory release]; [_cooldowns release]; [_jobs release]; [_directory release]; [_roots release];
    [super dealloc];
}

- (void)cancelTicket:(NoshiMapTileTicket *)ticket {
    NoshiMapTileJob *work = ticket->job;
    [ticket->done release]; ticket->done = nil;
    ticket->owner = nil;
    if (!work) return;
    [work retain];
    [work.tickets removeObjectIdenticalTo:ticket];
    [ticket->job release]; ticket->job = nil;
    if (!work.tickets.count) {
        work.cancelled = YES;
        [work.operation cancel];
        work.operation = nil;
        if ([_jobs objectForKey:work.key] == work) [_jobs removeObjectForKey:work.key];
    }
    [work release];
}

- (void)trimDisk {
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray *entries = [NSMutableArray array];
    unsigned long long total = 0;
    for (NSString *name in [files contentsOfDirectoryAtPath:_directory error:NULL]) {
        NSString *path = [_directory stringByAppendingPathComponent:name];
        NSDictionary *attrs = [files attributesOfItemAtPath:path error:NULL];
        unsigned long long size = [attrs fileSize];
        total += size;
        [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:path,@"path",[NSNumber numberWithUnsignedLongLong:size],@"size",
            [attrs fileModificationDate] ? [attrs fileModificationDate] : [NSDate distantPast],@"date",nil]];
    }
    [entries sortUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES]]];
    NSUInteger remaining = entries.count;
    for (NSDictionary *entry in entries) {
        if (total <= DISK_LIMIT && remaining <= 2048) break;
        NSError *error = nil;
        if ([files removeItemAtPath:[entry objectForKey:@"path"] error:&error]) { total -= [[entry objectForKey:@"size"] unsignedLongLongValue]; --remaining; }
        else NSLog(@"noshigram: map cache trim failed: %@",error);
    }
}

- (NoshiMapTileTicket *)loadTile:(noshi_map_tile)tile completion:(void (^)(UIImage *, NSString *))completion {
    NoshiMapTileTicket *ticket = [[[NoshiMapTileTicket alloc] init] autorelease];
    ticket->owner = self;
    ticket->done = [completion copy];
    if (tile.zoom > NOSHI_MAP_MAX_ZOOM || tile.x >= (1u<<tile.zoom) || tile.y >= (1u<<tile.zoom) || _jobs.count >= 128) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (ticket->done) ticket->done(nil,@"invalid tile"); [ticket cancel]; });
        return ticket;
    }
    NSString *source=@"osm";
    if ([[_cooldowns objectForKey:source] timeIntervalSinceNow]>0) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (ticket->done) ticket->done(nil,@"map server asked to wait"); [ticket cancel]; });
        return ticket;
    }
    NSString *key = [NSString stringWithFormat:@"%u-%u-%u",tile.zoom,tile.x,tile.y];
    NSDictionary *ready = [_memory objectForKey:key];
    if ([[ready objectForKey:@"expires"] timeIntervalSinceNow] > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (ticket->done) ticket->done([ready objectForKey:@"image"],nil); [ticket cancel]; });
        return ticket;
    }
    NoshiMapTileJob *work = [_jobs objectForKey:key];
    if (work) {
        ticket->job = [work retain]; [work.tickets addObject:ticket];
        return ticket;
    }
    work = [[[NoshiMapTileJob alloc] init] autorelease];
    work.key = key;
    work.tickets = [NSMutableArray arrayWithObject:ticket];
    ticket->job = [work retain];
    [_jobs setObject:work forKey:key];
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = [_directory stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"plist"]];
        NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        NSDictionary *cached=[attrs fileSize]<=512*1024 ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        NSData *data = [cached objectForKey:@"data"];
        UIImage *image = NoshiTileImage(data);
        NSDate *expires = [cached objectForKey:@"expires"];
        if (![expires isKindOfClass:[NSDate class]]) expires = [NSDate distantPast];
        NSString *failure = nil;
        BOOL cacheable = YES;
        if (!work.cancelled && (!image || [expires timeIntervalSinceNow] <= 0)) {
            NSString *host = @"tile.openstreetmap.org";
            NSString *urlPath = [NSString stringWithFormat:@"/%u/%u/%u.png",tile.zoom,tile.x,tile.y];
            NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            NSString *agent = [NSString stringWithFormat:@"User-Agent: Noshigram/%@ (com.noshigram.app; iOS)",version ? version : @"1.0"];
            NSMutableArray *headers = [NSMutableArray arrayWithObjects:agent,@"Accept: image/png",@"Accept-Encoding: identity",nil];
            NSString *etag = image ? NoshiTileValidator([cached objectForKey:@"etag"]) : nil;
            NSString *modified = image ? NoshiTileValidator([cached objectForKey:@"modified"]) : nil;
            if (etag.length) [headers addObject:[@"If-None-Match: " stringByAppendingString:etag]];
            if (modified.length) [headers addObject:[@"If-Modified-Since: " stringByAppendingString:modified]];
            const char *lines[7] = {0};
            for (NSUInteger i=0;i<headers.count;++i) lines[i] = [[headers objectAtIndex:i] UTF8String];
            noshi_https_request request;
            noshi_https_response response;
            memset(&request,0,sizeof(request));
            request.host = host.UTF8String; request.path = urlPath.UTF8String; request.port = 443;
            request.headers = lines; request.roots_pem = _roots.bytes; request.roots_len = _roots.length;
            request.timeout_ms = 12000; request.is_cancelled = NoshiMapCancelled; request.cancel_ctx = work;
            request.connect_socket = NoshiShiroNetworkConnectSocket;
            memset(&response,0,sizeof(response));
            noshi_status status = [[_cooldowns objectForKey:source] timeIntervalSinceNow]>0 ? NOSHI_E_TIMEOUT : noshi_https_get(&request,&response);
            if (status == NOSHI_OK) {
                NSDictionary *reply = NoshiTileHeaders(response.headers);
                if (response.status==429 || response.status==503) {
                    NSTimeInterval seconds=MAX(60,MIN(3600,[[reply objectForKey:@"retry-after"] doubleValue]));
                    [_cooldowns setObject:[NSDate dateWithTimeIntervalSinceNow:seconds] forKey:source];
                }
                BOOL store = YES;
                expires = NoshiTileExpiry(reply,&store);
                if (response.status == 200 && [[[reply objectForKey:@"content-type"] lowercaseString] hasPrefix:@"image/png"]) {
                    data = [NSData dataWithBytes:response.body length:response.body_len];
                    image = NoshiTileImage(data);
                } else if (response.status != 304 || !image) image = nil;
                if (!image) failure = [NSString stringWithFormat:@"tile HTTP %d or invalid PNG",response.status];
                if (image && store && !work.cancelled) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:data,@"data",expires,@"expires",nil];
                    NSString *newTag = NoshiTileValidator([reply objectForKey:@"etag"]);
                    NSString *newModified = NoshiTileValidator([reply objectForKey:@"last-modified"]);
                    if (newTag ? newTag.length : etag.length) [entry setObject:newTag ? newTag : etag forKey:@"etag"];
                    if (newModified ? newModified.length : modified.length) [entry setObject:newModified ? newModified : modified forKey:@"modified"];
                    @synchronized(self) {
                        NSError *error = nil;
                        if (![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:&error] ||
                            ![entry writeToFile:path atomically:YES]) NSLog(@"noshigram: map cache write failed: %@",error);
                        [self trimDisk];
                    }
                }
                if (!store) {
                    cacheable = NO; [_memory removeObjectForKey:key];
                    @synchronized(self) { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; }
                }
            } else { image = nil; failure = [NSString stringWithUTF8String:noshi_status_name(status)]; }
            noshi_https_response_free(&response);
        }
        if (image && cacheable && !work.cancelled) [_memory setObject:[NSDictionary dictionaryWithObjectsAndKeys:image,@"image",expires,@"expires",nil] forKey:key cost:256*256*4];
        if (failure && !work.cancelled) NSLog(@"noshigram: map tile %@ failed: %@",key,failure);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_jobs objectForKey:key] == work) {
                [_jobs removeObjectForKey:key];
                NSArray *waiting = [[work.tickets copy] autorelease];
                [work.tickets removeAllObjects];
                for (NoshiMapTileTicket *each in waiting) {
                    each->owner = nil;
                    [each->job release]; each->job = nil;
                    void (^done)(UIImage *,NSString *) = each->done;
                    each->done = nil;
                    if (done) { done(image,failure); [done release]; }
                }
            }
            work.operation = nil;
        });
        [pool drain];
    }];
    work.operation = operation;
    [_workers addOperation:operation];
    return ticket;
}
@end

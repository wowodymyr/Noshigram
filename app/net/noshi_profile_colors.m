#import "noshi_profile_colors.h"

#import "noshi_session_internal.h"

#include "noshi_people.h"

#import "noshi_rpc.h"

static NSMutableDictionary *NoshiProfileColorTable;
static BOOL NoshiProfileColorsAsking;

@implementation NoshiProfileColors

+ (void)loadWithSession:(NoshiSession *)session completion:(void (^)(void))done {
    if (NoshiProfileColorTable || !session) {
        if (done) done();
        return;
    }
    void (^finished)(void) = [done copy];
    /* a second screen that asks while the first one waits is not given a second request: it is told when the list is there, by the same answer */
    static NSMutableArray *waiting;
    if (!waiting) waiting = [[NSMutableArray alloc] init];
    if (finished) [waiting addObject:[[finished copy] autorelease]];
    [finished release];
    if (NoshiProfileColorsAsking) return;
    NoshiProfileColorsAsking = YES;
    [session invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_profile_colors_request(arena, 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableDictionary *table = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_profile_color *rows = calloc(NOSHI_PROFILE_COLORS_MAX, sizeof(*rows));
            size_t count = 0;
            if (rows && noshi_profile_colors_parse(result->value, rows, NOSHI_PROFILE_COLORS_MAX, &count, NULL) == NOSHI_OK) {
                table = [NSMutableDictionary dictionary];
                for (size_t i = 0; i < count; ++i) {
                    [table setObject:[NSData dataWithBytes:&rows[i] length:sizeof(rows[i])] forKey:[NSNumber numberWithInt:rows[i].id]];
                }
            } else {
                error = @"MALFORMED";
            }
            free(rows);
        }
        if (error) NSLog(@"noshigram: the profile colors were not loaded: %@", error);
        [session deliverMain:^{
            NoshiProfileColorsAsking = NO;
            if (table) NoshiProfileColorTable = [table retain];
            NSArray *callbacks = [[waiting copy] autorelease];
            [waiting removeAllObjects];
            for (void (^callback)(void) in callbacks) callback();
        }];
    }];
}

+ (BOOL)blendForColorId:(int32_t)colorId dark:(BOOL)dark center:(uint32_t *)center edge:(uint32_t *)edge {
    NSData *packed = [NoshiProfileColorTable objectForKey:[NSNumber numberWithInt:colorId]];
    if (packed.length != sizeof(noshi_profile_color)) return NO;
    noshi_profile_color row;
    memcpy(&row, packed.bytes, sizeof(row));
    const uint32_t *bg = dark && row.has_dark ? row.dark_bg : row.bg;
    if (center) *center = bg[0];
    if (edge) *edge = bg[1];
    return YES;
}

@end

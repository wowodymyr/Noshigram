#import "noshi_session_logins.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_logins.h"

@implementation NoshiUnconfirmedLogin

@synthesize sessionHash = _hash;
@synthesize date = _date;
@synthesize device = _device;
@synthesize place = _place;

- (id)initWithRow:(const noshi_unconfirmed_login *)row {
    self = [super init];
    if (!self) return nil;
    _hash = row->hash;
    _date = row->date;
    _device = [[NSString stringWithUTF8String:row->device] copy];
    _place = [[NSString stringWithUTF8String:row->place] copy];
    if (!_device) _device = [@"" copy];
    if (!_place) _place = [@"" copy];
    return self;
}

- (void)dealloc {
    [_device release];
    [_place release];
    [super dealloc];
}

@end

@implementation NoshiSession (Logins)

- (void)loadUnconfirmedLogins:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_logins_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *logins = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_unconfirmed_login *rows = calloc(NOSHI_LOGINS_MAX, sizeof(*rows));
            size_t count = 0;
            noshi_status status = rows ? noshi_logins_parse(result->value, rows, NOSHI_LOGINS_MAX, &count) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                logins = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [logins addObject:[[[NoshiUnconfirmedLogin alloc] initWithRow:&rows[i]] autorelease]];
            } else {
                NSLog(@"noshigram: account.getAuthorizations answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:logins error:error completion:done];
        [done release];
    }];
}

- (void)answerLogin:(NoshiUnconfirmedLogin *)login confirm:(BOOL)confirm completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    long long hash = login.sessionHash;
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return confirm ? noshi_login_confirm_request(arena, hash, request) : noshi_login_reset_request(arena, hash, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(delivered); [done release]; }];
    }];
}

- (void)confirmLogin:(NoshiUnconfirmedLogin *)login completion:(void (^)(NSString *))completion {
    [self answerLogin:login confirm:YES completion:completion];
}

- (void)terminateLogin:(NoshiUnconfirmedLogin *)login completion:(void (^)(NSString *))completion {
    [self answerLogin:login confirm:NO completion:completion];
}

@end

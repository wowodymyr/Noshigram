#import "noshi_session_theme.h"

#import "noshi_rpc.h"
#import "noshi_session_internal.h"

#include "noshi_theme_link.h"

@implementation NoshiThemeLink
@synthesize title = _title, file = _file, hasColors = _hasColors, dark = _dark, accent = _accent;

- (id)initWithInfo:(const noshi_theme_link_info *)info {
    self = [super init];
    if (!self) return nil;
    _title = [[NSString stringWithUTF8String:info->title] copy];
    if (info->has_file) _file = [[NoshiMedia mediaWithInfo:&info->file] retain];
    _hasColors = info->has_colors != 0;
    _dark = info->dark != 0;
    _accent = info->accent;
    /* a title that was not valid utf-8 comes back as nil, and the theme cannot be shown without one */
    if (!_title.length || (info->has_file && !_file)) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_file release];
    [super dealloc];
}
@end

@implementation NoshiSession (Theme)

- (void)loadThemeOfSlug:(NSString *)slug completion:(void (^)(NoshiThemeLink *, NSString *))completion {
    void (^done)(NoshiThemeLink *, NSString *) = [completion copy];
    NSString *wanted = [[slug copy] autorelease];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_theme_link_request(arena, wanted.UTF8String, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NoshiThemeLink *theme = nil;
        NSString *error = nil;
        if (result->status == NOSHI_E_ARG) {
            error = @"ARG";
        } else if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_theme_link_info info;
            if (noshi_theme_link_parse(result->value, &info) == NOSHI_OK) theme = [[[NoshiThemeLink alloc] initWithInfo:&info] autorelease];
            if (!theme) error = @"MALFORMED";
        }
        [self noteRpcError:error];
        NSString *failure = [[error copy] autorelease];
        [self deliverMain:^{ done(theme, failure); [done release]; }];
    }];
}

@end

#import "noshi_bot.h"

static NSString *NoshiUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiBotCommand
@synthesize name = _name;
@synthesize text = _text;
- (id)initWithRow:(const noshi_bot_command *)row {
    self = [super init];
    if (!self) return nil;
    _name = [NoshiUtf8(row->name) copy];
    _text = [NoshiUtf8(row->text) copy];
    return self;
}
- (void)dealloc {
    [_name release];
    [_text release];
    [super dealloc];
}
@end

@implementation NoshiBotInfo
@synthesize botDescription = _botDescription;
@synthesize picture = _picture;
@synthesize commands = _commands;
@synthesize menuKind = _menuKind;
@synthesize privacyUrl = _privacyUrl;

+ (NoshiBotInfo *)infoWithRow:(const noshi_bot_info *)row {
    NoshiBotInfo *info = [[[NoshiBotInfo alloc] init] autorelease];
    info->_botDescription = [NoshiUtf8(row->description) copy];
    if (row->has_picture) info->_picture = [[NoshiMedia mediaWithInfo:&row->picture] retain];
    NSMutableArray *commands = [NSMutableArray arrayWithCapacity:row->command_count];
    for (uint16_t i = 0; i < row->command_count; ++i) {
        NoshiBotCommand *command = [[NoshiBotCommand alloc] initWithRow:&row->commands[i]];
        [commands addObject:command];
        [command release];
    }
    info->_commands = [commands copy];
    info->_menuKind = (noshi_bot_menu_kind)row->menu_kind;
    info->_privacyUrl = [NoshiUtf8(row->privacy_url) copy];
    return info;
}

- (void)dealloc {
    [_botDescription release];
    [_picture release];
    [_commands release];
    [_privacyUrl release];
    [super dealloc];
}
@end

@implementation NoshiCallbackAnswer
@synthesize alert = _alert;
@synthesize message = _message;
@synthesize url = _url;

+ (NoshiCallbackAnswer *)answerWithRow:(const noshi_callback_answer *)row {
    NoshiCallbackAnswer *answer = [[[NoshiCallbackAnswer alloc] init] autorelease];
    answer->_alert = row->alert;
    answer->_message = [NoshiUtf8(row->message) copy];
    if (row->has_url) answer->_url = [NoshiUtf8(row->url) copy];
    return answer;
}

- (void)dealloc {
    [_message release];
    [_url release];
    [super dealloc];
}
@end

@implementation NoshiWebFile
@synthesize url = _url;
@synthesize proxied = _proxied;
@synthesize accessHash = _accessHash;

+ (NoshiWebFile *)fileWithRef:(const noshi_web_ref *)ref {
    if (!ref->present) return nil;
    NoshiWebFile *file = [[[NoshiWebFile alloc] init] autorelease];
    file->_url = [NoshiUtf8(ref->url) copy];
    file->_proxied = ref->proxied;
    file->_accessHash = ref->access_hash;
    return file;
}

- (void)dealloc {
    [_url release];
    [super dealloc];
}
@end

@implementation NoshiInlineResult
@synthesize kind = _kind;
@synthesize queryId = _queryId;
@synthesize resultId = _resultId;
@synthesize title = _title;
@synthesize subtitle = _subtitle;
@synthesize media = _media;
@synthesize thumb = _thumb;
@synthesize width = _width;
@synthesize height = _height;
@synthesize duration = _duration;

+ (NoshiInlineResult *)resultWithRow:(const noshi_inline_result *)row {
    NoshiInlineResult *result = [[[NoshiInlineResult alloc] init] autorelease];
    result->_kind = (noshi_inline_kind)row->kind;
    result->_queryId = row->query_id;
    result->_resultId = [NoshiUtf8(row->id) copy];
    result->_title = [NoshiUtf8(row->title) copy];
    result->_subtitle = [NoshiUtf8(row->description) copy];
    if (row->media.kind != NOSHI_PREVIEW_NONE) result->_media = [[NoshiMedia mediaWithInfo:&row->media] retain];
    result->_thumb = [[NoshiWebFile fileWithRef:&row->thumb] retain];
    result->_width = row->width;
    result->_height = row->height;
    result->_duration = row->duration;
    return result;
}

- (void)dealloc {
    [_resultId release];
    [_title release];
    [_subtitle release];
    [_media release];
    [_thumb release];
    [super dealloc];
}
@end

@implementation NoshiInlinePage
@synthesize queryId = _queryId;
@synthesize gallery = _gallery;
@synthesize nextOffset = _nextOffset;
@synthesize switchText = _switchText;
@synthesize switchParam = _switchParam;
@synthesize webText = _webText;
@synthesize results = _results;

+ (NoshiInlinePage *)pageWithRow:(const noshi_inline_page *)row results:(NSArray *)results {
    NoshiInlinePage *page = [[[NoshiInlinePage alloc] init] autorelease];
    page->_queryId = row->query_id;
    page->_gallery = row->gallery;
    page->_nextOffset = [NoshiUtf8(row->next_offset) copy];
    page->_switchText = [NoshiUtf8(row->switch_text) copy];
    page->_switchParam = [NoshiUtf8(row->switch_param) copy];
    page->_webText = [NoshiUtf8(row->web_text) copy];
    page->_results = [results copy];
    return page;
}

- (void)dealloc {
    [_nextOffset release];
    [_switchText release];
    [_switchParam release];
    [_webText release];
    [_results release];
    [super dealloc];
}
@end

@implementation NoshiUrlAuth
@synthesize kind = _kind;
@synthesize requestWrite = _requestWrite;
@synthesize requestPhone = _requestPhone;
@synthesize botName = _botName;
@synthesize domain = _domain;
@synthesize url = _url;
@synthesize codes = _codes;

+ (NoshiUrlAuth *)authWithRow:(const noshi_url_auth *)row {
    NoshiUrlAuth *auth = [[[NoshiUrlAuth alloc] init] autorelease];
    auth->_kind = (noshi_url_auth_kind)row->kind;
    auth->_requestWrite = row->request_write;
    auth->_requestPhone = row->request_phone;
    auth->_botName = [NoshiUtf8(row->bot) copy];
    auth->_domain = [NoshiUtf8(row->domain) copy];
    auth->_url = [NoshiUtf8(row->url) copy];
    NSMutableArray *codes = [NSMutableArray arrayWithCapacity:row->code_count];
    for (uint8_t i = 0; i < row->code_count; ++i) [codes addObject:NoshiUtf8(row->codes[i])];
    auth->_codes = [codes copy];
    return auth;
}

- (void)dealloc {
    [_botName release];
    [_domain release];
    [_url release];
    [_codes release];
    [super dealloc];
}
@end

@implementation NoshiStarsInvoice
- (void)dealloc {
    [slug release];
    [title release];
    [invoiceDescription release];
    [super dealloc];
}
@end

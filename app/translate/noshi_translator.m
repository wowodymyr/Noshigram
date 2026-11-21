#import "noshi_translator.h"

#import "noshi_http_call.h"
#import "noshi_language.h"
#import "noshi_message.h"
#import "noshi_session_translate.h"
#import "noshi_translate_config.h"

#include "noshi_translate_html.h"
#include "noshi_translate_lang.h"
#include "noshi_translate_llm.h"
#include "noshi_translate_text.h"

#define ANSWER_LIMIT (1024u * 1024u)
#define CALL_TIMEOUT 30.0
#define LLM_ATTEMPTS 3
/* the key that the web client of Google carries; it is public in the page and alike */
static NSString *const NoshiGoogleWebKey = @"AIzaSyDLEeFI5OtFBwYBIoK_jj5m32rZK5CkCXA";
static NSString *const NoshiLingoToken = @"token 9sdftiq37bnv410eon2l";
static NSString *const NoshiPhoneUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 10_0 like Mac OS X) AppleWebKit/602.1.38 (KHTML, like Gecko) Version/10.0 Mobile/14A5297c Safari/602.1";

@implementation NoshiTranslation

@synthesize text = _text;
@synthesize entities = _entities;

- (id)initWithText:(NSString *)text entities:(NSArray *)entities {
    self = [super init];
    if (!self) return nil;
    _text = [text copy];
    _entities = [entities copy];
    return self;
}

- (void)dealloc {
    [_text release];
    [_entities release];
    [super dealloc];
}

@end

@interface NoshiTranslateJob () {
    NSString *_text;
    NSArray *_entities;
    NSString *_language;
    NSString *_context;
    NoshiSession *_session;
    void (^_completion)(NoshiTranslation *, NSString *);
    NoshiHttpCall *_call;
    NSMutableArray *_links;
    BOOL _markup;
    BOOL _cancelled;
    BOOL _finished;
    NSUInteger _attempt;
}
@end

@implementation NoshiTranslateJob

+ (NoshiTranslateJob *)translateText:(NSString *)text entities:(NSArray *)entities to:(NSString *)language context:(NSString *)context
                               session:(NoshiSession *)session completion:(void (^)(NoshiTranslation *, NSString *))completion {
    NoshiTranslateJob *job = [[NoshiTranslateJob alloc] init];
    job->_text = [text copy];
    job->_entities = [entities copy];
    job->_language = [language copy];
    job->_context = [context copy];
    job->_session = [session retain];
    job->_completion = [completion copy];
    /* the job keeps itself alive until it has answered or been cancelled, so a caller may drop it at once */
    [job performSelector:@selector(begin) withObject:nil afterDelay:0];
    return [job autorelease];
}

- (void)dealloc {
    [_text release];
    [_entities release];
    [_language release];
    [_context release];
    [_session release];
    [_completion release];
    [_call release];
    [_links release];
    [super dealloc];
}

- (void)cancel {
    if (_cancelled || _finished) return;
    _cancelled = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_call cancel];
    [_call release];
    _call = nil;
    [_completion release];
    _completion = nil;
}

#pragma mark answers

- (void)fail:(NSString *)message {
    if (_cancelled || _finished) return;
    _finished = YES;
    void (^done)(NoshiTranslation *, NSString *) = _completion;
    _completion = nil;
    if (done) {
        done(nil, message);
        [done release];
    }
}

- (void)deliver:(NoshiTranslation *)translation {
    if (_cancelled || _finished) return;
    _finished = YES;
    void (^done)(NoshiTranslation *, NSString *) = _completion;
    _completion = nil;
    if (done) {
        done(translation, nil);
        [done release];
    }
}

static NSString *NoshiServerMessage(NSData *body) {
    if (!body.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    id error = [json objectForKey:@"error"];
    id message = [error isKindOfClass:[NSDictionary class]] ? [error objectForKey:@"message"] : ([error isKindOfClass:[NSString class]] ? error : [json objectForKey:@"message"]);
    if (![message isKindOfClass:[NSString class]] || ![message length]) return nil;
    return [message length] > 200 ? [[message substringToIndex:200] stringByAppendingString:@"…"] : message;
}

/* the sentence for a call that did not give an answer to read */
- (NSString *)failureOfStatus:(NSInteger)status failure:(NSString *)failure body:(NSData *)body {
    if (!status) {
        NSLog(@"noshigram: a translation call failed: %@", failure);
        return NSLocalizedString(@"tr.error.network", nil);
    }
    NSString *line = [NSString stringWithFormat:NSLocalizedString(@"tr.error.http", nil), [NSString stringWithFormat:@"%ld", (long)status]];
    NSString *detail = NoshiServerMessage(body);
    return detail ? [NSString stringWithFormat:@"%@ %@", line, detail] : line;
}

- (NSString *)parseFailure {
    return NSLocalizedString(@"tr.error.parse", nil);
}

/* the answer is plain text when the question was; with markup it goes through the reader of tags and the runs are given their addresses back */
- (void)finishWithText:(NSString *)raw {
    if (_cancelled || _finished) return;
    if (!raw.length) {
        [self fail:[self parseFailure]];
        return;
    }
    if (!_markup) {
        [self deliver:[[[NoshiTranslation alloc] initWithText:raw entities:nil] autorelease]];
        return;
    }
    NSUInteger length = raw.length;
    if (length > NOSHI_TH_TEXT_MAX * 2u) {
        [self fail:[self parseFailure]];
        return;
    }
    uint16_t *in = malloc(length * sizeof(uint16_t)), *out = malloc(NOSHI_TH_TEXT_MAX * 2u * sizeof(uint16_t));
    noshi_th_span *spans = malloc(NOSHI_TH_SPAN_MAX * sizeof(*spans));
    size_t outLength = 0, spanCount = 0;
    NoshiTranslation *result = nil;
    if (in && out && spans) {
        [raw getCharacters:in range:NSMakeRange(0, length)];
        if (noshi_th_decode(in, length, out, NOSHI_TH_TEXT_MAX * 2u, &outLength, spans, NOSHI_TH_SPAN_MAX, &spanCount) == NOSHI_OK) {
            NSString *plain = [NSString stringWithCharacters:out length:outLength];
            NSMutableArray *entities = [NSMutableArray array];
            NSUInteger nextLink = 0;
            for (size_t i = 0; i < spanCount; ++i) {
                NSRange range = NSMakeRange(spans[i].offset, spans[i].length);
                NoshiTextStyle style;
                NSString *url = nil;
                switch (spans[i].kind) {
                case NOSHI_TH_BOLD: style = NoshiTextStyleBold; break;
                case NOSHI_TH_ITALIC: style = NoshiTextStyleItalic; break;
                case NOSHI_TH_UNDERLINE: style = NoshiTextStyleUnderline; break;
                case NOSHI_TH_STRIKE: style = NoshiTextStyleStrike; break;
                case NOSHI_TH_CODE: style = NoshiTextStyleCode; break;
                default: {
                    /* the n-th link of the answer is the n-th of the question, whatever it kind of address it was; one too many has nothing to point at */
                    if (nextLink >= _links.count) continue;
                    NoshiTextEntity *original = [_links objectAtIndex:nextLink++];
                    style = original.style;
                    url = original.url;
                    break;
                }
                }
                [entities addObject:[[[NoshiTextEntity alloc] initWithStyle:style range:range url:url] autorelease]];
            }
            result = [[[NoshiTranslation alloc] initWithText:plain entities:entities] autorelease];
        }
    }
    free(in);
    free(out);
    free(spans);
    if (result) [self deliver:result];
    else [self fail:[self parseFailure]];
}

#pragma mark start

/* the text as the services get it: with the styled runs as tags, or as it is when it has none that a translator can keep */
- (NSString *)questionText {
    NSMutableArray *links = [NSMutableArray array];
    noshi_th_span *spans = malloc(MAX(1u, _entities.count) * sizeof(*spans));
    size_t count = 0;
    NSUInteger length = _text.length;
    if (!spans || length > NOSHI_TH_TEXT_MAX || _entities.count > NOSHI_TH_SPAN_MAX) {
        free(spans);
        return _text;
    }
    for (NoshiTextEntity *entity in _entities) {
        int32_t kind = 0;
        switch (entity.style) {
        case NoshiTextStyleBold: kind = NOSHI_TH_BOLD; break;
        case NoshiTextStyleItalic: kind = NOSHI_TH_ITALIC; break;
        case NoshiTextStyleUnderline: kind = NOSHI_TH_UNDERLINE; break;
        case NoshiTextStyleStrike: kind = NOSHI_TH_STRIKE; break;
        case NoshiTextStyleCode: kind = NOSHI_TH_CODE; break;
        case NoshiTextStyleLink:
        case NoshiTextStyleMention:
        case NoshiTextStyleHashtag:
        case NoshiTextStyleBotCommand: kind = NOSHI_TH_LINK; break;
        default: break;
        }
        if (!kind || entity.range.length == 0 || NSMaxRange(entity.range) > length) continue;
        spans[count].kind = kind;
        spans[count].offset = (uint32_t)entity.range.location;
        spans[count].length = (uint32_t)entity.range.length;
        ++count;
        if (kind == NOSHI_TH_LINK) [links addObject:entity];
    }
    NSString *question = _text;
    if (count) {
        uint16_t *in = malloc((length ? length : 1) * sizeof(uint16_t)), *out = malloc(NOSHI_TH_TEXT_MAX * 2u * sizeof(uint16_t));
        size_t outLength = 0;
        if (in && out) {
            [_text getCharacters:in range:NSMakeRange(0, length)];
            if (noshi_th_encode(in, length, spans, count, out, NOSHI_TH_TEXT_MAX * 2u, &outLength) == NOSHI_OK) {
                question = [NSString stringWithCharacters:out length:outLength];
                _markup = YES;
                /* the links of the answer are matched with the ones of the question in the order of the text */
                [links sortUsingComparator:^NSComparisonResult(NoshiTextEntity *a, NoshiTextEntity *b) {
                    return a.range.location < b.range.location ? NSOrderedAscending : (a.range.location > b.range.location ? NSOrderedDescending : NSOrderedSame);
                }];
                _links = [links retain];
            }
        }
        free(in);
        free(out);
    }
    free(spans);
    return question;
}

- (void)begin {
    if (_cancelled) return;
    if (!_text.length || !_language.length) {
        [self fail:[self parseFailure]];
        return;
    }
    int provider = NoshiTranslateProviderChoice();
    NSString *question = [self questionText];
    switch (provider) {
    case NoshiTranslateProviderYandex: [self runYandex:question]; break;
    case NoshiTranslateProviderLingo: [self runLingo:question]; break;
    case NoshiTranslateProviderBing: [self runBing:question]; break;
    case NoshiTranslateProviderDeepL: [self runDeepL:question]; break;
    case NoshiTranslateProviderTelegram: [self runTelegram:question]; break;
    case NoshiTranslateProviderTranSmart: [self runTranSmart:question]; break;
    case NoshiTranslateProviderLLM: [self runLLM:question]; break;
    default: [self runGoogle:question]; break;
    }
}

/* the language code the service wants, or nil after the sentence for the person has been given */
- (NSString *)targetFor:(int)provider api:(int)api {
    char code[NOSHI_TR_LANG_MAX];
    noshi_status status = noshi_tr_target_for(provider, api, _language.UTF8String, code, sizeof(code));
    if (status == NOSHI_E_UNSUPPORTED) {
        [self fail:[NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"tr.unsupported", nil), _language]];
        return nil;
    }
    if (status != NOSHI_OK) {
        [self fail:[self parseFailure]];
        return nil;
    }
    return [NSString stringWithUTF8String:code];
}

- (NSMutableURLRequest *)requestFor:(NSString *)url method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:CALL_TIMEOUT];
    [request setHTTPMethod:method];
    [request setHTTPShouldHandleCookies:NO];
    return request;
}

- (NSMutableURLRequest *)formRequestFor:(NSString *)url fields:(NSArray *)pairs {
    NSMutableURLRequest *request = [self requestFor:url method:@"POST"];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < pairs.count; i += 2) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", NoshiURLEscape([pairs objectAtIndex:i]), NoshiURLEscape([pairs objectAtIndex:i + 1])]];
    }
    [request setHTTPBody:[[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    return request;
}

- (NSMutableURLRequest *)jsonRequestFor:(NSString *)url object:(id)object {
    NSMutableURLRequest *request = [self requestFor:url method:@"POST"];
    NSData *body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    [request setHTTPBody:body];
    [request setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    return request;
}

/* runs the request; the parser gets the JSON of a 2xx answer and returns the translated text, or nil for an answer it cannot read */
- (void)send:(NSURLRequest *)request parse:(NSString *(^)(id json))parse {
    NoshiTranslateJob *job = self;
    [_call release];
    _call = [[NoshiHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT completion:^(NSData *body, NSInteger status, NSString *failure) {
        if (job->_cancelled) return;
        if (!status || status < 200 || status > 299) {
            [job fail:[job failureOfStatus:status failure:failure body:body]];
            return;
        }
        id json = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
        NSString *translated = json ? parse(json) : nil;
        if (translated.length) [job finishWithText:translated];
        else [job fail:[job parseFailure]];
    }] retain];
}

/* the first item of a JSON array, nil for anything that is not a non-empty array */
static id NoshiFirst(id value) {
    return [value isKindOfClass:[NSArray class]] && [(NSArray *)value count] ? [(NSArray *)value objectAtIndex:0] : nil;
}

static NSString *NoshiString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static id NoshiKeyed(NSString *name, id object) {
    return [object isKindOfClass:[NSDictionary class]] ? [object objectForKey:name] : nil;
}

static NSString *NoshiKey(NSString *name, id object) {
    return [object isKindOfClass:[NSDictionary class]] ? NoshiString([object objectForKey:name]) : nil;
}

#pragma mark google

- (void)runGoogle:(NSString *)question {
    BOOL fresh = NoshiTranslateGoogleNew();
    NSString *key = NoshiTranslateGoogleKey();
    int api = fresh ? NOSHI_TR_GOOGLE_NEW : (key.length ? NOSHI_TR_GOOGLE_CLOUD : NOSHI_TR_GOOGLE_APP);
    NSString *target = [self targetFor:NOSHI_TR_GOOGLE api:api];
    if (!target) return;
    if (api == NOSHI_TR_GOOGLE_CLOUD) {
        NSMutableURLRequest *request = [self formRequestFor:@"https://translation.googleapis.com/language/translate/v2"
                                                     fields:[NSArray arrayWithObjects:@"q", question, @"target", target, @"format", @"text", @"key", key, nil]];
        [self send:request parse:^NSString *(id json) {
            id data = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"data"] : nil;
            id list = [data isKindOfClass:[NSDictionary class]] ? [data objectForKey:@"translations"] : nil;
            id first = NoshiFirst(list);
            return NoshiKey(@"translatedText", first);
        }];
        return;
    }
    NSString *query = NoshiURLEscape(question);
    NSString *url;
    NSMutableURLRequest *request;
    if (api == NOSHI_TR_GOOGLE_NEW) {
        url = [NSString stringWithFormat:@"https://translate-pa.googleapis.com/v1/translate?params.client=gtx&query.source_language=auto&query.target_language=%@"
                                         @"&query.display_language=en-US&data_types=TRANSLATION&key=%@&query.text=%@", NoshiURLEscape(target), NoshiGoogleWebKey, query];
    } else {
        url = [NSString stringWithFormat:@"https://translate.google.com/translate_a/single?dj=1&q=%@&sl=auto&tl=%@&ie=UTF-8&oe=UTF-8&client=at&dt=t&otf=2", query,
                                         NoshiURLEscape(target)];
    }
    /* the whole text rides in the address, and servers refuse addresses much longer than this */
    if (url.length > 15000) {
        [self fail:NSLocalizedString(@"tr.error.long", nil)];
        return;
    }
    request = [self requestFor:url method:@"GET"];
    if (api == NOSHI_TR_GOOGLE_NEW) {
        [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
        [request setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];
        [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
        BOOL chinese = [target hasPrefix:@"zh"];
        NSString *original = question;
        [self send:request parse:^NSString *(id json) {
            NSString *translated = NoshiKey(@"translation", json);
            if (!translated || !chinese) return translated;
            /* the answer for Chinese doubles every line break */
            char *buffer = malloc(translated.length * 3 + original.length + 8);
            NSString *fixed = translated;
            if (buffer && noshi_tr_restore_newlines(original.UTF8String, translated.UTF8String, buffer, translated.length * 3 + original.length + 8) == NOSHI_OK) {
                fixed = [NSString stringWithUTF8String:buffer];
            }
            free(buffer);
            return fixed;
        }];
    } else {
        [request setValue:@"GoogleTranslate/6.14.0.04.343003216 (Linux; U; Android 10; Redmi K20 Pro)" forHTTPHeaderField:@"User-Agent"];
        [self send:request parse:^NSString *(id json) {
            id sentences = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"sentences"] : nil;
            if (![sentences isKindOfClass:[NSArray class]]) return nil;
            NSMutableString *joined = [NSMutableString string];
            for (id sentence in sentences) {
                NSString *part = NoshiKey(@"trans", sentence);
                if (part) [joined appendString:part];
            }
            return joined;
        }];
    }
}

#pragma mark yandex, lingo, transmart

/* NSUUID came with ios 6 */
static NSString *NoshiUUIDString(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *text = (NSString *)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return [text autorelease];
}

static NSString *NoshiRandomHex(void) {
    return [[[NSString stringWithFormat:@"%08x%08x%08x%08x", arc4random(), arc4random(), arc4random(), arc4random()] copy] autorelease];
}

- (void)runYandex:(NSString *)question {
    NSString *target = [self targetFor:NOSHI_TR_YANDEX api:0];
    if (!target) return;
    static NSString *uuid;
    if (!uuid) uuid = [NoshiRandomHex() retain];
    NSString *url = [NSString stringWithFormat:@"https://translate.yandex.net/api/v1/tr.json/translate?srv=android&uuid=%@&id=%@-9-0", uuid, NoshiRandomHex()];
    NSMutableURLRequest *request = [self formRequestFor:url fields:[NSArray arrayWithObjects:@"text", question, @"lang", target, nil]];
    [request setValue:NoshiPhoneUserAgent forHTTPHeaderField:@"User-Agent"];
    [self send:request parse:^NSString *(id json) {
        if (![json isKindOfClass:[NSDictionary class]] || [[json objectForKey:@"code"] intValue] != 200) return nil;
        id list = [json objectForKey:@"text"];
        return NoshiString(NoshiFirst(list));
    }];
}

static NSString *NoshiJoinedLines(id list) {
    if (![list isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (id line in list) {
        if (![line isKindOfClass:[NSString class]]) return nil;
        /* the service answers a lone high surrogate for a line it could not read; it is no text */
        [lines addObject:[line length] == 1 && [line characterAtIndex:0] == 0xD835 ? @"" : line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)runLingo:(NSString *)question {
    NSString *target = [self targetFor:NOSHI_TR_LINGO api:0];
    if (!target) return;
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:[question componentsSeparatedByString:@"\n"], @"source",
                          [NSString stringWithFormat:@"auto2%@", target], @"trans_type",
                          [NSString stringWithFormat:@"%llu", (unsigned long long)([[NSDate date] timeIntervalSince1970] * 1000)], @"request_id",
                          [NSNumber numberWithBool:YES], @"detect", nil];
    NSMutableURLRequest *request = [self jsonRequestFor:@"https://api.interpreter.caiyunai.com/v1/translator" object:body];
    [request setValue:NoshiLingoToken forHTTPHeaderField:@"X-Authorization"];
    [request setValue:NoshiPhoneUserAgent forHTTPHeaderField:@"User-Agent"];
    [self send:request parse:^NSString *(id json) {
        return [json isKindOfClass:[NSDictionary class]] ? NoshiJoinedLines([json objectForKey:@"target"]) : nil;
    }];
}

- (void)runTranSmart:(NSString *)question {
    NSString *target = [self targetFor:NOSHI_TR_TRANSMART api:0];
    if (!target) return;
    NSString *browser = [NSString stringWithFormat:@"%u.%u.%u", 100 + arc4random() % 17, arc4random() % 20, arc4random() % 20];
    NSString *client = [NSString stringWithFormat:@"browser-chrome-%@-%@-%@-%llu", browser, arc4random() % 2 ? @"Mac OS" : @"Windows",
                        NoshiUUIDString(), (unsigned long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:client, @"client_key", @"auto_translation", @"fn", @"", @"session", @"", @"user", nil], @"header",
        [NSDictionary dictionaryWithObjectsAndKeys:@"en", @"lang", [question componentsSeparatedByString:@"\n"], @"text_list", nil], @"source",
        [NSDictionary dictionaryWithObject:target forKey:@"lang"], @"target",
        @"normal", @"model_category", @"", @"text_domain", @"plain", @"type", nil];
    NSMutableURLRequest *request = [self jsonRequestFor:@"https://transmart.qq.com/api/imt" object:body];
    [request setValue:NoshiPhoneUserAgent forHTTPHeaderField:@"User-Agent"];
    [self send:request parse:^NSString *(id json) {
        return [json isKindOfClass:[NSDictionary class]] ? NoshiJoinedLines([json objectForKey:@"auto_translation"]) : nil;
    }];
}

#pragma mark bing

/* the page of the translator holds the numbers its own script sends along with a text (IG, IID and a token with a
   lifetime), and the translation is a form post to the same host */
static NSString *const NoshiBingAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/151.0.4129.59";
static NSDictionary *NoshiBingConfig;
static NSUInteger NoshiBingCounter;

static NSString *NoshiFirstMatch(NSString *text, NSString *pattern) {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSTextCheckingResult *match = [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match && match.numberOfRanges > 1 ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
}

static NSString *NoshiHeaderValue(NSDictionary *headers, NSString *name) {
    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] && [[key lowercaseString] isEqualToString:name]) {
            id value = [headers objectForKey:key];
            return [value isKindOfClass:[NSString class]] ? value : nil;
        }
    }
    return nil;
}

static BOOL NoshiBingConfigIsFresh(void) {
    if (!NoshiBingConfig) return NO;
    double now = [[NSDate date] timeIntervalSince1970] * 1000;
    return now - [[NoshiBingConfig objectForKey:@"ts"] doubleValue] <= [[NoshiBingConfig objectForKey:@"interval"] doubleValue];
}

- (void)runBing:(NSString *)question {
    NSString *target = [self targetFor:NOSHI_TR_BING api:0];
    if (!target) return;
    if (question.length > 3000) {
        [self fail:NSLocalizedString(@"tr.error.long", nil)];
        return;
    }
    if (NoshiBingConfigIsFresh()) [self bingTranslate:question to:target refreshed:NO];
    else [self bingFetchThen:question to:target];
}

- (void)bingFetchThen:(NSString *)question to:(NSString *)target {
    NSString *host = [NoshiBingConfig objectForKey:@"host"];
    NSMutableURLRequest *request = [self requestFor:[NSString stringWithFormat:@"https://%@/translator", host.length ? host : @"www.bing.com"] method:@"GET"];
    [request setValue:NoshiBingAgent forHTTPHeaderField:@"User-Agent"];
    NoshiTranslateJob *job = self;
    [_call release];
    _call = [[NoshiHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT sameSite:YES completion:^(NSData *body, NSInteger status, NSString *failure) {
        if (job->_cancelled) return;
        if (status < 200 || status > 299) {
            [job fail:[job failureOfStatus:status failure:failure body:nil]];
            return;
        }
        NSString *page = body.length ? [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] autorelease] : nil;
        if (!page) {
            [job fail:[job parseFailure]];
            return;
        }
        NSString *ig = NoshiFirstMatch(page, @"IG:\\s*\"([^\"]+)\""), *iid = NoshiFirstMatch(page, @"data-iid=\"([^\"]+)\"");
        NSString *params = NoshiFirstMatch(page, @"params_AbusePreventionHelper\\s*=\\s*(\\[[^\\]]+\\])");
        id values = params ? [NSJSONSerialization JSONObjectWithData:[params dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        NSString *final = job->_call.responseURL.host;
        if (!ig || !iid || ![values isKindOfClass:[NSArray class]] || [(NSArray *)values count] < 3 || !final.length) {
            [job fail:[job parseFailure]];
            return;
        }
        NSString *key = [NSString stringWithFormat:@"%@", [values objectAtIndex:0]], *token = NoshiString([values objectAtIndex:1]);
        if (!token || ![key longLongValue]) {
            [job fail:[job parseFailure]];
            return;
        }
        [NoshiBingConfig release];
        NoshiBingConfig = [[NSDictionary alloc] initWithObjectsAndKeys:final, @"host", ig, @"ig", iid, @"iid", key, @"key", token, @"token",
                             [NSNumber numberWithLongLong:[key longLongValue]], @"ts", [NSNumber numberWithLongLong:[[values objectAtIndex:2] longLongValue]], @"interval", nil];
        NoshiBingCounter = 0;
        [job bingTranslate:question to:target refreshed:YES];
    }] retain];
}

- (void)bingTranslate:(NSString *)question to:(NSString *)target refreshed:(BOOL)refreshed {
    NSDictionary *config = NoshiBingConfig;
    NSString *host = [config objectForKey:@"host"];
    NSString *url = [NSString stringWithFormat:@"https://%@/ttranslatev3?isVertical=1&IG=%@&IID=%@&SFX=%lu&ref=TThis&edgepdftranslator=1", host,
                     NoshiURLEscape([config objectForKey:@"ig"]), NoshiURLEscape([config objectForKey:@"iid"]), (unsigned long)++NoshiBingCounter];
    NSMutableArray *fields = [NSMutableArray arrayWithObjects:@"fromLang", @"auto-detect", @"to", target, @"text", question, @"token", [config objectForKey:@"token"],
                              @"key", [config objectForKey:@"key"], @"tryFetchingGenderDebiasedTranslations", @"true", nil];
    NSMutableURLRequest *request = [self formRequestFor:url fields:fields];
    [request setValue:NoshiBingAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"https://%@/translator", host] forHTTPHeaderField:@"Referer"];
    NoshiTranslateJob *job = self;
    [_call release];
    _call = [[NoshiHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT completion:^(NSData *body, NSInteger status, NSString *failure) {
        if (job->_cancelled) return;
        NSString *type = NoshiHeaderValue(job->_call.responseHeaders, @"content-type");
        BOOL json = [[type lowercaseString] hasPrefix:@"application/json"];
        NSString *translated = nil;
        if (status >= 200 && status <= 299 && json && body.length) {
            id list = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
            id first = NoshiFirst(list);
            id items = [first isKindOfClass:[NSDictionary class]] ? [first objectForKey:@"translations"] : nil;
            translated = NoshiKey(@"text", NoshiFirst(items));
        } else if (status >= 200 && status <= 299 && NoshiHeaderValue(job->_call.responseHeaders, @"isgenderdebiasedtranslation")) {
            [job bingDebiased:question to:target];
            return;
        }
        if (translated.length) {
            [job finishWithText:translated];
        } else if (!refreshed) {
            /* the kept numbers may have gone stale before their time; one fresh set is tried before giving up */
            [NoshiBingConfig release];
            NoshiBingConfig = nil;
            [job bingFetchThen:question to:target];
        } else if (status < 200 || status > 299) {
            [job fail:[job failureOfStatus:status failure:failure body:nil]];
        } else {
            [job fail:[job parseFailure]];
        }
    }] retain];
}

/* some texts get a second form of the translation; the masculine one is taken it */
- (void)bingDebiased:(NSString *)question to:(NSString *)target {
    NSDictionary *config = NoshiBingConfig;
    NSString *host = [config objectForKey:@"host"];
    NSString *url = [NSString stringWithFormat:@"https://%@/ttranslatev3?isVertical=1&IG=%@&IID=%@&SFX=%lu&ref=TThis&edgepdftranslator=1", host,
                     NoshiURLEscape([config objectForKey:@"ig"]), NoshiURLEscape([config objectForKey:@"iid"]), (unsigned long)++NoshiBingCounter];
    NSMutableURLRequest *request = [self formRequestFor:url fields:[NSArray arrayWithObjects:@"fromLang", @"auto-detect", @"to", target, @"text", question,
                                                                     @"token", [config objectForKey:@"token"], @"key", [config objectForKey:@"key"],
                                                                     @"tryFetchingGenderDebiasedTranslations", @"true", @"isGenderDebiasViewPresent", @"true", nil]];
    [request setValue:NoshiBingAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"https://%@/translator", host] forHTTPHeaderField:@"Referer"];
    [self send:request parse:^NSString *(id json) {
        return NoshiKey(@"masculineTranslation", json);
    }];
}

#pragma mark deepl

- (void)runDeepL:(NSString *)question {
    NSString *key = NoshiTranslateDeepLKey();
    if (!key.length) {
        [self fail:NSLocalizedString(@"tr.keynotset", nil)];
        return;
    }
    NSString *mapped = [self targetFor:NOSHI_TR_DEEPL api:0];
    if (!mapped) return;
    char code[NOSHI_TR_LANG_MAX];
    if (noshi_tr_deepl_target(mapped.UTF8String, code, sizeof(code)) != NOSHI_OK) {
        [self fail:[self parseFailure]];
        return;
    }
    NSMutableArray *fields = [NSMutableArray arrayWithObjects:@"text", question, @"target_lang", [NSString stringWithUTF8String:code], nil];
    if (_markup) [fields addObjectsFromArray:[NSArray arrayWithObjects:@"tag_handling", @"html", nil]];
    /* prefer_*, not the strict values: a language that has no formality is refused by the strict ones, and the translation would fail instead of coming plain */
    if (NoshiTranslateDeepLFormality() == 1) [fields addObjectsFromArray:[NSArray arrayWithObjects:@"formality", @"prefer_less", nil]];
    if (NoshiTranslateDeepLFormality() == 2) [fields addObjectsFromArray:[NSArray arrayWithObjects:@"formality", @"prefer_more", nil]];
    NSString *host = [key hasSuffix:@":fx"] ? @"api-free.deepl.com" : @"api.deepl.com";
    NSMutableURLRequest *request = [self formRequestFor:[NSString stringWithFormat:@"https://%@/v2/translate", host] fields:fields];
    [request setValue:[@"DeepL-Auth-Key " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [self send:request parse:^NSString *(id json) {
        id list = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"translations"] : nil;
        return NoshiKey(@"text", NoshiFirst(list));
    }];
}

#pragma mark telegram

- (void)runTelegram:(NSString *)question {
    NSString *target = [self targetFor:NOSHI_TR_TELEGRAM api:0];
    if (!target) return;
    if (!_session) {
        [self fail:NSLocalizedString(@"tr.error.network", nil)];
        return;
    }
    NoshiTranslateJob *job = [self retain];
    [_session translateText:question to:target completion:^(NSString *translated, NSString *errorName) {
        if (translated.length) {
            [job finishWithText:translated];
        } else if ([errorName isEqualToString:@"ARG"]) {
            [job fail:NSLocalizedString(@"tr.error.long", nil)];
        } else if ([errorName isEqualToString:@"MALFORMED"]) {
            [job fail:[job parseFailure]];
        } else {
            NSLog(@"noshigram: the translation of Telegram failed: %@", errorName);
            [job fail:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"tr.error.network", nil)
                                                           : [NSString stringWithFormat:NSLocalizedString(@"tr.error.http", nil), errorName]];
        }
        [job release];
    }];
}

#pragma mark ai translator

/* models for which the optional fields (temperature, reasoning) got a 400, so they are left out from then on */
static NSMutableSet *NoshiPlainModels(void) {
    static NSMutableSet *set;
    if (!set) set = [[NSMutableSet alloc] init];
    return set;
}

static NSArray *NoshiKeysOf(NSString *text) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByString:@","]) {
        NSString *key = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length && ![keys containsObject:key]) [keys addObject:key];
    }
    return keys;
}

/* several keys in one field are used in turn, one for each request */
static NSString *NoshiNextLlmKey(int preset) {
    static NSUInteger turn;
    NSArray *keys = NoshiKeysOf(NoshiLlmKey(preset));
    return keys.count ? [keys objectAtIndex:turn++ % keys.count] : nil;
}

static NSString *NoshiVertexModelPath(NSString *model) {
    NSString *name = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name hasPrefix:@"publishers/"]) return name;
    if ([name hasPrefix:@"models/"]) return [@"publishers/google/" stringByAppendingString:name];
    if ([name hasPrefix:@"google/"]) return [@"publishers/google/models/" stringByAppendingString:[name substringFromIndex:7]];
    return [@"publishers/google/models/" stringByAppendingString:name];
}

- (NSString *)llmPromptFor:(NSString *)question language:(NSString *)name {
    NSString *custom = NoshiLlmSystemPrompt();
    char *buffer = malloc(question.length * 4 + NoshiLlmUserPrompt().length * 2 + 256);
    NSString *prompt = nil;
    if (buffer && noshi_llm_user_prompt(NoshiLlmUserPrompt().UTF8String, question.UTF8String, name.UTF8String, custom.length > 0, buffer,
                                          question.length * 4 + NoshiLlmUserPrompt().length * 2 + 256) == NOSHI_OK) prompt = [NSString stringWithUTF8String:buffer];
    free(buffer);
    return prompt;
}

- (void)runLLM:(NSString *)question {
    int preset = NoshiLlmPresetChoice();
    NSString *key = NoshiNextLlmKey(preset);
    if (!key.length || [key rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) {
        [self fail:NSLocalizedString(@"tr.keynotset", nil)];
        return;
    }
    NSString *model = NoshiLlmModel(preset);
    if (!model.length) {
        [self fail:NSLocalizedString(@"tr.nomodel", nil)];
        return;
    }
    NSString *base = NoshiLlmBaseURL(preset);
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSString *language = [self targetFor:NOSHI_TR_LLM api:0];
    if (!language) return;
    /* the model is told the language by its name in English */
    NSString *named = NoshiEnglishLanguageName(language);
    NSString *prompt = [self llmPromptFor:question language:named];
    if (!prompt) {
        [self fail:NSLocalizedString(@"tr.error.long", nil)];
        return;
    }
    NSString *system = NoshiLlmSystemPrompt();
    if (!system.length) system = [NSString stringWithUTF8String:noshi_llm_default_system()];
    NSMutableArray *messages = [NSMutableArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role", system, @"content", nil]];
    if (NoshiLlmUsesContext() && _context.length) {
        char *buffer = malloc(_context.length * 4 + 256);
        if (buffer && noshi_llm_context_prompt(_context.UTF8String, buffer, _context.length * 4 + 256) == NOSHI_OK) {
            [messages addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", [NSString stringWithUTF8String:buffer], @"content", nil]];
        }
        free(buffer);
    }
    [messages addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", prompt, @"content", nil]];
    [self sendLLM:messages preset:preset base:base model:model key:key plain:[NoshiPlainModels() containsObject:[NSString stringWithFormat:@"%@|%@", base, model]]];
}

/* the optional fields are sent first; a model that answers 400 to them gets one more request without them, and is remembered */
- (void)sendLLM:(NSArray *)messages preset:(int)preset base:(NSString *)base model:(NSString *)model key:(NSString *)key plain:(BOOL)plain {
    BOOL vertex = preset == NoshiLlmPresetVertex;
    noshi_llm_reasoning reasoning;
    noshi_llm_plan_reasoning(base.UTF8String, model.UTF8String, &reasoning);
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    NSString *url;
    if (vertex) {
        NSMutableArray *systemParts = [NSMutableArray array], *contents = [NSMutableArray array];
        for (NSDictionary *message in messages) {
            NSString *text = [message objectForKey:@"content"], *role = [message objectForKey:@"role"];
            if (!text.length) continue;
            NSDictionary *part = [NSDictionary dictionaryWithObject:text forKey:@"text"];
            if ([role isEqualToString:@"system"]) {
                [systemParts addObject:part];
                continue;
            }
            /* neighbours of one role share a content block */
            NSMutableDictionary *last = [contents lastObject];
            if (last && [[last objectForKey:@"role"] isEqualToString:@"user"]) [[last objectForKey:@"parts"] addObject:part];
            else [contents addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:@"user", @"role", [NSMutableArray arrayWithObject:part], @"parts", nil]];
        }
        [body setObject:contents forKey:@"contents"];
        if (systemParts.count) [body setObject:[NSDictionary dictionaryWithObject:systemParts forKey:@"parts"] forKey:@"systemInstruction"];
        if (!plain && reasoning.style == NOSHI_LLM_REASONING_VERTEX) {
            NSDictionary *thinking = reasoning.has_budget ? [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:reasoning.budget] forKey:@"thinkingBudget"]
                                                          : [NSDictionary dictionaryWithObject:[NSString stringWithUTF8String:reasoning.level] forKey:@"thinkingLevel"];
            [body setObject:[NSDictionary dictionaryWithObject:thinking forKey:@"thinkingConfig"] forKey:@"generationConfig"];
        }
        url = [NSString stringWithFormat:@"%@/%@:generateContent", base, NoshiVertexModelPath(model)];
    } else {
        [body setObject:model forKey:@"model"];
        [body setObject:messages forKey:@"messages"];
        if (!plain) {
            if (NoshiLlmSupportsTemperature(preset, model)) [body setObject:[NSNumber numberWithFloat:NoshiLlmTemperature()] forKey:@"temperature"];
            NSString *effort = [NSString stringWithUTF8String:reasoning.effort];
            switch (reasoning.style) {
            case NOSHI_LLM_REASONING_EFFORT: [body setObject:effort forKey:@"reasoning_effort"]; break;
            case NOSHI_LLM_REASONING_THINKING_OFF:
                [body setObject:[NSDictionary dictionaryWithObject:@"disabled" forKey:@"type"] forKey:@"thinking"];
                break;
            case NOSHI_LLM_REASONING_ROUTER:
                [body setObject:[NSDictionary dictionaryWithObject:effort forKey:@"effort"] forKey:@"reasoning"];
                break;
            case NOSHI_LLM_REASONING_GATEWAY:
                [body setObject:[NSDictionary dictionaryWithObject:effort forKey:@"effort"] forKey:@"reasoning"];
                [body setObject:[NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObject:@"ttft" forKey:@"sort"] forKey:@"gateway"] forKey:@"providerOptions"];
                break;
            case NOSHI_LLM_REASONING_GATEWAY_DEEPSEEK_OFF:
                [body setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObject:@"ttft" forKey:@"sort"], @"gateway",
                    [NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObject:@"disabled" forKey:@"type"] forKey:@"thinking"], @"deepseek", nil]
                         forKey:@"providerOptions"];
                break;
            default: break;
            }
        }
        url = [base stringByAppendingString:@"/chat/completions"];
    }
    if (![NSURL URLWithString:url]) {
        [self fail:NSLocalizedString(@"tr.url.invalid", nil)];
        return;
    }
    NSMutableURLRequest *request = [self jsonRequestFor:url object:body];
    if (vertex) [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    else [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    NoshiTranslateJob *job = self;
    [_call release];
    _call = [[NoshiHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT completion:^(NSData *data, NSInteger status, NSString *failure) {
        if (job->_cancelled) return;
        if (status == 400 && !plain) {
            [NoshiPlainModels() addObject:[NSString stringWithFormat:@"%@|%@", base, model]];
            NSLog(@"noshigram: HTTP 400 with the optional fields, trying again without them");
            [job sendLLM:messages preset:preset base:base model:model key:key plain:YES];
            return;
        }
        /* a rate limit waits and tries again, with jitter so that several requests do not come back together */
        if (status == 429 && job->_attempt + 1 < LLM_ATTEMPTS) {
            NSTimeInterval wait = (double)(1u << job->_attempt) + (double)(arc4random() % 500) / 1000.0;
            ++job->_attempt;
            [job performSelector:@selector(retryLLM:) withObject:[NSArray arrayWithObjects:messages, [NSNumber numberWithInt:preset], base, model, key, [NSNumber numberWithBool:plain], nil]
                      afterDelay:wait];
            return;
        }
        if (status < 200 || status > 299) {
            [job fail:[job failureOfStatus:status failure:failure body:data]];
            return;
        }
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *translated = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            if (vertex) {
                id candidates = [json objectForKey:@"candidates"];
                id content = NoshiKeyed(@"content", NoshiFirst(candidates));
                id parts = [content isKindOfClass:[NSDictionary class]] ? [content objectForKey:@"parts"] : nil;
                NSMutableString *joined = [NSMutableString string];
                if ([parts isKindOfClass:[NSArray class]]) {
                    for (id part in parts) {
                        if (![part isKindOfClass:[NSDictionary class]] || [[part objectForKey:@"thought"] boolValue]) continue;
                        NSString *piece = NoshiString([part objectForKey:@"text"]);
                        if (piece) [joined appendString:piece];
                    }
                }
                translated = joined;
            } else {
                id choices = [json objectForKey:@"choices"];
                id first = NoshiFirst(choices);
                id message = [first isKindOfClass:[NSDictionary class]] ? [first objectForKey:@"message"] : nil;
                translated = NoshiKey(@"content", message);
            }
        }
        translated = [translated stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (translated.length) [job finishWithText:translated];
        else [job fail:[job parseFailure]];
    }] retain];
}

- (void)retryLLM:(NSArray *)arguments {
    if (_cancelled) return;
    [self sendLLM:[arguments objectAtIndex:0] preset:[[arguments objectAtIndex:1] intValue] base:[arguments objectAtIndex:2] model:[arguments objectAtIndex:3]
              key:[arguments objectAtIndex:4] plain:[[arguments objectAtIndex:5] boolValue]];
}

@end

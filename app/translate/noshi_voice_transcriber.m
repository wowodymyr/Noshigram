#import "noshi_voice_transcriber.h"
#include "noshi_base64.h"

#include "noshi_voice.h"

#import "noshi_http_call.h"
#import "noshi_translate_config.h"

/* a note of two minutes is 3.8 MB as 16 kHz WAV and 5.1 MB as base64, which with the request body is what an old phone can hold at once */
#define VOICE_SECONDS_MAX 120
#define VOICE_SAMPLES_MAX ((size_t)VOICE_SECONDS_MAX * NOSHI_VOICE_RATE)
#define ANSWER_LIMIT (256u * 1024u)
#define CALL_TIMEOUT 90.0

static NSString *const NoshiTranscribePrompt = @"Transcribe the speech of this audio verbatim, in the language it is spoken in. Output only the transcription, with no introduction and no explanation. If there is no speech, output nothing.";

typedef struct {
    int16_t *samples;
    size_t count;
    int overflow;
} NoshiVoiceSamples;

static int NoshiVoiceCollect(void *ctx, const int16_t *samples, size_t count) {
    NoshiVoiceSamples *target = ctx;
    if (count > VOICE_SAMPLES_MAX - target->count) {
        target->overflow = 1;
        return 1;
    }
    memcpy(target->samples + target->count, samples, count * sizeof(int16_t));
    target->count += count;
    return 0;
}

/* one JSON string literal, quoted and escaped */
static NSString *NoshiJsonLiteral(NSString *text) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:text] options:0 error:NULL];
    NSString *array = data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
    return array.length > 2 ? [array substringWithRange:NSMakeRange(1, array.length - 2)] : nil;
}

static NSString *NoshiFirstKey(NSString *keys) {
    for (NSString *part in [keys componentsSeparatedByString:@","]) {
        NSString *key = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length) return key;
    }
    return nil;
}

@interface NoshiVoiceTranscriber () {
    BOOL _cancelled;
    NoshiHttpCall *_call;
    void (^_completion)(NSString *, NSString *);
}
@end

@implementation NoshiVoiceTranscriber

+ (BOOL)isConfigured {
    int preset = NoshiLlmPresetChoice();
    return preset != NoshiLlmPresetVertex && NoshiFirstKey(NoshiLlmKey(preset)).length && NoshiLlmModel(preset).length;
}

+ (NoshiVoiceTranscriber *)transcribeVoiceAtPath:(NSString *)oggPath completion:(void (^)(NSString *, NSString *))completion {
    NoshiVoiceTranscriber *job = [[[NoshiVoiceTranscriber alloc] init] autorelease];
    job->_completion = [completion copy];
    [job retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool { [job prepareBodyFromPath:oggPath]; }
        [job release];
    });
    return job;
}

- (void)dealloc {
    [_call cancel];
    [_call release];
    [_completion release];
    [super dealloc];
}

- (void)cancel {
    _cancelled = YES;
    [_call cancel];
}

- (void)finishWithText:(NSString *)text failure:(NSString *)failure {
    NSString *shownText = [[text copy] autorelease], *shownFailure = [[failure copy] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^done)(NSString *, NSString *) = _completion;
        _completion = nil;
        if (!_cancelled && done) done(shownText, shownFailure);
        [done release];
    });
}

/* off the main thread: the note becomes WAV samples, and the samples the body of the request */
- (void)prepareBodyFromPath:(NSString *)path {
    NSData *ogg = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!ogg.length) {
        [self finishWithText:nil failure:NSLocalizedString(@"chat.msg.transcribe.unreadable", nil)];
        return;
    }
    NoshiVoiceSamples target = {malloc(VOICE_SAMPLES_MAX * sizeof(int16_t)), 0, 0};
    if (!target.samples) {
        [self finishWithText:nil failure:NSLocalizedString(@"chat.msg.transcribe.long", nil)];
        return;
    }
    noshi_status status = noshi_voice_decode(ogg.bytes, ogg.length, NoshiVoiceCollect, &target, NULL);
    if (target.overflow) {
        free(target.samples);
        [self finishWithText:nil failure:NSLocalizedString(@"chat.msg.transcribe.long", nil)];
        return;
    }
    if (status != NOSHI_OK || !target.count) {
        NSLog(@"noshigram: the voice note did not decode for the transcription: %s", noshi_status_name(status));
        free(target.samples);
        [self finishWithText:nil failure:NSLocalizedString(@"chat.msg.transcribe.unreadable", nil)];
        return;
    }
    NSData *body = [self bodyForSamples:target.samples count:target.count];
    free(target.samples);
    if (!body) {
        [self finishWithText:nil failure:NSLocalizedString(@"chat.msg.transcribe.long", nil)];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self sendBody:body]; });
}

- (NSData *)bodyForSamples:(const int16_t *)samples count:(size_t)count {
    int preset = NoshiLlmPresetChoice();
    NSString *model = NoshiJsonLiteral(NoshiLlmModel(preset)), *prompt = NoshiJsonLiteral(NoshiTranscribePrompt);
    if (!model || !prompt) return nil;
    uint8_t header[44];
    noshi_wav_header(NOSHI_VOICE_RATE, count, header);
    size_t wavLength = sizeof(header) + count * sizeof(int16_t);
    uint8_t *wav = malloc(wavLength);
    if (!wav) return nil;
    memcpy(wav, header, sizeof(header));
    memcpy(wav + sizeof(header), samples, count * sizeof(int16_t));
    size_t encodedCapacity = (wavLength + 2) / 3 * 4 + 1, encodedLength = 0;
    char *encoded = malloc(encodedCapacity);
    if (!encoded || noshi_base64_encode(wav, wavLength, encoded, encodedCapacity, &encodedLength) != NOSHI_OK) {
        free(wav);
        free(encoded);
        return nil;
    }
    free(wav);
    NSString *head = [NSString stringWithFormat:@"{\"model\":%@,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":%@},{\"type\":\"input_audio\",\"input_audio\":{\"data\":\"", model, prompt];
    NSString *tail = @"\",\"format\":\"wav\"}}]}]}";
    NSMutableData *body = [NSMutableData dataWithCapacity:head.length + encodedLength + tail.length];
    [body appendData:[head dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendBytes:encoded length:encodedLength];
    [body appendData:[tail dataUsingEncoding:NSUTF8StringEncoding]];
    free(encoded);
    return body;
}

- (void)sendBody:(NSData *)body {
    if (_cancelled) return;
    int preset = NoshiLlmPresetChoice();
    NSString *key = NoshiFirstKey(NoshiLlmKey(preset));
    NSString *base = NoshiLlmBaseURL(preset);
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/chat/completions"]];
    if (!key.length || !url) {
        [self finishWithText:nil failure:NSLocalizedString(key.length ? @"tr.url.invalid" : @"tr.keynotset", nil)];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:CALL_TIMEOUT];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:body];
    [request setValue:@"application/json; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [_call release];
    _call = [[NoshiHttpCall startRequest:request limit:ANSWER_LIMIT timeout:CALL_TIMEOUT completion:^(NSData *data, NSInteger status, NSString *failure) {
        if (_cancelled) return;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (status < 200 || status > 299) {
            NSString *reason = nil;
            id error = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"error"] : nil;
            if ([error isKindOfClass:[NSDictionary class]]) error = [error objectForKey:@"message"];
            if ([error isKindOfClass:[NSString class]] && [error length]) reason = error;
            if (!reason) reason = failure.length ? failure : [NSString stringWithFormat:@"HTTP %ld", (long)status];
            NSLog(@"noshigram: the voice transcription answered %ld", (long)status);
            [self finishWithText:nil failure:reason];
            return;
        }
        [self finishWithText:[self textOfAnswer:json] failure:nil];
    }] retain];
}

/* the text of the first choice, whether the provider gives it as a string or as parts */
- (NSString *)textOfAnswer:(id)json {
    id choices = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"choices"] : nil;
    id first = [choices isKindOfClass:[NSArray class]] && [choices count] ? [choices objectAtIndex:0] : nil;
    id message = [first isKindOfClass:[NSDictionary class]] ? [first objectForKey:@"message"] : nil;
    id content = [message isKindOfClass:[NSDictionary class]] ? [message objectForKey:@"content"] : nil;
    NSMutableString *text = [NSMutableString string];
    if ([content isKindOfClass:[NSString class]]) [text appendString:content];
    else if ([content isKindOfClass:[NSArray class]]) {
        for (id part in content) {
            id piece = [part isKindOfClass:[NSDictionary class]] ? [part objectForKey:@"text"] : nil;
            if ([piece isKindOfClass:[NSString class]]) [text appendString:piece];
        }
    }
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end

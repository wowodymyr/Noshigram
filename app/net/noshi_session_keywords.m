#import "noshi_session_keywords.h"

#import "noshi_emoji_keywords.h"
#import "noshi_rpc.h"
#import "noshi_session_internal.h"

@implementation NoshiSession (EmojiKeywords)

- (void)updateEmojiKeywords:(NoshiEmojiKeywords *)keywords completion:(void (^)(NSString *errorName))completion {
    [self updateEmojiKeywords:keywords fromVersion:keywords.version mayRestart:YES completion:completion];
}

- (void)updateEmojiKeywords:(NoshiEmojiKeywords *)keywords fromVersion:(int32_t)version mayRestart:(BOOL)mayRestart completion:(void (^)(NSString *errorName))completion {
    void (^done)(NSString *) = [completion copy];
    NoshiEmojiKeywords *held = [keywords retain];
    NSString *language = [keywords.language copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_keywords_request(arena, language.UTF8String, version, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        BOOL again = NO;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = [held applyAnswer:result->value];
            if (status == NOSHI_E_STATE && mayRestart) {
                again = YES;
            } else if (status != NOSHI_OK) {
                NSLog(@"noshigram: the emoji keywords of %@ were refused: %s", language, noshi_status_name(status));
                error = @"INTERNAL";
            }
        }
        if (again) {
            [self updateEmojiKeywords:held fromVersion:0 mayRestart:NO completion:done];
        } else {
            NSString *delivered = [[error copy] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(delivered); });
        }
        [done release];
        [held release];
        [language release];
    }];
}

@end

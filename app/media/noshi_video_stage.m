#import "noshi_video_stage.h"

#include "noshi_fmp4.h"

BOOL NoshiWritePlainVideo(NSString *source, NSString *destination) {
    noshi_status status = noshi_fmp4_scan(source.fileSystemRepresentation);
    if (status != NOSHI_OK) {
        if (status != NOSHI_E_NOTFOUND) NSLog(@"noshigram: the video %@ could not be looked at: %s", source.lastPathComponent, noshi_status_name(status));
        return NO;
    }
    status = noshi_fmp4_remux(source.fileSystemRepresentation, destination.fileSystemRepresentation);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the fragmented video %@ could not be made plain: %s", source.lastPathComponent, noshi_status_name(status));
        return NO;
    }
    return YES;
}

BOOL NoshiStageVideo(NSString *source, NSString *destination, NSError **error) {
    if (NoshiWritePlainVideo(source, destination)) return YES;
    return [[NSFileManager defaultManager] linkItemAtPath:source toPath:destination error:error];
}

dispatch_queue_t NoshiVideoStageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("noshigram.video.stage", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

void NoshiStageVideoAsync(NSString *source, NSString *destination, void (^completion)(BOOL, NSError *)) {
    void (^done)(BOOL, NSError *) = [completion copy];
    NSString *from = [source copy], *to = [destination copy];
    dispatch_async(NoshiVideoStageQueue(), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        BOOL staged = NoshiStageVideo(from, to, &error);
        [error retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            done(staged, error);
            [error release];
            [done release];
        });
        [from release];
        [to release];
        [pool drain];
    });
}

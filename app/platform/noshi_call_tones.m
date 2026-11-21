#import "noshi_call_tones.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

/* looked up at run time like the other AVFoundation classes: the arm64 slice is linked against an sdk where AVAudioPlayer lives in AVFAudio, which ios 10
   does not have */
static id NoshiTonePlayer;

typedef struct {
    NSString *name;
    NSString *type;
    /* AVAudioPlayer loops after the first play, so -1 is for ever and 2 is three plays */
    NSInteger loops;
    NSTimeInterval seconds;
} NoshiToneSpec;

static NoshiToneSpec NoshiToneFor(NoshiCallTone tone) {
    switch (tone) {
    case NoshiCallToneRingback: return (NoshiToneSpec){@"voip_ringback", @"caf", -1, 0};
    case NoshiCallToneConnecting: return (NoshiToneSpec){@"voip_connecting", @"mp3", -1, 0};
    case NoshiCallToneBusy: return (NoshiToneSpec){@"voip_busy", @"caf", 2, 3.0};
    case NoshiCallToneFailed: return (NoshiToneSpec){@"voip_fail", @"caf", 0, 2.05};
    case NoshiCallToneEnded: return (NoshiToneSpec){@"voip_end", @"caf", 0, 1.2};
    }
    return (NoshiToneSpec){nil, nil, 0, 0};
}

NSTimeInterval NoshiCallToneDuration(NoshiCallTone tone) {
    return NoshiToneFor(tone).seconds;
}

void NoshiCallToneStop(void) {
    [NoshiTonePlayer stop];
    [NoshiTonePlayer release];
    NoshiTonePlayer = nil;
}

void NoshiCallToneStart(NoshiCallTone tone) {
    NoshiToneSpec spec = NoshiToneFor(tone);
    NoshiCallToneStop();
    NSString *path = spec.name ? [[NSBundle mainBundle] pathForResource:spec.name ofType:spec.type] : nil;
    Class playerClass = NSClassFromString(@"AVAudioPlayer");
    if (!path || !playerClass) {
        NSLog(@"noshigram: the call tone %@ is not available", spec.name);
        return;
    }
    NSError *error = nil;
    id player = [[playerClass alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (!player) {
        NSLog(@"noshigram: the call tone %@ would not open: %@", spec.name, error);
        return;
    }
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(player, @selector(setNumberOfLoops:), spec.loops);
    ((BOOL (*)(id, SEL))objc_msgSend)(player, @selector(prepareToPlay));
    /* the class is found by name, so the compiler has no one declaration to take play from: it is AVAudioPlayer's, which answers whether it started */
    if (!((BOOL (*)(id, SEL))objc_msgSend)(player, @selector(play))) NSLog(@"noshigram: the call tone %@ would not play", spec.name);
    NoshiTonePlayer = player;
}

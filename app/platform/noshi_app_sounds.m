#import "noshi_app_sounds.h"

#import <AudioToolbox/AudioToolbox.h>

#import "noshi_notify_store.h"

#include "noshi_notify.h"

void NoshiPlayAppSound(NSString *file) {
    static NSMutableDictionary *loaded;
    if (!file.length) return;
    if (!loaded) loaded = [[NSMutableDictionary alloc] init];
    NSNumber *known = [loaded objectForKey:file];
    SystemSoundID sound = (SystemSoundID)[known unsignedIntValue];
    if (!known) {
        NSString *path = [[NSBundle mainBundle] pathForResource:file ofType:nil];
        OSStatus status = path ? AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath:path], &sound) : kAudioServicesUnsupportedPropertyError;
        if (status != kAudioServicesNoError) {
            NSLog(@"noshigram: the sound %@ could not be prepared (%d)", file, (int)status);
            sound = 0;
        }
        /* a sound that failed is remembered as none, so it is not tried at every message */
        [loaded setObject:[NSNumber numberWithUnsignedInt:sound] forKey:file];
    }
    if (sound) AudioServicesPlaySystemSound(sound);
}

void NoshiVibrateOnce(void) {
    if (!NoshiNotifyInAppVibrate()) return;
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

void NoshiVibrateForCall(void) {
    /* 2 is the off of the call vibration setting */
    if (NoshiNotifyCallVibration() == 2) return;
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

static void NoshiPlayInChatFile(BOOL incoming, NSString *file) {
    static NSTimeInterval lastIn, lastOut;
    if (!NoshiNotifyInChatSounds()) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    /* the same gaps: half a second between sounds of incoming messages, a tenth for the ones sent */
    if (incoming ? now - lastIn < 0.5 : now - lastOut < 0.1) return;
    if (incoming) lastIn = now;
    else lastOut = now;
    NoshiPlayAppSound(file);
}

void NoshiPlayInChatSound(BOOL incoming) {
    NoshiPlayInChatFile(incoming, incoming ? @"sound_in.caf" : @"sound_out.caf");
}

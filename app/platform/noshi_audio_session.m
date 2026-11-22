#import <AudioToolbox/AudioToolbox.h>
#import "noshi_audio_session.h"

#include <dlfcn.h>
#import <objc/message.h>

NSString *NoshiAudioConstant(const char *name) {
    NSString **value = (NSString **)dlsym(RTLD_DEFAULT, name);
    return value ? *value : nil;
}

AVAudioSession *NoshiAudioSession(void) {
    return [NSClassFromString(@"AVAudioSession") sharedInstance];
}

Class NoshiAudioRecorderClass(void) {
    return NSClassFromString(@"AVAudioRecorder");
}

NSString *NoshiAudioCategoryPlayAndRecord(void) {
    return NoshiAudioConstant("AVAudioSessionCategoryPlayAndRecord");
}

BOOL NoshiAudioSessionBeginPlayback(void) {
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    NSString *category = NoshiAudioCategoryPlayback();
    if (!audio || !category || ![audio setCategory:category error:&error] || ![audio setActive:YES error:&error]) {
        NSLog(@"noshigram: audio session refused playback: %@", error);
        return NO;
    }
    return YES;
}

BOOL NoshiAudioSessionBeginEarpiece(void) {
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    NSString *category = NoshiAudioCategoryPlayAndRecord();
    if (!audio || !category || ![audio setCategory:category error:&error] || ![audio setActive:YES error:&error]) {
        NSLog(@"noshigram: audio session refused the earpiece route: %@", error);
        return NO;
    }
    /* the record category may keep an earlier override to the loudspeaker */
    NoshiAudioSessionSetSpeaker(NO);
    return YES;
}

BOOL NoshiAudioSessionCanUseBluetoothMicrophone(void) {
    return [NoshiAudioSession() respondsToSelector:NSSelectorFromString(@"setCategory:withOptions:error:")];
}

BOOL NoshiAudioSessionBeginRecording(BOOL bluetooth) {
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    NSString *category = NoshiAudioCategoryPlayAndRecord();
    if (!audio || !category) return NO;
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    BOOL set;
    if (bluetooth && [audio respondsToSelector:withOptions]) {
        /* AVAudioSessionCategoryOptionAllowBluetooth is 4 */
        set = ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, 4, &error);
    } else {
        set = [audio setCategory:category error:&error];
    }
    if (!set || ![audio setActive:YES error:&error]) {
        NSLog(@"noshigram: audio session refused the recording: %@", error);
        return NO;
    }
    return YES;
}

BOOL NoshiAudioSessionBeginMixedPlayback(void) {
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    NSString *category = NoshiAudioCategoryPlayback();
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    if (!audio || !category || ![audio respondsToSelector:withOptions]) return NO;
    /* AVAudioSessionCategoryOptionMixWithOthers is 1 */
    BOOL set = ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, 1, &error);
    if (!set || ![audio setActive:YES error:&error]) {
        NSLog(@"noshigram: audio session refused mixed playback: %@", error);
        return NO;
    }
    return YES;
}

NSString *NoshiAudioSessionCategory(void) {
    return [NoshiAudioSession() category];
}

NSString *NoshiAudioCategoryPlayback(void) {
    return NoshiAudioConstant("AVAudioSessionCategoryPlayback");
}

/* the record category of a call, with the Bluetooth option where the system has it: without it a headset never carries the microphone of a call (ios 6 and later) */
static BOOL NoshiAudioSetCallCategory(AVAudioSession *audio, BOOL bluetooth, NSError **error) {
    NSString *category = NoshiAudioCategoryPlayAndRecord();
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    if (!category) return NO;
    if ([audio respondsToSelector:withOptions]) {
        /* AVAudioSessionCategoryOptionAllowBluetooth is 4 */
        return ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, bluetooth ? 4 : 0, error);
    }
    return [audio setCategory:category error:error];
}

static void NoshiAudioSetVoiceChatMode(AVAudioSession *audio) {
    NSError *error = nil;
    /* the mode came with ios 5 and only tunes the microphone for speech; a call runs without it */
    NSString *mode = NoshiAudioConstant("AVAudioSessionModeVoiceChat");
    if (mode && [audio respondsToSelector:@selector(setMode:error:)] && ![audio setMode:mode error:&error]) NSLog(@"noshigram: voice chat mode refused: %@", error);
}

BOOL NoshiAudioSessionBeginCall(void) {
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    if (!audio || !NoshiAudioSetCallCategory(audio, YES, &error)) {
        NSLog(@"noshigram: audio session refused the call: %@", error);
        return NO;
    }
    NoshiAudioSetVoiceChatMode(audio);
    if (![audio setActive:YES error:&error]) {
        NSLog(@"noshigram: audio session refused the call: %@", error);
        return NO;
    }
    return YES;
}

static BOOL NoshiAudioPortIsBluetooth(NSString *type) {
    return type && ([type isEqualToString:NoshiAudioConstant("AVAudioSessionPortBluetoothHFP")] || [type isEqualToString:NoshiAudioConstant("AVAudioSessionPortBluetoothA2DP")] ||
                    [type isEqualToString:NoshiAudioConstant("AVAudioSessionPortBluetoothLE")]);
}

/* a cable: headphones, a headset with a microphone, or a usb sound card */
static BOOL NoshiAudioPortIsWired(NSString *type) {
    return type && ([type isEqualToString:NoshiAudioConstant("AVAudioSessionPortHeadphones")] || [type isEqualToString:NoshiAudioConstant("AVAudioSessionPortHeadsetMic")] ||
                    [type isEqualToString:NoshiAudioConstant("AVAudioSessionPortUSBAudio")]);
}

/* the input ports of ios 7 and later: the headset when a type matches, else the built in microphone */
static id NoshiAudioInputPort(AVAudioSession *audio, BOOL bluetooth) {
    if (![audio respondsToSelector:NSSelectorFromString(@"availableInputs")]) return nil;
    NSString *builtIn = NoshiAudioConstant("AVAudioSessionPortBuiltInMic");
    for (id port in [audio valueForKey:@"availableInputs"]) {
        NSString *type = [port valueForKey:@"portType"];
        if (bluetooth ? NoshiAudioPortIsBluetooth(type) : [type isEqualToString:builtIn]) return port;
    }
    return nil;
}

BOOL NoshiAudioSessionBluetoothInputAvailable(NSString **name) {
    AVAudioSession *audio = NoshiAudioSession();
    if (name) *name = nil;
    if (!audio) return NO;
    id port = NoshiAudioInputPort(audio, YES);
    if (port) {
        if (name) *name = [port valueForKey:@"portName"];
        return YES;
    }
    if (![audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) return NO;
    id route = [audio valueForKey:@"currentRoute"];
    for (id output in [route valueForKey:@"outputs"]) {
        if (NoshiAudioPortIsBluetooth([output valueForKey:@"portType"])) {
            if (name) *name = [output valueForKey:@"portName"];
            return YES;
        }
    }
    return NO;
}

/* ios 5 has no route object: the route is a string such as "Headphone", "HeadsetInOut" or "HeadsetBT" */
static NSString *NoshiAudioLegacyRouteName(void) {
    CFStringRef route = NULL;
    UInt32 size = sizeof(route);
    if (AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &size, &route) != noErr || !route) return nil;
    return [(NSString *)route autorelease];
}

BOOL NoshiAudioSessionWiredAvailable(NSString **name) {
    AVAudioSession *audio = NoshiAudioSession();
    if (name) *name = nil;
    if (!audio) return NO;
    if ([audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) {
        for (id output in [[audio valueForKey:@"currentRoute"] valueForKey:@"outputs"]) {
            if (NoshiAudioPortIsWired([output valueForKey:@"portType"])) {
                if (name) *name = [output valueForKey:@"portName"];
                return YES;
            }
        }
        /* a headset also lists its microphone among the inputs, which ios 7 shows before it is the route */
        if ([audio respondsToSelector:NSSelectorFromString(@"availableInputs")]) {
            for (id port in [audio valueForKey:@"availableInputs"]) {
                if (NoshiAudioPortIsWired([port valueForKey:@"portType"])) {
                    if (name) *name = [port valueForKey:@"portName"];
                    return YES;
                }
            }
        }
        return NO;
    }
    NSString *legacy = NoshiAudioLegacyRouteName();
    return legacy && ([legacy rangeOfString:@"Headphone"].location != NSNotFound || ([legacy rangeOfString:@"Headset"].location != NSNotFound && [legacy rangeOfString:@"BT"].location == NSNotFound));
}

NoshiAudioRoute NoshiAudioSessionCurrentRoute(void) {
    AVAudioSession *audio = NoshiAudioSession();
    if (!audio) return NoshiAudioRouteEarpiece;
    if (![audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) {
        NSString *legacy = NoshiAudioLegacyRouteName();
        if (legacy && [legacy rangeOfString:@"BT"].location != NSNotFound) return NoshiAudioRouteBluetooth;
        if (legacy && [legacy rangeOfString:@"Speaker"].location != NSNotFound) return NoshiAudioRouteSpeaker;
        if (legacy && ([legacy rangeOfString:@"Headphone"].location != NSNotFound || [legacy rangeOfString:@"Headset"].location != NSNotFound)) return NoshiAudioRouteWired;
        return NoshiAudioRouteEarpiece;
    }
    NSString *speaker = NoshiAudioConstant("AVAudioSessionPortBuiltInSpeaker");
    for (id output in [[audio valueForKey:@"currentRoute"] valueForKey:@"outputs"]) {
        NSString *type = [output valueForKey:@"portType"];
        if (NoshiAudioPortIsBluetooth(type)) return NoshiAudioRouteBluetooth;
        if (NoshiAudioPortIsWired(type)) return NoshiAudioRouteWired;
        if (speaker && [type isEqualToString:speaker]) return NoshiAudioRouteSpeaker;
    }
    return NoshiAudioRouteEarpiece;
}

BOOL NoshiAudioSessionSelectRoute(NoshiAudioRoute route) {
    AVAudioSession *audio = NoshiAudioSession();
    NSError *error = nil;
    if (!audio) return NO;
    if (route == NoshiAudioRouteSpeaker) {
        NoshiAudioSessionSetSpeaker(YES);
        return YES;
    }
    BOOL bluetooth = route == NoshiAudioRouteBluetooth;
    /* ios 6 has no preferred input: the headset is the route while the category allows it, and the earpiece once it does not; a category change drops the mode and the override, so both are set again */
    BOOL preferred = [audio respondsToSelector:NSSelectorFromString(@"setPreferredInput:error:")];
    if (!preferred || bluetooth) {
        if (!NoshiAudioSetCallCategory(audio, bluetooth, &error)) {
            NSLog(@"noshigram: audio session refused the call route: %@", error);
            return NO;
        }
        NoshiAudioSetVoiceChatMode(audio);
        if (![audio setActive:YES error:&error]) {
            NSLog(@"noshigram: audio session refused the call route: %@", error);
            return NO;
        }
    }
    NoshiAudioSessionSetSpeaker(NO);
    if (preferred && route == NoshiAudioRouteWired) {
        /* the cable wins over the built in output once nothing overrides it; the microphone of the headset follows when it has one, else the built in one stays */
        id headset = nil;
        for (id port in [audio valueForKey:@"availableInputs"]) {
            if (NoshiAudioPortIsWired([port valueForKey:@"portType"])) { headset = port; break; }
        }
        if (headset && !((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(audio, NSSelectorFromString(@"setPreferredInput:error:"), headset, &error)) {
            NSLog(@"noshigram: the headset input was refused: %@", error);
            return NO;
        }
        return YES;
    }
    if (preferred) {
        id port = NoshiAudioInputPort(audio, bluetooth);
        if (!port && bluetooth) {
            NSLog(@"noshigram: no bluetooth input to prefer");
            return NO;
        }
        if (!((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(audio, NSSelectorFromString(@"setPreferredInput:error:"), port, &error)) {
            NSLog(@"noshigram: the preferred input was refused: %@", error);
            return NO;
        }
    }
    return YES;
}

void NoshiAudioSessionEndCall(void) {
    NoshiAudioSessionSetSpeaker(NO);
    NSError *error = nil;
    AVAudioSession *audio = NoshiAudioSession();
    if (audio && ![audio setActive:NO error:&error]) NSLog(@"noshigram: audio session would not close after the call: %@", error);
}

void NoshiAudioSessionSetSpeaker(BOOL speaker) {
    AVAudioSession *audio = NoshiAudioSession();
    NSError *error = nil;
    if (!audio) return;
    /* 'spkr' is AVAudioSessionPortOverrideSpeaker; the method is ios 6, ios 5 has only the c property */
    SEL override = NSSelectorFromString(@"overrideOutputAudioPort:error:");
    if ([audio respondsToSelector:override]) {
        NSMethodSignature *signature = [audio methodSignatureForSelector:override];
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        NSUInteger port = speaker ? 'spkr' : 0;
        NSError **errorOut = &error;
        [call setTarget:audio];
        [call setSelector:override];
        [call setArgument:&port atIndex:2];
        [call setArgument:&errorOut atIndex:3];
        [call invoke];
        if (error) NSLog(@"noshigram: the loudspeaker route was refused: %@", error);
        return;
    }
    UInt32 route = speaker ? kAudioSessionOverrideAudioRoute_Speaker : kAudioSessionOverrideAudioRoute_None;
    OSStatus status = AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute, sizeof(route), &route);
    if (status != 0) NSLog(@"noshigram: the loudspeaker route was refused: %d", (int)status);
}

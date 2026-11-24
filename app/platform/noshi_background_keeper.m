#import "noshi_background_keeper.h"

#import <objc/message.h>

#import "noshi_audio_session.h"
#import "noshi_now_playing.h"
#import "noshi_voip_socket.h"

#define SAMPLE_RATE 8000
#define LOOP_SECONDS 1

/* the player is an id, so its BOOL returning methods are sent with their types, as the sdks of the two slices are not asked */
static BOOL NoshiPlayerPlay(id player) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"play"));
}

static BOOL NoshiPlayerPrepare(id player) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"prepareToPlay"));
}

/* a WAV of one second of 8 kHz mono 16 bit silence: the header is 44 bytes and every sample is zero */
static NSData *NoshiSilence(void) {
    uint32_t bytes = SAMPLE_RATE * LOOP_SECONDS * 2;
    NSMutableData *wav = [NSMutableData dataWithLength:44 + bytes];
    uint8_t *p = wav.mutableBytes;
    uint32_t chunk = 36 + bytes, rate = SAMPLE_RATE, byteRate = SAMPLE_RATE * 2;
    uint16_t format = 1, channels = 1, align = 2, bits = 16;
    uint32_t sixteen = 16;
    memcpy(p, "RIFF", 4);
    memcpy(p + 4, &chunk, 4);
    memcpy(p + 8, "WAVEfmt ", 8);
    memcpy(p + 16, &sixteen, 4);
    memcpy(p + 20, &format, 2);
    memcpy(p + 22, &channels, 2);
    memcpy(p + 24, &rate, 4);
    memcpy(p + 28, &byteRate, 4);
    memcpy(p + 32, &align, 2);
    memcpy(p + 34, &bits, 2);
    memcpy(p + 36, "data", 4);
    memcpy(p + 40, &bytes, 4);
    return wav;
}

@interface NoshiBackgroundKeeper () {
    /* an AVAudioPlayer; the class is looked up by name, since the arm64 slice's sdk keeps it in a framework ios 10 does not have */
    id _player;
    BOOL _listening;
}
@end

/* the silence mixes with the sound of other apps, but a mixed session is never the one that plays for the control center: while a song of
   this app holds the remote buttons the silence plays in the song's own session and leaves its category alone */
static BOOL NoshiKeeperTakeSession(void) {
    return NoshiRemoteControlsActive() ? NoshiAudioSessionBeginPlayback() : NoshiAudioSessionBeginMixedPlayback();
}

/* the keeper that plays the silence now; the notifier owns it */
static NoshiBackgroundKeeper *NoshiPlayingKeeper;

@implementation NoshiBackgroundKeeper

+ (BOOL)needed {
    return !NoshiVoipSocketSupported();
}

- (void)dealloc {
    if (NoshiPlayingKeeper == self) NoshiPlayingKeeper = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player stop];
    [_player release];
    [super dealloc];
}

+ (BOOL)takeSessionFromSong {
    NoshiBackgroundKeeper *keeper = NoshiPlayingKeeper;
    if (!keeper.running) return NO;
    if (!NoshiKeeperTakeSession()) return NO;
    /* a change of the category may pause the silence */
    if (![keeper->_player isPlaying] && !NoshiPlayerPlay(keeper->_player)) NSLog(@"noshigram: the background sound would not go on after the song");
    return YES;
}

- (BOOL)running {
    return _player != nil && [_player isPlaying];
}

- (void)observeInterruptions {
    if (_listening) return;
    NSString *name = NoshiAudioConstant("AVAudioSessionInterruptionNotification");
    if (!name) return;
    _listening = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interrupted:) name:name object:nil];
}

/* a call or an alarm took the session; when it gives it back the silence goes on, or the app would sleep with nothing to wake it */
- (void)interrupted:(NSNotification *)note {
    NSNumber *type = [note.userInfo objectForKey:@"AVAudioSessionInterruptionTypeKey"];
    if (!_player || type.integerValue != 0) return;
    if (!NoshiKeeperTakeSession()) return;
    if (!NoshiPlayerPlay(_player)) NSLog(@"noshigram: the background sound would not resume after an interruption");
}

- (BOOL)start {
    if (self.running) return YES;
    /* a call or a recording owns the session, and changing its category would cut it */
    NSString *category = NoshiAudioSessionCategory();
    if (category && [category isEqualToString:NoshiAudioCategoryPlayAndRecord()]) {
        NSLog(@"noshigram: the background sound waits, a call or a recording has the audio session");
        return NO;
    }
    Class playerClass = NSClassFromString(@"AVAudioPlayer");
    if (!playerClass) {
        NSLog(@"noshigram: this system has no audio player for the background sound");
        return NO;
    }
    if (!NoshiKeeperTakeSession()) return NO;
    NSError *error = nil;
    if (!_player) {
        _player = [[playerClass alloc] initWithData:NoshiSilence() error:&error];
        if (!_player) {
            NSLog(@"noshigram: the silence for the background sound did not load: %@", error);
            return NO;
        }
        [_player setNumberOfLoops:-1];
        NoshiPlayerPrepare(_player);
    }
    [self observeInterruptions];
    if (!NoshiPlayerPlay(_player)) {
        NSLog(@"noshigram: the background sound would not start");
        return NO;
    }
    NoshiPlayingKeeper = self;
    NSLog(@"noshigram: the background sound plays");
    return YES;
}

- (void)stop {
    if (NoshiPlayingKeeper == self) NoshiPlayingKeeper = nil;
    if (!_player) return;
    [_player stop];
    NSLog(@"noshigram: the background sound stopped");
}

@end

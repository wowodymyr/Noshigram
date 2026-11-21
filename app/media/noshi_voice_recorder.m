#import "noshi_voice_recorder.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "noshi_audio_session.h"
#import "noshi_chat_settings.h"

#include <stdio.h>

#include "noshi_voice.h"

/* a tap that ends under this is a slip of the finger, not a note */
#define MIN_SECONDS 0.6
#define CHUNK_SAMPLES 3200

@interface NoshiVoiceRecorder () {
    AVAudioRecorder *_recorder;
    NSString *_wavPath;
    BOOL _failed;
}
@end

@implementation NoshiVoiceRecorder

@synthesize failed = _failed;

static NSString *NoshiTemporaryPath(NSString *extension) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"noshigram-%08x%08x.%@", arc4random(), arc4random(), extension]];
}

- (void)dealloc {
    [self cancel];
    [super dealloc];
}

- (BOOL)start {
    NSError *error = nil;
    if (!NoshiAudioSessionBeginRecording(NoshiChatRecordViaBluetooth())) return NO;
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:kAudioFormatLinearPCM], NoshiAudioConstant("AVFormatIDKey"),
        [NSNumber numberWithFloat:NOSHI_VOICE_RATE], NoshiAudioConstant("AVSampleRateKey"),
        [NSNumber numberWithInt:1], NoshiAudioConstant("AVNumberOfChannelsKey"),
        [NSNumber numberWithInt:16], NoshiAudioConstant("AVLinearPCMBitDepthKey"),
        [NSNumber numberWithBool:NO], NoshiAudioConstant("AVLinearPCMIsBigEndianKey"),
        [NSNumber numberWithBool:NO], NoshiAudioConstant("AVLinearPCMIsFloatKey"), nil];
    _wavPath = [NoshiTemporaryPath(@"wav") retain];
    _recorder = [[NoshiAudioRecorderClass() alloc] initWithURL:[NSURL fileURLWithPath:_wavPath] settings:settings error:&error];
    if (!_recorder) {
        NSLog(@"noshigram: cannot make the recorder: %@", error);
        [self cancel];
        return NO;
    }
    _recorder.meteringEnabled = YES;
    if (![_recorder record]) {
        NSLog(@"noshigram: the microphone did not start");
        [self cancel];
        return NO;
    }
    return YES;
}

- (NSTimeInterval)elapsed {
    return _recorder.recording ? _recorder.currentTime : 0;
}

- (float)level {
    if (!_recorder.recording) return 0;
    [_recorder updateMeters];
    /* decibels from about -50 (a quiet room) to 0 (clipping) mapped onto a straight scale */
    float power = [_recorder averagePowerForChannel:0];
    return MAX(0.0f, MIN(1.0f, (power + 50.0f) / 50.0f));
}

- (void)cancel {
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    if (_wavPath) {
        [[NSFileManager defaultManager] removeItemAtPath:_wavPath error:NULL];
        [_wavPath release];
        _wavPath = nil;
    }
    [NoshiAudioSession() setActive:NO error:NULL];
}

static int NoshiWriteOgg(void *ctx, const uint8_t *bytes, size_t len) {
    return fwrite(bytes, 1, len, (FILE *)ctx) == len ? 0 : 1;
}

/* off the main thread: the recorded wav becomes an ogg file next to it; NO leaves no file behind */
static BOOL NoshiEncode(NSString *wavPath, NSString *oggPath, int32_t *durationMs, NSMutableData *waveform) {
    NSData *wav = [NSData dataWithContentsOfFile:wavPath options:NSDataReadingMappedIfSafe error:NULL];
    size_t offset = 0, count = 0;
    noshi_status status = wav ? noshi_wav_pcm16(wav.bytes, wav.length, NOSHI_VOICE_RATE, &offset, &count) : NOSHI_E_IO;
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the recording is not usable: %s", noshi_status_name(status));
        return NO;
    }
    /* the samples are read from the mapped file, since a copy of half an hour of them is 57 MB on a phone that has little to spare; the data chunk of a wav
       starts on an even byte, which is what a 16 bit read needs */
    if (offset % sizeof(int16_t)) {
        NSLog(@"noshigram: the recording has its samples at an odd offset %zu", offset);
        return NO;
    }
    const int16_t *samples = (const int16_t *)((const uint8_t *)wav.bytes + offset);
    FILE *out = fopen(oggPath.fileSystemRepresentation, "wb");
    noshi_voice_encoder *encoder = NULL;
    status = out ? noshi_voice_encoder_new(&encoder, NoshiWriteOgg, out) : NOSHI_E_IO;
    for (size_t at = 0; status == NOSHI_OK && at < count; at += CHUNK_SAMPLES) {
        status = noshi_voice_encoder_feed(encoder, samples + at, MIN((size_t)CHUNK_SAMPLES, count - at));
    }
    if (status == NOSHI_OK) status = noshi_voice_encoder_finish(encoder);
    else noshi_voice_encoder_free(encoder);
    if (out && fclose(out) != 0 && status == NOSHI_OK) status = NOSHI_E_IO;
    if (status == NOSHI_OK) status = noshi_waveform_build(samples, count, waveform.mutableBytes, waveform.length);
    if (status != NOSHI_OK) {
        NSLog(@"noshigram: the voice note was not encoded: %s", noshi_status_name(status));
        [[NSFileManager defaultManager] removeItemAtPath:oggPath error:NULL];
        return NO;
    }
    *durationMs = (int32_t)((uint64_t)count * 1000u / NOSHI_VOICE_RATE);
    return YES;
}

- (void)finishWithCompletion:(void (^)(NSString *, int32_t, NSData *))completion {
    NSTimeInterval length = _recorder.currentTime;
    NSString *wavPath = [_wavPath retain];
    void (^done)(NSString *, int32_t, NSData *) = [completion copy];
    [_recorder stop];
    [_recorder release];
    _recorder = nil;
    [_wavPath release];
    _wavPath = nil;
    [NoshiAudioSession() setActive:NO error:NULL];
    if (!wavPath || length < MIN_SECONDS) {
        if (wavPath) [[NSFileManager defaultManager] removeItemAtPath:wavPath error:NULL];
        [wavPath release];
        done(nil, 0, nil);
        [done release];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *oggPath = NoshiTemporaryPath(@"ogg");
        NSMutableData *waveform = [NSMutableData dataWithLength:NOSHI_WAVEFORM_BYTES];
        int32_t durationMs = 0;
        BOOL ok = NoshiEncode(wavPath, oggPath, &durationMs, waveform);
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:NULL];
        NSData *delivered = [[waveform copy] autorelease];
        NSString *deliveredPath = ok ? [[oggPath copy] autorelease] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            _failed = !ok;
            done(deliveredPath, durationMs, delivered);
            [done release];
            [wavPath release];
        });
        [pool drain];
    });
}

@end

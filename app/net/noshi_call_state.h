#import <Foundation/Foundation.h>

#import "noshi_photo.h"

/* where a one-to-one voice call stands, as the call screen words it */
typedef enum {
    NoshiCallPhaseRequesting,     /* ours: the key parameters and the request are on their way */
    NoshiCallPhaseCalling,        /* ours: the request is in, the callee's phone has not rung yet */
    NoshiCallPhaseRinging,        /* ours: the callee's phone rings */
    NoshiCallPhaseIncoming,       /* theirs: our phone rings */
    NoshiCallPhaseExchanging,     /* the two sides make the key */
    NoshiCallPhaseConnecting,     /* the key is made and the audio connects */
    NoshiCallPhaseActive,         /* talking */
    NoshiCallPhaseReconnecting,   /* the link broke while talking */
    NoshiCallPhaseEnded
} NoshiCallPhase;

/* why a call ended, for the screen and the notice that follows it */
typedef enum {
    NoshiCallEndNone,
    NoshiCallEndHangup,           /* one side hung up after the call began */
    NoshiCallEndDeclined,         /* the callee turned it down */
    NoshiCallEndBusy,
    NoshiCallEndMissed,           /* nobody answered in time */
    NoshiCallEndFailed,           /* the call could not be set up or the link was lost */
    NoshiCallEndOutdated,         /* the other app is too old for calls with this one */
    NoshiCallEndPrivacy           /* the person does not take calls from us */
} NoshiCallEnd;

/* one call as the screens see it; the engine builds a new snapshot at every change; screens never change it */
@interface NoshiCall : NSObject {
    long long _callId;
    long long _peerId;
    NSString *_peerName;
    BOOL _outgoing;
    NoshiCallPhase _phase;
    NoshiCallEnd _end;
    NSArray *_emoji;
    NSTimeInterval _startedAt;
    BOOL _muted;
    int _bars;
    NoshiPhoto *_photo;
    BOOL _video;
    BOOL _cameraOn;
    BOOL _remoteVideo;
    BOOL _remoteMuted;
}
@property (nonatomic, readonly) long long callId;
/* the user on the other end */
@property (nonatomic, readonly) long long peerId;
@property (nonatomic, readonly, copy) NSString *peerName;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) NoshiCallPhase phase;
@property (nonatomic, readonly) NoshiCallEnd end;
/* the four emoji both people read aloud to check the key, empty before the key exists */
@property (nonatomic, readonly, retain) NSArray *emoji;
/* when the audio connected, on the clock of the device; zero before */
@property (nonatomic, readonly) NSTimeInterval startedAt;
@property (nonatomic, readonly) BOOL muted;
/* signal bars from 1 to 4 */
@property (nonatomic, readonly) int bars;
/* the other person's picture when the app knows it, else nil */
@property (nonatomic, retain) NoshiPhoto *photo;
/* the call was asked for with video; the camera of this phone runs; the other phone sends its picture; the other microphone is muted */
@property (nonatomic, assign) BOOL video;
@property (nonatomic, assign) BOOL cameraOn;
@property (nonatomic, assign) BOOL remoteVideo;
@property (nonatomic, assign) BOOL remoteMuted;

- (id)initWithCallId:(long long)callId peerId:(long long)peerId peerName:(NSString *)peerName outgoing:(BOOL)outgoing phase:(NoshiCallPhase)phase
                 end:(NoshiCallEnd)end emoji:(NSArray *)emoji startedAt:(NSTimeInterval)startedAt muted:(BOOL)muted bars:(int)bars;
@end

#import <Foundation/Foundation.h>

#import "noshi_photo.h"

/* where a group call (a voice chat) stands, as its screen words it */
typedef enum {
    NoshiGroupPhaseJoining,       /* the call is looked up and the join request is on its way */
    NoshiGroupPhaseConnecting,    /* the server answered; the media path is not up yet */
    NoshiGroupPhaseActive,        /* in the call */
    NoshiGroupPhaseReconnecting,  /* the path went silent */
    NoshiGroupPhaseEnded
} NoshiGroupPhase;

typedef enum {
    NoshiGroupEndNone,
    NoshiGroupEndLeft,            /* this account left */
    NoshiGroupEndFinished,        /* the call was ended for everybody */
    NoshiGroupEndFailed,          /* it could not be set up, or the path was lost for good */
    NoshiGroupEndNoCall,          /* no voice chat runs in the chat any more */
    NoshiGroupEndUnsupported,     /* an encrypted conference or a live stream, which this app does not join */
    NoshiGroupEndRemoved          /* the server no longer lists this phone in the call */
} NoshiGroupEnd;

/* one member of a call as the screen draws it */
@interface NoshiGroupMember : NSObject {
    long long _peerId;
    int _peerKind;
    uint32_t _source;
    NSString *_name;
    NoshiPhoto *_photo;
    BOOL _muted, _self, _speaking, _canSelfUnmute, _mutedByYou;
    int _volume;
    int _activeDate;
}
@property (nonatomic, readonly) long long peerId;
/* 1 user, 2 chat, 3 channel */
@property (nonatomic, readonly) int peerKind;
/* the ssrc of its audio */
@property (nonatomic, readonly) uint32_t source;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, retain) NoshiPhoto *photo;
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) BOOL isSelf;
@property (nonatomic, readonly) BOOL speaking;
/* the admins let this member unmute itself */
@property (nonatomic, readonly) BOOL canSelfUnmute;
@property (nonatomic, readonly) BOOL mutedByYou;
/* the volume set for this member, in hundredths of a percent, zero for the default */
@property (nonatomic, readonly) int volume;
/* the unix time it last spoke, zero when it has not */
@property (nonatomic, readonly) int activeDate;

- (id)initWithPeerId:(long long)peerId kind:(int)kind source:(uint32_t)source name:(NSString *)name photo:(NoshiPhoto *)photo muted:(BOOL)muted self:(BOOL)isSelf
            speaking:(BOOL)speaking canSelfUnmute:(BOOL)canSelfUnmute mutedByYou:(BOOL)mutedByYou volume:(int)volume activeDate:(int)activeDate;
@end

/* one call as the screens see it; the engine builds a new snapshot at every change and the screens never change it */
@interface NoshiGroupCall : NSObject {
    long long _callId;
    NSString *_title;
    NSString *_chatTitle;
    int _participantsCount;
    NoshiGroupPhase _phase;
    NoshiGroupEnd _end;
    BOOL _muted, _canUnmute, _canManage, _selfSpeaking;
    NSTimeInterval _startedAt;
    NSArray *_members;
    NSString *_error;
}
@property (nonatomic, readonly) long long callId;
@property (nonatomic, readonly, copy) NSString *title;
/* the group or channel the call runs in */
@property (nonatomic, readonly, copy) NSString *chatTitle;
@property (nonatomic, readonly) int participantsCount;
@property (nonatomic, readonly) NoshiGroupPhase phase;
@property (nonatomic, readonly) NoshiGroupEnd end;
/* this phone's microphone is off */
@property (nonatomic, readonly) BOOL muted;
/* the admins allow this account to unmute itself; false while it is muted by them */
@property (nonatomic, readonly) BOOL canUnmute;
/* the account may end the call for everybody and mute others */
@property (nonatomic, readonly) BOOL canManage;
@property (nonatomic, readonly) BOOL selfSpeaking;
/* when the audio connected, on the clock of the device; zero before */
@property (nonatomic, readonly) NSTimeInterval startedAt;
/* NoshiGroupMember items: this account first, then those speaking, then the rest by the time they joined */
@property (nonatomic, readonly, retain) NSArray *members;
/* the reason of a failure for the notice that follows, nil otherwise */
@property (nonatomic, readonly, copy) NSString *error;

- (id)initWithCallId:(long long)callId title:(NSString *)title chatTitle:(NSString *)chatTitle count:(int)count phase:(NoshiGroupPhase)phase end:(NoshiGroupEnd)end
               muted:(BOOL)muted canUnmute:(BOOL)canUnmute canManage:(BOOL)canManage selfSpeaking:(BOOL)selfSpeaking startedAt:(NSTimeInterval)startedAt
             members:(NSArray *)members error:(NSString *)error;
@end

/* what a chat shows about the voice chat that runs in it: the banner above the messages */
@interface NoshiVoiceChat : NSObject {
    long long _callId;
    NSString *_title;
    int _participantsCount;
    BOOL _joinable;
}
@property (nonatomic, readonly) long long callId;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) int participantsCount;
/* this app can join it: not a conference, not a live stream, not scheduled for later */
@property (nonatomic, readonly) BOOL joinable;
- (id)initWithCallId:(long long)callId title:(NSString *)title count:(int)count joinable:(BOOL)joinable;
@end

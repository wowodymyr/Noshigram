#import <Foundation/Foundation.h>

/* the sounds a call makes of itself, those of the original Telegram; main thread only */
typedef enum {
    NoshiCallToneRingback,
    NoshiCallToneConnecting,
    NoshiCallToneBusy,
    NoshiCallToneFailed,
    NoshiCallToneEnded
} NoshiCallTone;

/* starts the tone and stops the one before it; a missing file leaves silence and says so in the log */
void NoshiCallToneStart(NoshiCallTone tone);
void NoshiCallToneStop(void);
/* how long the tone plays, 0 for those that go on until they are stopped */
NSTimeInterval NoshiCallToneDuration(NoshiCallTone tone);

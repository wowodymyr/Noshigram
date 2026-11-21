#import <Foundation/Foundation.h>

#include "noshi_lite_rules.h"

/* the power saving settings: which animations run, the battery level under which none do, smooth transitions and
   the class of the device; main thread only */

extern NSString *const NoshiLiteModeDidChangeNotification;

/* starts reading the battery and applies the smooth transitions setting; once, at launch */
void NoshiLiteModeStart(void);

/* whether the animation of flag runs now: chosen, and not under the power saver */
BOOL NoshiLiteEnabled(uint32_t flag);
void NoshiLiteSetFlag(uint32_t flag, BOOL on);

/* the battery percent under which the power saver applies: 0 never, 100 always */
int NoshiLitePowerSaverLevel(void);
void NoshiLiteSetPowerSaverLevel(int level);
BOOL NoshiLitePowerSaverApplied(void);
/* 0 to 100, or -1 when the device cannot tell */
int NoshiLiteBatteryPercent(void);

/* whether the account has Telegram Premium, which picks the bit of the emoji flags; kept for the next launch */
void NoshiLiteSetPremium(BOOL premium);

/* the animations of the interface that UIKit runs between screens and in its sheets */
BOOL NoshiLiteSmoothTransitions(void);
void NoshiLiteSetSmoothTransitions(BOOL on);

/* the class of the device: the person's choice (0 auto, 1 high, 2 average, 3 low) and what it comes to */
int NoshiLiteClassChoice(void);
void NoshiLiteSetClassChoice(int choice);
noshi_lite_class NoshiLiteClass(void);
noshi_lite_class NoshiLiteMeasuredClass(void);
NSString *NoshiLiteClassName(noshi_lite_class device_class);

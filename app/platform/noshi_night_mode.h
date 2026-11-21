#import <Foundation/Foundation.h>

#include "noshi_night.h"

/* the automatic night theme: at a time of the day, or when the screen is dim, the app puts on its dark theme, and
   takes it off again */

/* posted on the main thread when the person changed the setup */
extern NSString *const NoshiNightModeDidChangeNotification;

noshi_night_config NoshiNightConfig(void);
/* a config that is not valid is not stored */
void NoshiNightSetConfig(noshi_night_config config);

/* the clock, the screen and the system now, as the core takes them: 1 for night, 0 for day, -1 for no opinion */
int NoshiNightDecision(void);

/* whether the system has an appearance of its own the app can follow (ios 13 and later); the choice is offered only where it has */
BOOL NoshiNightSystemAvailable(void);

/* where the phone is, for the schedule by the sun */
void NoshiNightRequestLocation(void (^completion)(BOOL known));
/* whether a place is stored */
BOOL NoshiNightHasLocation(void);

/* looks at the clock and the screen once and, when the setup says the theme should turn, stores the new theme.
   announce posts the theme change so the screens are built again */
BOOL NoshiNightCheck(BOOL announce);

/* starts looking: every half minute, when the app comes to the front and when the brightness changes */
void NoshiNightStart(BOOL (^gate)(void));
void NoshiNightStop(void);

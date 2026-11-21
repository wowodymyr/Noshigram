#import <Foundation/Foundation.h>

#include "noshi_passcode.h"

/* the passcode lock of the app: what is kept of the code, how long a leave may last, and how fast wrong tries are
   let through */

typedef enum {
    NoshiPasscodeResultOK,
    NoshiPasscodeResultWrong,
    NoshiPasscodeResultWait
} NoshiPasscodeResult;

BOOL NoshiPasscodeEnabled(void);
noshi_passcode_type NoshiPasscodeType(void);

/* a fresh salt is made for every code; NO when the code does not fit the type or the system has no random bytes */
BOOL NoshiPasscodeSet(noshi_passcode_type type, NSString *code);
void NoshiPasscodeClear(void);

/* waitSeconds, when given, is how long the lock still refuses tries (after a wrong code or on Wait) */
NoshiPasscodeResult NoshiPasscodeCheck(NSString *code, NSUInteger *waitSeconds);
NSUInteger NoshiPasscodeWaitRemaining(void);

/* seconds away that the app allows before it asks for the code again: 0 never, 1 on every return */
uint32_t NoshiPasscodeAutoLock(void);
void NoshiPasscodeSetAutoLock(uint32_t seconds);

/* the sensor may open the lock in place of the code; it never replaces the code, which stays the way in when the sensor fails, and it goes with the code */
BOOL NoshiPasscodeBiometricEnabled(void);
void NoshiPasscodeSetBiometric(BOOL on);

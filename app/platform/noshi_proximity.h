#import <Foundation/Foundation.h>

/* the proximity sensor, shared by the parts of the app that want the phone's ear: a voice message that follows the
   phone to the earpiece, and a voice message that is recorded while the phone is held up */

/* posted when the phone comes to the ear or leaves it */
extern NSString *const NoshiProximityDidChangeNotification;

/* whether this device has a proximity sensor, found out once by switching it on for a moment; the chat settings offer the ear features only where it has */
BOOL NoshiProximityAvailable(void);
/* NO when the device has no proximity sensor (an iPad, an iPod), and then nothing was started */
BOOL NoshiProximityStart(void);
void NoshiProximityStop(void);
/* something is close to the sensor */
BOOL NoshiProximityNear(void);
/* the phone stands up and down, as it does at the ear, and not flat on a table or a bed, where the sensor can be
   covered too */
BOOL NoshiPhoneIsUpright(void);

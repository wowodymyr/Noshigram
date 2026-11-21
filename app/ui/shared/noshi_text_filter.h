#import <Foundation/Foundation.h>

@class NoshiPhoto;

/* the text of a name or a message with the stacked combining marks ("zalgo") cut down, when the setting is on;
   positions in the text move, so a text that carries entities must not go through it */
NSString *NoshiFilteredText(NSString *text);

/* a number the way a profile shows it, +1 (572) 228-07-71; the digits as they came behind a plus when the dial code list is missing */
NSString *NoshiPhoneDisplay(NSString *phone);

/* the number of the account the way a screen of the account shows it: the number as NoshiPhoneDisplay gives it, or "+" and as many
   bullets when the setting hides it */
NSString *NoshiOwnPhoneText(NSString *phone);

/* the caption and value pairs a profile adds when the setting asks for the id and the data center; the id of the
   person or chat, and the data center its photo lives in (left out when there is no photo, since the data center
   is only known from it) */
NSArray *NoshiIdentityRows(long long peerId, NoshiPhoto *photo);

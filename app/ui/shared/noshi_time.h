#import <Foundation/Foundation.h>

#include "noshi_time_zone.h"

extern NSString *const NoshiTimeDidChangeNotification;

/* display preferences never change message timestamps or the device clock */
int32_t NoshiTimeZoneChoice(void);
void NoshiTimeZoneSetChoice(int32_t minutes);
NSString *NoshiTimeZoneChoiceText(void);
NSString *NoshiTimeZoneOffsetText(int32_t minutes);
NSCalendar *NoshiDisplayCalendar(void);

/* the time of a message the way chat lists show it: the clock today, the weekday within the last week, the short
   date before that */
NSString *NoshiListTimeText(int32_t unixDate);

/* the date a run of messages is filed under in a chat: Today, Yesterday, the weekday within the week, else the date */
NSString *NoshiDayText(int32_t unixDate);

/* "last seen" lines for the contact list */
NSString *NoshiLastSeenText(int presence, int32_t seen);

/* the fullscreen media header includes both its day and local clock */
NSString *NoshiMediaTimeText(int32_t unixDate);

/* the time of day alone, in the short form of the system's language, such as the clock under a bubble */
NSString *NoshiClockText(int32_t unixDate);

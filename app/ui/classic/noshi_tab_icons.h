#import <UIKit/UIKit.h>

/* the pictures of the bottom bar, drawn from the outlines of telegram for ios of the 2014 to 2018 years: the person in a ring,
   the receiver, the two bubbles and the gear, 31 points square in the given color */
typedef enum {
    NoshiTabIconChats,
    NoshiTabIconContacts,
    NoshiTabIconCalls,
    NoshiTabIconSettings
} NoshiTabIcon;

UIImage *NoshiTabIconImage(NoshiTabIcon icon, UIColor *color);

/* fills or strokes an outline written in the few commands those pictures use: M, L and C take absolute points, Z closes and fills,
   S closes and strokes, U strokes without closing */
void NoshiDrawOutline(CGContextRef context, const char *path);

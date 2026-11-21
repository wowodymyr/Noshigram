#import <Foundation/Foundation.h>

/* the filters of AyuMoments that need no server: a list of regular expressions, and the messages of others whose
   text one of them matches are left out of a chat */

NSArray *NoshiAyuRegexList(void);
void NoshiAyuSetRegexList(NSArray *patterns);
/* nil when the pattern compiles, else what is wrong with it */
NSString *NoshiAyuRegexProblem(NSString *pattern);
/* whether the filters are on and one of them matches the text */
BOOL NoshiAyuHidesText(NSString *text);

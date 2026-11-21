#import <Foundation/Foundation.h>

/* logs frame rate drops and the time cells take, to find what slows the chat list; it does nothing unless the user
   default noshigram.perf is set (defaults write <bundle id> noshigram.perf -bool YES over ssh), since its display link
   and sampler cost power */
void NoshiPerfStart(void);
void NoshiPerfRecord(const char *name, double seconds);
double NoshiPerfNow(void);
/* appends a line to Caches/noshigram-perf.log, which can be read over ssh when no usb log is attached */
void NoshiPerfLine(NSString *line);

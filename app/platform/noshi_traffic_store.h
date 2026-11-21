#import <Foundation/Foundation.h>

/* what the app sent and received, kept across launches; main thread only */

typedef struct NoshiTrafficTotals {
    unsigned long long sent[2];         /* 0 Wi-Fi, 1 mobile */
    unsigned long long received[2];
    NSTimeInterval since;               /* when the counting began, or was reset */
} NoshiTrafficTotals;

/* once at launch: names the network the connections run on and flushes the counters every half minute */
void NoshiTrafficStart(void);
/* whether the phone is on the mobile network, which is when no Wi-Fi interface has an address */
BOOL NoshiNetworkOnCellular(void);
/* adds what the sockets counted since the last call to the totals, and says the network class for what follows */
void NoshiTrafficFlush(void);
NoshiTrafficTotals NoshiTrafficRead(void);
void NoshiTrafficReset(void);

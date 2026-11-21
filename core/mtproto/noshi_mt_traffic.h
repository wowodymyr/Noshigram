#ifndef NOSHI_MT_TRAFFIC_H
#define NOSHI_MT_TRAFFIC_H

#include <stdint.h>

/* bytes the connections of the app sent and received, counted where the sockets read and write, apart for Wi-Fi
   and for the mobile network */

typedef struct noshi_traffic {
    uint64_t sent[2];       /* index 0 Wi-Fi, 1 mobile */
    uint64_t received[2];
} noshi_traffic;

/* 0 for Wi-Fi, anything else for the mobile network */
void noshi_traffic_set_cellular(int cellular);
/* adds to the class that is set now */
void noshi_traffic_add(uint64_t sent, uint64_t received);
/* what was counted since the last take, which then starts again from zero */
void noshi_traffic_take(noshi_traffic *out);

#endif

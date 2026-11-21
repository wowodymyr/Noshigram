#ifndef NOSHI_STATUS_H
#define NOSHI_STATUS_H

typedef enum noshi_status {
    NOSHI_OK = 0,
    NOSHI_E_ARG = -1,
    NOSHI_E_MALFORMED = -2,
    NOSHI_E_TRUNCATED = -3,   /* incomplete frames can resume, malformed frames cannot */
    NOSHI_E_UNSUPPORTED = -4,
    NOSHI_E_LIMIT = -5,
    NOSHI_E_NOMEM = -6,
    NOSHI_E_CRYPTO = -7,
    NOSHI_E_SECURITY = -8,
    NOSHI_E_STATE = -9,
    NOSHI_E_TIMEOUT = -10,
    NOSHI_E_IO = -11,
    NOSHI_E_EOF = -12,
    NOSHI_E_RETRY = -13,
    NOSHI_E_NOTFOUND = -14,
    NOSHI_E_RPC = -15,
    NOSHI_E_STORAGE = -16
} noshi_status;

const char *noshi_status_name(noshi_status status);

#endif

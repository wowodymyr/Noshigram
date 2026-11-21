#include "noshi_status.h"

const char *noshi_status_name(noshi_status status) {
    switch (status) {
    case NOSHI_OK: return "ok";
    case NOSHI_E_ARG: return "bad argument";
    case NOSHI_E_MALFORMED: return "malformed input";
    case NOSHI_E_TRUNCATED: return "truncated input";
    case NOSHI_E_UNSUPPORTED: return "unsupported input";
    case NOSHI_E_LIMIT: return "limit exceeded";
    case NOSHI_E_NOMEM: return "out of memory";
    case NOSHI_E_CRYPTO: return "crypto failure";
    case NOSHI_E_SECURITY: return "validation failed";
    case NOSHI_E_STATE: return "wrong state";
    case NOSHI_E_TIMEOUT: return "timeout";
    case NOSHI_E_IO: return "io error";
    case NOSHI_E_EOF: return "end of stream";
    case NOSHI_E_RETRY: return "retry";
    case NOSHI_E_NOTFOUND: return "not found";
    case NOSHI_E_RPC: return "rpc error";
    case NOSHI_E_STORAGE: return "storage error";
    }
    return "unknown status";
}

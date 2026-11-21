#import <Foundation/Foundation.h>

#include "noshi_session_file.h"

/* the session files of one account directory, sealed with a key that belongs to the device. both the main link and
   the media links read and write them through these two calls */

/* NOSHI_E_NOTFOUND when there is no usable file: a missing one, or one that is damaged or sealed with a key
   that is gone (it is deleted then, and a new handshake replaces it). NOSHI_E_STORAGE while the keychain is
   locked before the first unlock, the file is left alone then. a file from before sealing is read and sealed
   again in place */
noshi_status NoshiSessionLoad(NSString *directory, int32_t dc, noshi_mt_session_state *out);
noshi_status NoshiSessionStore(NSString *directory, int32_t dc, const noshi_mt_session_state *state);

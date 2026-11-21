#import <Foundation/Foundation.h>

#include "noshi_status.h"

/* the files the session keeps in its directory: one key file per data center, and the account file */
NSString *NoshiFilePath(NSString *directory, NSString *name);
NSString *NoshiSessionPath(NSString *directory, int32_t dc);
NSString *NoshiAccountPath(NSString *directory);

/* the file is written aside and renamed, so a crash never leaves half of it behind; mode 0600 */
noshi_status NoshiWriteFile(NSString *path, const uint8_t *data, size_t len);
/* a missing file is NOSHI_E_NOTFOUND; buf holds cap bytes and the read stops there, so a caller that
   wants to catch a longer file passes one byte more than it expects */
noshi_status NoshiReadFile(NSString *path, uint8_t *buf, size_t cap, size_t *len);

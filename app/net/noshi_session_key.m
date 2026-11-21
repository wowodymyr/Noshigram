#import "noshi_session_key.h"

#import <Security/Security.h>
#include <string.h>
#include <unistd.h>
#include "noshi_bytes.h"
#include "noshi_files.h"
#include "noshi_random.h"

static NSString *const NoshiSessionKeyService = @"com.noshigram.app.session";

static uint8_t g_key[NOSHI_SESSION_KEY_LEN];
static BOOL g_key_ready;

static NSDictionary *NoshiSessionKeyQuery(void) {
    return [NSDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass,
            NoshiSessionKeyService, (id)kSecAttrService, @"device", (id)kSecAttrAccount, nil];
}

/* kept beside the proxy record, outside the account directories */
static NSString *NoshiSessionKeyFilePath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"session-key"];
}

/* a jailbroken install without the keychain entitlement answers -34018, and none of the other refusals gets better by asking
   again, so the private file holds the key then. a device locked since boot is the one answer that passes by itself: the
   key may sit in the keychain already, and a second one made in the file would seal the sessions with a key that is lost
   at the next unlock */
static BOOL NoshiSessionKeychainLocked(OSStatus result) {
    return result == errSecInteractionNotAllowed;
}

static noshi_status NoshiSessionKeyFromFile(uint8_t key[NOSHI_SESSION_KEY_LEN]) {
    size_t len;
    uint8_t buf[NOSHI_SESSION_KEY_LEN + 1];
    noshi_status status = NoshiReadFile(NoshiSessionKeyFilePath(), buf, sizeof(buf), &len);
    if (status == NOSHI_OK && len != NOSHI_SESSION_KEY_LEN) {
        /* a short key was cut by a crash that the rename should have prevented, and the files sealed by it cannot be read anyway */
        NSLog(@"noshigram: the session key file has %zu bytes, expected %d", len, NOSHI_SESSION_KEY_LEN);
        status = NOSHI_E_MALFORMED;
    }
    if (status == NOSHI_OK) memcpy(key, buf, NOSHI_SESSION_KEY_LEN);
    noshi_wipe(buf, sizeof(buf));
    return status;
}

static noshi_status NoshiSessionKeyToFile(const uint8_t key[NOSHI_SESSION_KEY_LEN]) {
    NSString *path = NoshiSessionKeyFilePath();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: the session key directory could not be created: %@", error);
        return NOSHI_E_STORAGE;
    }
    return NoshiWriteFile(path, key, NOSHI_SESSION_KEY_LEN);
}

/* the cache is filled only from a key that is stored, so a failed write never leaves sessions sealed with a key that exists in memory alone */
static noshi_status NoshiSessionKeyLoad(void) {
    uint8_t key[NOSHI_SESSION_KEY_LEN];
    BOOL keychainRefused = NO;
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:NoshiSessionKeyQuery()];
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    CFTypeRef value = NULL;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef)query, &value);
    if (result == errSecSuccess) {
        NSData *data = [(NSData *)value autorelease];
        if (data.length != NOSHI_SESSION_KEY_LEN) {
            NSLog(@"noshigram: the keychain session key has %lu bytes, expected %d", (unsigned long)data.length, NOSHI_SESSION_KEY_LEN);
            return NOSHI_E_MALFORMED;
        }
        memcpy(g_key, data.bytes, NOSHI_SESSION_KEY_LEN);
        g_key_ready = YES;
        return NOSHI_OK;
    }
    if (NoshiSessionKeychainLocked(result)) return NOSHI_E_STORAGE;
    if (result != errSecItemNotFound) {
        NSLog(@"noshigram: session key keychain read failed: %d", (int)result);
        keychainRefused = YES;
    }

    noshi_status status = NoshiSessionKeyFromFile(key);
    if (status == NOSHI_E_NOTFOUND) {
        status = noshi_random(key, sizeof(key));
        if (status != NOSHI_OK) return status;
        if (!keychainRefused) {
            NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:NoshiSessionKeyQuery()];
            [item setObject:[NSData dataWithBytes:key length:sizeof(key)] forKey:(id)kSecValueData];
            [item setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
            result = SecItemAdd((CFDictionaryRef)item, NULL);
            if (result == errSecSuccess) {
                memcpy(g_key, key, sizeof(key));
                g_key_ready = YES;
                noshi_wipe(key, sizeof(key));
                return NOSHI_OK;
            }
            NSLog(@"noshigram: session key keychain write failed: %d", (int)result);
            if (NoshiSessionKeychainLocked(result)) {
                noshi_wipe(key, sizeof(key));
                return NOSHI_E_STORAGE;
            }
        }
        status = NoshiSessionKeyToFile(key);
    }
    if (status == NOSHI_OK) {
        memcpy(g_key, key, sizeof(key));
        g_key_ready = YES;
    }
    noshi_wipe(key, sizeof(key));
    return status;
}

static noshi_status NoshiSessionKey(uint8_t out[NOSHI_SESSION_KEY_LEN]) {
    noshi_status status = NOSHI_OK;
    @synchronized (NoshiSessionKeyService) {
        if (!g_key_ready) status = NoshiSessionKeyLoad();
        if (status == NOSHI_OK) memcpy(out, g_key, NOSHI_SESSION_KEY_LEN);
    }
    return status;
}

noshi_status NoshiSessionStore(NSString *directory, int32_t dc, const noshi_mt_session_state *state) {
    uint8_t key[NOSHI_SESSION_KEY_LEN];
    uint8_t buf[NOSHI_SESSION_SEALED_LEN];
    size_t len = 0;
    noshi_status status = NoshiSessionKey(key);
    if (status == NOSHI_OK) status = noshi_session_seal(key, dc, state, buf, sizeof(buf), &len);
    if (status == NOSHI_OK) status = NoshiWriteFile(NoshiSessionPath(directory, dc), buf, len);
    noshi_wipe(key, sizeof(key));
    noshi_wipe(buf, sizeof(buf));
    return status;
}

noshi_status NoshiSessionLoad(NSString *directory, int32_t dc, noshi_mt_session_state *out) {
    uint8_t key[NOSHI_SESSION_KEY_LEN];
    uint8_t buf[NOSHI_SESSION_SEALED_LEN + 1];
    size_t len;
    int plain = 0;
    NSString *path = NoshiSessionPath(directory, dc);
    noshi_status status = NoshiReadFile(path, buf, sizeof(buf), &len);
    if (status != NOSHI_OK) return status;
    status = NoshiSessionKey(key);
    if (status != NOSHI_OK) {
        noshi_wipe(buf, sizeof(buf));
        return status;
    }
    status = noshi_session_open(key, buf, len, dc, out, &plain);
    noshi_wipe(key, sizeof(key));
    noshi_wipe(buf, sizeof(buf));
    if (status != NOSHI_OK) {
        /* a damaged key cannot be repaired, a new handshake replaces it */
        NSLog(@"noshigram: session file for dc %d is unusable (%s), starting a new session", (int)dc, noshi_status_name(status));
        unlink(path.fileSystemRepresentation);
        return NOSHI_E_NOTFOUND;
    }
    if (plain) {
        /* the plain file stays readable until the sealed one is in place, a failed write loses nothing */
        noshi_status sealed = NoshiSessionStore(directory, dc, out);
        if (sealed != NOSHI_OK) NSLog(@"noshigram: session file for dc %d was not sealed: %s", (int)dc, noshi_status_name(sealed));
    }
    return NOSHI_OK;
}

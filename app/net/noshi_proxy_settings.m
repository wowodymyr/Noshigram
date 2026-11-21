#import "noshi_proxy_settings.h"

#import <Security/Security.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "noshi_clock.h"
#include "noshi_bytes.h"
#include "noshi_mt_traffic.h"
#import "noshi_traffic_store.h"

NSString *const NoshiProxyDidChangeNotification = @"NoshiProxyDidChange";
static NSString *const NoshiProxyEnabledKey = @"noshigram.proxy.enabled";
static NSString *const NoshiProxyService = @"com.noshigram.app.proxy";
#define PROXY_LIST_MAX 64
#define PROXY_DATA_MAX (256u * 1024u)

static NSDictionary *NoshiProxyQuery(void) {
    return [NSDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass,
            NoshiProxyService, (id)kSecAttrService, @"selected", (id)kSecAttrAccount, nil];
}

static noshi_status NoshiProxyDecode(NSString *text, noshi_proxy *proxy) {
    if (![text isKindOfClass:[NSString class]] || !text.length || !proxy) return NOSHI_E_ARG;
    noshi_tg_link link;
    noshi_status status = noshi_tg_link_parse(text.UTF8String, &link);
    if (status == NOSHI_OK) status = noshi_proxy_from_link(&link, proxy);
    noshi_wipe(&link, sizeof(link));
    return status;
}

static NSString *NoshiProxyFilePath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"proxy-link"];
}

/* a jailbroken install without the keychain entitlement answers -34018, and other builds answer with other codes (a missing keychain, a refused access group, a read-only
   store): none of those gets better by asking again, so the private file takes the record. a locked device is the one answer that passes by itself, and the keychain
   keeps the record then, so it is an error and not a reason to start a second copy in the file */
static BOOL NoshiProxyKeychainLocked(OSStatus result) {
    return result == errSecInteractionNotAllowed;
}

/* the jailbreak build may lack a keychain entitlement; the private file keeps the same complete record */
static noshi_status NoshiProxyReadData(NSData **out, BOOL *fileBacked) {
    *out = nil;
    *fileBacked = NO;
    NSString *path = NoshiProxyFilePath();
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (attributes) {
        if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > PROXY_DATA_MAX) return NOSHI_E_LIMIT;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return NOSHI_E_STORAGE;
        *out = data;
        *fileBacked = YES;
        return NOSHI_OK;
    }
    if (error && !([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError))) return NOSHI_E_STORAGE;
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:NoshiProxyQuery()];
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    CFTypeRef value = NULL;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef)query, &value);
    if (result == errSecItemNotFound) return NOSHI_E_NOTFOUND;
    if (result != errSecSuccess) {
        NSLog(@"noshigram: proxy keychain read failed: %d", (int)result);
        return NoshiProxyKeychainLocked(result) ? NOSHI_E_STORAGE : NOSHI_E_UNSUPPORTED;
    }
    NSData *data = [(NSData *)value autorelease];
    if (data.length > PROXY_DATA_MAX) return NOSHI_E_LIMIT;
    *out = data;
    return NOSHI_OK;
}

static noshi_status NoshiProxyLoad(NSMutableArray **links, NSUInteger *selected, BOOL *fileBacked) {
    NSData *data = nil;
    *links = nil;
    *selected = 0;
    noshi_status status = NoshiProxyReadData(&data, fileBacked);
    if (status != NOSHI_OK) return status;
    NSString *legacy = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    noshi_proxy proxy;
    if (legacy && NoshiProxyDecode(legacy, &proxy) == NOSHI_OK) {
        noshi_wipe(&proxy, sizeof(proxy));
        *links = [NSMutableArray arrayWithObject:legacy];
        return NOSHI_OK;
    }
    noshi_wipe(&proxy, sizeof(proxy));
    NSError *error = nil;
    id record = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (![record isKindOfClass:[NSDictionary class]] || ![[record objectForKey:@"version"] isKindOfClass:[NSNumber class]] ||
        [[record objectForKey:@"version"] integerValue] != 1 || ![[record objectForKey:@"links"] isKindOfClass:[NSArray class]] ||
        ![[record objectForKey:@"selected"] isKindOfClass:[NSNumber class]]) return NOSHI_E_MALFORMED;
    NSArray *saved = [record objectForKey:@"links"];
    long long index = [[record objectForKey:@"selected"] longLongValue];
    if (saved.count > PROXY_LIST_MAX || index < 0 || (saved.count ? (unsigned long long)index >= saved.count : index != 0)) return NOSHI_E_MALFORMED;
    for (id text in saved) {
        status = NoshiProxyDecode(text, &proxy);
        noshi_wipe(&proxy, sizeof(proxy));
        if (status != NOSHI_OK) return NOSHI_E_MALFORMED;
    }
    *links = [NSMutableArray arrayWithArray:saved];
    *selected = (NSUInteger)index;
    return NOSHI_OK;
}

static BOOL NoshiProxyWriteFile(NSData *data) {
    NSString *path = NoshiProxyFilePath();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: proxy directory could not be created: %@", error);
        return NO;
    }
    char *temporary = strdup([[path stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]);
    if (!temporary) return NO;
    int fd = mkstemp(temporary);
    BOOL ok = fd >= 0;
    const uint8_t *bytes = data.bytes;
    size_t left = data.length;
    while (ok && left) {
        ssize_t written = write(fd, bytes, left);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { ok = NO; break; }
        bytes += written;
        left -= (size_t)written;
    }
    if (fd >= 0 && close(fd) != 0) ok = NO;
    if (ok && rename(temporary, path.fileSystemRepresentation) != 0) ok = NO;
    if (!ok) { NSLog(@"noshigram: proxy file could not be written: %s", strerror(errno)); unlink(temporary); }
    free(temporary);
    return ok;
}

static noshi_status NoshiProxySave(NSArray *links, NSUInteger selected, BOOL fileBacked) {
    NSDictionary *record = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"version", links, @"links",
                            [NSNumber numberWithUnsignedInteger:selected], @"selected", nil];
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || data.length > PROXY_DATA_MAX) return NOSHI_E_STORAGE;
    if (fileBacked) return NoshiProxyWriteFile(data) ? NOSHI_OK : NOSHI_E_STORAGE;
    NSDictionary *query = NoshiProxyQuery();
    NSDictionary *update = [NSDictionary dictionaryWithObject:data forKey:(id)kSecValueData];
    OSStatus result = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
    if (result == errSecItemNotFound) {
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:query];
        [item addEntriesFromDictionary:update];
        [item setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
        result = SecItemAdd((CFDictionaryRef)item, NULL);
    }
    if (result != errSecSuccess) {
        NSLog(@"noshigram: proxy keychain write failed: %d", (int)result);
        if (!NoshiProxyKeychainLocked(result) && NoshiProxyWriteFile(data)) return NOSHI_OK;
        return NOSHI_E_STORAGE;
    }
    return NOSHI_OK;
}

static noshi_status NoshiProxyReadLocked(noshi_proxy *proxy) {
    NSMutableArray *links;
    NSUInteger selected;
    BOOL fileBacked;
    noshi_status status = NoshiProxyLoad(&links, &selected, &fileBacked);
    if (status != NOSHI_OK) return status;
    return links.count ? NoshiProxyDecode([links objectAtIndex:selected], proxy) : NOSHI_E_NOTFOUND;
}

noshi_status NoshiProxyRead(noshi_proxy *proxy, BOOL *enabled) {
    if (!proxy || !enabled) return NOSHI_E_ARG;
    memset(proxy, 0, sizeof(*proxy));
    @synchronized (NoshiProxyService) {
        *enabled = [[NSUserDefaults standardUserDefaults] boolForKey:NoshiProxyEnabledKey];
        return *enabled ? NoshiProxyReadLocked(proxy) : NOSHI_OK;
    }
}

noshi_status NoshiProxyStoreLink(NSString *text) {
    noshi_proxy proxy;
    noshi_status status = NoshiProxyDecode(text, &proxy);
    noshi_wipe(&proxy, sizeof(proxy));
    if (status != NOSHI_OK) return status;
    @synchronized (NoshiProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        status = NoshiProxyLoad(&links, &selected, &fileBacked);
        if (status == NOSHI_E_NOTFOUND || status == NOSHI_E_UNSUPPORTED) {
            links = [NSMutableArray array];
            selected = 0;
            fileBacked = status == NOSHI_E_UNSUPPORTED;
        } else if (status != NOSHI_OK) return status;
        NSUInteger index = [links indexOfObject:text];
        if (index == NSNotFound) {
            if (links.count >= PROXY_LIST_MAX) return NOSHI_E_LIMIT;
            [links addObject:text];
            index = links.count - 1;
        }
        status = NoshiProxySave(links, index, fileBacked);
        if (status != NOSHI_OK) return status;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:NoshiProxyEnabledKey];
        if (![[NSUserDefaults standardUserDefaults] synchronize]) return NOSHI_E_STORAGE;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiProxyDidChangeNotification object:nil];
    return NOSHI_OK;
}

noshi_status NoshiProxyList(NSArray **entries) {
    if (!entries) return NOSHI_E_ARG;
    *entries = nil;
    @synchronized (NoshiProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        noshi_status status = NoshiProxyLoad(&links, &selected, &fileBacked);
        if (status == NOSHI_E_NOTFOUND || status == NOSHI_E_UNSUPPORTED) { *entries = [NSArray array]; return NOSHI_OK; }
        if (status != NOSHI_OK) return status;
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:links.count];
        for (NSUInteger i = 0; i < links.count; ++i) {
            noshi_proxy proxy;
            status = NoshiProxyDecode([links objectAtIndex:i], &proxy);
            if (status != NOSHI_OK) { noshi_wipe(&proxy, sizeof(proxy)); return status; }
            NSString *address = [NSString stringWithFormat:@"%s:%u (%@)", proxy.server, (unsigned)proxy.port, proxy.kind == NOSHI_PROXY_MTPROTO ? @"MTProto" : @"SOCKS5"];
            noshi_wipe(&proxy, sizeof(proxy));
            [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:address, @"address", [NSNumber numberWithBool:i == selected], @"selected", nil]];
        }
        *entries = list;
        return NOSHI_OK;
    }
}

static noshi_status NoshiProxyChange(NSUInteger index, BOOL remove) {
    @synchronized (NoshiProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        noshi_status status = NoshiProxyLoad(&links, &selected, &fileBacked);
        if (status != NOSHI_OK) return status;
        if (index >= links.count) return NOSHI_E_ARG;
        if (remove) {
            [links removeObjectAtIndex:index];
            if (index < selected) --selected;
            else if (selected >= links.count) selected = links.count ? links.count - 1 : 0;
        } else selected = index;
        status = NoshiProxySave(links, selected, fileBacked);
        if (status != NOSHI_OK) return status;
        if (!remove || !links.count) {
            [[NSUserDefaults standardUserDefaults] setBool:!remove forKey:NoshiProxyEnabledKey];
            if (![[NSUserDefaults standardUserDefaults] synchronize]) return NOSHI_E_STORAGE;
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiProxyDidChangeNotification object:nil];
    return NOSHI_OK;
}

noshi_status NoshiProxySelect(NSUInteger index) { return NoshiProxyChange(index, NO); }
noshi_status NoshiProxyRemove(NSUInteger index) { return NoshiProxyChange(index, YES); }

noshi_status NoshiProxySetEnabled(BOOL enabled) {
    @synchronized (NoshiProxyService) {
        if (enabled) {
            noshi_proxy proxy;
            noshi_status status = NoshiProxyReadLocked(&proxy);
            noshi_wipe(&proxy, sizeof(proxy));
            if (status != NOSHI_OK) return status;
        }
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:NoshiProxyEnabledKey];
        if (![[NSUserDefaults standardUserDefaults] synchronize]) return NOSHI_E_STORAGE;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiProxyDidChangeNotification object:nil];
    return NOSHI_OK;
}

NSString *NoshiProxyDisplay(void) {
    noshi_proxy proxy;
    BOOL enabled = NO;
    noshi_status status = NoshiProxyRead(&proxy, &enabled);
    NSString *text = status == NOSHI_OK && enabled ? [NSString stringWithFormat:@"%s:%u", proxy.server, (unsigned)proxy.port] : nil;
    noshi_wipe(&proxy, sizeof(proxy));
    return text;
}

static noshi_status NoshiConnectDirect(noshi_mt_socket *socket, const char *host, uint16_t port, int timeout) {
    /* what the new connection carries is counted for the network it was opened on */
    noshi_traffic_set_cellular(NoshiNetworkOnCellular());
    return noshi_mt_socket_connect(socket, host, port, timeout);
}

noshi_status NoshiProxyConnect(noshi_mt_socket *socket, const char *host, uint16_t port, int timeout, noshi_mt_client_config *config) {
    noshi_proxy proxy;
    BOOL enabled = NO;
    noshi_status status = NoshiProxyRead(&proxy, &enabled);
    if (status != NOSHI_OK) return status;
    config->transport = NOSHI_MT_INTERMEDIATE;
    config->obfuscation.has_secret = 0;
    memset(config->obfuscation.secret, 0, sizeof(config->obfuscation.secret));
    if (!enabled) return NoshiConnectDirect(socket, host, port, timeout);
    uint64_t deadline = noshi_system_clock.monotonic_ms(NULL) + (uint64_t)timeout;
    status = NoshiConnectDirect(socket, proxy.server, proxy.port, timeout);
    uint64_t now = noshi_system_clock.monotonic_ms(NULL);
    int left = now < deadline ? (int)(deadline - now) : 0;
    if (status == NOSHI_OK && !left) { noshi_mt_socket_close(socket); status = NOSHI_E_TIMEOUT; }
    if (status == NOSHI_OK && proxy.kind == NOSHI_PROXY_SOCKS5)
        status = noshi_mt_socket_negotiate_socks5(socket, proxy.user[0] ? proxy.user : NULL,
                    proxy.user[0] ? proxy.password : NULL, host, port, left);
    if (status == NOSHI_OK && proxy.kind == NOSHI_PROXY_MTPROTO) {
        if (proxy.tls_domain[0]) status = noshi_mt_socket_start_faketls(socket, proxy.secret, proxy.tls_domain, left);
        if (status == NOSHI_OK) {
            config->transport = proxy.padded ? NOSHI_MT_PADDED_INTERMEDIATE : NOSHI_MT_INTERMEDIATE;
            config->obfuscation.has_secret = 1;
            memcpy(config->obfuscation.secret, proxy.secret, sizeof(proxy.secret));
        }
    }
    noshi_wipe(&proxy, sizeof(proxy));
    return status;
}

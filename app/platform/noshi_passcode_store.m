#import "noshi_passcode_store.h"

#include "noshi_random.h"

static NSString *const NoshiPasscodeHashKey = @"noshigram.passcode.hash";
static NSString *const NoshiPasscodeSaltKey = @"noshigram.passcode.salt";
static NSString *const NoshiPasscodeTypeKey = @"noshigram.passcode.type";
static NSString *const NoshiPasscodeAutoLockKey = @"noshigram.passcode.autolock";
static NSString *const NoshiPasscodeBiometricKey = @"noshigram.passcode.biometric";
static NSString *const NoshiPasscodeFailuresKey = @"noshigram.passcode.failures";
static NSString *const NoshiPasscodeUntilKey = @"noshigram.passcode.until";

/* the default: an hour away */
#define AUTO_LOCK_DEFAULT 3600
#define WAIT_MAX_SECONDS 300

static NSData *NoshiPasscodeSalt(void) {
    NSData *salt = [[NSUserDefaults standardUserDefaults] dataForKey:NoshiPasscodeSaltKey];
    return salt.length == NOSHI_PASSCODE_SALT_LEN ? salt : nil;
}

BOOL NoshiPasscodeEnabled(void) {
    NSString *hash = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiPasscodeHashKey];
    return hash.length == NOSHI_PASSCODE_HEX_LEN && NoshiPasscodeSalt() != nil;
}

noshi_passcode_type NoshiPasscodeType(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:NoshiPasscodeTypeKey] == NOSHI_PASSCODE_PASSWORD ? NOSHI_PASSCODE_PASSWORD : NOSHI_PASSCODE_PIN;
}

BOOL NoshiPasscodeSet(noshi_passcode_type type, NSString *code) {
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || !noshi_passcode_valid(type, bytes.bytes, bytes.length)) return NO;
    uint8_t salt[NOSHI_PASSCODE_SALT_LEN];
    char hex[NOSHI_PASSCODE_HEX_LEN + 1];
    if (noshi_random(salt, sizeof(salt)) != NOSHI_OK || noshi_passcode_hash(salt, bytes.bytes, bytes.length, hex) != NOSHI_OK) {
        NSLog(@"noshigram: the passcode could not be hashed");
        return NO;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSString stringWithUTF8String:hex] forKey:NoshiPasscodeHashKey];
    [defaults setObject:[NSData dataWithBytes:salt length:sizeof(salt)] forKey:NoshiPasscodeSaltKey];
    [defaults setInteger:type forKey:NoshiPasscodeTypeKey];
    [defaults removeObjectForKey:NoshiPasscodeFailuresKey];
    [defaults removeObjectForKey:NoshiPasscodeUntilKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the passcode was not saved");
    return YES;
}

void NoshiPasscodeClear(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:NoshiPasscodeHashKey];
    [defaults removeObjectForKey:NoshiPasscodeSaltKey];
    [defaults removeObjectForKey:NoshiPasscodeTypeKey];
    [defaults removeObjectForKey:NoshiPasscodeBiometricKey];
    [defaults removeObjectForKey:NoshiPasscodeFailuresKey];
    [defaults removeObjectForKey:NoshiPasscodeUntilKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the removal of the passcode was not saved");
}

NSUInteger NoshiPasscodeWaitRemaining(void) {
    double until = [[NSUserDefaults standardUserDefaults] doubleForKey:NoshiPasscodeUntilKey];
    double left = until - [[NSDate date] timeIntervalSince1970];
    /* a clock set back must not stretch the wait past its longest step */
    if (left <= 0) return 0;
    return (NSUInteger)MIN(ceil(left), (double)WAIT_MAX_SECONDS);
}

NoshiPasscodeResult NoshiPasscodeCheck(NSString *code, NSUInteger *waitSeconds) {
    if (waitSeconds) *waitSeconds = 0;
    NSUInteger remaining = NoshiPasscodeWaitRemaining();
    if (remaining > 0) {
        if (waitSeconds) *waitSeconds = remaining;
        return NoshiPasscodeResultWait;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *salt = NoshiPasscodeSalt();
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [defaults stringForKey:NoshiPasscodeHashKey];
    if (salt && bytes && hash && noshi_passcode_matches(salt.bytes, bytes.bytes, bytes.length, hash.UTF8String)) {
        [defaults removeObjectForKey:NoshiPasscodeFailuresKey];
        [defaults removeObjectForKey:NoshiPasscodeUntilKey];
        return NoshiPasscodeResultOK;
    }
    NSInteger failures = [defaults integerForKey:NoshiPasscodeFailuresKey] + 1;
    uint32_t wait = noshi_passcode_wait_seconds((uint32_t)MIN(failures, (NSInteger)INT32_MAX));
    [defaults setInteger:failures forKey:NoshiPasscodeFailuresKey];
    if (wait > 0) [defaults setDouble:[[NSDate date] timeIntervalSince1970] + wait forKey:NoshiPasscodeUntilKey];
    /* the count must survive a kill of the app, or restarting it would give four more tries each time */
    if (![defaults synchronize]) NSLog(@"noshigram: the count of wrong passcodes was not saved");
    if (waitSeconds) *waitSeconds = wait;
    return NoshiPasscodeResultWrong;
}

uint32_t NoshiPasscodeAutoLock(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:NoshiPasscodeAutoLockKey];
    return stored ? (uint32_t)MAX(0, [stored integerValue]) : AUTO_LOCK_DEFAULT;
}

void NoshiPasscodeSetAutoLock(uint32_t seconds) {
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)seconds forKey:NoshiPasscodeAutoLockKey];
}

BOOL NoshiPasscodeBiometricEnabled(void) {
    return NoshiPasscodeEnabled() && [[NSUserDefaults standardUserDefaults] boolForKey:NoshiPasscodeBiometricKey];
}

void NoshiPasscodeSetBiometric(BOOL on) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:on forKey:NoshiPasscodeBiometricKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the biometric choice was not saved");
}

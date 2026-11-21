#import "noshi_text_filter.h"

#import "noshi_chat_settings.h"
#import "noshi_photo.h"

#include "noshi_phone.h"
#include "noshi_zalgo.h"

NSString *NoshiFilteredText(NSString *text) {
    if (!text.length || !NoshiChatFlagGet(NoshiChatFlagFilterZalgo)) return text;
    const char *bytes = text.UTF8String;
    if (!bytes) return text;
    size_t size = strlen(bytes) + 1;
    char *buffer = malloc(size);
    if (!buffer) return text;
    NSString *result = text;
    size_t written = noshi_zalgo_filter(bytes, buffer, size);
    if (written != (size_t)-1 && written < size - 1) {
        NSString *filtered = [NSString stringWithUTF8String:buffer];
        if (filtered) result = filtered;
    }
    free(buffer);
    return result;
}

/* the dial code table is read once, from the list the phone screens share; nothing is grouped when the list does not load */
static const noshi_country *NoshiPhoneCountries(size_t *count) {
    static noshi_country *table = NULL;
    static size_t tableCount = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"countries" ofType:@"txt"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        noshi_country *made = calloc(NOSHI_COUNTRY_MAX, sizeof(noshi_country));
        noshi_status status = data && made ? noshi_country_parse(data.bytes, data.length, made, NOSHI_COUNTRY_MAX, &tableCount) : NOSHI_E_NOTFOUND;
        if (status != NOSHI_OK) {
            NSLog(@"noshigram: country list for phone numbers did not load (%s)", noshi_status_name(status));
            free(made);
            tableCount = 0;
            return;
        }
        table = made;
    });
    *count = tableCount;
    return table;
}

NSString *NoshiPhoneDisplay(NSString *phone) {
    if (!phone.length) return @"";
    char digits[NOSHI_PHONE_MAX_DIGITS + 1];
    char shown[64];
    size_t count = 0;
    const noshi_country *table = NoshiPhoneCountries(&count);
    if (!noshi_phone_digits(phone.UTF8String, digits, sizeof(digits)) || !table ||
        noshi_phone_display(table, count, digits, shown, sizeof(shown)) != NOSHI_OK) {
        return [@"+" stringByAppendingString:phone];
    }
    return [NSString stringWithUTF8String:shown];
}

NSString *NoshiOwnPhoneText(NSString *phone) {
    if (!phone.length) return @"";
    if (!NoshiChatFlagGet(NoshiChatFlagHidePhone)) return NoshiPhoneDisplay(phone);
    return [@"+" stringByAppendingString:[@"" stringByPaddingToLength:phone.length withString:@"•" startingAtIndex:0]];
}

NSArray *NoshiIdentityRows(long long peerId, NoshiPhoto *photo) {
    NSMutableArray *rows = [NSMutableArray array];
    if (!NoshiChatFlagGet(NoshiChatFlagShowIds) || peerId <= 0) return rows;
    [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.id", nil), [NSString stringWithFormat:@"%lld", peerId], nil]];
    if (photo && photo.ref.dc > 0) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"profile.dc", nil), [NSString stringWithFormat:@"%d", (int)photo.ref.dc], nil]];
    return rows;
}

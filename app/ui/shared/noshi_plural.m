#import "noshi_plural.h"

#import "noshi_language.h"

NSString *NoshiPluralForm(NSInteger count) {
    if ([NoshiInterfaceLanguage() isEqualToString:@"ru"]) {
        NSInteger tail = count % 100, last = count % 10;
        if (tail >= 11 && tail <= 14) return @"other";
        if (last == 1) return @"one";
        if (last >= 2 && last <= 4) return @"few";
        return @"other";
    }
    return count == 1 ? @"one" : @"other";
}

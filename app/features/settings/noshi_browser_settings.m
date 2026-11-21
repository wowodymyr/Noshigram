#import "noshi_browser_settings.h"

static NSString *const BrowserKey = @"noshigram.browser.choice";

NSString *NoshiBrowserChoice(void) {
    NSString *choice = [[NSUserDefaults standardUserDefaults] stringForKey:BrowserKey];
    if ([choice isEqualToString:@"safari"] || [choice isEqualToString:@"chrome"] || [choice isEqualToString:@"firefox"] || [choice isEqualToString:@"brave"]) return choice;
    return @"noshigram";
}

BOOL NoshiBrowserOpenExternal(NSURL *url, NSString *choice) {
    NSString *scheme = [url.scheme lowercaseString];
    if ((! [scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) || !url.host.length) return NO;
    NSURL *target = url;
    if ([choice isEqualToString:@"chrome"]) {
        NSString *prefix = [scheme isEqualToString:@"https"] ? @"googlechromes" : @"googlechrome";
        target = [NSURL URLWithString:[prefix stringByAppendingString:[url.absoluteString substringFromIndex:scheme.length]]];
    } else if ([choice isEqualToString:@"firefox"] || [choice isEqualToString:@"brave"]) {
        CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)url.absoluteString, NULL,
            CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8);
        if (!escaped) return NO;
        NSString *address = [NSString stringWithFormat:@"%@://open-url?url=%@", choice, (NSString *)escaped];
        CFRelease(escaped);
        target = [NSURL URLWithString:address];
    } else if (![choice isEqualToString:@"safari"]) return NO;
    return target && [[UIApplication sharedApplication] openURL:target];
}

NoshiSettingsSection *NoshiBrowserChoiceSection(void (^changed)(void)) {
    void (^done)(void) = [[changed copy] autorelease];
    NSString *choice = NoshiBrowserChoice();
    NSArray *names = [NSArray arrayWithObjects:@"noshigram", @"safari", @"chrome", @"firefox", @"brave", nil];
    NSArray *labels = [NSArray arrayWithObjects:@"Noshigram", NSLocalizedString(@"browser.settings.system", nil), @"Google Chrome", @"Firefox", @"Brave", nil];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; ++i) {
        NSString *name = [names objectAtIndex:i];
        NSString *probe = [name isEqualToString:@"chrome"] ? @"googlechrome://" : [NSString stringWithFormat:@"%@://", name];
        if (i > 1 && ![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:probe]] && ![choice isEqualToString:name]) continue;
        [rows addObject:[NoshiSettingsRow checkRowWithTitle:[labels objectAtIndex:i] subtitle:nil checked:[choice isEqualToString:name] tap:^{
            [[NSUserDefaults standardUserDefaults] setObject:name forKey:BrowserKey];
            if (done) done();
        }]];
    }
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"browser.settings.default", nil) footer:NSLocalizedString(@"browser.settings.system.info", nil) rows:rows];
}

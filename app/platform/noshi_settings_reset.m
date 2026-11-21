#import "noshi_settings_reset.h"

#import "noshi_chat_settings.h"
#import "noshi_language.h"
#import "noshi_theme.h"

void NoshiResetSettings(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    NSUInteger removed = 0;
    for (NSString *key in [all allKeys]) {
        if ([key rangeOfString:@"noshigram" options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == NSNotFound) continue;
        /* the list of the signed in accounts and the traffic counted so far are data of the phone, not choices of the person; a reset that dropped the passcode
           would open the lock to anyone who holds the phone */
        if ([key hasPrefix:@"noshigram.account"] || [key hasPrefix:@"noshigram.traffic"] || [key hasPrefix:@"noshigram.report"] || [key hasPrefix:@"noshigram.passcode"]) continue;
        [defaults removeObjectForKey:key];
        ++removed;
    }
    if (![defaults synchronize]) NSLog(@"noshigram: the reset of the settings was not saved");
    NSLog(@"noshigram: %lu stored settings were reset", (unsigned long)removed);
    /* values the settings keep in memory for the drawing of every avatar and card */
    NoshiChatSettingsForgetCached();
    NoshiApplyInterfaceLanguage();
    NoshiThemeApplyStored();
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiLanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiChatSettingsDidChangeNotification object:nil];
}

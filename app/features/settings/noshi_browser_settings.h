#import "noshi_settings_kit.h"

/* web links keep Telegram routing separate from the chosen browser */
NSString *NoshiBrowserChoice(void);
BOOL NoshiBrowserOpenExternal(NSURL *url, NSString *choice);

/* the rows of the choice among the browsers that are installed; changed runs after a pick so the page can draw the check again */
NoshiSettingsSection *NoshiBrowserChoiceSection(void (^changed)(void));

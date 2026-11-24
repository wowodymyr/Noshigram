#import "noshi_settings_kit.h"
#import "noshi_weak_reference.h"

/* the settings the client adds to those of telegram, each in the standard page it belongs to; weak names that page, which every row asks to rebuild
   itself after a change and uses to show a menu or push a page */

/* Language: the translation of messages, and how times and numbers are written */
NoshiSettingsSection *NoshiTranslateSettingsSection(NoshiWeakReference *weak);
NoshiSettingsSection *NoshiFormatSettingsSection(NoshiWeakReference *weak);

/* Chat Settings */
/* the rows of the chat list beyond its two looks: stories, search, the title, the pictures of senders and the archive */
NSArray *NoshiChatListExtraRows(NoshiWeakReference *weak);
/* playback beyond the original: the step of the seek, what pauses when the app goes down, the camera tile and the sound and quality of videos */
NSArray *NoshiPlaybackExtraRows(NoshiWeakReference *weak);
NoshiSettingsSection *NoshiMessagesSettingsSection(NoshiWeakReference *weak);
NoshiSettingsSection *NoshiPremiumElementsSection(void);
NoshiSettingsSection *NoshiMessageMenuSection(void);
NoshiSettingsSection *NoshiResetSettingsSection(NoshiWeakReference *weak);

/* Stickers: their size, time and shape in a chat */
NSArray *NoshiStickerLookRows(NoshiWeakReference *weak);

/* Folders: the look of the tabs */
NoshiSettingsSection *NoshiFolderTabsSection(NoshiWeakReference *weak);

/* Privacy: what profiles show on this phone, and the questions before what cannot be taken back */
NoshiSettingsSection *NoshiProfileDisplaySection(void);
NoshiSettingsSection *NoshiConfirmSettingsSection(NoshiWeakReference *weak);

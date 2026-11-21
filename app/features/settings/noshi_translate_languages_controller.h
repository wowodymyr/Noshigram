#import "noshi_settings_kit.h"

typedef enum {
    /* one language to translate into, or the language of the app */
    NoshiTranslateLanguagesTarget,
    /* the languages that get no Translate button */
    NoshiTranslateLanguagesSkipped
} NoshiTranslateLanguagesMode;

/* a list of the languages a translator knows, searchable; in the target mode a tap picks the language and leaves */
@interface NoshiTranslateLanguagesController : NoshiSettingsPageController

- (id)initWithMode:(NoshiTranslateLanguagesMode)mode;

@end

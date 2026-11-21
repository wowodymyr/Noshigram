#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

typedef enum {
    NoshiStickerCatalogFeatured,
    NoshiStickerCatalogArchived,
    NoshiStickerCatalogEmoji
} NoshiStickerCatalogKind;

/* a list of sticker sets of the Stickers and Emoji screen */
@interface NoshiStickerCatalogController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media kind:(NoshiStickerCatalogKind)kind;

@end

#import "noshi_star_gift.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *NoshiUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation NoshiStarGift

@synthesize row = _gift;
@synthesize title = _title;
@synthesize slug = _slug;
@synthesize model = _model;
@synthesize pattern = _pattern;
@synthesize backdrop = _backdrop;
@synthesize ownerName = _ownerName;
@synthesize sticker = _sticker;
@synthesize patternSticker = _patternSticker;

+ (NoshiStarGift *)giftWithRow:(const noshi_gift *)row {
    NoshiStarGift *gift = [[[NoshiStarGift alloc] init] autorelease];
    gift->_gift = *row;
    gift->_title = [NoshiUtf8(row->title) copy];
    gift->_slug = [NoshiUtf8(row->slug) copy];
    gift->_model = [NoshiUtf8(row->model) copy];
    gift->_pattern = [NoshiUtf8(row->pattern) copy];
    gift->_backdrop = [NoshiUtf8(row->backdrop) copy];
    gift->_ownerName = [NoshiUtf8(row->owner_name) copy];
    gift->_sticker = [[NoshiMedia mediaWithInfo:&row->sticker] retain];
    if (row->pattern_sticker.ref.source != NOSHI_MEDIA_SOURCE_NONE) gift->_patternSticker = [[NoshiMedia mediaWithInfo:&row->pattern_sticker] retain];
    return gift;
}

- (void)dealloc {
    [_title release];
    [_slug release];
    [_model release];
    [_pattern release];
    [_backdrop release];
    [_ownerName release];
    [_sticker release];
    [_patternSticker release];
    [super dealloc];
}

- (long long)giftId { return _gift.unique ? _gift.catalog_id : _gift.id; }
- (BOOL)unique { return _gift.unique; }
- (BOOL)limited { return _gift.limited; }
- (BOOL)soldOut { return _gift.sold_out; }
- (BOOL)birthday { return _gift.birthday; }
- (BOOL)requiresPremium { return _gift.require_premium; }
- (BOOL)auction { return _gift.auction; }
- (BOOL)canBuy { return !_gift.unique && !_gift.sold_out && !_gift.auction; }
- (long long)stars { return _gift.stars; }
- (long long)convertStars { return _gift.convert_stars; }
- (long long)upgradeStars { return _gift.upgrade_stars; }
- (int32_t)remains { return _gift.remains; }
- (int32_t)total { return _gift.total; }
- (int32_t)number { return _gift.num; }
- (long long)ownerId { return _gift.owner_id; }
- (BOOL)hasBackdropColors { return _gift.has_backdrop; }
- (uint32_t)backdropCenter { return _gift.backdrop_center; }
- (uint32_t)backdropEdge { return _gift.backdrop_edge; }
- (uint32_t)backdropText { return _gift.backdrop_text; }
- (uint32_t)backdropPattern { return _gift.backdrop_pattern; }
- (int32_t)modelPermille { return _gift.model_permille; }
- (int32_t)patternPermille { return _gift.pattern_permille; }
- (int32_t)backdropPermille { return _gift.backdrop_permille; }

@end

@implementation NoshiSavedGift

@synthesize customImageName = _customImageName;

@synthesize gift = _gift;
@synthesize fromName = _fromName;
@synthesize note = _note;
@synthesize noteEntities = _noteEntities;
@synthesize fromPerson = _fromPerson;
@synthesize fromId = _fromId;
@synthesize date = _date;
@synthesize messageId = _messageId;
@synthesize nameHidden = _nameHidden;
@synthesize hidden = _hidden;
@synthesize canUpgrade = _canUpgrade;
@synthesize pinned = _pinned;
@synthesize convertStars = _convertStars;
@synthesize upgradeStars = _upgradeStars;
@synthesize transferStars = _transferStars;
@synthesize canTransferAt = _canTransferAt;

+ (NoshiSavedGift *)savedGiftWithRow:(const noshi_saved_gift *)row {
    NoshiSavedGift *saved = [[[NoshiSavedGift alloc] init] autorelease];
    saved->_gift = [[NoshiStarGift giftWithRow:&row->gift] retain];
    saved->_fromName = [NoshiUtf8(row->from_name) copy];
    saved->_note = [NoshiUtf8(row->note) copy];
    saved->_noteEntities = [NoshiTextEntities(saved->_note, row->note_entities, row->note_entity_count, row->note_urls) retain];
    saved->_fromId = row->from_id;
    if (row->from_person.id > 0) saved->_fromPerson = [[NoshiPerson alloc] initWithRow:&row->from_person];
    saved->_date = row->date;
    saved->_messageId = row->msg_id;
    saved->_nameHidden = row->name_hidden;
    saved->_hidden = row->unsaved;
    saved->_canUpgrade = row->can_upgrade;
    saved->_pinned = row->pinned;
    saved->_refunded = row->refunded;
    saved->_convertStars = row->convert_stars;
    saved->_upgradeStars = row->upgrade_stars;
    saved->_transferStars = row->transfer_stars;
    saved->_canTransferAt = row->can_transfer_at;
    return saved;
}

- (NoshiPhoto *)fromPhoto { return _fromPerson.photo; }

- (void)setSenderPerson:(NoshiPerson *)person {
    if (!person) return;
    [_fromPerson release];
    _fromPerson = [person retain];
    _fromId = person.userId;
    [_fromName release];
    _fromName = [person.name copy];
}

- (BOOL)canConvertAt:(int64_t)now period:(int32_t)period {
    noshi_saved_gift gift;
    memset(&gift, 0, sizeof(gift));
    gift.gift = _gift.row;
    gift.date = _date;
    gift.convert_stars = _convertStars;
    gift.refunded = _refunded;
    return noshi_gift_can_convert(&gift, now, period) ? YES : NO;
}

- (void)dealloc {
    [_gift release];
    [_fromName release];
    [_note release];
    [_noteEntities release];
    [_fromPerson release];
    [_customImageName release];
    [super dealloc];
}

@end

@implementation NoshiPaymentQuote

- (long long)stars { return stars; }

- (void)dealloc {
    [note release];
    [noteRuns release];
    [noteStrings release];
    [super dealloc];
}

@end

#import "noshi_session_internal.h"

#import "noshi_rpc.h"
#import "noshi_star_gift.h"

#include "noshi_bots.h"

/* the server sends the text of a gift note as is, so the limit is the core's */
@implementation NoshiSession (Gifts)

- (void)loadGiftConvertPeriod:(void (^)(int32_t, NSString *))completion {
    void (^done)(int32_t, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        *request = noshi_tl_new_obj(arena, "help.getAppConfig");
        return *request ? noshi_tl_set_i32(arena, *request, "hash", 0) : NOSHI_E_NOMEM;
    } handler:^(const noshi_mt_rpc_result *result) {
        int32_t period = 0;
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        if (!error && noshi_gift_convert_period_parse(result->value, &period) != NOSHI_OK) error = @"CONFIG_INVALID";
        [self noteRpcError:error];
        NSString *delivered = [[error copy] autorelease];
        [self deliverMain:^{ done(period, delivered); [done release]; }];
    }];
}

- (void)loadGiftCatalog:(NoshiListCompletion)completion {
    NoshiListCompletion done = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gifts_request(arena, 0, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_gift *rows = calloc(NOSHI_GIFTS_MAX, sizeof(*rows));
            size_t count = 0;
            int32_t hash = 0;
            noshi_status status = rows ? noshi_gifts_parse(result->value, rows, NOSHI_GIFTS_MAX, &count, &hash) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[NoshiStarGift giftWithRow:&rows[i]]];
            } else {
                NSLog(@"noshigram: payments.getStarGifts answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self finishLoad:gifts error:error completion:done];
        [done release];
    }];
}

- (void)loadSavedGiftsOfDialog:(NoshiDialog *)dialog offset:(NSString *)offset completion:(NoshiSavedGiftsCompletion)completion {
    NoshiSavedGiftsCompletion done = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSString *start = offset ? [offset copy] : [@"" copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_saved_gifts_request(arena, &peer, start.UTF8String, 30, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        NSMutableArray *gifts = nil;
        NSString *next = nil;
        NSString *error = nil;
        NSInteger total = 0;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_saved_gift *rows = calloc(NOSHI_SAVED_GIFTS_MAX, sizeof(*rows));
            noshi_saved_gift_page page;
            size_t count = 0;
            noshi_status status = rows ? noshi_saved_gifts_parse(result->value, rows, NOSHI_SAVED_GIFTS_MAX, &count, &page) : NOSHI_E_NOMEM;
            if (status == NOSHI_OK) {
                gifts = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) [gifts addObject:[NoshiSavedGift savedGiftWithRow:&rows[i]]];
                total = page.total;
                if (page.next_offset[0]) next = [NSString stringWithUTF8String:page.next_offset];
            } else {
                NSLog(@"noshigram: payments.getSavedStarGifts answer rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            }
            free(rows);
        }
        [self noteRpcError:error];
        NSArray *deliveredGifts = [[gifts copy] autorelease];
        NSString *deliveredNext = [[next copy] autorelease];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredGifts, total, deliveredNext, deliveredError); [done release]; }];
    }];
    [start release];
}

- (void)loadStarsBalance:(void (^)(long long, NSString *))completion {
    void (^done)(long long, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_stars_balance_request(arena, request);
    } handler:^(const noshi_mt_rpc_result *result) {
        int64_t stars = 0;
        NSString *error = nil;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = noshi_stars_balance_parse(result->value, &stars);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: payments.getStarsStatus answer rejected: %s", noshi_status_name(status));
                error = status == NOSHI_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(stars, deliveredError); [done release]; }];
    }];
}

/* worker only: the invoice a quote stands for */
static noshi_status NoshiBuildInvoice(noshi_arena *arena, NoshiPaymentQuote *quote, noshi_tl_value **invoice) {
    switch (quote->kind) {
    case NoshiPaymentGiftSend:
        return noshi_gift_invoice_send(arena, &quote->peer, quote->giftId, quote->note.UTF8String, quote->noteRuns.bytes, quote->noteRunCount, quote->hideName, quote->includeUpgrade, invoice);
    case NoshiPaymentGiftUpgrade:
        return noshi_gift_invoice_upgrade(arena, quote->messageId, quote->keepDetails, invoice);
    case NoshiPaymentGiftTransfer:
        return noshi_gift_invoice_transfer(arena, quote->messageId, &quote->peer, invoice);
    case NoshiPaymentPaidMedia:
        return noshi_paid_media_invoice(arena, &quote->peer, quote->messageId, invoice);
    case NoshiPaymentInviteSubscription:
        return noshi_invite_subscription_invoice(arena, quote->note.UTF8String, invoice);
    }
    return NOSHI_E_ARG;
}

- (void)askForm:(NoshiPaymentQuote *)quote completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    void (^done)(NoshiPaymentQuote *, NSString *) = [completion copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *invoice = NULL;
        noshi_status status = NoshiBuildInvoice(arena, quote, &invoice);
        if (status == NOSHI_OK) status = noshi_payment_form_request(arena, invoice, request);
        return status;
    } handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = nil;
        int64_t form = 0, stars = 0;
        if (result->status != NOSHI_OK) {
            error = NoshiRpcErrorName(result);
        } else {
            noshi_status status = noshi_payment_form_parse(result->value, &form, &stars);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: payments.getPaymentForm answer rejected: %s", noshi_status_name(status));
                error = status == NOSHI_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
            }
        }
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{
            if (!deliveredError) {
                quote->formId = form;
                quote->stars = stars;
            }
            done(deliveredError ? nil : quote, deliveredError);
            [done release];
        }];
    }];
}

- (void)quoteSendingGift:(NoshiStarGift *)gift toDialog:(NoshiDialog *)dialog note:(NSString *)note hideName:(BOOL)hideName
          includeUpgrade:(BOOL)includeUpgrade completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    [self quoteSendingGift:gift toDialog:dialog note:note entities:nil hideName:hideName includeUpgrade:includeUpgrade completion:completion];
}

- (void)quoteSendingGift:(NoshiStarGift *)gift toDialog:(NoshiDialog *)dialog note:(NSString *)note entities:(NSArray *)entities hideName:(BOOL)hideName
          includeUpgrade:(BOOL)includeUpgrade completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    NoshiPaymentQuote *quote = [[[NoshiPaymentQuote alloc] init] autorelease];
    quote->kind = NoshiPaymentGiftSend;
    quote->giftId = gift.giftId;
    quote->peer = NoshiPeerRefOfDialog(dialog);
    quote->note = [(note ? note : @"") copy];
    quote->hideName = hideName;
    quote->includeUpgrade = includeUpgrade;
    NSMutableData *strings = nil;
    size_t runs = 0;
    NSMutableData *packed = NoshiPackSendEntities(entities, &strings, &runs);
    quote->noteRuns = [packed retain];
    quote->noteStrings = [strings retain];
    quote->noteRunCount = runs;
    [self askForm:quote completion:completion];
}

- (void)quoteUpgradingGift:(NoshiSavedGift *)gift keepDetails:(BOOL)keepDetails completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    NoshiPaymentQuote *quote = [[[NoshiPaymentQuote alloc] init] autorelease];
    quote->kind = NoshiPaymentGiftUpgrade;
    quote->messageId = gift.messageId;
    quote->keepDetails = keepDetails;
    [self askForm:quote completion:completion];
}

- (void)quoteTransferringGift:(NoshiSavedGift *)gift toDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    NoshiPaymentQuote *quote = [[[NoshiPaymentQuote alloc] init] autorelease];
    quote->kind = NoshiPaymentGiftTransfer;
    quote->messageId = gift.messageId;
    quote->peer = NoshiPeerRefOfDialog(dialog);
    [self askForm:quote completion:completion];
}

- (void)quoteSubscribingInviteHash:(NSString *)hash completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    NoshiPaymentQuote *quote = [[[NoshiPaymentQuote alloc] init] autorelease];
    quote->kind = NoshiPaymentInviteSubscription;
    quote->note = [hash copy];
    [self askForm:quote completion:completion];
}

- (void)quoteUnlockingMediaOfMessageId:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiPaymentQuote *, NSString *))completion {
    NoshiPaymentQuote *quote = [[[NoshiPaymentQuote alloc] init] autorelease];
    quote->kind = NoshiPaymentPaidMedia;
    quote->messageId = messageId;
    quote->peer = NoshiPeerRefOfDialog(dialog);
    [self askForm:quote completion:completion];
}

- (void)payQuote:(NoshiPaymentQuote *)quote completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self loadStarsBalance:^(long long balance, NSString *balanceError) {
        if (balanceError) { done(balanceError); [done release]; return; }
        if (balance < quote->stars) { done(@"BALANCE_LOW"); [done release]; return; }
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            noshi_tl_value *invoice = NULL;
            noshi_status status = NoshiBuildInvoice(arena, quote, &invoice);
            if (status == NOSHI_OK) status = noshi_payment_send_request(arena, quote->formId, invoice, request);
            return status;
        } handler:^(const noshi_mt_rpc_result *result) {
            NSString *error = nil;
            if (result->status != NOSHI_OK) {
                error = NoshiRpcErrorName(result);
            } else {
                noshi_status status = noshi_payment_result_check(result->value);
                if (status != NOSHI_OK) {
                    NSLog(@"noshigram: payments.sendStarsForm answer rejected: %s", noshi_status_name(status));
                    error = status == NOSHI_E_UNSUPPORTED ? @"STARS_UNSUPPORTED" : @"INTERNAL";
                }
            }
            [self noteRpcError:error];
            NSString *deliveredError = [[error copy] autorelease];
            [self deliverMain:^{ done(deliveredError); [done release]; }];
        }];
    }];
}

/* a request with no answer worth reading: the server says true, or an error name */
- (void)runGiftRequest:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    [self invokeBuilt:build handler:^(const noshi_mt_rpc_result *result) {
        NSString *error = result->status == NOSHI_OK ? nil : NoshiRpcErrorName(result);
        [self noteRpcError:error];
        NSString *deliveredError = [[error copy] autorelease];
        [self deliverMain:^{ done(deliveredError); [done release]; }];
    }];
}

- (void)setGift:(NoshiSavedGift *)gift hidden:(BOOL)hidden completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_save_request(arena, messageId, hidden, request);
    } completion:completion];
}

- (void)convertGift:(NoshiSavedGift *)gift completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_convert_request(arena, messageId, request);
    } completion:completion];
}

- (void)upgradeGift:(NoshiSavedGift *)gift keepDetails:(BOOL)keepDetails completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_upgrade_request(arena, messageId, keepDetails, request);
    } completion:completion];
}

- (void)transferGift:(NoshiSavedGift *)gift toDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    int32_t messageId = gift.messageId;
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_transfer_request(arena, messageId, &peer, request);
    } completion:completion];
}

- (void)wearGiftWithId:(long long)collectibleId completion:(void (^)(NSString *))completion {
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_wear_request(arena, collectibleId, request);
    } completion:completion];
}

- (void)pinGifts:(NSArray *)gifts completion:(void (^)(NSString *))completion {
    NSMutableData *ids = [NSMutableData data];
    for (NoshiSavedGift *gift in gifts) {
        int32_t messageId = gift.messageId;
        [ids appendBytes:&messageId length:sizeof(messageId)];
    }
    size_t count = ids.length / sizeof(int32_t);
    [self runGiftRequest:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_gift_pin_request(arena, ids.bytes, count, request);
    } completion:completion];
}

@end

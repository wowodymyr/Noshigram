#import "noshi_forward.h"
#import <objc/runtime.h>

#include "noshi_message_actions.h"

#import "noshi_chat_settings.h"
#import "noshi_gift_screen.h"
#import "noshi_message.h"
#import "noshi_person.h"
#import "noshi_session_actions.h"
#import "noshi_settings_kit.h"
#import "noshi_topic_icon.h"
#import "noshi_custom_emoji_loader.h"
#import "noshi_weak_reference.h"

static BOOL NoshiCanCopyForward(NoshiMessage *message) {
    NoshiMedia *media = message.media;
    BOOL fullPhoto = media.kind == NOSHI_PREVIEW_PHOTO && media.fullPhotoFile != nil;
    return !message.service && noshi_copy_forward_allowed(media.kind, message.text.length > 0,
        fullPhoto || media.file != nil, media.viewOnce, fullPhoto ? media.fullPhotoSize : media.size, media.duration);
}

static long long NoshiCopyRandomId(void) {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

static void NoshiCopyMessagesWithLines(NoshiSession *session, NoshiMediaCache *cache, NSArray *messages, NSUInteger index, NoshiDialog *target, NSDictionary *lines, void (^completion)(NSUInteger, NSString *)) {
    if (index >= messages.count) { completion(index, nil); return; }
    NoshiMessage *message = [messages objectAtIndex:index];
    NoshiMedia *media = message.media;
    long long randomId = NoshiCopyRandomId();
    NoshiSendCompletion done = ^(int32_t messageId, NSString *error) {
        (void)messageId;
        if (error) { completion(index, error); return; }
        NoshiCopyMessagesWithLines(session, cache, messages, index + 1, target, lines, completion);
    };
    /* the author's line: the name in bold and the @username after it, then the words of the message under it */
    NSString *line = [lines objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    NSString *words = message.text ? message.text : @"";
    NSArray *entities = message.entities;
    if (line.length) {
        NSUInteger shift = line.length + 1;
        NSMutableArray *shifted = [NSMutableArray array];
        NSRange boldRange = [line rangeOfString:@" @" options:NSBackwardsSearch];
        NSUInteger nameLength = boldRange.location == NSNotFound ? line.length : boldRange.location;
        [shifted addObject:[[[NoshiTextEntity alloc] initWithStyle:NoshiTextStyleBold range:NSMakeRange(0, nameLength) url:nil] autorelease]];
        for (NoshiTextEntity *entity in message.entities) {
            NoshiTextEntity *moved = [[[NoshiTextEntity alloc] initWithStyle:entity.style range:NSMakeRange(entity.range.location + shift, entity.range.length) url:entity.url] autorelease];
            moved.documentId = entity.documentId; moved.userId = entity.userId; moved.date = entity.date; moved.flags = entity.flags;
            [shifted addObject:moved];
        }
        entities = shifted;
        words = [NSString stringWithFormat:@"%@\n%@", line, words];
    }
    if (media.kind == NOSHI_PREVIEW_NONE || media.kind == NOSHI_PREVIEW_TEXT) {
        [session sendText:words entities:entities toDialog:target randomId:randomId completion:done];
        return;
    }
    if (media.kind == NOSHI_PREVIEW_STICKER) {
        [session sendSticker:media toDialog:target randomId:randomId completion:done];
        return;
    }
    NoshiRemoteFile *file = media.kind == NOSHI_PREVIEW_PHOTO && media.fullPhotoFile ? media.fullPhotoFile : media.file;
    long long size = media.kind == NOSHI_PREVIEW_PHOTO && media.fullPhotoFile ? media.fullPhotoSize : media.size;
    [cache loadPathForFile:file size:size progress:nil completion:^(NSString *path) {
        if (!path) { completion(index, @"DOWNLOAD_FAILED"); return; }
        int32_t duration = media.duration * 1000;
        switch (media.kind) {
        case NOSHI_PREVIEW_PHOTO: {
            /* the cache names a file by its key with no extension, and the upload sends that name: the server answers PHOTO_EXT_INVALID to a photo without .jpg */
            NSString *named = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"copy-%08x%08x.jpg", arc4random(), arc4random()]];
            NSError *copyError = nil;
            if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:named error:&copyError]) {
                NSLog(@"noshigram: the photo to copy could not be staged: %@", copyError);
                completion(index, @"INTERNAL");
                return;
            }
            [session sendPhotoAtPath:named caption:words spoiler:media.spoiler toDialog:target randomId:randomId completion:^(int32_t messageId, NSString *error) {
                [[NSFileManager defaultManager] removeItemAtPath:named error:NULL];
                done(messageId, error);
            }];
            break;
        }
        case NOSHI_PREVIEW_VIDEO:
            [session sendVideoAtPath:path durationMs:duration width:media.width height:media.height caption:words spoiler:media.spoiler toDialog:target randomId:randomId completion:done]; break;
        case NOSHI_PREVIEW_VIDEO_MESSAGE:
            [session sendRoundVideoAtPath:path durationMs:duration side:media.width toDialog:target randomId:randomId completion:done]; break;
        case NOSHI_PREVIEW_VOICE:
            [session sendVoiceAtPath:path durationMs:duration waveform:media.waveformBars toDialog:target randomId:randomId completion:done]; break;
        default:
            [session sendDocumentAtPath:path name:media.name mime:media.mime caption:words toDialog:target randomId:randomId completion:done]; break;
        }
    }];
}

static void NoshiForwardMessagesNow(NoshiSession *session, NoshiMediaCache *cache, NoshiDialog *from, BOOL chatRestricted, NSArray *messages, NoshiDialog *target, BOOL hideAuthor, void (^completion)(NSString *message));

/* the target of the cancel button of the topic list: it closes the list and answers with nothing */
@interface NoshiForwardCancel : NSObject {
    void (^_block)(void);
}
- (id)initWithBlock:(void (^)(void))block;
- (void)fire;
@end

@implementation NoshiForwardCancel
- (id)initWithBlock:(void (^)(void))block {
    self = [super init];
    if (self) _block = [block copy];
    return self;
}
- (void)fire { if (_block) _block(); }
- (void)dealloc { [_block release]; [super dealloc]; }
@end

static UIViewController *NoshiForwardFrontController(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

/* a forum asks for the topic the messages go to, as the other clients do: the topics of the group in a list over the screen, and the one that is tapped is the target; a forum whose
   topics do not load keeps the answer of the group itself, which the server reads as its General topic */
static void NoshiChooseForwardTopic(NoshiSession *session, NoshiMediaCache *cache, NoshiDialog *target, void (^done)(NoshiDialog *chosen)) {
    if (!target.forum || target.topicId > 0) { done(target); return; }
    void (^answer)(NoshiDialog *) = [done copy];
    [session loadTopicsOfDialog:target completion:^(NSArray *topics, NSString *errorName) {
        UIViewController *front = NoshiForwardFrontController();
        if (errorName || !topics.count || !front) {
            if (errorName) NSLog(@"noshigram: the topics for a forward did not load: %@", errorName);
            answer(target);
            [answer release];
            return;
        }
        NoshiSettingsPageController *page = [[[NoshiSettingsPageController alloc] init] autorelease];
        page.pageTitle = NSLocalizedString(@"chat.forward.topic", nil);
        UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:page] autorelease];
        navigation.modalPresentationStyle = UIModalPresentationFormSheet;
        __block BOOL chosen = NO;
        /* a row carries the icon of its topic, the picture of the custom emoji when it is in memory and the hash in the topic's color until then */
        NSArray *(^makeRows)(void) = ^NSArray *{
            NSMutableArray *rows = [NSMutableArray array];
            for (NoshiDialog *topic in topics) {
                if (topic.topicClosed) continue;
                [rows addObject:[NoshiSettingsRow rowWithTileImage:NoshiTopicIconImage(topic) title:topic.title subtitle:nil tap:^{
                    if (chosen) return;
                    chosen = YES;
                    [navigation dismissViewControllerAnimated:YES completion:^{ answer(topic); [answer release]; }];
                }]];
            }
            return rows;
        };
        NSArray *rows = makeRows();
        if (!rows.count) { answer(target); [answer release]; return; }
        page.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:rows]];
        NSMutableArray *icons = [NSMutableArray array];
        for (NoshiDialog *topic in topics) if (topic.topicIconEmoji) [icons addObject:[NSNumber numberWithLongLong:topic.topicIconEmoji]];
        if (icons.count) {
            NoshiWeakReference *weakPage = [NoshiWeakReference referenceTo:page];
            [NoshiCustomEmojiLoader loadDocuments:icons session:session media:cache documents:nil picture:^{
                NoshiSettingsPageController *shown = weakPage.target;
                if (!shown) return;
                shown.sections = [NSArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:makeRows()]];
                [shown reloadSettings];
            }];
        }
        NoshiForwardCancel *cancel = [[[NoshiForwardCancel alloc] initWithBlock:^{
            if (chosen) return;
            chosen = YES;
            [navigation dismissViewControllerAnimated:YES completion:^{ answer(nil); [answer release]; }];
        }] autorelease];
        objc_setAssociatedObject(page, "noshigram.forward.cancel", cancel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        page.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"picker.cancel", nil) style:UIBarButtonItemStyleBordered target:cancel action:@selector(fire)] autorelease];
        [front presentViewController:navigation animated:YES completion:nil];
    }];
}

void NoshiForwardMessages(NoshiSession *session, NoshiMediaCache *cache, NoshiDialog *from, BOOL chatRestricted, NSArray *messages, NoshiDialog *target, BOOL hideAuthor, void (^completion)(NSString *message)) {
    void (^finish)(NSString *) = [completion copy];
    NoshiChooseForwardTopic(session, cache, target, ^(NoshiDialog *chosen) {
        /* nothing was chosen: the list was cancelled, and nothing goes */
        if (!chosen) { [finish release]; return; }
        NoshiForwardMessagesNow(session, cache, from, chatRestricted, messages, chosen, hideAuthor, finish);
        [finish release];
    });
}

static void NoshiForwardMessagesNow(NoshiSession *session, NoshiMediaCache *cache, NoshiDialog *from, BOOL chatRestricted, NSArray *messages, NoshiDialog *target, BOOL hideAuthor, void (^completion)(NSString *message)) {
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:messages.count];
    (void)chatRestricted;
    for (NoshiMessage *message in messages) [ids addObject:[NSNumber numberWithInt:message.messageId]];
    __block NSDictionary *authorLines = nil;
    void (^copy)(void) = ^{
        /* a poll, a place or a contact in the pick cannot be sent again; the rest of a pick must still go, and the person is told how many stayed behind */
        NSMutableArray *copyable = [NSMutableArray arrayWithCapacity:messages.count];
        for (NoshiMessage *message in messages) if (NoshiCanCopyForward(message)) [copyable addObject:message];
        long skipped = (long)(messages.count - copyable.count);
        if (!copyable.count) { completion(NSLocalizedString(@"forward.copy.failed", nil)); return; }
        NoshiCopyMessagesWithLines(session, cache, copyable, 0, target, authorLines, ^(NSUInteger sent, NSString *error) {
            if (error && sent) completion([NSString stringWithFormat:NSLocalizedString(@"forward.copy.partial", nil), (long)sent, NoshiGiftErrorText(error)]);
            else if (error) completion(NoshiGiftErrorText(error));
            else completion(skipped ? [NSString stringWithFormat:NSLocalizedString(@"forward.copy.skipped", nil), (long)copyable.count, skipped] : nil);
        });
    };
    /* without the author, and the person asked for his name: the messages go as copies that open with the name and the @username of whoever wrote them */
    if (hideAuthor && NoshiChatFlagGet(NoshiChatFlagForwardAuthor)) {
        NSMutableArray *keys = [NSMutableArray array];
        for (NoshiMessage *message in messages) {
            NSNumber *key = [NSNumber numberWithLongLong:message.senderKey];
            if (message.senderKey && ![keys containsObject:key]) [keys addObject:key];
        }
        [session loadCachedPeopleWithIds:keys completion:^(NSDictionary *people) {
            NSMutableDictionary *lines = [NSMutableDictionary dictionary];
            for (NSNumber *key in people) {
                NoshiPerson *person = [people objectForKey:key];
                if (!person.name.length) continue;
                [lines setObject:person.username.length ? [NSString stringWithFormat:@"%@ @%@", person.name, person.username] : person.name forKey:key];
            }
            authorLines = [lines retain];
            copy();
        }];
        return;
    }
    [session forwardMessageIds:ids fromDialog:from toDialog:target hideAuthor:hideAuthor completion:^(NSString *error) {
        completion(error ? NoshiGiftErrorText(error) : nil);
    }];
}

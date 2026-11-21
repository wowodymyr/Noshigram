#import "noshi_share_intake.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/message.h>

#import "noshi_attach_flow.h"
#import "noshi_image_decoder.h"
#import "noshi_message.h"

NSString *const NoshiShareFilesNotification = @"NoshiShareFiles";

/* the longest side a shared picture keeps, as the gallery sheet does for the original quality */
#define SHARE_SIDE_MAX 2560.0
#define SHARE_JPEG_QUALITY 0.9
#define SHARE_FILES_MAX 10

static NSString *NoshiShareTemporaryJpeg(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"noshigram-share-%08x%08x.jpg", arc4random(), arc4random()]];
}

static BOOL NoshiShareConforms(NSString *extension, CFStringRef type) {
    if (!extension.length) return NO;
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
    BOOL fits = uti && UTTypeConformsTo(uti, type);
    if (uti) CFRelease(uti);
    return fits;
}

/* off the main thread: the outgoing item of one file, or nil when the file cannot be read */
static NoshiOutgoing *NoshiShareOutgoing(NSURL *url, NSString **removable) {
    NSString *path = url.path;
    NSString *extension = path.pathExtension;
    BOOL gif = [extension caseInsensitiveCompare:@"gif"] == NSOrderedSame;
    if (!gif && NoshiShareConforms(extension, kUTTypeImage)) {
        UIImage *image = NoshiDecodeImageAtURL(url, SHARE_SIDE_MAX);
        NSData *jpeg = image ? UIImageJPEGRepresentation(image, SHARE_JPEG_QUALITY) : nil;
        NSString *jpegPath = jpeg ? NoshiShareTemporaryJpeg() : nil;
        if (jpegPath && [jpeg writeToFile:jpegPath atomically:YES]) {
            NoshiOutgoing *outgoing = [[[NoshiOutgoing alloc] init] autorelease];
            outgoing->kind = NoshiOutgoingPhoto;
            outgoing->path = [jpegPath copy];
            outgoing->name = [jpegPath.lastPathComponent copy];
            outgoing->width = (int32_t)image.size.width;
            outgoing->height = (int32_t)image.size.height;
            *removable = jpegPath;
            return outgoing;
        }
        /* a picture the decoder cannot read still goes out as the file it is */
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) return nil;
    NoshiOutgoing *outgoing = [[[NoshiOutgoing alloc] init] autorelease];
    outgoing->kind = NoshiOutgoingFile;
    outgoing->path = [path copy];
    outgoing->name = [path.lastPathComponent copy];
    outgoing->mime = [NoshiMimeOfPath(path) copy];
    outgoing->animated = gif;
    return outgoing;
}

static long long NoshiShareRandomId(void) {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

static void NoshiShareNext(NSArray *urls, NSUInteger index, NoshiDialog *dialog, NoshiSession *session, void (^done)(NSString *), NSString *failure) {
    if (index >= urls.count) {
        done(failure);
        [done release];
        return;
    }
    NSURL *url = [urls objectAtIndex:index];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *removable = nil;
        NoshiOutgoing *outgoing = [NoshiShareOutgoing(url, &removable) retain];
        NSString *spare = [removable copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            /* it outlives this block, since the send answers later */
            void (^finish)(NSString *) = [[^(NSString *error) {
                NSFileManager *files = [NSFileManager defaultManager];
                if (spare) [files removeItemAtPath:spare error:NULL];
                [files removeItemAtPath:url.path error:NULL];
                NoshiShareNext(urls, index + 1, dialog, session, done, failure ? failure : error);
            } copy] autorelease];
            if (!outgoing) {
                NSLog(@"noshigram: the shared file %@ cannot be read", url.lastPathComponent);
                finish(@"SHARE_FILE_UNREADABLE");
            } else {
                [session sendOutgoing:outgoing toDialog:dialog randomId:NoshiShareRandomId() replyTo:0 completion:^(int32_t messageId, NSString *error) {
                    (void)messageId;
                    if (error) NSLog(@"noshigram: the shared file %@ was not sent: %@", url.lastPathComponent, error);
                    finish(error);
                }];
            }
            [outgoing release];
            [spare release];
        });
        [pool drain];
    });
}

void NoshiShareSendFiles(NSArray *urls, NSString *text, NoshiDialog *dialog, NoshiSession *session, void (^done)(NSString *errorName)) {
    NSArray *bounded = urls.count > SHARE_FILES_MAX ? [urls subarrayWithRange:NSMakeRange(0, SHARE_FILES_MAX)] : urls;
    void (^files)(NSString *) = [done copy];
    if (!text.length) {
        NoshiShareNext(bounded, 0, dialog, session, files, nil);
        return;
    }
    [session sendText:text entities:nil toDialog:dialog randomId:NoshiShareRandomId() completion:^(int32_t messageId, NSString *error) {
        (void)messageId;
        if (error) NSLog(@"noshigram: the shared text was not sent: %@", error);
        NoshiShareNext(bounded, 0, dialog, session, files, error);
    }];
}

#pragma mark extension hand-over

#define SHARE_GROUP @"group.com.noshigram.app"
#define SHARE_FOLDER @"Share"
#define SHARE_MANIFEST @"manifest.plist"
#define SHARE_CLAIMED @"manifest.taken"
#define SHARE_KEEP_SECONDS (24 * 60 * 60)

static NSString *NoshiShareRoot(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    SEL select = NSSelectorFromString(@"containerURLForSecurityApplicationGroupIdentifier:");
    if (![manager respondsToSelector:select]) return nil;
    NSURL *container = ((id (*)(id, SEL, NSString *))objc_msgSend)(manager, select, SHARE_GROUP);
    return container ? [[container path] stringByAppendingPathComponent:SHARE_FOLDER] : nil;
}

void NoshiShareDiscard(NSString *directory) {
    if (directory.length) [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

void NoshiShareCollectPending(void) {
    NSString *root = NoshiShareRoot();
    if (!root) return;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *newest = nil;
    NSDate *newestDate = nil;
    for (NSString *name in [manager contentsOfDirectoryAtPath:root error:NULL]) {
        NSString *directory = [root stringByAppendingPathComponent:name];
        NSDate *made = [[manager attributesOfItemAtPath:directory error:NULL] fileModificationDate];
        BOOL waiting = [manager fileExistsAtPath:[directory stringByAppendingPathComponent:SHARE_MANIFEST]];
        if (!made || [made timeIntervalSinceNow] < -SHARE_KEEP_SECONDS) {
            NoshiShareDiscard(directory);
            continue;
        }
        /* a folder with no waiting manifest is being filled by the extension, or is taken and still being sent; it is left alone until it is old */
        if (!waiting) continue;
        if (!newestDate || [made compare:newestDate] == NSOrderedDescending) {
            NoshiShareDiscard(newest);
            newest = directory;
            newestDate = made;
        } else {
            NoshiShareDiscard(directory);
        }
    }
    if (!newest) return;
    /* the rename succeeds for one caller only, and the wake url and the return to the front both come here */
    NSString *manifestPath = [newest stringByAppendingPathComponent:SHARE_MANIFEST], *claimed = [newest stringByAppendingPathComponent:SHARE_CLAIMED];
    if (![manager moveItemAtPath:manifestPath toPath:claimed error:NULL]) return;
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:claimed];
    NSMutableArray *urls = [NSMutableArray array];
    for (id name in [manifest objectForKey:@"files"]) {
        /* the names come from another process, so only a plain name inside the folder is taken */
        if ([name isKindOfClass:[NSString class]] && [name length] && [[name lastPathComponent] isEqualToString:name] && ![name hasPrefix:@"."]) {
            [urls addObject:[NSURL fileURLWithPath:[newest stringByAppendingPathComponent:name]]];
        }
    }
    NSString *text = [manifest objectForKey:@"text"];
    if (![text isKindOfClass:[NSString class]]) text = nil;
    if (!urls.count && !text.length) { NoshiShareDiscard(newest); return; }
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:urls, @"urls", newest, @"directory", nil];
    if (text.length) [info setObject:text forKey:@"text"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiShareFilesNotification object:nil userInfo:info];
}

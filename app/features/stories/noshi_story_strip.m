#import "noshi_story_strip.h"
#import "noshi_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_chat_settings.h"
#import "noshi_avatar_view.h"
#import "noshi_alert.h"
#import "noshi_emoji_label.h"
#import "noshi_person.h"
#import "noshi_profile_photo_picker.h"
#import "noshi_story.h"
#import "noshi_story_camera_controller.h"
#import "noshi_story_ring.h"
#import "noshi_story_viewer_controller.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define STRIP_HEIGHT 92.0
#define ITEM_WIDTH 72.0
#define RING 58.0
#define PHOTO 50.0
#define REFRESH_SECONDS 45.0
#define RING_WIDTH 2.0
#define SEEN_WIDTH 1.3

/* the ring of the Telegram story cell: an unseen story is a stroke that runs from blue to green, one for close
   friends from lime to green, and a seen one a thin grey line */
@interface NoshiStoryRingView : UIControl {
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_name;
    CAGradientLayer *_gradient;
    CAShapeLayer *_stroke;
    UIButton *_plus;
}
/* selfDialog is the account as a chat with oneself, which has the photo that the own cell shows: the story list names the own cell by a chat that has none */
- (void)configureWithPeer:(NoshiStoryPeer *)peer avatars:(NoshiAvatarCache *)avatars selfDialog:(NoshiDialog *)selfDialog;
/* the plus of the own cell, which adds a story; hidden on every other cell */
@property (nonatomic, readonly) UIButton *plus;
@end

@implementation NoshiStoryRingView

@synthesize plus = _plus;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    NoshiAttachBounce(self, 0.06);
    CGFloat itemWidth = ITEM_WIDTH;
    CGRect box = CGRectMake((itemWidth - RING) / 2, 6, RING, RING);
    _gradient = [[CAGradientLayer layer] retain];
    _gradient.frame = box;
    _gradient.startPoint = CGPointMake(1, 0);
    _gradient.endPoint = CGPointMake(0, 1);
    _stroke = [[CAShapeLayer layer] retain];
    _stroke.frame = CGRectMake(0, 0, RING, RING);
    _stroke.fillColor = nil;
    _stroke.strokeColor = [UIColor blackColor].CGColor;
    _gradient.mask = _stroke;
    [self.layer addSublayer:_gradient];
    _avatar = [[NoshiAvatarView alloc] initWithFrame:CGRectMake((itemWidth - PHOTO) / 2, 6 + (RING - PHOTO) / 2, PHOTO, PHOTO)];
    [self addSubview:_avatar];
    [self buildPlusInWidth:itemWidth];
    /* a name stays inside its cell with two points to spare on either side, so the name next to it never touches it; one that does not fit ends in dots */
    _name = [[NoshiEmojiLabel alloc] initWithFrame:CGRectMake(2, 68, itemWidth - 4, 16)];
    _name.font = NoshiFontRegular(10.5);
    _name.textAlignment = NoshiTextAlignmentCenter;
    _name.textColor = NoshiColorSecondary();
    [self addSubview:_name];
    return self;
}

/* the plus on the corner of the own photo; the button is wider than the disc so a finger finds it */
- (void)buildPlusInWidth:(CGFloat)itemWidth {
    _plus = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plus.hidden = YES;
    _plus.accessibilityLabel = NSLocalizedString(@"story.add", nil);
    CGFloat disc = 24;
    CGFloat hit = 34;
    CGFloat photoRight = (itemWidth + PHOTO) / 2;
    CGFloat photoBottom = 6 + (RING - PHOTO) / 2 + PHOTO;
    _plus.frame = CGRectMake(photoRight - disc / 2 - hit / 2 + 2, photoBottom - disc / 2 - hit / 2 + 2, hit, hit);
    CGFloat inset = (hit - disc) / 2;
    UIImageView *face = [[[UIImageView alloc] initWithFrame:CGRectMake(inset, inset, disc, disc)] autorelease];
    face.userInteractionEnabled = NO;
    face.backgroundColor = NoshiColorAccent();
    face.layer.cornerRadius = disc / 2;
    face.layer.borderWidth = 2.5;
    face.layer.borderColor = NoshiColorScreen().CGColor;
    UIColor *ink = [UIColor whiteColor];
    CGFloat arm = 11, thick = 2.5;
    for (int i = 0; i < 2; ++i) {
        CALayer *bar = [CALayer layer];
        bar.backgroundColor = ink.CGColor;
        bar.cornerRadius = thick / 2;
        bar.frame = i ? CGRectMake((disc - arm) / 2, (disc - thick) / 2, arm, thick) : CGRectMake((disc - thick) / 2, (disc - arm) / 2, thick, arm);
        [face.layer addSublayer:bar];
    }
    [_plus addSubview:face];
    [self addSubview:_plus];
}

- (void)dealloc {
    [_plus release];
    [_avatar release];
    [_name release];
    [_gradient release];
    [_stroke release];
    [super dealloc];
}

- (void)configureRingForPeer:(NoshiStoryPeer *)peer {
    BOOL unseen = peer.unread > 0;
    CGFloat width = unseen ? RING_WIDTH : SEEN_WIDTH;
    CGFloat inset = width / 2;
    _stroke.lineWidth = width;
    _stroke.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(inset, inset, RING - width, RING - width)].CGPath;
    UIColor *from, *to;
    NoshiStoryRingColors(unseen, peer.closeFriends, &from, &to);
    _gradient.colors = [NSArray arrayWithObjects:(id)from.CGColor, (id)to.CGColor, nil];
}

- (void)configureWithPeer:(NoshiStoryPeer *)peer avatars:(NoshiAvatarCache *)avatars selfDialog:(NoshiDialog *)selfDialog {
    NoshiDialog *owner = peer.owner;
    BOOL unseen = peer.unread > 0;
    [self configureRingForPeer:peer];
    /* the own cell without a story of its own has no ring at all, only the photo and the plus */
    _gradient.hidden = owner.saved && peer.count == 0;
    _plus.hidden = !owner.saved;
    BOOL borrows = owner.saved && !owner.photo && selfDialog;
    NoshiChatTrace([NSString stringWithFormat:@"story cell saved %d photo %@ self %@ borrows %d", (int)owner.saved, owner.photo.key, selfDialog.photo.key, (int)borrows]);
    _avatar.initials = owner.initials.length || !borrows ? owner.initials : selfDialog.initials;
    _avatar.seed = owner.avatarSeed;
    [_avatar setPhoto:borrows ? selfDialog.photo : owner.photo cache:avatars];
    NSString *title = owner.saved ? NSLocalizedString(@"story.mine", nil) : owner.title;
    _name.text = title;
    _name.textColor = unseen ? NoshiColorTitle() : NoshiColorSecondary();
    self.accessibilityLabel = unseen ? [NSString stringWithFormat:@"%@, %d", title, (int)peer.unread] : title;
}

@end

@interface NoshiStoryStrip () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_host;
    void (^_changed)(void);
    void (^_peersChanged)(void);
    NoshiWeakReference *_weak;
    UIScrollView *_scroll;
    NSArray *_peers;
    CGFloat _height;
    BOOL _loading;
    BOOL _viewerOpen;
    /* the signed in person as a chat with oneself, which stands for the own cell when the server lists no story of ours */
    NoshiDialog *_selfDialog;
    BOOL _selfAsked;
    BOOL _posting;
    /* what the row shows: the server's list, with an own cell in front when it has none */
    NSArray *_cells;
    CFAbsoluteTime _loadedAt;
}
@end

@implementation NoshiStoryStrip

@synthesize height = _height;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
                 host:(UIViewController *)host changed:(void (^)(void))changed {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _host = [[NoshiWeakReference referenceTo:host] retain];
    _changed = [changed copy];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 320, 0)];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.backgroundColor = [UIColor clearColor];
    _scroll.clipsToBounds = YES;
    _peers = [[NSArray alloc] init];
    _cells = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_session release];
    [_avatars release];
    [_media release];
    [_host release];
    [_changed release];
    [_peersChanged release];
    [_weak release];
    [_scroll release];
    [_peers release];
    [_cells release];
    [_selfDialog release];
    [super dealloc];
}

- (UIView *)view { return _scroll; }

@synthesize peersChanged = _peersChanged;

- (NoshiStoryPeer *)peerForDialog:(NoshiDialog *)dialog {
    if (dialog.kind != NOSHI_DIALOG_USER || dialog.saved) return nil;
    for (NoshiStoryPeer *peer in _peers) {
        if (peer.owner.saved) continue;
        if (peer.owner.peerKind == dialog.peerKind && peer.owner.peerId == dialog.peerId) return peer;
    }
    return nil;
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    NoshiWeakReference *weak = _weak;
    [_session loadStoryPeers:^(NSArray *peers, NSString *errorName) {
        NoshiStoryStrip *me = weak.target;
        if (!me) return;
        me->_loading = NO;
        me->_loadedAt = CFAbsoluteTimeGetCurrent();
        if (errorName) {
            NSLog(@"noshigram: story strip not refreshed: %@", errorName);
            return;
        }
        [me showPeers:peers];
    }];
}

- (void)refresh {
    if (CFAbsoluteTimeGetCurrent() - _loadedAt < REFRESH_SECONDS) return;
    [self reload];
}

/* the own story first, always: the server lists it only while we have one, and the cell is also where a new one starts */
- (void)loadSelfDialog {
    if (_selfAsked) return;
    _selfAsked = YES;
    /* the own cell wears the photo of the last time at once, and the answer replaces it */
    NoshiPerson *known = _selfDialog ? nil : [_session ownPerson];
    if (known) {
        _selfDialog = [[NoshiDialog savedMessagesWithPerson:known] retain];
        [self showPeers:_peers];
    }
    NoshiWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiStoryStrip *me = weak.target;
        if (!me) return;
        NoshiPerson *person = items.count ? [items objectAtIndex:0] : nil;
        NoshiDialog *dialog = person ? [NoshiDialog savedMessagesWithPerson:person] : nil;
        if (!dialog) {
            NSLog(@"noshigram: the own story cell has no profile to stand on: %@", errorName);
            me->_selfAsked = NO;
            return;
        }
        [me->_selfDialog release];
        me->_selfDialog = [dialog retain];
        [me showPeers:me->_peers];
    }];
}

- (BOOL)hasOwnStories {
    NoshiStoryPeer *first = _peers.count ? [_peers objectAtIndex:0] : nil;
    return first.owner.saved;
}

- (void)showPeers:(NSArray *)peers {
    /* the caller may hand over _peers itself, so the copy is made before the old list is let go */
    NSArray *kept = [peers copy];
    [_peers release];
    _peers = kept;
    NSMutableArray *cells = [NSMutableArray arrayWithArray:_peers];
    if (![self hasOwnStories] && _selfDialog) [cells insertObject:[NoshiStoryPeer peerWithOwner:_selfDialog count:0] atIndex:0];
    /* the own cell wears the photo of the account in either case, so the account is asked for once, whether or not it has stories */
    if (!_selfDialog) [self loadSelfDialog];
    [_cells release];
    _cells = [cells copy];
    for (UIView *old in [[_scroll.subviews copy] autorelease]) [old removeFromSuperview];
    CGFloat rowHeight = STRIP_HEIGHT;
    CGFloat itemWidth = ITEM_WIDTH;
    CGFloat height = _cells.count ? rowHeight : 0;
    for (NSUInteger i = 0; i < _cells.count; ++i) {
        NoshiStoryRingView *ring = [[[NoshiStoryRingView alloc] initWithFrame:CGRectMake(8 + i * itemWidth, 2, itemWidth, rowHeight - 4)] autorelease];
        ring.tag = (NSInteger)i;
        [ring configureWithPeer:[_cells objectAtIndex:i] avatars:_avatars selfDialog:_selfDialog];
        [ring addTarget:self action:@selector(ringTapped:) forControlEvents:UIControlEventTouchUpInside];
        [ring.plus addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:ring];
    }
    _scroll.contentSize = CGSizeMake(16 + _cells.count * itemWidth, height);
    if (height != _height) {
        _height = height;
        CGRect frame = _scroll.frame;
        frame.size.height = height;
        _scroll.frame = frame;
        if (_changed) _changed();
    }
    if (_peersChanged) _peersChanged();
}

- (void)layoutInWidth:(CGFloat)width {
    CGRect frame = _scroll.frame;
    frame.size.width = width;
    frame.size.height = _height;
    _scroll.frame = frame;
}

/* the flag says a viewer is up; when nothing is presented over the host any more, the viewer left in a way that never ran its close handler, and the
   flag must not keep every ring dead */
- (BOOL)viewerIsOpen {
    UIViewController *host = _host.target;
    if (_viewerOpen && host && !host.presentedViewController) {
        NSLog(@"noshigram: the story viewer is gone but was never closed; the rings work again");
        _viewerOpen = NO;
    }
    return _viewerOpen;
}

/* the server's list is what the viewer pages through; an own cell that was put in front is not in it, and a tap on it starts a story */
- (void)ringTapped:(UIControl *)ring {
    UIViewController *host = _host.target;
    if (!host || [self viewerIsOpen] || (NSUInteger)ring.tag >= _cells.count) return;
    NoshiStoryPeer *cell = [_cells objectAtIndex:(NSUInteger)ring.tag];
    if (cell.count == 0) { [self addTapped]; return; }
    NSUInteger offset = _cells.count - _peers.count;
    _viewerOpen = YES;
    NoshiStoryViewerController *viewer = [[[NoshiStoryViewerController alloc] initWithSession:_session peers:_peers index:(NSUInteger)ring.tag - offset
                                                                                          avatars:_avatars media:_media] autorelease];
    NoshiWeakReference *weak = _weak;
    viewer.closeHandler = ^{
        NoshiStoryStrip *me = weak.target;
        if (!me) return;
        me->_viewerOpen = NO;
        /* what was seen now has quiet rings */
        [me reload];
    };
    [host presentViewController:viewer animated:YES completion:nil];
}

/* the camera screen makes the story; a device without a camera, or the library button of the screen, picks a photo
   instead */
- (void)addTapped {
    UIViewController *host = _host.target;
    if (!host || _posting || [self viewerIsOpen]) return;
    if (![NoshiStoryCameraController cameraAvailable]) { [self pickFromLibraryIn:host]; return; }
    NoshiStoryCameraController *camera = [[[NoshiStoryCameraController alloc] init] autorelease];
    NoshiWeakReference *weak = _weak;
    camera.session = _session;
    camera.publishHandler = ^(NSString *path, NSString *caption, NoshiStoryAudience *audience) {
        NoshiStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
        if (!me) { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; return; }
        [me postStoryAtPath:path caption:caption audience:audience];
    };
    camera.closeHandler = ^{
        NoshiStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
    };
    camera.galleryHandler = ^{
        NoshiStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        if (!top) return;
        [top dismissViewControllerAnimated:YES completion:^{ [me pickFromLibraryIn:top]; }];
    };
    [host presentViewController:camera animated:YES completion:nil];
}

- (void)pickFromLibraryIn:(UIViewController *)host {
    NoshiWeakReference *weak = _weak;
    [NoshiProfilePhotoPicker pickWholeFrom:host picked:^(NSString *path) {
        if (!path) {
            NSLog(@"noshigram: the story photo could not be prepared");
            NoshiShowNotice(nil, NSLocalizedString(@"story.add.failed", nil));
            return;
        }
        NoshiStoryStrip *me = weak.target;
        if (!me) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        /* the picker is still leaving the screen, so the editor comes a turn later */
        dispatch_async(dispatch_get_main_queue(), ^{ [me dressStoryAtPath:path]; });
    } unavailable:^{
        NoshiShowNotice(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

/* a photo from the library gets the same screen as a shot: words over it, a caption and the audience, before it goes up */
- (void)dressStoryAtPath:(NSString *)path {
    UIViewController *host = _host.target;
    if (!host) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }
    NoshiStoryCameraController *editor = [[[NoshiStoryCameraController alloc] initWithPhotoPath:path] autorelease];
    NoshiWeakReference *weak = _weak;
    editor.session = _session;
    editor.publishHandler = ^(NSString *file, NSString *caption, NoshiStoryAudience *audience) {
        NoshiStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
        if (!me) { [[NSFileManager defaultManager] removeItemAtPath:file error:NULL]; return; }
        [me postStoryAtPath:file caption:caption audience:audience];
    };
    editor.closeHandler = ^{
        NoshiStoryStrip *me = weak.target;
        UIViewController *top = me ? me->_host.target : nil;
        [top dismissViewControllerAnimated:YES completion:nil];
    };
    [host presentViewController:editor animated:YES completion:nil];
}

/* the file goes up as a story and is deleted either way; the row is asked again when it is live */
- (void)postStoryAtPath:(NSString *)path caption:(NSString *)caption audience:(NoshiStoryAudience *)audience {
    if (_posting) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }
    _posting = YES;
    NoshiWeakReference *weak = _weak;
    [_session postStoryPhotoAtPath:path caption:caption audience:audience completion:^(NSString *errorName) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NoshiStoryStrip *again = weak.target;
        if (!again) return;
        again->_posting = NO;
        if (errorName) {
            NSLog(@"noshigram: the story was not published: %@", errorName);
            NoshiShowNotice(nil, NSLocalizedString(@"story.add.failed", nil));
            return;
        }
        [again reload];
    }];
}

@end

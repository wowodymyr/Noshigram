#import "noshi_channel_picker_controller.h"

#import "noshi_gift_screen.h"
#import "noshi_people_avatars.h"
#import "noshi_person.h"
#import "noshi_session_profile.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiChannelPickerController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiWeakReference *_weak;
    NoshiPeopleAvatars *_faces;
    NSArray *_channels;
    NSString *_status;
    long long _currentChannelId;
    void (^_pickHandler)(NoshiDialog *);
}
@end

@implementation NoshiChannelPickerController

@synthesize currentChannelId = _currentChannelId;
@synthesize pickHandler = _pickHandler;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    (void)media;
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_faces invalidate];
    [_faces release];
    [_session release];
    [_avatars release];
    [_channels release];
    [_status release];
    [_pickHandler release];
    [super dealloc];
}

- (NSString *)screenTitle {
    return self.pageTitle;
}

- (void)setScreenTitle:(NSString *)title {
    self.pageTitle = title;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadChannelsForProfile:^(NSArray *items, NSString *errorName) {
        NoshiChannelPickerController *me = weak.target;
        if (!me) return;
        [me->_status release];
        if (!items) {
            me->_status = [NoshiGiftErrorText(errorName) copy];
        } else {
            [me->_channels release];
            me->_channels = [items retain];
            me->_status = [(items.count ? @"" : NSLocalizedString(@"profile.channel.none", nil)) copy];
        }
        [me rebuild];
    }];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)choose:(NoshiDialog *)channel {
    if (_pickHandler) _pickHandler(channel);
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    if (!_faces) _faces = [[NoshiPeopleAvatars alloc] initWithCache:_avatars changed:^{ [(NoshiChannelPickerController *)weak.target rebuild]; }];
    UIImage *mark = NoshiSymbolImage(NoshiSymbolCheck, 22, NoshiColorAccent());
    NoshiSettingsRow *none = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolBlock title:NSLocalizedString(@"profile.channel.remove", nil) destructive:YES
                                                                  tap:^{ [(NoshiChannelPickerController *)weak.target choose:nil]; }];
    if (_currentChannelId == 0) none.trailingImage = mark;
    NSMutableArray *rows = [NSMutableArray array];
    for (NoshiDialog *channel in _channels) {
        UIImage *face = [_faces imageForKey:[NSString stringWithFormat:@"%lld", channel.peerId] initials:channel.initials seed:channel.avatarSeed deleted:NO photo:channel.photo];
        NoshiSettingsRow *row = [NoshiSettingsRow rowWithTileImage:face title:channel.title subtitle:NSLocalizedString(@"profile.channel.kind", nil)
                                                                   tap:^{ [(NoshiChannelPickerController *)weak.target choose:channel]; }];
        if (channel.peerId == _currentChannelId) row.trailingImage = mark;
        [rows addObject:row];
    }
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:none]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:_status rows:rows]];
    self.sections = sections;
    [self reloadSettings];
}

@end

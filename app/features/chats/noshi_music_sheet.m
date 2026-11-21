#import "noshi_music_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_dismiss_pan.h"
#import "noshi_emoji_label.h"
#import "noshi_lyrics_screen.h"
#import "noshi_music_player.h"
#import "noshi_platform.h"
#import "noshi_remote_file.h"
#import "noshi_slider.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

#define ROW_HEIGHT 60.0
#define COVER_SIDE 44.0
#define HEADER_HEIGHT 190.0

@interface NoshiQueueCell : UITableViewCell {
    UIImageView *_cover;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_performer;
    NSString *_key;
    NoshiWeakReference *_weak;
}
- (void)showTrack:(NoshiMedia *)track player:(NoshiMusicPlayer *)player;
@end

@implementation NoshiQueueCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.backgroundColor = [UIColor clearColor];
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 5;
    [self.contentView addSubview:_cover];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = NoshiFontSemibold(15);
    [self.contentView addSubview:_title];
    _performer = [[NoshiEmojiLabel alloc] init];
    _performer.font = NoshiFontRegular(13);
    _performer.textColor = NoshiColorSecondary();
    [self.contentView addSubview:_performer];
    return self;
}
- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_key release];
    [_cover release];
    [_title release];
    [_performer release];
    [super dealloc];
}
- (void)showTrack:(NoshiMedia *)track player:(NoshiMusicPlayer *)player {
    _title.text = NoshiTrackTitle(track);
    _title.textColor = [player isCurrentTrack:track] ? NoshiColorAccent() : NoshiColorTitle();
    _performer.text = NoshiTrackPerformer(track);
    NSString *key = track.file.key;
    if (!(key == _key || [key isEqualToString:_key])) {
        [_key release];
        _key = [key copy];
        _cover.image = nil;
        if (key.length) {
            NoshiWeakReference *weak = _weak;
            [player.media loadCoverForTrack:track maxSide:COVER_SIDE * NoshiScreenScale() completion:^(UIImage *image) {
                NoshiQueueCell *cell = weak.target;
                if (cell && [key isEqualToString:cell->_key]) cell->_cover.image = image ? image : NoshiSymbolImage(NoshiSymbolPlayerNote, 24, NoshiColorAccent());
            }];
        }
    }
    if (!_cover.image) _cover.image = NoshiSymbolImage(NoshiSymbolPlayerNote, 24, NoshiColorAccent());
    _cover.backgroundColor = NoshiColorField();
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _cover.frame = CGRectMake(14, 8, COVER_SIDE, COVER_SIDE);
    _title.frame = CGRectMake(70, _performer.text.length ? 8 : 19, MAX(0, width - 84), 22);
    _performer.frame = CGRectMake(70, 31, MAX(0, width - 84), 19);
}
@end

@interface NoshiMusicSheet () <UITableViewDataSource, UITableViewDelegate> {
    UIView *_panel;
    UIView *_dim;
    UITableView *_table;
    UIImageView *_cover;
    NoshiEmojiLabel *_title;
    NoshiEmojiLabel *_performer;
    UISlider *_slider;
    UILabel *_elapsed;
    UILabel *_remaining;
    UIButton *_toggle;
    BOOL _scrubbing;
    BOOL _closing;
    NSArray *_shownQueue;
    NoshiMedia *_shownTrack;
    NoshiMusicState _shownState;
}
@end

@implementation NoshiMusicSheet
+ (void)present {
    UIView *host = NoshiOverlayHost();
    if (!host || ![NoshiMusicPlayer sharedPlayer].track) return;
    for (UIView *view in host.subviews) if ([view isKindOfClass:self]) return;
    NoshiMusicSheet *sheet = [[[self alloc] initWithFrame:host.bounds] autorelease];
    [host addSubview:sheet];
    [sheet enter];
}
static UIButton *SheetButton(NoshiSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:NoshiSymbolImage(symbol, 24, NoshiColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim = [[UIView alloc] initWithFrame:self.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    [self addSubview:_dim];
    _panel = [[UIView alloc] init];
    _panel.backgroundColor = NoshiColorCard();
    _panel.layer.cornerRadius = 12;
    _panel.clipsToBounds = YES;
    [self addSubview:_panel];
    NoshiAddDismissPan(_panel, self, @selector(dismiss));
    _cover = [[UIImageView alloc] init];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 5;
    [_panel addSubview:_cover];
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = NoshiFontSemibold(16);
    _title.textColor = NoshiColorTitle();
    [_panel addSubview:_title];
    _performer = [[NoshiEmojiLabel alloc] init];
    _performer.font = NoshiFontRegular(14);
    _performer.textColor = NoshiColorSecondary();
    [_panel addSubview:_performer];
    _slider = [[NoshiSlider alloc] init];
    _slider.accessibilityLabel = NSLocalizedString(@"media.seek", nil);
    [_slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_panel addSubview:_slider];
    _elapsed = [[UILabel alloc] init];
    _remaining = [[UILabel alloc] init];
    for (UILabel *label in [NSArray arrayWithObjects:_elapsed, _remaining, nil]) {
        label.backgroundColor = [UIColor clearColor]; label.font = NoshiFontRegular(12); label.textColor = NoshiColorSecondary(); [_panel addSubview:label];
    }
    _remaining.textAlignment = NoshiTextAlignmentRight;
    UIButton *previous = SheetButton(NoshiSymbolPlayerPrevious, self, @selector(previous), @"music.previous");
    previous.tag = 1; [_panel addSubview:previous];
    _toggle = [SheetButton(NoshiSymbolPlayerPlay, self, @selector(toggle), @"music.play") retain];
    [_panel addSubview:_toggle];
    UIButton *next = SheetButton(NoshiSymbolPlayerNext, self, @selector(next), @"music.next");
    next.tag = 2; [_panel addSubview:next];
    UIButton *shuffle = SheetButton(NoshiSymbolPlayerShuffle, self, @selector(shuffle), @"music.shuffle");
    shuffle.tag = 4; [_panel addSubview:shuffle];
    UIButton *repeat = SheetButton(NoshiSymbolPlayerRepeat, self, @selector(repeat), @"music.repeat");
    repeat.tag = 5; [_panel addSubview:repeat];
    UIButton *close = SheetButton(NoshiSymbolPlayerClose, self, @selector(dismiss), @"notice.cancel");
    close.tag = 3; [_panel addSubview:close];
    UIButton *lyrics = SheetButton(NoshiSymbolMaterialLyrics, self, @selector(openLyrics), @"music.lyrics");
    lyrics.tag = 6; [_panel addSubview:lyrics];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    /* the system draws a light line between the songs of the queue, which shows as a white stripe on the dark sheet; the rows have their own spacing */
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = ROW_HEIGHT;
    _table.dataSource = self; _table.delegate = self;
    [_panel addSubview:_table];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(changed:) name:NoshiMusicPlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(tick:) name:NoshiMusicPlayerDidTickNotification object:nil];
    [self refresh];
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil; _table.delegate = nil;
    [_dim release]; [_panel release]; [_table release]; [_cover release]; [_title release]; [_performer release];
    [_slider release]; [_elapsed release]; [_remaining release]; [_toggle release];
    [_shownQueue release]; [_shownTrack release];
    [super dealloc];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width, 480);
    CGFloat height = MIN(self.bounds.size.height - NoshiSafeInsets(self).top - 12, 620);
    /* the panel is moved by its transform while it comes and goes, and a frame set under a transform resizes it */
    NoshiPlaceView(_panel, CGRectMake((self.bounds.size.width - width) / 2, self.bounds.size.height - height, width, height));
    _cover.frame = CGRectMake(16, 20, 54, 54);
    _title.frame = CGRectMake(82, 23, MAX(0, width - 182), 22);
    /* a failed song gives its whole reason the room of the slider, which has nothing to show then */
    BOOL failed = [NoshiMusicPlayer sharedPlayer].state == NoshiMusicStateFailed;
    _performer.numberOfLines = failed ? 0 : 1;
    _performer.frame = failed ? CGRectMake(82, 47, MAX(0, width - 98), 74) : CGRectMake(82, 47, MAX(0, width - 182), 20);
    _slider.hidden = _elapsed.hidden = _remaining.hidden = failed;
    [_panel viewWithTag:3].frame = CGRectMake(width - 48, 8, 40, 40);
    [_panel viewWithTag:6].frame = CGRectMake(width - 92, 8, 40, 40);
    _slider.frame = CGRectMake(16, 78, width - 32, 24);
    _elapsed.frame = CGRectMake(18, 101, 64, 18);
    _remaining.frame = CGRectMake(width - 82, 101, 64, 18);
    CGFloat center = width / 2;
    _toggle.frame = CGRectMake(center - 24, 126, 48, 48);
    [_panel viewWithTag:1].frame = CGRectMake(center - 94, 126, 48, 48);
    [_panel viewWithTag:2].frame = CGRectMake(center + 46, 126, 48, 48);
    [_panel viewWithTag:4].frame = CGRectMake(center - 150, 126, 48, 48);
    [_panel viewWithTag:5].frame = CGRectMake(center + 102, 126, 48, 48);
    _table.frame = CGRectMake(0, HEADER_HEIGHT, width, MAX(0, height - HEADER_HEIGHT));
    _table.contentInset = UIEdgeInsetsMake(0, 0, NoshiSafeInsets(self).bottom, 0);
}
static NSString *SheetTime(NSTimeInterval value) {
    NSInteger seconds = MAX(0, (NSInteger)value);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}
- (void)refresh {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    if (!player.track) { [self dismiss]; return; }
    _title.text = NoshiTrackTitle(player.track);
    _performer.text = player.state == NoshiMusicStateFailed ? player.failureText : NoshiTrackPerformer(player.track);
    [self setNeedsLayout];
    _cover.image = player.cover ? player.cover : NoshiSymbolImage(NoshiSymbolPlayerNote, 28, NoshiColorAccent());
    _cover.backgroundColor = NoshiColorField();
    BOOL playing = player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStateLoading;
    [_toggle setImage:NoshiSymbolImage(playing ? NoshiSymbolPlayerPause : NoshiSymbolPlayerPlay, 28, NoshiColorTitle()) forState:UIControlStateNormal];
    _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    UIButton *shuffle = (UIButton *)[_panel viewWithTag:4];
    [shuffle setImage:NoshiSymbolImage(NoshiSymbolPlayerShuffle, 24, player.shuffle ? NoshiColorAccent() : NoshiColorTitle()) forState:UIControlStateNormal];
    shuffle.accessibilityValue = NSLocalizedString(player.shuffle ? @"music.on" : @"music.off", nil);
    UIButton *repeat = (UIButton *)[_panel viewWithTag:5];
    [repeat setImage:NoshiSymbolImage(player.repeatMode == NoshiMusicRepeatSong ? NoshiSymbolPlayerRepeatOne : NoshiSymbolPlayerRepeat, 24, player.repeatMode == NoshiMusicRepeatOff ? NoshiColorTitle() : NoshiColorAccent()) forState:UIControlStateNormal];
    repeat.accessibilityValue = NSLocalizedString(player.repeatMode == NoshiMusicRepeatSong ? @"music.repeat.song" : (player.repeatMode == NoshiMusicRepeatList ? @"music.repeat.list" : @"music.off"), nil);
    _slider.enabled = player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStatePaused;
    if (_shownQueue != player.queue || _shownTrack != player.track || _shownState != player.state) {
        [_shownQueue release]; _shownQueue = [player.queue retain];
        [_shownTrack release]; _shownTrack = [player.track retain];
        _shownState = player.state;
        [_table reloadData];
    }
    [self tick:nil];
}
/* the lyrics come up over the whole screen, with the strip of the player on top of them; the screen looks them up and says so when there are none */
- (void)openLyrics {
    [NoshiLyricsScreen present];
}
- (void)shuffle { [[NoshiMusicPlayer sharedPlayer] toggleShuffle]; }
- (void)repeat { [[NoshiMusicPlayer sharedPlayer] cycleRepeat]; }
- (void)changed:(NSNotification *)note { (void)note; [self refresh]; }
- (void)tick:(NSNotification *)note {
    (void)note;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    if (!_scrubbing) _slider.value = player.duration > 0 ? player.position / player.duration : 0;
    _elapsed.text = SheetTime(player.position);
    _remaining.text = [@"-" stringByAppendingString:SheetTime(player.duration - player.position)];
}
- (void)scrubBegan { _scrubbing = YES; }
- (void)scrubEnded { _scrubbing = NO; [[NoshiMusicPlayer sharedPlayer] seekToFraction:_slider.value]; }
- (void)previous { [[NoshiMusicPlayer sharedPlayer] previous]; }
- (void)toggle { [[NoshiMusicPlayer sharedPlayer] togglePause]; }
- (void)next { [[NoshiMusicPlayer sharedPlayer] next]; }
/* how far the panel goes to stand just below the screen, from where it rests; the top is taken from the center, which a pull by the finger does not move */
- (CGFloat)panelTravel {
    return self.bounds.size.height - (_panel.center.y - _panel.bounds.size.height / 2);
}
/* the player slides up from the bottom edge with the dim coming in under it, the way the other sheets arrive */
- (void)enter {
    [self layoutIfNeeded];
    _panel.transform = CGAffineTransformMakeTranslation(0, [self panelTravel]);
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0.5, NoshiPopupCurve(YES), nil);
    NoshiAnimateView(_panel, CGAffineTransformIdentity, 1, NoshiPopupCurve(YES), nil);
}
- (void)dismiss {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    NoshiAnimateView(_dim, CGAffineTransformIdentity, 0, NoshiPopupCurve(NO), nil);
    NoshiAnimateView(_panel, CGAffineTransformMakeTranslation(0, [self panelTravel]), 1, NoshiPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return (NSInteger)[NoshiMusicPlayer sharedPlayer].queue.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NoshiQueueCell *cell = (NoshiQueueCell *)[table dequeueReusableCellWithIdentifier:@"track"];
    if (!cell) cell = [[[NoshiQueueCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"track"] autorelease];
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    [cell showTrack:[player.queue objectAtIndex:(NSUInteger)path.row] player:player];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    [[NoshiMusicPlayer sharedPlayer] playQueueTrackAtIndex:(NSUInteger)path.row];
}
@end

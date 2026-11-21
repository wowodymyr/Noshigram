#import "noshi_video_editor.h"
#import "noshi_alert_view.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "noshi_animation.h"
#import "noshi_editor_chrome.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_video_composition.h"
#import "noshi_video_crop_view.h"
#import "noshi_video_timeline.h"
#import "noshi_weak_reference.h"
#include "noshi_video_edit.h"

#define VIDEO_FRAME_COUNT 10
/* the states of the crop button: the whole picture, a frame of any shape, then a frame of each of five shapes */
#define VIDEO_CROP_STATES 7

@interface NoshiVideoPreview : UIView
@end
@implementation NoshiVideoPreview
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface NoshiVideoEditor () {
    NSURL *_url;
    void (^_completion)(double, double, BOOL, NSInteger, BOOL, CGRect);
    NoshiWeakReference *_weak;
    AVPlayer *_player;
    AVPlayerItem *_item;
    NoshiVideoPreview *_preview;
    UIView *_playBadge;
    NoshiEditorPanel *_top;
    NoshiEditorPanel *_bottom;
    NoshiVideoTimeline *_timeline;
    NoshiEditorButton *_cancel;
    NoshiEditorButton *_done;
    NoshiEditorButton *_play;
    NoshiEditorButton *_sound;
    NoshiEditorButton *_rotate;
    NoshiEditorButton *_mirror;
    NoshiEditorButton *_cropButton;
    UILabel *_length;
    UIActivityIndicatorView *_spinner;
    CADisplayLink *_link;
    double _duration;
    double _start;
    double _end;
    BOOL _muted;
    NSInteger _turns;
    BOOL _mirrored;
    /* the state of the crop button, and the frame as fractions of the picture after its turns; empty while the whole picture is kept */
    NSUInteger _cropState;
    CGRect _crop;
    NoshiVideoCropView *_cropView;
    BOOL _playing;
    BOOL _resumeAfterDrag;
    BOOL _closed;
    BOOL _entered;
    BOOL _loaded;
}
@end

@implementation NoshiVideoEditor
- (id)initWithURL:(NSURL *)url start:(double)start end:(double)end muted:(BOOL)muted turns:(NSInteger)turns mirrored:(BOOL)mirrored crop:(CGRect)crop
      completion:(void (^)(double, double, BOOL, NSInteger, BOOL, CGRect))completion {
    self = [super init];
    if (self) {
        _url = [url retain];
        _completion = [completion copy];
        _weak = [[NoshiWeakReference referenceTo:self] retain];
        _start = start; _end = end; _muted = muted; _turns = turns; _mirrored = mirrored;
        /* a frame kept from an earlier visit opens as a frame of any shape, to be taken up where it was left */
        _crop = CGRectIsEmpty(crop) ? CGRectZero : crop;
        _cropState = CGRectIsEmpty(_crop) ? 0 : 1;
        self.wantsFullScreenLayout = YES;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}
- (void)dealloc {
    NoshiStatusBarShow(self, UIStatusBarAnimationNone);
    [_weak clear];
    [_link invalidate]; [_link release];
    [_player pause]; ((AVPlayerLayer *)_preview.layer).player = nil;
    [_player release]; [_item release]; [_url release]; [_completion release]; [_weak release];
    [_preview release]; [_playBadge release]; [_top release]; [_bottom release]; [_timeline release];
    [_cancel release]; [_done release]; [_play release]; [_sound release]; [_rotate release]; [_mirror release]; [_cropButton release];
    [_cropView release]; [_length release]; [_spinner release];
    [super dealloc];
}
- (NoshiEditorButton *)tool:(NoshiSymbol)symbol title:(NSString *)key action:(SEL)action {
    NoshiEditorButton *button = [[NoshiEditorButton alloc] initWithStyle:NoshiEditorButtonTool symbol:symbol title:NSLocalizedString(key, nil)];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_bottom.content addSubview:button];
    return button;
}
- (NoshiEditorButton *)barButton:(NSString *)key symbol:(NoshiSymbol)symbol style:(NoshiEditorButtonStyle)style action:(SEL)action {
    BOOL classic = NoshiThemeIsClassic();
    /* the old system keeps words on its bars, except for the check that finishes the work; the modern look keeps icons */
    BOOL word = classic && style != NoshiEditorButtonAccent;
    NoshiEditorButton *button = word ? [[NoshiEditorButton alloc] initWithStyle:style title:NSLocalizedString(key, nil)]
                                       : [[NoshiEditorButton alloc] initWithStyle:style symbol:symbol title:nil];
    button.accessibilityLabel = NSLocalizedString(key, nil);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_top.content addSubview:button];
    return button;
}
- (void)loadView {
    BOOL classic = NoshiThemeIsClassic();
    self.view = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    self.view.backgroundColor = [UIColor blackColor];
    _preview = [[NoshiVideoPreview alloc] init];
    ((AVPlayerLayer *)_preview.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view addSubview:_preview];
    /* the frame of the crop stands over the picture, which the preview shows whole while the frame is being shaped */
    _cropView = [[NoshiVideoCropView alloc] init];
    _cropView.hidden = YES;
    NoshiWeakReference *cropWeak = _weak;
    _cropView.changed = ^(CGRect crop) {
        NoshiVideoEditor *editor = cropWeak.target;
        if (editor) editor->_crop = crop;
    };
    [self.view addSubview:_cropView];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlay)] autorelease];
    [_preview addGestureRecognizer:tap];
    /* the mark of a paused picture, which comes back when the video stops and goes when it plays */
    _playBadge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 72)];
    _playBadge.userInteractionEnabled = NO;
    _playBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45]; _playBadge.layer.cornerRadius = 36;
    UIImageView *glyph = [[[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPlay, 30, [UIColor whiteColor])] autorelease];
    glyph.contentMode = UIViewContentModeCenter; glyph.frame = CGRectMake(4, 0, 72, 72);
    [_playBadge addSubview:glyph];
    [self.view addSubview:_playBadge];

    _top = [[NoshiEditorPanel alloc] init]; [self.view addSubview:_top];
    _cancel = [self barButton:@"attach.cancel" symbol:NoshiSymbolCross style:classic ? NoshiEditorButtonPill : NoshiEditorButtonRound action:@selector(cancel)];
    _done = [self barButton:@"media.done" symbol:NoshiSymbolCheck style:NoshiEditorButtonAccent action:@selector(done)]; _done.enabled = NO;
    _length = [[UILabel alloc] init]; _length.backgroundColor = [UIColor clearColor]; _length.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    _length.font = NoshiFontSemibold(15); _length.textAlignment = (NSTextAlignment)NoshiTextAlignmentCenter;
    [_top.content addSubview:_length];

    _bottom = [[NoshiEditorPanel alloc] init]; [self.view addSubview:_bottom];
    _timeline = [[NoshiVideoTimeline alloc] init];
    _timeline.start = _start; _timeline.end = _end; _timeline.position = _start;
    [_timeline addTarget:self action:@selector(timelineChanged) forControlEvents:UIControlEventValueChanged];
    [_timeline addTarget:self action:@selector(timelineGrabbed) forControlEvents:UIControlEventTouchDown];
    [_timeline addTarget:self action:@selector(timelineReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_bottom.content addSubview:_timeline];
    _play = [self tool:NoshiSymbolPlay title:@"video.edit.play" action:@selector(togglePlay)];
    _sound = [self tool:NoshiSymbolSpeaker title:@"video.edit.sound" action:@selector(toggleMute)];
    _rotate = [self tool:NoshiSymbolRotate title:@"media.rotate" action:@selector(rotate)];
    _mirror = [self tool:NoshiSymbolMirror title:@"media.flip" action:@selector(mirror)];
    _cropButton = [self tool:NoshiSymbolCrop title:@"video.crop.original" action:@selector(crop)];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES; [self.view addSubview:_spinner]; [_spinner startAnimating];
    _top.alpha = 0; _bottom.alpha = 0; _playBadge.alpha = 0;
    [self updateControls];
    [self loadAsset];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; NoshiStatusBarHide(self, UIStatusBarAnimationNone); }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_entered) return;
    _entered = YES;
    NoshiEditorRise([NSArray arrayWithObject:_top], -18, 0);
    NoshiEditorRise([NSArray arrayWithObject:_bottom], 36, 0);
    NoshiEditorRise([NSArray arrayWithObjects:_play, _sound, _rotate, _mirror, _cropButton, nil], 14, 0.03);
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopLink];
    [_player pause]; _playing = NO;
    NoshiStatusBarShow(self, UIStatusBarAnimationNone);
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL classic = NoshiThemeIsClassic(), floating = !classic;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets safe = NoshiSafeInsets(self.view);
    CGFloat k = NoshiEditorScale();
    CGFloat width = size.width, gap = floating ? round(10 * k) : 0;
    BOOL landscape = width > size.height && size.height < 500;
    CGFloat topY = floating ? safe.top + 8 : safe.top, topHeight = floating ? round(44 * k) : 48;
    CGFloat round40 = round(40 * k), inner = floor((topHeight - round40) / 2);
    CGFloat edgeL = floating ? 4 : safe.left + 4, edgeR = floating ? 4 : safe.right + 4;
    CGFloat topColumn = floating ? MIN(width - safe.left - safe.right - 2 * gap, round(560 * k)) : width;
    CGFloat topX = floating ? safe.left + gap + floor((width - safe.left - safe.right - 2 * gap - topColumn) / 2) : 0;
    NoshiPlaceView(_top, CGRectMake(topX, topY, topColumn, topHeight));
    if (floating) {
        _cancel.frame = CGRectMake(edgeL, inner, round40, round40);
        _done.frame = CGRectMake(topColumn - edgeR - round40, inner, round40, round40);
    } else {
        _cancel.frame = CGRectMake(edgeL, 0, 84, 48);
        _done.frame = CGRectMake(topColumn - edgeR - 56, 0, 56, 48);
    }
    _length.frame = CGRectMake(floor(topColumn / 2 - 50), 0, 100, topHeight);

    CGFloat timelineHeight = [NoshiVideoTimeline preferredHeight], toolsHeight = floating ? round(64 * k) : 56;
    CGFloat cardHeight = 10 + timelineHeight + 8 + toolsHeight + 10;
    CGFloat extend = floating ? 0 : safe.bottom;
    CGFloat panelWidth = landscape ? MIN(360, MAX(280, width * 0.46)) : (floating ? MIN(width - safe.left - safe.right - 2 * gap, round(560 * k)) : width);
    CGFloat panelX = landscape ? width - safe.right - panelWidth - (floating ? gap : 0) : (floating ? floor((width - panelWidth) / 2) : 0);
    CGFloat panelY = landscape ? MAX(topY + topHeight + 8, floor((size.height - cardHeight) / 2) + topHeight / 2) : size.height - safe.bottom - gap - cardHeight;
    if (landscape && !floating) { panelY = size.height - cardHeight - safe.bottom; }
    NoshiPlaceView(_bottom, CGRectMake(panelX, panelY, panelWidth, cardHeight + extend));
    CGFloat inset = floating ? 12 : 8;
    _timeline.frame = CGRectMake(inset, 10, panelWidth - 2 * inset, timelineHeight);
    CGFloat toolsWidth = panelWidth - 2 * (floating ? 8 : 4), toolWidth = floor(toolsWidth / 5), toolX = (panelWidth - toolWidth * 5) / 2;
    NSArray *tools = [NSArray arrayWithObjects:_play, _sound, _rotate, _mirror, _cropButton, nil];
    for (NSUInteger i = 0; i < tools.count; ++i) [(UIView *)[tools objectAtIndex:i] setFrame:CGRectMake(toolX + i * toolWidth, 10 + timelineHeight + 8, toolWidth, toolsHeight)];

    CGFloat previewTop = topY + topHeight + (floating ? 8 : 0);
    CGFloat previewRight = landscape ? panelX - 8 : width - safe.right;
    CGFloat previewBottom = landscape ? size.height - safe.bottom : panelY - 8;
    _preview.frame = CGRectMake(safe.left, previewTop, MAX(1, previewRight - safe.left), MAX(1, previewBottom - previewTop));
    _playBadge.center = _preview.center;
    _spinner.center = _preview.center;
    [self layoutCropView];
}
- (void)updateControls {
    _timeline.start = _start; _timeline.end = _end; _timeline.duration = _duration;
    _length.text = _duration > 0 ? NoshiVideoTimeText((_end - _start) * _duration) : @"";
    [_play setSymbol:_playing ? NoshiSymbolPause : NoshiSymbolPlay animated:YES];
    [_play setTitle:NSLocalizedString(_playing ? @"video.edit.pause" : @"video.edit.play", nil) animated:YES];
    [_sound setSymbol:_muted ? NoshiSymbolSpeakerSlash : NoshiSymbolSpeaker animated:YES];
    [_sound setLit:_muted animated:YES];
    _sound.accessibilityLabel = NSLocalizedString(_muted ? @"video.edit.unmute" : @"video.edit.mute", nil);
    _play.enabled = _duration > 0;
    _timeline.enabled = _duration > 0;
    NSArray *shapes = [NSArray arrayWithObjects:NSLocalizedString(@"video.crop.original", nil), NSLocalizedString(@"media.free", nil), @"1:1", @"4:3", @"3:4", @"16:9", @"9:16", nil];
    NSString *shape = [shapes objectAtIndex:MIN(_cropState, (NSUInteger)(VIDEO_CROP_STATES - 1))];
    [_cropButton setTitle:shape animated:YES];
    _cropButton.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"media.crop", nil), shape];
    [_cropButton setLit:_cropState != 0 animated:YES];
    [_rotate setLit:_turns != 0 animated:YES];
    [_mirror setLit:_mirrored animated:YES];
    [self refreshBadge];
}
- (void)refreshBadge {
    BOOL shown = _loaded && !_playing && !_timeline.activeHandle;
    NoshiAnimateView(_playBadge, shown ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.7, 0.7), shown ? 1 : 0, shown ? NOSHI_MOTION_SPRING : NOSHI_MOTION_DISMISS, nil);
}
- (void)loadAsset {
    NSURL *url = [_url retain]; NoshiWeakReference *weak = _weak;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        double duration = CMTimeGetSeconds(asset.duration);
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        BOOL valid = isfinite(duration) && duration > 0 && duration <= 86400 && tracks.count > 0;
        NSMutableArray *frames = [NSMutableArray array];
        if (valid) {
            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(160, 100);
            for (int i = 0; i < VIDEO_FRAME_COUNT; ++i) {
                CGImageRef image = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(duration * i / VIDEO_FRAME_COUNT, 600) actualTime:NULL error:NULL];
                [frames addObject:image ? [UIImage imageWithCGImage:image] : (id)[NSNull null]];
                if (image) CGImageRelease(image);
            }
        }
        NSArray *result = [frames copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            NoshiVideoEditor *editor = weak.target;
            if (editor && !editor->_closed) {
                [editor->_spinner stopAnimating];
                double from = 0, length = 0;
                if (!valid || noshi_video_edit_range(duration, editor->_start, editor->_end, &from, &length) != NOSHI_OK) {
                    UIAlertView *alert = [[[NoshiAlertClass() alloc] initWithTitle:nil message:NSLocalizedString(@"video.edit.failed", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil] autorelease];
                    [alert show];
                } else {
                    editor->_duration = duration;
                    editor->_item = [[AVPlayerItem playerItemWithAsset:asset] retain];
                    editor->_player = [[AVPlayer playerWithPlayerItem:editor->_item] retain];
                    ((AVPlayerLayer *)editor->_preview.layer).player = editor->_player;
                    if ((editor->_turns || editor->_mirrored) && ![editor applyComposition]) {
                        editor->_done.enabled = NO;
                        [editor updateControls];
                        NSLog(@"noshigram: video orientation cannot be edited");
                        [editor showEditError];
                        [result release]; [url release];
                        return;
                    }
                    editor->_loaded = YES;
                    [editor applyMute]; [editor seekTo:editor->_start];
                    editor->_timeline.position = editor->_start;
                    [editor->_timeline setFrames:result];
                    editor->_done.enabled = YES;
                    NoshiEditorPop(editor->_preview);
                    [editor updateControls]; [editor.view setNeedsLayout];
                }
            }
            [result release]; [url release];
        });
        [pool drain];
    });
}
- (void)seekTo:(double)position { if (_player) [_player seekToTime:CMTimeMakeWithSeconds(position * _duration, 600)]; }

#pragma mark - timeline

- (void)timelineGrabbed {
    _resumeAfterDrag = _playing;
    if (_playing) [self setPlaying:NO];
    [self refreshBadge];
}
- (void)timelineChanged {
    _start = _timeline.start; _end = _timeline.end;
    [self seekTo:_timeline.position];
    _length.text = NoshiVideoTimeText((_end - _start) * _duration);
}
- (void)timelineReleased {
    NoshiEditorPop(_length);
    [self updateControls];
    if (_resumeAfterDrag) {
        _resumeAfterDrag = NO;
        double time = CMTimeGetSeconds(_player.currentTime);
        if (!isfinite(time) || time < _start * _duration || time >= _end * _duration) [self seekTo:_start];
        [self setPlaying:YES];
    }
}

#pragma mark - playback

- (void)stopLink {
    [_link invalidate]; [_link release]; _link = nil;
}
/* the playhead follows the player at thirty frames a second, and the video loops inside the part that is kept */
- (void)tick:(CADisplayLink *)link {
    if (!_playing || _timeline.activeHandle) return;
    double time = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(time) || _duration <= 0) return;
    if (time >= _end * _duration) { [self seekTo:_start]; _timeline.position = _start; return; }
    _timeline.position = time / _duration;
}
- (void)setPlaying:(BOOL)playing {
    if (!_player || playing == _playing) return;
    _playing = playing;
    if (playing) {
        double time = CMTimeGetSeconds(_player.currentTime);
        if (!isfinite(time) || time < _start * _duration || time >= _end * _duration) [self seekTo:_start];
        [_player play];
        if (!_link) {
            _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
            NoshiSetFrameRate(_link, 30);
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
    } else {
        [_player pause];
        [self stopLink];
    }
    [self updateControls];
}
- (void)togglePlay { if (_player) [self setPlaying:!_playing]; }
- (void)applyMute {
    NSMutableArray *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in [_item.asset tracksWithMediaType:AVMediaTypeAudio]) {
        AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [input setVolume:_muted ? 0 : 1 atTime:kCMTimeZero]; [parameters addObject:input];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix]; mix.inputParameters = parameters; _item.audioMix = mix;
}
- (void)toggleMute { _muted = !_muted; [self applyMute]; [self updateControls]; }

#pragma mark - orientation

- (void)showEditError {
    UIAlertView *alert = [[[NoshiAlertClass() alloc] initWithTitle:nil message:NSLocalizedString(@"video.edit.failed", nil) delegate:nil
        cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil] autorelease];
    [alert show];
}
- (BOOL)applyComposition {
    if (!_item) return NO;
    /* the preview has the turns and the mirror and never the crop: the frame over the whole picture shows what the crop keeps, where a picture cut by the composition was drawn
       by the player of an old system stretched over the size of the whole video */
    AVVideoComposition *composition = _turns || _mirrored ? NoshiVideoComposition(_item.asset, _turns, _mirrored, CGRectZero) : nil;
    if ((_turns || _mirrored) && !composition) return NO;
    _item.videoComposition = composition;
    return YES;
}
/* the size of the picture the preview shows: the render size of the composition, or the natural size turned by the track's own transform */
- (CGSize)pictureSize {
    AVVideoComposition *composition = _item.videoComposition;
    if (composition) return composition.renderSize;
    NSArray *tracks = [_item.asset tracksWithMediaType:AVMediaTypeVideo];
    if (!tracks.count) return CGSizeZero;
    AVAssetTrack *track = [tracks objectAtIndex:0];
    CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    return CGSizeMake(fabs(size.width), fabs(size.height));
}
/* how much the aspect fit of the preview scales a picture of this size */
- (CGFloat)fitOfSize:(CGSize)size {
    if (size.width < 1 || size.height < 1) return 0;
    return MIN(_preview.bounds.size.width / size.width, _preview.bounds.size.height / size.height);
}
/* the player draws the new picture only after a seek, so the old shape is shown again from that moment and the picture settles in the new one with a spring;
   starting earlier turns the stale frame instead */
- (void)seekToStartThenChange:(CGAffineTransform)from {
    _timeline.position = _start;
    NoshiWeakReference *weak = _weak;
    [_player seekToTime:CMTimeMakeWithSeconds(_start * _duration, 600) completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NoshiVideoEditor *editor = weak.target;
            if (finished && editor && !editor->_closed && editor->_preview.window) NoshiAnimateEnter(editor->_preview, from, 0.5, NOSHI_MOTION_SPRING);
        });
    }];
}
- (void)rotate {
    if (!_item) return;
    NSInteger old = _turns; _turns = (_turns + 1) % 4;
    CGSize before = [self pictureSize];
    if (![self applyComposition]) { _turns = old; [self showEditError]; return; }
    [self turnCropForQuarterTurn];
    [_rotate playQuarterTurn];
    /* a quarter turn swaps the sides, and the aspect fit scales the new shape differently from the old one; the turned preview has to match the old picture's size */
    CGFloat was = [self fitOfSize:before], now = [self fitOfSize:[self pictureSize]];
    CGFloat scale = was > 0 && now > 0 ? was / now : 1;
    [self seekToStartThenChange:CGAffineTransformScale(CGAffineTransformMakeRotation((CGFloat)(-M_PI_2)), scale, scale)];
    [self updateControls];
}
- (void)mirror {
    if (!_item) return;
    _mirrored = !_mirrored;
    if (![self applyComposition]) { _mirrored = !_mirrored; [self showEditError]; return; }
    if (_cropState) _crop = CGRectMake(1 - CGRectGetMaxX(_crop), _crop.origin.y, _crop.size.width, _crop.size.height);
    [_mirror playFlip];
    [self seekToStartThenChange:CGAffineTransformMakeScale(-1, 1)];
    [self updateControls];
}
/* a quarter turn of the picture carries the frame with it: the turns come before the mirror, so over a mirrored picture the same turn runs the other way round */
- (void)turnCropForQuarterTurn {
    if (!_cropState) return;
    CGRect r = _crop;
    _crop = _mirrored ? CGRectMake(r.origin.y, 1 - CGRectGetMaxX(r), r.size.height, r.size.width)
                      : CGRectMake(1 - CGRectGetMaxY(r), r.origin.x, r.size.height, r.size.width);
}
/* the whole picture, a frame of any shape, then a centered frame of each shape; the frame stays as it is when it goes from the shapes to the free one, to be shaped further */
- (void)crop {
    if (!_item) return;
    CGSize picture = [self pictureSize];
    if (picture.width < 2 || picture.height < 2) return;
    static const double ratios[] = {1, 4.0 / 3, 3.0 / 4, 16.0 / 9, 9.0 / 16};
    _cropState = (_cropState + 1) % VIDEO_CROP_STATES;
    if (_cropState == 0) _crop = CGRectZero;
    else if (_cropState == 1) { if (CGRectIsEmpty(_crop)) _crop = CGRectMake(0, 0, 1, 1); }
    else _crop = [NoshiVideoCropView centeredCropOfRatio:ratios[_cropState - 2] inPicture:picture];
    [self layoutCropView];
    [self updateControls];
}
/* the frame stands over the picture as the preview fits it, and keeps the shape of the state while it is dragged */
- (void)layoutCropView {
    CGSize picture = _loaded ? [self pictureSize] : CGSizeZero;
    BOOL show = _cropState != 0 && picture.width > 1 && picture.height > 1 && _preview.bounds.size.width > 1;
    _cropView.hidden = !show;
    if (!show) return;
    _cropView.frame = CGRectInset(AVMakeRectWithAspectRatioInsideRect(picture, _preview.frame), -NoshiVideoCropMargin, -NoshiVideoCropMargin);
    _cropView.pictureSize = picture;
    _cropView.ratio = _cropState >= 2 && _crop.size.height > 0 ? _crop.size.width / _crop.size.height : 0;
    _cropView.crop = _crop;
}
- (void)cancel { _closed = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)done {
    double start = 0, duration = 0;
    if (noshi_video_edit_range(_duration, _start, _end, &start, &duration) != NOSHI_OK) return;
    _closed = YES;
    void (^completion)(double, double, BOOL, NSInteger, BOOL, CGRect) = [[_completion copy] autorelease];
    double from = _start, to = _end; BOOL muted = _muted, mirrored = _mirrored; NSInteger turns = _turns;
    /* a frame that keeps the whole picture is no crop, so the video is not re-encoded for nothing */
    CGRect crop = _cropState == 0 || (_crop.origin.x < 0.0005 && _crop.origin.y < 0.0005 && _crop.size.width > 0.999 && _crop.size.height > 0.999) ? CGRectZero : _crop;
    [self dismissViewControllerAnimated:YES completion:^{ if (completion) completion(from, to, muted, turns, mirrored, crop); }];
}
@end

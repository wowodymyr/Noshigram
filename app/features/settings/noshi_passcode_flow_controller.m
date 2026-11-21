#import "noshi_passcode_flow_controller.h"

#import "noshi_passcode_entry_view.h"
#import "noshi_passcode_store.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

@interface NoshiPasscodeFlowController () {
    NoshiPasscodeFlowMode _mode;
    void (^_completion)(BOOL done);
    NoshiPasscodeEntryView *_entry;
    UIButton *_cancel;
    UIButton *_options;
    /* the first typing of a new code, until the second one confirms it */
    NSString *_first;
    noshi_passcode_type _chosen;
    BOOL _finished;
}
@end

@implementation NoshiPasscodeFlowController

- (id)initWithMode:(NoshiPasscodeFlowMode)mode completion:(void (^)(BOOL))completion {
    self = [super init];
    if (!self) return nil;
    _mode = mode;
    _completion = [completion copy];
    _chosen = mode == NoshiPasscodeFlowVerify ? NoshiPasscodeType() : NOSHI_PASSCODE_PIN;
    return self;
}

- (void)dealloc {
    [_completion release];
    [_entry release];
    [_cancel release];
    [_options release];
    [_first release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    self.view = root;
    _entry = [[NoshiPasscodeEntryView alloc] initWithFrame:root.bounds];
    _entry.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _entry.type = _chosen;
    NoshiPasscodeFlowController *flow = self;
    _entry.submit = ^(NSString *code) { [flow codeEntered:code]; };
    [root addSubview:_entry];
    _cancel = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_cancel setTitle:NSLocalizedString(@"passcode.cancel", nil) forState:UIControlStateNormal];
    [_cancel setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    _cancel.titleLabel.font = NoshiFontRegular(17);
    _cancel.frame = CGRectMake(8, 22, 92, 44);
    _cancel.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    _cancel.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
    [_cancel addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancel];
    if (_mode == NoshiPasscodeFlowSetup) {
        _options = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_options setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
        _options.titleLabel.font = NoshiFontRegular(16);
        _options.frame = CGRectMake(self.view.bounds.size.width - 188, 22, 180, 44);
        _options.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        _options.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        _options.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
        [_options addTarget:self action:@selector(switchType) forControlEvents:UIControlEventTouchUpInside];
        [root addSubview:_options];
    }
    [self showStep];
}

/* the buttons sit right under the status bar (nothing in landscape on ios 7 and later), and the words start below them */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat barTop = NoshiStatusBarHeight();
    CGFloat width = self.view.bounds.size.width;
    _cancel.frame = CGRectMake(8, barTop, 92, 44);
    _options.frame = CGRectMake(width - 188, barTop, 180, 44);
    if (_entry.topInset != barTop + 44) {
        _entry.topInset = barTop + 44;
        [_entry setNeedsLayout];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_entry focus];
    if (_mode == NoshiPasscodeFlowVerify) [_entry holdForSeconds:NoshiPasscodeWaitRemaining()];
}

- (void)showStep {
    _entry.type = _chosen;
    _options.hidden = _first != nil;
    [_options setTitle:NSLocalizedString(_chosen == NOSHI_PASSCODE_PIN ? @"passcode.to.password" : @"passcode.to.pin", nil) forState:UIControlStateNormal];
    if (_mode == NoshiPasscodeFlowVerify) {
        _entry.title = NoshiPasscodeText(@"passcode.enter", _chosen);
        return;
    }
    _entry.title = NoshiPasscodeText(_first ? @"passcode.confirm" : @"passcode.new", _chosen);
    if (!_first) _entry.message = NSLocalizedString(_chosen == NOSHI_PASSCODE_PIN ? @"passcode.new.pin.info" : @"passcode.new.password.info", nil);
}

- (void)switchType {
    _chosen = _chosen == NOSHI_PASSCODE_PIN ? NOSHI_PASSCODE_PASSWORD : NOSHI_PASSCODE_PIN;
    [self showStep];
    [_entry focus];
}

- (void)cancelPressed {
    [self finish:NO];
}

- (void)finish:(BOOL)done {
    if (_finished) return;
    _finished = YES;
    [_entry resignFirstResponder];
    void (^completion)(BOOL) = [_completion retain];
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(done);
        [completion release];
    }];
}

- (void)codeEntered:(NSString *)code {
    if (_mode == NoshiPasscodeFlowVerify) {
        NSUInteger wait = 0;
        NoshiPasscodeResult result = NoshiPasscodeCheck(code, &wait);
        if (result == NoshiPasscodeResultOK) {
            [self finish:YES];
            return;
        }
        [_entry rejectCode];
        _entry.message = result == NoshiPasscodeResultWrong ? NoshiPasscodeText(@"passcode.wrong", _chosen) : nil;
        [_entry holdForSeconds:wait];
        return;
    }
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || !noshi_passcode_valid(_chosen, bytes.bytes, bytes.length)) {
        [_entry rejectCode];
        _entry.message = NoshiPasscodeText(@"passcode.invalid", _chosen);
        return;
    }
    if (!_first) {
        _first = [code copy];
        [_entry reset];
        _entry.message = nil;
        [self showStep];
        [_entry focus];
        return;
    }
    if (![_first isEqualToString:code]) {
        [_first release];
        _first = nil;
        [self showStep];
        [_entry rejectCode];
        _entry.message = NoshiPasscodeText(@"passcode.mismatch", _chosen);
        return;
    }
    if (!NoshiPasscodeSet(_chosen, code)) {
        [_first release];
        _first = nil;
        [self showStep];
        [_entry rejectCode];
        _entry.message = NoshiPasscodeText(@"passcode.failed", _chosen);
        return;
    }
    [self finish:YES];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return NoshiOrientationMask();
}
#pragma clang diagnostic pop

@end

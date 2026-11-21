#import "noshi_report_flow.h"
#import "noshi_alert_view.h"

#import "noshi_gift_screen.h"
#import "noshi_sheet.h"
#import "noshi_theme.h"
#import "noshi_session_report.h"

/* the alert with a text field starts at ios 5, which is the lowest this app runs on */
enum { NoshiAlertStylePlainTextInput = 2 };

@interface NoshiReportFlow () <UIActionSheetDelegate> {
    NoshiDialog *_dialog;
    NoshiSession *_session;
    void (^_done)(void);
}
@end

@implementation NoshiReportFlow

static NSString *const NoshiReportReasonKeys[NOSHI_REPORT_REASON_COUNT] = {
    @"report.reason.spam", @"report.reason.violence", @"report.reason.pornography", @"report.reason.childabuse",
    @"report.reason.copyright", @"report.reason.drugs", @"report.reason.personal", @"report.reason.other",
};

- (id)initWithDialog:(NoshiDialog *)dialog session:(NoshiSession *)session done:(void (^)(void))done {
    self = [super init];
    if (!self) return nil;
    _dialog = [dialog retain];
    _session = [session retain];
    _done = [done copy];
    return self;
}

- (void)dealloc {
    [_dialog release];
    [_session release];
    [_done release];
    [super dealloc];
}

+ (void)startForDialog:(NoshiDialog *)dialog session:(NoshiSession *)session host:(UIViewController *)host done:(void (^)(void))done {
    NSMutableArray *reasons = [NSMutableArray arrayWithCapacity:NOSHI_REPORT_REASON_COUNT];
    for (int reason = 0; reason < NOSHI_REPORT_REASON_COUNT; ++reason) [reasons addObject:NSLocalizedString(NoshiReportReasonKeys[reason], nil)];
    NoshiReportFlow *flow = [[NoshiReportFlow alloc] initWithDialog:dialog session:session done:done];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"report.title", nil) delegate:flow cancelButtonTitle:nil
                                              destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *title in reasons) [sheet addButtonWithTitle:title];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"picker.cancel", nil)];
    [sheet showInView:host.view];
    [sheet release];
    /* the sheet only borrows its delegate; the flow lives on until the last answer and releases itself there */
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex) {
        [self release];
        return;
    }
    [self choseReason:index];
}

/* a reason was picked from either list; "other" asks for a line first */
- (void)choseReason:(NSInteger)index {
    if (index < 0 || index >= NOSHI_REPORT_REASON_COUNT) {
        [self release];
        return;
    }
    if (index != NOSHI_REPORT_OTHER) {
        [self sendReason:(noshi_report_reason)index comment:nil];
        return;
    }
    [self askComment];
}

- (void)askComment {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"report.comment", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil) otherButtonTitles:NSLocalizedString(@"report.send", nil), nil];
    [alert setAlertViewStyle:NoshiAlertStylePlainTextInput];
    [alert show];
    [alert release];
}

/* the alert view has no protocol declared here, because UIAlertView is looked up by name */
- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    NSString *comment = [[[alert textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (index == [alert cancelButtonIndex]) {
        [self release];
        return;
    }
    /* the server rejects "other" with nothing to read, so an empty line asks again instead of sending */
    if (!comment.length) {
        [self askComment];
        return;
    }
    [self sendReason:NOSHI_REPORT_OTHER comment:comment];
}

- (void)sendReason:(noshi_report_reason)reason comment:(NSString *)comment {
    [_session reportDialog:_dialog reason:reason comment:comment completion:^(NSString *errorName) {
        if (errorName) {
            NSLog(@"noshigram: report of %lld was not taken: %@", _dialog.peerId, errorName);
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
        } else {
            NoshiGiftAlert(nil, NSLocalizedString(@"report.sent", nil));
            if (_done) _done();
        }
        [self release];
    }];
}

@end

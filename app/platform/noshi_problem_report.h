#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* the reports of the app's own failures, which go to the developer in a private message from the account of the
   person; a crash the app recorded in its log before it died */

/* looks for crashes the log holds that were not told yet, a little after the screens start, and sends them */
void NoshiProblemReportsStart(NoshiSession *session);
/* what a report is headed with: the version and the build, the processor, the system and the model of the phone; also shown in the settings */
NSString *NoshiProblemReportHeader(void);
/* the account is the developer's own, so a report to the developer would go to itself */
BOOL NoshiProblemReportIsDeveloper(NoshiSession *session);
/* sends a zip to the developer as a file (to the saved messages when the account is the developer's), whatever the crash report switch says; done runs on the queue of the session with whether the message went out */
void NoshiProblemReportSendArchive(NoshiSession *session, NSString *path, void (^done)(BOOL sent));

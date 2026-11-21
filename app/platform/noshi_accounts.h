#import <UIKit/UIKit.h>

/* the accounts signed in on this phone; one of them is active, and only that one has a connection */

/* the support directory that holds all the accounts */
NSString *NoshiAccountsRoot(void);
NSString *NoshiAccountDirectory(NSString *name);
/* the names of the accounts that are signed in, the first one first */
NSArray *NoshiAccountNames(void);
/* the name of the active account; the first one when none was chosen or the chosen one is gone */
NSString *NoshiAccountActive(void);
void NoshiAccountSetActive(NSString *name);
/* a name no account has used, with its directory made */
NSString *NoshiAccountMakeNew(void);
/* takes an account that never signed in, or signed out, off the disk; the first one only loses its record */
void NoshiAccountRemove(NSString *name);

/* what the list of accounts shows for an account that is not connected: the name, the username, and the user id to tell the same person twice */
NSDictionary *NoshiAccountInfo(NSString *name);
void NoshiAccountSetInfo(NSString *name, NSString *title, NSString *username, long long userId);
/* the profile photo of an account, kept on the phone so the list can show it while the account has no connection; nil when it has none or none was kept */
UIImage *NoshiAccountPhoto(NSString *name);
void NoshiAccountSetPhoto(NSString *name, UIImage *image);
/* the account lost its photo: the one kept would show on in the list of accounts */
void NoshiAccountClearPhoto(NSString *name);
/* keeps the photo of the person for the active account, or drops the kept one when the person has none; the list of accounts draws it for an account without a connection */
@class NoshiPerson, NoshiAvatarCache;
void NoshiAccountKeepPhotoOfPerson(NoshiPerson *person, NoshiAvatarCache *avatars);
/* the name of another account that is signed in as the same user, or nil */
NSString *NoshiAccountNameOfUser(long long userId, NSString *except);

/* posted by the account page: the active account is to become userInfo[@"name"], or a new one is to be signed in */
extern NSString *const NoshiAccountSwitchNotification;
extern NSString *const NoshiAccountAddNotification;

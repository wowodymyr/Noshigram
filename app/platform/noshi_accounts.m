#import "noshi_accounts.h"

#import "noshi_avatar_cache.h"
#import "noshi_person.h"
#import "noshi_session.h"

NSString *const NoshiAccountSwitchNotification = @"NoshiAccountSwitchNotification";
NSString *const NoshiAccountAddNotification = @"NoshiAccountAddNotification";

static NSString *const NoshiAccountActiveKey = @"noshigram.account.active";
static NSString *const NoshiAccountInfoKey = @"noshigram.account.info";
static NSString *const NoshiAccountPrefix = @"account-";

NSString *NoshiAccountsRoot(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: cannot create %@: %@", directory, error);
    }
    return directory;
}

NSString *NoshiAccountDirectory(NSString *name) {
    return name.length ? [NoshiAccountsRoot() stringByAppendingPathComponent:name] : NoshiAccountsRoot();
}

NSArray *NoshiAccountNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    if ([NoshiSession hasAccountInDirectory:NoshiAccountsRoot()]) [names addObject:@""];
    NSArray *entries = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:NoshiAccountsRoot() error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:NoshiAccountPrefix]) continue;
        if ([NoshiSession hasAccountInDirectory:NoshiAccountDirectory(entry)]) [names addObject:entry];
    }
    return names;
}

NSString *NoshiAccountActive(void) {
    NSArray *names = NoshiAccountNames();
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:NoshiAccountActiveKey];
    if (chosen && [names containsObject:chosen]) return chosen;
    return names.count ? [names objectAtIndex:0] : @"";
}

void NoshiAccountSetActive(NSString *name) {
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:NoshiAccountActiveKey];
}

NSString *NoshiAccountMakeNew(void) {
    NSInteger number = 2;
    NSString *name;
    do {
        name = [NoshiAccountPrefix stringByAppendingFormat:@"%ld", (long)number++];
    } while ([[NSFileManager defaultManager] fileExistsAtPath:NoshiAccountDirectory(name)]);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:NoshiAccountDirectory(name) withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: cannot create the account directory %@: %@", name, error);
        return nil;
    }
    return name;
}

static NSDictionary *NoshiAccountInfos(void) {
    NSDictionary *infos = [[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiAccountInfoKey];
    return infos ? infos : [NSDictionary dictionary];
}

static NSString *NoshiAccountPhotoPath(NSString *name) {
    return [NoshiAccountDirectory(name) stringByAppendingPathComponent:@"account_photo.png"];
}

void NoshiAccountRemove(NSString *name) {
    NSMutableDictionary *infos = [NSMutableDictionary dictionaryWithDictionary:NoshiAccountInfos()];
    [infos removeObjectForKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:infos forKey:NoshiAccountInfoKey];
    [[NSFileManager defaultManager] removeItemAtPath:NoshiAccountPhotoPath(name) error:NULL];
    if (!name.length) return;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:NoshiAccountDirectory(name) error:&error]) NSLog(@"noshigram: the account directory %@ stays: %@", name, error);
}

NSDictionary *NoshiAccountInfo(NSString *name) {
    return [NoshiAccountInfos() objectForKey:name];
}

void NoshiAccountSetInfo(NSString *name, NSString *title, NSString *username, long long userId) {
    NSMutableDictionary *infos = [NSMutableDictionary dictionaryWithDictionary:NoshiAccountInfos()];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:title ? title : @"", @"title", username ? username : @"", @"username",
                          [NSNumber numberWithLongLong:userId], @"user", nil];
    [infos setObject:info forKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:infos forKey:NoshiAccountInfoKey];
}

UIImage *NoshiAccountPhoto(NSString *name) {
    return [UIImage imageWithContentsOfFile:NoshiAccountPhotoPath(name)];
}

void NoshiAccountSetPhoto(NSString *name, UIImage *image) {
    if (!image || image.size.width < 1 || image.size.height < 1) return;
    /* the list draws it at 48 points, so a picture of 128 pixels is enough for any screen scale */
    CGFloat scale = MIN(1, 128.0 / MAX(image.size.width, image.size.height));
    CGSize size = CGSizeMake(MAX(1, floor(image.size.width * scale)), MAX(1, floor(image.size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(size, NO, 1);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    /* a photo with see-through parts keeps them, which a jpeg would turn black */
    NSData *data = UIImagePNGRepresentation(small);
    NSString *path = NoshiAccountPhotoPath(name);
    NSError *error = nil;
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) NSLog(@"noshigram: the photo of the account %@ was not kept: %@", name, error);
}

void NoshiAccountClearPhoto(NSString *name) {
    NSString *path = NoshiAccountPhotoPath(name);
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        NSLog(@"noshigram: the photo of the account %@ stays: %@", name, error);
    }
}

void NoshiAccountKeepPhotoOfPerson(NoshiPerson *person, NoshiAvatarCache *avatars) {
    NSString *name = [[NoshiAccountActive() copy] autorelease];
    if (!person.photo) {
        NoshiAccountClearPhoto(name);
        return;
    }
    [avatars loadImageForPhoto:person.photo completion:^(UIImage *image) { if (image) NoshiAccountSetPhoto(name, image); }];
}

NSString *NoshiAccountNameOfUser(long long userId, NSString *except) {
    NSDictionary *infos = NoshiAccountInfos();
    for (NSString *name in NoshiAccountNames()) {
        if ([name isEqualToString:except]) continue;
        if ([[[infos objectForKey:name] objectForKey:@"user"] longLongValue] == userId) return name;
    }
    return nil;
}

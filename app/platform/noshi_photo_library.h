#import <UIKit/UIKit.h>

BOOL NoshiPhotosAvailable(void);
void NoshiRecentPhotos(NSUInteger limit, void (^completion)(NSArray *assets, NSString *error));
NSURL *NoshiPhotoURL(id asset);
BOOL NoshiPhotoURLIsVideo(NSURL *url);
/* whether the picture is a gif, which is sent as it is so that it keeps moving */
BOOL NoshiPhotoURLIsGif(NSURL *url);
/* the length in seconds of the video this asset is, 0 for a picture */
NSTimeInterval NoshiPhotoVideoDuration(id asset);
void NoshiPhotoThumbnail(id asset, CGFloat side, void (^completion)(UIImage *image));
int NoshiPhotoPreview(NSURL *url, void (^completion)(UIImage *image, NSURL *movie, NSString *error));
/* the file as the library holds it, not the version shrunk for the screen: its bytes, the extension of its type
   and its name */
int NoshiPhotoOriginal(NSURL *url, void (^completion)(NSData *data, NSString *extension, NSString *name, NSString *error));
void NoshiCancelPhotoRequest(int request);

#import <UIKit/UIKit.h>

/* what a downloaded file turns out to be, from its first bytes */
typedef enum {
    NoshiFileFormatUnknown,
    NoshiFileFormatWebP,
    NoshiFileFormatGzip,      /* a lottie sticker */
    NoshiFileFormatMatroska,  /* a vp9 video sticker */
    NoshiFileFormatMP4        /* the clip of a gif or a video whose only preview is a clip */
} NoshiFileFormat;

NoshiFileFormat NoshiFileFormatOfData(NSData *data);

/* turns picture bytes into an image no larger than maxSide pixels on its longer side */
UIImage *NoshiDecodeImage(NSData *data, CGFloat maxSide);

/* file-backed ImageIO thumbnails avoid decoding a camera original at its full size */
UIImage *NoshiDecodeImageAtURL(NSURL *url, CGFloat maxSide);

/* fits the visible alpha bounds to the same square used by ordinary emoji */
UIImage *NoshiFitEmojiImage(UIImage *image);



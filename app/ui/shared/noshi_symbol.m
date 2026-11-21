#import "noshi_symbol.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_symbol_paths.h"

/* the bundled mask of a symbol, resources/icons/symbol_*, cut drawables by tools/make_assets.py */
static NSString *NoshiSymbolMaskName(NoshiSymbol symbol) {
    switch (symbol) {
    case NoshiSymbolMagnifier: return @"symbol_magnifier";
    case NoshiSymbolPlusCircle: return @"symbol_pluscircle";
    case NoshiSymbolCompose: return @"symbol_compose";
    case NoshiSymbolBookmark: return @"symbol_bookmark";
    case NoshiSymbolPin: return @"symbol_pin";
    case NoshiSymbolBellSlash: return @"symbol_bellslash";
    case NoshiSymbolArchive: return @"symbol_archive";
    case NoshiSymbolChevronRight: return @"symbol_chevronright";
    case NoshiSymbolCheck: return @"symbol_check";
    case NoshiSymbolCheckDouble: return @"symbol_checkdouble";
    case NoshiSymbolKeyboard: return @"symbol_keyboard";
    case NoshiSymbolSendArrow: return @"symbol_sendarrow";
    case NoshiSymbolClock: return @"symbol_clock";
    case NoshiSymbolArrowDown: return @"symbol_arrowdown";
    case NoshiSymbolPlay: return @"symbol_play";
    case NoshiSymbolDocument: return @"symbol_document";
    case NoshiSymbolSticker: return @"symbol_sticker";
    case NoshiSymbolBackspace: return @"symbol_backspace";
    case NoshiSymbolMicrophone:
    case NoshiSymbolMicrophoneSlash: return @"symbol_microphone";
    case NoshiSymbolVideoCamera: return @"symbol_videocamera";
    case NoshiSymbolCameraFlip: return @"symbol_cameraflip";
    case NoshiSymbolPaperclip: return @"symbol_paperclip";
    case NoshiSymbolGallery: return @"symbol_gallery";
    case NoshiSymbolMapPin: return @"symbol_mappin";
    case NoshiSymbolLock: return @"symbol_lock";
    /* one shape of the dots in the whole app: the vertical one, whatever name a screen asks for */
    case NoshiSymbolEllipsis: return @"symbol_ellipsisvertical";
    case NoshiSymbolSun: return @"symbol_sun";
    case NoshiSymbolMoon: return @"symbol_moon";
    case NoshiSymbolMegaphone: return @"symbol_megaphone";
    case NoshiSymbolGift: return @"symbol_gift";
    case NoshiSymbolHeart: return @"symbol_heart";
    case NoshiSymbolHeartOutline: return @"symbol_heartoutline";
    case NoshiSymbolStar: return @"symbol_star";
    case NoshiSymbolClose: return @"symbol_close";
    case NoshiSymbolTrashCan: return @"symbol_trashcan";
    case NoshiSymbolTrashLid: return @"symbol_trashlid";
    case NoshiSymbolTrash: return @"symbol_trashcan";
    case NoshiSymbolAt: return @"symbol_at";
    case NoshiSymbolCake: return @"symbol_cake";
    case NoshiSymbolLogout: return @"symbol_logout";
    case NoshiSymbolQr: return @"symbol_qr";
    case NoshiSymbolLink: return @"symbol_link";
    case NoshiSymbolMusic: return @"symbol_music";
    case NoshiSymbolPause: return @"symbol_pause";
    case NoshiSymbolNext: return @"symbol_next";
    case NoshiSymbolPrevious: return @"symbol_previous";
    case NoshiSymbolEyeSlash: return @"symbol_eyeslash";
    case NoshiSymbolSpeaker: return @"symbol_speaker";
    case NoshiSymbolSpeakerSlash: return @"symbol_speakerslash";
    case NoshiSymbolEllipsisVertical: return @"symbol_ellipsisvertical";
    case NoshiSymbolBell: return @"symbol_bell";
    case NoshiSymbolEye: return @"symbol_eye";
    case NoshiSymbolShare: return @"symbol_share";
    case NoshiSymbolBellMuted: return @"symbol_bellmuted";
    case NoshiSymbolPinnedList: return @"symbol_pinnedlist";
    case NoshiSymbolBroom: return @"symbol_broom";
    case NoshiSymbolBack: return @"symbol_back";
    case NoshiSymbolExternalLink: return @"symbol_externallink";
    case NoshiSymbolApps: return @"symbol_apps";
    case NoshiSymbolCopy: return @"symbol_copy";
    case NoshiSymbolFingerprint: return @"symbol_fingerprint";
    case NoshiSymbolStars: return @"symbol_stars";
    case NoshiSymbolCrop: return @"symbol_crop";
    case NoshiSymbolAdjust: return @"symbol_adjust";
    case NoshiSymbolDraw: return @"symbol_draw";
    case NoshiSymbolRotate: return @"symbol_rotate";
    case NoshiSymbolMirror: return @"symbol_mirror";
    case NoshiSymbolHeaderDraw: return @"symbol_headerdraw";
    case NoshiSymbolMember: return @"symbol_member";
    case NoshiSymbolReport: return @"symbol_report";
    case NoshiSymbolReply: return @"symbol_reply";
    case NoshiSymbolForward: return @"symbol_forward";
    case NoshiSymbolUnpin: return @"symbol_unpin";
    case NoshiSymbolInfo: return @"symbol_info";
    case NoshiSymbolRepeat: return @"symbol_repeat";
    case NoshiSymbolSettingsAccount: return @"symbol_settingsaccount";
    case NoshiSymbolSettingsChat: return @"symbol_settingschat";
    case NoshiSymbolSettingsStickers: return @"symbol_settingsstickers";
    case NoshiSymbolSettingsPrivacy: return @"symbol_settingsprivacy";
    case NoshiSymbolSettingsSounds: return @"symbol_settingssounds";
    case NoshiSymbolSettingsData: return @"symbol_settingsdata";
    case NoshiSymbolSettingsFolders: return @"symbol_settingsfolders";
    case NoshiSymbolSettingsDevices: return @"symbol_settingsdevices";
    case NoshiSymbolSettingsPower: return @"symbol_settingspower";
    case NoshiSymbolSettingsLanguage: return @"symbol_settingslanguage";
    case NoshiSymbolSettingsPremium: return @"symbol_settingspremium";
    case NoshiSymbolSettingsStars: return @"symbol_settingsstars";
    case NoshiSymbolSettingsBusiness: return @"symbol_settingsbusiness";
    case NoshiSymbolSettingsGift: return @"symbol_settingsgift";
    case NoshiSymbolSettingsAsk: return @"symbol_settingsask";
    case NoshiSymbolSettingsFaq: return @"symbol_settingsfaq";
    case NoshiSymbolSettingsFeatures: return @"symbol_settingsfeatures";
    case NoshiSymbolSettingsPolicy: return @"symbol_settingspolicy";
    case NoshiSymbolBlock: return @"symbol_block";
    case NoshiSymbolQrMini: return @"symbol_qrmini";
    case NoshiSymbolGlobe: return @"symbol_globe";
    case NoshiSymbolTranslate: return @"symbol_translate";
    case NoshiSymbolMessage: return @"symbol_message";
    case NoshiSymbolAppDevices: return @"symbol_appdevices";
    case NoshiSymbolDeviceAndroid: return @"symbol_deviceandroid";
    case NoshiSymbolDeviceAndroidTablet: return @"symbol_deviceandroidtablet";
    case NoshiSymbolDeviceIphone: return @"symbol_deviceiphone";
    case NoshiSymbolDeviceIpad: return @"symbol_deviceipad";
    case NoshiSymbolDeviceWindows: return @"symbol_devicewindows";
    case NoshiSymbolDeviceMac: return @"symbol_devicemac";
    case NoshiSymbolDeviceDesktop: return @"symbol_devicedesktop";
    case NoshiSymbolDeviceChrome: return @"symbol_devicechrome";
    case NoshiSymbolDeviceEdge: return @"symbol_deviceedge";
    case NoshiSymbolDeviceFirefox: return @"symbol_devicefirefox";
    case NoshiSymbolDeviceOpera: return @"symbol_deviceopera";
    case NoshiSymbolDeviceSafari: return @"symbol_devicesafari";
    case NoshiSymbolDeviceWeb: return @"symbol_deviceweb";
    case NoshiSymbolFileHQ: return @"symbol_filehq";
    case NoshiSymbolSpoiler: return @"symbol_spoiler";
    case NoshiSymbolQualitySD: return @"symbol_qualitysd";
    case NoshiSymbolQualityHD: return @"symbol_qualityhd";
    case NoshiSymbolCallback: return @"symbol_callback";
    case NoshiSymbolVideoCallMenu: return @"symbol_videocall";
    case NoshiSymbolBackground: return @"symbol_background";
    case NoshiSymbolGroupsMenu: return @"symbol_groupsmenu";
    case NoshiSymbolClearHistory: return @"symbol_clearhistory";
    case NoshiSymbolHelp: return @"symbol_help";
    case NoshiSymbolSettingsOld: return @"symbol_settingsold";
    case NoshiSymbolFave: return @"symbol_fave";
    case NoshiSymbolPinLine: return @"symbol_pinline";
    case NoshiSymbolGhost: return @"symbol_ghost";
    case NoshiSymbolPlayerPlay: return @"player_play";
    case NoshiSymbolPlayerPause: return @"player_pause";
    case NoshiSymbolPlayerPrevious: return @"player_previous";
    case NoshiSymbolPlayerNext: return @"player_next";
    case NoshiSymbolPlayerClose: return @"player_close";
    case NoshiSymbolMaterialMic: return @"material_mic";
    case NoshiSymbolMaterialVideocam: return @"material_videocam";
    case NoshiSymbolPlayerShuffle: return @"player_shuffle";
    case NoshiSymbolPlayerRepeat: return @"player_repeat";
    case NoshiSymbolPlayerRepeatOne: return @"player_repeat_one";
    case NoshiSymbolPlayerNote: return @"player_note";
    case NoshiSymbolMaterialLyrics: return @"material_lyrics";
    case NoshiSymbolMaterialCheck: return @"material_check";
    case NoshiSymbolMaterialDoneAll: return @"material_done_all";
    case NoshiSymbolMaterialSchedule: return @"material_schedule";
    case NoshiSymbolMaterialError: return @"material_error";
    case NoshiSymbolMaterialCloseOutlined: return @"material_close_outlined";
    case NoshiSymbolSpeed: return @"symbol_speed";
    case NoshiSymbolSpeedVerySlow: return @"symbol_speedveryslow";
    case NoshiSymbolSpeedSlow: return @"symbol_speedslow";
    case NoshiSymbolSpeedNormal: return @"symbol_speednormal";
    case NoshiSymbolSpeedFast: return @"symbol_speedfast";
    case NoshiSymbolSpeedVeryFast: return @"symbol_speedveryfast";
    case NoshiSymbolCopyPhoto: return @"symbol_copyphoto";
    case NoshiSymbolShareOut: return @"symbol_shareout";
    case NoshiSymbolLinkStory: return @"symbol_link2";
    case NoshiSymbolHammer: return nil;
    case NoshiSymbolStatistics: return nil;
    case NoshiSymbolCameraPlus: return nil;
    case NoshiSymbolBlur: return nil;
    case NoshiSymbolPipette: return nil;
    case NoshiSymbolUndo: return nil;
    case NoshiSymbolCross: return nil;
    case NoshiSymbolChats: return nil;
    case NoshiSymbolPerson: return nil;
    case NoshiSymbolGear: return nil;
    case NoshiSymbolSmiley: return nil;
    case NoshiSymbolPhone: return nil;
    case NoshiSymbolProfileMessage: return nil;
    case NoshiSymbolProfileMute: return nil;
    case NoshiSymbolProfileUnmute: return nil;
    }
    return nil;
}

/* a claw hammer on a slant, in one color, drawn on a grid of 24 units as the bundled glyphs are cut: a handle with round ends, a head with soft corners, and a claw
   that curls from the head to the left */
static UIImage *NoshiHammerImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [color setFill];
    CGFloat unit = side / 24 * 0.72;
    CGContextTranslateCTM(context, side / 2, side / 2);
    CGContextScaleCTM(context, unit, unit);
    CGContextRotateCTM(context, (CGFloat)(M_PI / 4));
    CGContextTranslateCTM(context, -12, -12);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(10.5, 7, 3, 16) cornerRadius:1.5] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.2, 2, 11, 6.4) cornerRadius:1.4] fill];
    UIBezierPath *claw = [UIBezierPath bezierPath];
    [claw moveToPoint:CGPointMake(8, 2.6)];
    [claw addCurveToPoint:CGPointMake(2, 5.8) controlPoint1:CGPointMake(5.6, 2.4) controlPoint2:CGPointMake(3.4, 3.6)];
    [claw addCurveToPoint:CGPointMake(3.6, 8.0) controlPoint1:CGPointMake(2.2, 6.8) controlPoint2:CGPointMake(2.8, 7.6)];
    [claw addCurveToPoint:CGPointMake(8, 6.9) controlPoint1:CGPointMake(4.6, 6.8) controlPoint2:CGPointMake(6, 6.4)];
    [claw closePath];
    [claw fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* three rounded bars that rise from left to right, on a grid of 24 units */
static UIImage *NoshiStatisticsImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [color setFill];
    CGContextScaleCTM(context, side / 24, side / 24);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.5, 12.5, 4.6, 8) cornerRadius:1.4] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.7, 7.5, 4.6, 13) cornerRadius:1.4] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(15.9, 3.5, 4.6, 17) cornerRadius:1.4] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a camera with the plus of "add" cut into its lower right corner, on a grid of 24 units */
static UIImage *NoshiCameraPlusImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(context, side / 24, side / 24);
    [color setFill];
    UIBezierPath *camera = [UIBezierPath bezierPath];
    [camera appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(1.5, 6.2, 19, 14.3) cornerRadius:3.2]];
    [camera appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7.2, 3, 7.4, 5) cornerRadius:1.6]];
    /* the lens is a hole: even odd fill */
    [camera appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6.6, 9.6, 8.4, 8.4)]];
    camera.usesEvenOddFillRule = YES;
    [camera fill];
    /* the plus has a clear ring round it, cut out of the body, so it stands on its own */
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeClear);
    CGContextFillEllipseInRect(context, CGRectMake(13.2, 12.2, 10.8, 10.8));
    CGContextRestoreGState(context);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(17.6, 14.4, 1.9, 6.4) cornerRadius:0.95] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(15.35, 16.65, 6.4, 1.9) cornerRadius:0.95] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a drop on a grid of 24 units, with a small clear glint cut into its lower left so it reads as water and not as a pin */
static UIImage *NoshiBlurImage(CGFloat side, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(context, side / 24, side / 24);
    [color setFill];
    UIBezierPath *drop = [UIBezierPath bezierPath];
    [drop moveToPoint:CGPointMake(12, 2.2)];
    [drop addCurveToPoint:CGPointMake(18.8, 14) controlPoint1:CGPointMake(13.3, 6.2) controlPoint2:CGPointMake(18.8, 9.6)];
    [drop addCurveToPoint:CGPointMake(12, 21.4) controlPoint1:CGPointMake(18.8, 18) controlPoint2:CGPointMake(15.8, 21.4)];
    [drop addCurveToPoint:CGPointMake(5.2, 14) controlPoint1:CGPointMake(8.2, 21.4) controlPoint2:CGPointMake(5.2, 18)];
    [drop addCurveToPoint:CGPointMake(12, 2.2) controlPoint1:CGPointMake(5.2, 9.6) controlPoint2:CGPointMake(10.7, 6.2)];
    [drop closePath];
    [drop fill];
    CGContextSetBlendMode(context, kCGBlendModeClear);
    UIBezierPath *glint = [UIBezierPath bezierPath];
    [glint addArcWithCenter:CGPointMake(12, 14.4) radius:4.3 startAngle:(CGFloat)(M_PI * 0.62) endAngle:(CGFloat)(M_PI * 0.98) clockwise:YES];
    glint.lineWidth = 1.7;
    glint.lineCapStyle = kCGLineCapRound;
    [glint stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* a path in the notation of the vector drawables of the exteraless editor (absolute M, L, H, V, C and Z), on a square grid of the given size; the icons that came from there
   are kept as their own numbers instead of being redrawn by eye */
static UIBezierPath *NoshiVectorPath(const char *d) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint current = CGPointZero, start = CGPointZero;
    char command = 0;
    const char *p = d;
    while (*p) {
        while (*p == ' ' || *p == ',' || *p == '\n') ++p;
        if (!*p) break;
        if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
            command = *p++;
            if (command == 'Z' || command == 'z') { [path closePath]; current = start; command = 0; continue; }
        } else if (!command) break;
        double v[6];
        int need = command == 'C' ? 6 : (command == 'H' || command == 'V' ? 1 : 2);
        if (command != 'C' && command != 'M' && command != 'L' && command != 'H' && command != 'V') break;
        for (int i = 0; i < need; ++i) {
            char *end = NULL;
            v[i] = strtod(p, &end);
            if (end == p) return path;
            p = end;
            while (*p == ' ' || *p == ',') ++p;
        }
        if (command == 'M') { current = CGPointMake((CGFloat)v[0], (CGFloat)v[1]); start = current; [path moveToPoint:current]; command = 'L'; }
        else if (command == 'L') { current = CGPointMake((CGFloat)v[0], (CGFloat)v[1]); [path addLineToPoint:current]; }
        else if (command == 'H') { current.x = (CGFloat)v[0]; [path addLineToPoint:current]; }
        else if (command == 'V') { current.y = (CGFloat)v[0]; [path addLineToPoint:current]; }
        else {
            [path addCurveToPoint:CGPointMake((CGFloat)v[4], (CGFloat)v[5]) controlPoint1:CGPointMake((CGFloat)v[0], (CGFloat)v[1]) controlPoint2:CGPointMake((CGFloat)v[2], (CGFloat)v[3])];
            current = CGPointMake((CGFloat)v[4], (CGFloat)v[5]);
        }
    }
    return path;
}

/* filled when stroke is 0, otherwise a round stroke of that width in grid units */
static UIImage *NoshiVectorImage(CGFloat side, UIColor *color, const char *d, CGFloat grid, CGFloat stroke) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), side / grid, side / grid);
    UIBezierPath *path = NoshiVectorPath(d);
    if (stroke > 0) {
        path.lineWidth = stroke; path.lineCapStyle = kCGLineCapRound; path.lineJoinStyle = kCGLineJoinRound;
        [color setStroke]; [path stroke];
    } else {
        path.usesEvenOddFillRule = YES;
        [color setFill]; [path fill];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the @3x bitmap of a mask (or the best one the bundle has) drawn into an alpha only bitmap of side x side pixels; NULL when the bundle has none, and the
   caller keeps the plain mask */
static CGImageRef NoshiCreateScaledMask(NSString *name, size_t side) {
    if (side < 2 || side > 512) return NULL;
    UIImage *source = nil;
    for (NSString *suffix in [NSArray arrayWithObjects:@"@3x", @"@2x", @"", nil]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:[name stringByAppendingString:suffix] ofType:@"png"];
        if (path) source = [UIImage imageWithContentsOfFile:path];
        if (source.CGImage) break;
    }
    if (!source.CGImage || CGImageGetWidth(source.CGImage) < side) return NULL;
    CGContextRef bitmap = CGBitmapContextCreate(NULL, side, side, 8, side, NULL, kCGImageAlphaOnly);
    if (!bitmap) return NULL;
    CGContextSetInterpolationQuality(bitmap, kCGInterpolationHigh);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, side, side), source.CGImage);
    CGImageRef scaled = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    return scaled;
}

/* the mask filled with color; a bitmap on every system, so the glyphs look the same from ios 5 to the newest release */
static UIImage *NoshiRenderSymbolImage(NoshiSymbol symbol, CGFloat pointSize, UIColor *color) {
    if (symbol == NoshiSymbolHammer) return NoshiHammerImage(pointSize, color);
    if (symbol == NoshiSymbolStatistics) return NoshiStatisticsImage(pointSize, color);
    if (symbol == NoshiSymbolCameraPlus) return NoshiCameraPlusImage(pointSize, color);
    if (symbol == NoshiSymbolBlur) return NoshiBlurImage(pointSize, color);
    if (symbol == NoshiSymbolPipette) return NoshiVectorImage(pointSize, color, "M11.793,7.207L11.293,6.707C10.902,6.317 10.902,5.683 11.293,5.293C11.683,4.902 12.317,4.902 12.707,5.293L13.707,6.293L16.439,3.561C17.025,2.975 17.975,2.975 18.561,3.561L20.439,5.439C21.025,6.025 21.025,6.975 20.439,7.561L17.707,10.293L18.707,11.293C19.098,11.683 19.098,12.317 18.707,12.707C18.317,13.098 17.683,13.098 17.293,12.707L16.793,12.207L8.879,20.121C8.316,20.684 7.553,21 6.757,21H4C3.448,21 3,20.552 3,20V17.243C3,16.447 3.316,15.684 3.879,15.121L5.06,16.302C4.81,16.552 4.67,16.89 4.67,17.243V19.33H6.757C7.11,19.33 7.448,19.19 7.698,18.941L15.612,11.026L12.974,8.388L5.06,16.302L3.879,15.121L11.793,7.207Z", 24, 0);
    if (symbol == NoshiSymbolUndo) return NoshiVectorImage(pointSize, color, "M34 58.5H41.5C50.6127 58.5 58 51.1127 58 42C58 32.8873 50.6127 25.5 41.5 25.5H16M29.5 39L16 25.5L29.5 12", 72, 5);
    if (symbol == NoshiSymbolChats) return NoshiVectorImage(pointSize, color, NoshiPathChats, NOSHI_PATH_CHATS_GRID, 0);
    if (symbol == NoshiSymbolPerson) return NoshiVectorImage(pointSize, color, NoshiPathPerson, NOSHI_PATH_PERSON_GRID, 0);
    if (symbol == NoshiSymbolGear) return NoshiVectorImage(pointSize, color, NoshiPathGear, NOSHI_PATH_GEAR_GRID, 0);
    if (symbol == NoshiSymbolSmiley) return NoshiVectorImage(pointSize, color, NoshiPathSmiley, NOSHI_PATH_SMILEY_GRID, 0);
    if (symbol == NoshiSymbolPhone) return NoshiVectorImage(pointSize, color, NoshiPathPhone, NOSHI_PATH_PHONE_GRID, 0);
    if (symbol == NoshiSymbolProfileMessage) return NoshiVectorImage(pointSize, color, NoshiPathProfileMessage, NOSHI_PATH_PROFILE_GRID, 0);
    if (symbol == NoshiSymbolProfileMute) return NoshiVectorImage(pointSize, color, NoshiPathProfileMute, NOSHI_PATH_PROFILE_GRID, 0);
    if (symbol == NoshiSymbolProfileUnmute) return NoshiVectorImage(pointSize, color, NoshiPathProfileUnmute, NOSHI_PATH_PROFILE_GRID, 0);
    if (symbol == NoshiSymbolCross) return NoshiVectorImage(pointSize, color, "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12Z", 24, 0);
    NSString *name = NoshiSymbolMaskName(symbol);
    UIImage *mask = name ? [UIImage imageNamed:name] : nil;
    if (!mask) {
        NSLog(@"noshigram: symbol %d has no bitmap in the bundle", (int)symbol);
        return nil;
    }
    CGSize size = CGSizeMake(pointSize, pointSize);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [color setFill];
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
    CGRect box = CGRectMake(0, 0, size.width, size.height);
    CGContextSaveGState(context);
    /* the largest bitmap of the mask, brought to the exact pixels of the glyph with the best filter; the clip of a mask drawn at its own size and scaled by the
       context was soft, and the check marks, which are small and thin, showed it */
    CGImageRef sharp = symbol == NoshiSymbolTrash ? NULL : NoshiCreateScaledMask(name, (size_t)lround(pointSize * NoshiScreenScale()));
    CGContextClipToMask(context, box, sharp ? sharp : mask.CGImage);
    if (sharp) CGImageRelease(sharp);
    CGContextFillRect(context, box);
    CGContextRestoreGState(context);
    if (symbol == NoshiSymbolTrash) {
        /* the lid mask shares the canvas of the can, so the pair is one trash can */
        UIImage *lid = [UIImage imageNamed:@"symbol_trashlid"];
        if (lid) {
            CGContextClipToMask(context, box, lid.CGImage);
            CGContextFillRect(context, box);
        }
    }
    if (symbol == NoshiSymbolMicrophoneSlash) {
        /* VoIPToggleButton: a 3 unit gap cut 2 units above a 2 unit round line, both from just outside the top left of the glyph to just outside its bottom right.
           the numbers are fractions of the mask's own canvas, and the context is still flipped by the mask drawing above */
        CGFloat from[2] = {0.171, 0.160}, to[2] = {0.829, 0.840};
        CGFloat lift = 0.080, slash = 0.082, gap = 0.123;
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetBlendMode(context, kCGBlendModeClear);
        CGContextSetLineWidth(context, gap * size.width);
        CGContextMoveToPoint(context, from[0] * size.width, (1 - from[1] + lift) * size.height);
        CGContextAddLineToPoint(context, to[0] * size.width, (1 - to[1] + lift) * size.height);
        CGContextStrokePath(context);
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        [color setStroke];
        CGContextSetLineWidth(context, slash * size.width);
        CGContextMoveToPoint(context, from[0] * size.width, (1 - from[1]) * size.height);
        CGContextAddLineToPoint(context, to[0] * size.width, (1 - to[1]) * size.height);
        CGContextStrokePath(context);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* rows ask for their marks on every configure and draw, and each ask rendered a new bitmap on the main thread */
UIImage *NoshiSymbolImage(NoshiSymbol symbol, CGFloat pointSize, UIColor *color) {
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 128;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([color getWhite:&white alpha:&a]) r = g = b = white;
        else return NoshiRenderSymbolImage(symbol, pointSize, color);
    }
    NSString *key = [NSString stringWithFormat:@"%d/%g/%g,%g,%g,%g", (int)symbol, (double)pointSize, (double)r, (double)g, (double)b, (double)a];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (!image) {
        image = NoshiRenderSymbolImage(symbol, pointSize, color);
        if (image) [cache setObject:image forKey:key];
    }
    return image;
}

/* the bundled masks are square: msg_check is 16 units, msg_seen 25 */
#define CHECK_CANVAS 16.0
#define CHECK_DOUBLE_CANVAS 25.0

/* a Material glyph cut to the box its ink fills in the 24 unit canvas of the SVG, drawn so that the ink is width points wide: the masks keep their padding, which pushed
   a mark off the slot it is aligned in */
static UIImage *NoshiInkImage(NoshiSymbol symbol, CGRect ink, CGFloat width, UIColor *color) {
    CGFloat unit = width / ink.size.width;
    UIImage *full = NoshiSymbolImage(symbol, 24 * unit, color);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, ink.size.height * unit), NO, 0);
    [full drawAtPoint:CGPointMake(-ink.origin.x * unit, -ink.origin.y * unit)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

NoshiSymbol NoshiSymbolCheckMark(void) { return NoshiThemeIsClassic() ? NoshiSymbolCheck : NoshiSymbolMaterialCheck; }
NoshiSymbol NoshiSymbolCloseMark(void) { return NoshiThemeIsClassic() ? NoshiSymbolClose : NoshiSymbolMaterialCloseOutlined; }

UIImage *NoshiSendingImage(CGFloat pointSize, UIColor *color) {
    if (NoshiThemeIsClassic()) return NoshiSymbolImage(NoshiSymbolClock, pointSize, color);
    return NoshiInkImage(NoshiSymbolMaterialSchedule, CGRectMake(2, 2, 20, 20), pointSize, color);
}

UIImage *NoshiFailedImage(CGFloat pointSize, UIColor *color) {
    return NoshiInkImage(NoshiSymbolMaterialError, CGRectMake(2, 2, 20, 20), pointSize, color);
}

/* the ticks of exteraGram (msg_check_s and msg_seen), cut to the box their ink fills and drawn so that one unit of the 12 unit canvas of the single tick is pointSize / 12 points: the single
   tick comes out pointSize wide and the double one 20 / 12 of it. the pictures are white masks that take the color */
static UIImage *NoshiTickImage(BOOL read, CGFloat pointSize, UIColor *color) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&a];
        r = g = b = white;
    }
    NSString *key = [NSString stringWithFormat:@"%d/%g/%g,%g,%g,%g/%g", read, (double)pointSize, (double)r, (double)g, (double)b, (double)a, (double)[UIScreen mainScreen].scale];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    UIImage *mask = [UIImage imageNamed:read ? @"tick_double" : @"tick_single"];
    if (!mask) return nil;
    CGFloat unit = pointSize / 12.0;
    /* the canvas is 24 units for the double tick and 12 for the single one; the ink is 20 x 11 from (2, 7) and 12 x 9 from (0, 2) */
    CGRect ink = read ? CGRectMake(2, 7, 20, 11) : CGRectMake(0, 2, 12, 9);
    CGFloat canvas = read ? 24 : 12;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(ink.size.width * unit, ink.size.height * unit), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [mask drawInRect:CGRectMake(-ink.origin.x * unit, -ink.origin.y * unit, canvas * unit, canvas * unit)];
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, ink.size.width * unit, ink.size.height * unit));
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}

UIImage *NoshiCheckImage(BOOL read, CGFloat pointSize, UIColor *color) {
    if (!NoshiThemeIsClassic()) {
        UIImage *tick = NoshiTickImage(read, pointSize, color);
        if (tick) return tick;
        /* the pictures of the ticks are missing from the bundle: the Material marks stand in, so a message never loses its state */
        if (read) return NoshiInkImage(NoshiSymbolMaterialDoneAll, CGRectMake(1, 6, 22, 12), pointSize * CHECK_DOUBLE_CANVAS / CHECK_CANVAS, color);
        return NoshiInkImage(NoshiSymbolMaterialCheck, CGRectMake(3.6667, 6, 16.6667, 12), pointSize, color);
    }
    return NoshiSymbolImage(read ? NoshiSymbolCheckDouble : NoshiSymbolCheck,
                              read ? pointSize * CHECK_DOUBLE_CANVAS / CHECK_CANVAS : pointSize, color);
}

UIImage *NoshiStarsGlyph(CGFloat side) {
    return NoshiSymbolImage(NoshiSymbolStars, side, [UIColor colorWithRed:250.0 / 255 green:183.0 / 255 blue:26.0 / 255 alpha:1]);
}

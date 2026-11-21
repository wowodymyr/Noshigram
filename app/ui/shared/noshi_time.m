#import "noshi_time.h"

#import <UIKit/UIKit.h>

#import "noshi_chat_settings.h"
#import "noshi_language.h"

#include "noshi_people.h"

NSString *const NoshiTimeDidChangeNotification = @"NoshiTimeDidChange";
static NSString *const NoshiTimeZoneKey = @"noshigram.timeZoneMinutes";
static NSMutableDictionary *sFormatters;
static BOOL sBoundsStale = YES;

int32_t NoshiTimeZoneChoice(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:NoshiTimeZoneKey];
    if (![value isKindOfClass:[NSNumber class]]) return NOSHI_TIME_ZONE_AUTO;
    long long minutes = [value longLongValue];
    if (minutes < INT32_MIN || minutes > INT32_MAX || !noshi_time_zone_valid((int32_t)minutes)) return NOSHI_TIME_ZONE_AUTO;
    return (int32_t)minutes;
}

static NSTimeZone *NoshiDisplayTimeZone(void) {
    int32_t minutes = NoshiTimeZoneChoice();
    return minutes == NOSHI_TIME_ZONE_AUTO ? [NSTimeZone systemTimeZone] : [NSTimeZone timeZoneForSecondsFromGMT:minutes * 60];
}

static void NoshiTimeChanged(void) {
    [sFormatters removeAllObjects];
    sBoundsStale = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiTimeDidChangeNotification object:nil];
}

static void NoshiObserveTime(void) {
    static BOOL observing;
    if (observing) return;
    observing = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^changed)(NSNotification *) = ^(NSNotification *note) {
        (void)note;
        [NSTimeZone resetSystemTimeZone];
        NoshiTimeChanged();
    };
    for (NSString *name in [NSArray arrayWithObjects:NSSystemTimeZoneDidChangeNotification, NSSystemClockDidChangeNotification,
                           NSCurrentLocaleDidChangeNotification, UIApplicationDidBecomeActiveNotification, nil])
        [center addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:changed];
}

void NoshiTimeZoneSetChoice(int32_t minutes) {
    if (!noshi_time_zone_valid(minutes)) {
        NSLog(@"noshigram: invalid display time zone offset %d", (int)minutes);
        return;
    }
    NoshiObserveTime();
    if (minutes == NoshiTimeZoneChoice()) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (minutes == NOSHI_TIME_ZONE_AUTO) [defaults removeObjectForKey:NoshiTimeZoneKey];
    else [defaults setObject:[NSNumber numberWithInt:minutes] forKey:NoshiTimeZoneKey];
    NoshiTimeChanged();
}

NSString *NoshiTimeZoneOffsetText(int32_t minutes) {
    if (minutes == NOSHI_TIME_ZONE_AUTO || !noshi_time_zone_valid(minutes)) return NSLocalizedString(@"time.zone.auto", nil);
    int magnitude = minutes < 0 ? -(int)minutes : (int)minutes;
    return [NSString stringWithFormat:@"UTC%c%02d:%02d", minutes < 0 ? '-' : '+', magnitude / 60, magnitude % 60];
}

NSString *NoshiTimeZoneChoiceText(void) {
    return NoshiTimeZoneOffsetText(NoshiTimeZoneChoice());
}

NSCalendar *NoshiDisplayCalendar(void) {
    NoshiObserveTime();
    NSCalendar *calendar = [[[NSCalendar currentCalendar] copy] autorelease];
    [calendar setTimeZone:NoshiDisplayTimeZone()];
    return calendar;
}

static NSDateFormatter *NoshiFormatter(NSString *template, NSDateFormatterStyle dateStyle) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:NoshiFormattingLocale()];
    [formatter setTimeZone:NoshiDisplayTimeZone()];
    if (template) {
        [formatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:template options:0 locale:NoshiFormattingLocale()]];
    } else {
        [formatter setDateStyle:dateStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return formatter;
}

/* time and locale notifications discard formatters that captured the old display settings */
static NSDateFormatter *NoshiCachedFormatter(NSString *key, NSString *template, NSDateFormatterStyle dateStyle) {
    NoshiObserveTime();
    if (!sFormatters) sFormatters = [[NSMutableDictionary alloc] init];
    NSString *full = [key stringByAppendingString:[NoshiFormattingLocale() localeIdentifier]];
    NSDateFormatter *formatter = [sFormatters objectForKey:full];
    if (!formatter) {
        formatter = NoshiFormatter(template, dateStyle);
        [sFormatters setObject:formatter forKey:full];
    }
    return formatter;
}

static NSDate *sToday = nil;
static NSDate *sYesterday = nil;
static NSDate *sWeekEdge = nil;
static NSDate *sNextMidnight = nil;

static void NoshiStoreBound(NSDate **slot, NSDate *value) {
    [value retain];
    [*slot release];
    *slot = value;
}

static NSDate *NoshiDayShifted(NSCalendar *calendar, NSDate *from, NSInteger days) {
    NSDateComponents *shift = [[[NSDateComponents alloc] init] autorelease];
    [shift setDay:days];
    return [calendar dateByAddingComponents:shift toDate:from options:0];
}

/* the day edges come from the calendar because a day is 23 or 25 hours long on a daylight saving switch, and they
   are kept until the stored next midnight */
static void NoshiRefreshDayBounds(void) {
    NoshiObserveTime();
    NSDate *now = [NSDate date];
    if (!sBoundsStale && sToday && [now compare:sToday] != NSOrderedAscending && [now compare:sNextMidnight] == NSOrderedAscending) return;
    NSCalendar *calendar = NoshiDisplayCalendar();
    NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    NSDate *today = [calendar dateFromComponents:parts];
    NoshiStoreBound(&sToday, today);
    NoshiStoreBound(&sYesterday, NoshiDayShifted(calendar, today, -1));
    NoshiStoreBound(&sWeekEdge, NoshiDayShifted(calendar, today, -6));
    NoshiStoreBound(&sNextMidnight, NoshiDayShifted(calendar, today, 1));
    sBoundsStale = NO;
}

NSString *NoshiListTimeText(int32_t unixDate) {
    if (unixDate <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    NoshiRefreshDayBounds();
    if ([date compare:sToday] != NSOrderedAscending) return [NoshiCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:date];
    if ([date compare:sWeekEdge] == NSOrderedDescending) return [NoshiCachedFormatter(@"weekday", @"EEE", NSDateFormatterNoStyle) stringFromDate:date];
    return [NoshiCachedFormatter(@"short", nil, NSDateFormatterShortStyle) stringFromDate:date];
}

NSString *NoshiDayText(int32_t unixDate) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    NoshiRefreshDayBounds();
    if ([date compare:sToday] != NSOrderedAscending) return NSLocalizedString(@"chat.today", nil);
    if ([date compare:sYesterday] != NSOrderedAscending) return NSLocalizedString(@"chat.yesterday", nil);
    if ([date compare:sWeekEdge] == NSOrderedDescending) return [NoshiCachedFormatter(@"weekdayfull", @"EEEE", NSDateFormatterNoStyle) stringFromDate:date];
    return [NoshiCachedFormatter(@"day", @"dMMMMyyyy", NSDateFormatterNoStyle) stringFromDate:date];
}

/* the list text drops the clock once the day is not today, but an exact last seen time has to keep it */
static NSString *NoshiExactSeenText(int32_t seen) {
    NSString *day = NoshiListTimeText(seen);
    NoshiRefreshDayBounds();
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seen];
    if ([date compare:sToday] != NSOrderedAscending) return day;
    NSString *clock = [NoshiCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:date];
    return [NSString stringWithFormat:@"%@, %@", day, clock];
}

NSString *NoshiLastSeenText(int presence, int32_t seen) {
    switch ((noshi_presence)presence) {
    case NOSHI_PRESENCE_ONLINE:
        return NSLocalizedString(@"seen.online", nil);
    case NOSHI_PRESENCE_OFFLINE: {
        if (seen <= 0) break;
        if (NoshiChatFlagGet(NoshiChatFlagRelativeSeen)) {
            /* a time in the future (a clock that runs ahead of the server) has no age, so it reads as the exact time */
            NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - seen;
            if (age >= 0 && age < 60) return NSLocalizedString(@"seen.ago.now", nil);
            if (age >= 60 && age < 3600) return [NSString stringWithFormat:NSLocalizedString(@"seen.ago.minutes", nil), (int)(age / 60)];
            if (age >= 3600 && age < 86400) return [NSString stringWithFormat:NSLocalizedString(@"seen.ago.hours", nil), (int)(age / 3600)];
        }
        return [NSString stringWithFormat:NSLocalizedString(@"seen.at", nil), NoshiExactSeenText(seen)];
    }
    case NOSHI_PRESENCE_RECENTLY:
        return NSLocalizedString(@"seen.recently", nil);
    case NOSHI_PRESENCE_LAST_WEEK:
        return NSLocalizedString(@"seen.week", nil);
    case NOSHI_PRESENCE_LAST_MONTH:
        return NSLocalizedString(@"seen.month", nil);
    case NOSHI_PRESENCE_DELETED:
        return NSLocalizedString(@"seen.deleted", nil);
    case NOSHI_PRESENCE_UNKNOWN:
        break;
    }
    return NSLocalizedString(@"seen.long", nil);
}

NSString *NoshiMediaTimeText(int32_t unixDate) {
    if (unixDate <= 0) return @"";
    NSString *day = NoshiDayText(unixDate);
    if ([day isEqualToString:NSLocalizedString(@"chat.today", nil)] || [day isEqualToString:NSLocalizedString(@"chat.yesterday", nil)]) day = day.lowercaseString;
    NSString *clock = [NoshiCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:[NSDate dateWithTimeIntervalSince1970:unixDate]];
    return [NSString stringWithFormat:NSLocalizedString(@"media.date", nil), day, clock];
}

/* the clock of a message follows the 12 or 24 hour choice of the system like the times of the list do */
NSString *NoshiClockText(int32_t unixDate) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:unixDate];
    if (NoshiChatFlagGet(NoshiChatFlagSeconds)) return [NoshiCachedFormatter(@"clockseconds", @"jmmss", NSDateFormatterNoStyle) stringFromDate:date];
    return [NoshiCachedFormatter(@"clock", @"jmm", NSDateFormatterNoStyle) stringFromDate:date];
}

#import <UIKit/UIKit.h>
#include "noshi_geo.h"

@class NoshiMapView;
@protocol NoshiMapViewDelegate <NSObject>
- (void)mapView:(NoshiMapView *)map didChangeCenter:(BOOL)finished;
@optional
- (void)mapView:(NoshiMapView *)map didSelectPlace:(NSUInteger)index;
@end

@interface NoshiMapView : UIView
@property (nonatomic, assign) id<NoshiMapViewDelegate> delegate;
@property (nonatomic, assign) BOOL picking;
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, assign) double zoom;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
- (void)showLocation:(noshi_geo_point)point zoom:(double)zoom;
- (void)showUserLocation:(noshi_geo_point)point;
/* an array of noshi_geo_point values, at most sixteen markers */
- (void)showPlaces:(NSData *)points;
- (void)setCenterLatitude:(double)latitude longitude:(double)longitude zoom:(double)zoom;
- (void)cancelTiles;
@end

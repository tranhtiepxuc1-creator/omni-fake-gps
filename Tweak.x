#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

// Bạn có thể sửa nhanh 2 dòng này trên GitHub để đổi vị trí tùy ý
#define FAKE_LATITUDE 11.02345
#define FAKE_LONGITUDE 108.23456

%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    CLLocationCoordinate2D realCoordinate = %orig;
    realCoordinate.latitude = FAKE_LATITUDE;
    realCoordinate.longitude = FAKE_LONGITUDE;
    return realCoordinate;
}
- (CLLocationDistance)altitude {
    return 15.0;
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    return [[CLLocation alloc] initWithLatitude:FAKE_LATITUDE longitude:FAKE_LONGITUDE];
}
%end

%ctl(constructor) {
    NSLog(@"[OMNI-GPS] Tweak đã kích hoạt thành công tại vị trí thiết lập!");
}

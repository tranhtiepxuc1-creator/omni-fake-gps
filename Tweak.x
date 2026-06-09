#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

// Thiết lập tọa độ giả định vị mong muốn
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

// ============================================================================
// SỬA LỖI: Sử dụng cú pháp %ctor chuẩn và hiện đại nhất của Logos để khởi tạo ngầm
// ============================================================================
%ctor {
    NSLog(@"[OMNI-GPS] Tweak Fake GPS 2026 đã kích hoạt thành công!");
}

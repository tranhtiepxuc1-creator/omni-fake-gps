#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

// --- LƯU TRỮ TRẠNG THÁI TOÀN CỤC ---
static BOOL isFakeGPXActive = NO;
static NSMutableArray *gpxPoints = nil; // Danh sách tọa độ từ file GPX
static NSInteger currentPointIndex = 0;
static double simulationSpeed = 1.0;   // Mặc định 1x
static double movementSpeedKmh = 5.0;  // Mặc định 5km/h

static CLLocationCoordinate2D currentFakeCoordinate;
static UIButton *floatingButton = nil;
static UIView *menuView = nil;

// --- HÀM ĐỌC PHÂN TÍCH FILE GPX ĐƠN GIẢN ---
void parseGPXString(NSString *gpxString) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    
    // Quét tìm các thẻ <trkpt lat="..." lon="..."> hoặc <wpt>
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\"\\s+lon=\"([^\"]+)\"" options:0 error:&error];
    NSArray *matches = [regex matchesInString:gpxString options:0 range:NSMakeRange(0, gpxString.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSString *latStr = [gpxString substringWithRange:[match rangeAtIndex:1]];
        NSString *lonStr = [gpxString substringWithRange:[match rangeAtIndex:2]];
        CLLocation *location = [[CLLocation alloc] initWithLatitude:[latStr doubleValue] longitude:[lonStr doubleValue]];
        [gpxPoints addObject:location];
    }
}

// --- HÀM CẬP NHẬT VỊ TRÍ THEO TUYẾN ĐƯỜNG GPX ---
void updateSimulation() {
    if (!isFakeGPXActive || !gpxPoints || gpxPoints.count == 0) return;
    
    CLLocation *targetPoint = gpxPoints[currentPointIndex];
    currentFakeCoordinate = targetPoint.coordinate;
    
    // Tăng tiến trình điểm tiếp theo
    currentPointIndex++;
    if (currentPointIndex >= gpxPoints.count) {
        currentPointIndex = 0; // Quay lại điểm đầu nếu hết tuyến đường
    }
    
    // Tính toán thời gian lặp lại dựa trên tốc độ di chuyển (km/h) và hệ số tua (speed)
    // Tốc độ di chuyển càng cao hoặc tua càng nhanh thì thời gian delay giữa các điểm càng ngắn
    double interval = (3.6 / movementSpeedKmh) / simulationSpeed;
    if (interval < 0.1) interval = 0.1;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        updateSimulation();
    });
}

// --- TỰ ĐỘNG VẼ GIAO DIỆN NÚT NỔI KHI APP MỞ ---
@interface OmniWindowManager : NSObject
+ (void)showFloatingUI;
@end

@implementation OmniWindowManager
+ (void)showFloatingUI {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        // 1. Tạo nút nổi hình tròn tinh tế
        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 150, 55, 55);
        floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.9 alpha:0.85];
        floatingButton.layer.cornerRadius = 27.5;
        [floatingButton setTitle:@"GPS" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
        floatingButton.layer.shadowRadius = 4.0;
        floatingButton.layer.shadowOpacity = 0.5;
        floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        
        // Thêm sự kiện Kéo thả nút nổi tự do trên màn hình
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        floatingButton.gestureRecognizers = @[panGesture];
        [floatingButton addTarget:self action:@selector(toggleMenu) forState:UIControlEventTouchUpInside];
        
        [keyWindow addSubview:floatingButton];
        
        // 2. Tạo Menu điều khiển ẩn/hiện
        menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 360)];
        menuView.center = keyWindow.center;
        menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.12 blue:0.16 alpha:0.95];
        menuView.layer.cornerRadius = 16;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.5].CGColor;
        menuView.hidden = YES;
        
        // Tiêu đề menu
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 280, 25)];
        titleLabel.text = @"OMNI GPS ROUTE CONTROLLER";
        titleLabel.textColor = [UIColor cyanColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:13];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:titleLabel];
        
        // Ô nhập nội dung file GPX
        UITextView *gpxInput = [[UITextView alloc] initWithFrame:CGRectMake(10, 45, 280, 100)];
        gpxInput.backgroundColor = [UIColor blackColor];
        gpxInput.textColor = [UIColor greenColor];
        gpxInput.font = [UIFont systemFontOfSize:10];
        gpxInput.layer.cornerRadius = 8;
        gpxInput.text = @"Dán nội dung văn bản file .gpx vào đây...";
        gpxInput.tag = 999;
        [menuView addSubview:gpxInput];
        
        // Nhãn chọn tốc độ thời gian
        UILabel *lblSpeed = [[UILabel alloc] initWithFrame:CGRectMake(10, 155, 280, 20)];
        lblSpeed.text = @"Tốc độ thời gian (0.1x - 10x): 1.0x";
        lblSpeed.textColor = [UIColor whiteColor];
        lblSpeed.font = [UIFont systemFontOfSize:11];
        [menuView addSubview:lblSpeed];
        
        UISlider *sliderSpeed = [[UISlider alloc] initWithFrame:CGRectMake(10, 175, 280, 20)];
        sliderSpeed.minimumValue = 0.1;
        sliderSpeed.maximumValue = 10.0;
        sliderSpeed.value = 1.0;
        [sliderSpeed addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        sliderSpeed.tag = 888;
        [menuView addSubview:sliderSpeed];
        
        // Nhãn chọn tốc độ di chuyển
        UILabel *lblMove = [[UILabel alloc] initWithFrame:CGRectMake(10, 205, 280, 20)];
        lblMove.text = @"Tốc độ di chuyển: 5 km/h";
        lblMove.textColor = [UIColor whiteColor];
        lblMove.font = [UIFont systemFontOfSize:11];
        [menuView addSubview:lblMove];
        
        UISlider *sliderMove = [[UISlider alloc] initWithFrame:CGRectMake(10, 225, 280, 20)];
        sliderMove.minimumValue = 1.0;
        sliderMove.maximumValue = 20.0;
        sliderMove.value = 5.0;
        [sliderMove addTarget:self action:@selector(moveChanged:) forControlEvents:UIControlEventValueChanged];
        sliderMove.tag = 777;
        [menuView addSubview:sliderMove];
        
        // Nút bấm kích hoạt mô phỏng tuyến đường
        UIButton *btnStart = [UIButton buttonWithType:UIButtonTypeCustom];
        btnStart.frame = CGRectMake(10, 265, 280, 40);
        btnStart.backgroundColor = [UIColor systemGreenColor];
        btnStart.layer.cornerRadius = 8;
        [btnStart setTitle:@"KÍCH HOẠT TUYẾN ĐƯỜNG GPX" forState:UIControlStateNormal];
        btnStart.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [btnStart addTarget:self action:@selector(startSimulation:) forState:UIControlEventTouchUpInside];
        btnStart.tag = 666;
        [menuView addSubview:btnStart];
        
        // Nút Đóng menu
        UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeCustom];
        btnClose.frame = CGRectMake(10, 315, 280, 35);
        btnClose.backgroundColor = [UIColor darkGrayColor];
        btnClose.layer.cornerRadius = 8;
        [btnClose setTitle:@"ĐÓNG CỬA SỔ CONTROL" forState:UIControlStateNormal];
        btnClose.titleLabel.font = [UIFont systemFontOfSize:11];
        [btnClose addTarget:self action:@selector(toggleMenu) forState:UIControlEventTouchUpInside];
        [menuView addSubview:menuView];
        
        [keyWindow addSubview:menuView];
    });
}

// Xử lý kéo thả nút nổi
+ (void)handlePan:(UIPanGestureRecognizer *)sender {
    UIView *piece = floatingButton;
    CGPoint translation = [sender translationInView:piece.superview];
    if ([sender state] == UIGestureRecognizerStateBegan || [sender state] == UIGestureRecognizerStateChanged) {
        [piece setCenter:CGPointMake([piece center].x + translation.x, [piece center].y + translation.y)];
        [sender setTranslation:CGPointZero inView:piece.superview];
    }
}

+ (void)toggleMenu {
    menuView.hidden = !menuView.hidden;
}

+ (void)speedChanged:(UISlider *)sender {
    simulationSpeed = sender.value;
    UILabel *lbl = (UILabel *)[menuView.subviews objectAtIndex:2];
    lbl.text = [NSString stringWithFormat:@"Tốc độ thời gian (0.1x - 10x): %.1fx", simulationSpeed];
}

+ (void)moveChanged:(UISlider *)sender {
    movementSpeedKmh = sender.value;
    UILabel *lbl = (UILabel *)[menuView.subviews objectAtIndex:4];
    lbl.text = [NSString stringWithFormat:@"Tốc độ di chuyển: %.1f km/h", movementSpeedKmh];
}

+ (void)startSimulation:(UIButton *)sender {
    UITextView *tv = (UITextView *)[menuView viewWithTag:999];
    if (isFakeGPXActive) {
        isFakeGPXActive = NO;
        [sender setTitle:@"KÍCH HOẠT TUYẾN ĐƯỜNG GPX" forState:UIControlStateNormal];
        sender.backgroundColor = [UIColor systemGreenColor];
    } else {
        parseGPXString(tv.text);
        if (gpxPoints.count > 0) {
            isFakeGPXActive = YES;
            [sender setTitle:@"ĐANG CHẠY MÔ PHỎNG - BẤM ĐỂ DỪNG" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemRedColor];
            updateSimulation();
        } else {
            alert(@"Lỗi", @"Nội dung GPX không hợp lệ hoặc không tìm thấy tọa độ.");
        }
    }
}

void alert(NSString *title, NSString *msg) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}
@end


// --- HOOK HỆ THỐNG ĐỊNH VỊ CORE-LOCATION CỦA APPLE ---
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    if (isFakeGPXActive && gpxPoints.count > 0) {
        return currentFakeCoordinate;
    }
    return %orig;
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    if (isFakeGPXActive && gpxPoints.count > 0) {
        return [[CLLocation alloc] initWithLatitude:currentFakeCoordinate.latitude longitude:currentFakeCoordinate.longitude];
    }
    return %orig;
}
%end

// Kích hoạt nạp UI nút nổi ngay khi app khởi động
%ctor {
    [OmniWindowManager showFloatingUI];
}

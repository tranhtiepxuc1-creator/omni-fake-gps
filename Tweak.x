#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

// --- LƯU TRỮ TRẠNG THÁI TOÀN CỤC ---
static BOOL isFakeGPXActive = NO;
static NSMutableArray *gpxPoints = nil; 
static NSInteger currentPointIndex = 0;
static double simulationSpeed = 1.0;   
static double movementSpeedKmh = 5.0;  

static CLLocationCoordinate2D currentFakeCoordinate;
static UIButton *floatingButton = nil;
static UIView *menuView = nil;

// --- HÀM ĐỌC PHÂN TÍCH FILE GPX ĐƠN GIẢN ---
void parseGPXString(NSString *gpxString) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    
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
    
    currentPointIndex++;
    if (currentPointIndex >= gpxPoints.count) {
        currentPointIndex = 0; 
    }
    
    double interval = (3.6 / movementSpeedKmh) / simulationSpeed;
    if (interval < 0.1) interval = 0.1;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        updateSimulation();
    });
}

// --- GIAO DIỆN ĐIỀU KHIỂN (HỢP THỨC HÓA TARGET ACTION) ---
@interface OmniControllerView : UIView
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)toggleMenu;
- (void)speedChanged:(UISlider *)sender;
- (void)moveChanged:(UISlider *)sender;
- (void)startSimulation:(UIButton *)sender;
@end

@implementation OmniControllerView

- (void)handlePan:(UIPanGestureRecognizer *)sender {
    CGPoint translation = [sender translationInView:floatingButton.superview];
    if ([sender state] == UIGestureRecognizerStateBegan || [sender state] == UIGestureRecognizerStateChanged) {
        [floatingButton setCenter:CGPointMake([floatingButton center].x + translation.x, [floatingButton center].y + translation.y)];
        [sender setTranslation:CGPointZero inView:floatingButton.superview];
    }
}

- (void)toggleMenu {
    menuView.hidden = !menuView.hidden;
}

- (void)speedChanged:(UISlider *)sender {
    simulationSpeed = sender.value;
    UILabel *lbl = (UILabel *)[menuView viewWithTag:801];
    lbl.text = [NSString stringWithFormat:@"Tốc độ thời gian (0.1x - 10x): %.1fx", simulationSpeed];
}

- (void)moveChanged:(UISlider *)sender {
    movementSpeedKmh = sender.value;
    UILabel *lbl = (UILabel *)[menuView viewWithTag:701];
    lbl.text = [NSString stringWithFormat:@"Tốc độ di chuyển: %.1f km/h", movementSpeedKmh];
}

- (void)startSimulation:(UIButton *)sender {
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
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lỗi" message:@"Nội dung GPX không hợp lệ." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].windows.firstObject.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    }
}
@end

// Biến điều hướng giao diện tĩnh
static OmniControllerView *uiHandler = nil;

// --- TỰ ĐỘNG KHỞI TẠO NÚT NỔI CHUẨN IOS MỚI ---
void initFloatingUI() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // SỬA LỖI: Lấy Window chính xác theo cấu trúc Multi-Scene hiện đại của iOS 13-18+
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (!keyWindow) return;

        uiHandler = [[OmniControllerView alloc] initWithFrame:CGRectZero];

        // 1. Tạo nút nổi hình tròn
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
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:uiHandler action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:panGesture];
        [floatingButton addTarget:uiHandler action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        
        [keyWindow addSubview:floatingButton];
        
        // 2. Tạo Menu điều khiển
        menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 360)];
        menuView.center = keyWindow.center;
        menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.12 blue:0.16 alpha:0.95];
        menuView.layer.cornerRadius = 16;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.5].CGColor;
        menuView.hidden = YES;
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 280, 25)];
        titleLabel.text = @"OMNI GPS ROUTE CONTROLLER";
        titleLabel.textColor = [UIColor cyanColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:13];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:titleLabel];
        
        UITextView *gpxInput = [[UITextView alloc] initWithFrame:CGRectMake(10, 45, 280, 100)];
        gpxInput.backgroundColor = [UIColor blackColor];
        gpxInput.textColor = [UIColor greenColor];
        gpxInput.font = [UIFont systemFontOfSize:10];
        gpxInput.layer.cornerRadius = 8;
        gpxInput.text = @"Dán nội dung văn bản file .gpx vào đây...";
        gpxInput.tag = 999;
        [menuView addSubview:gpxInput];
        
        UILabel *lblSpeed = [[UILabel alloc] initWithFrame:CGRectMake(10, 155, 280, 20)];
        lblSpeed.text = @"Tốc độ thời gian (0.1x - 10x): 1.0x";
        lblSpeed.textColor = [UIColor whiteColor];
        lblSpeed.font = [UIFont systemFontOfSize:11];
        lblSpeed.tag = 801;
        [menuView addSubview:lblSpeed];
        
        UISlider *sliderSpeed = [[UISlider alloc] initWithFrame:CGRectMake(10, 175, 280, 20)];
        sliderSpeed.minimumValue = 0.1;
        sliderSpeed.maximumValue = 10.0;
        sliderSpeed.value = 1.0;
        [sliderSpeed addTarget:uiHandler action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderSpeed];
        
        UILabel *lblMove = [[UILabel alloc] initWithFrame:CGRectMake(10, 205, 280, 20)];
        lblMove.text = @"Tốc độ di chuyển: 5.0 km/h";
        lblMove.textColor = [UIColor whiteColor];
        lblMove.font = [UIFont systemFontOfSize:11];
        lblMove.tag = 701;
        [menuView addSubview:lblMove];
        
        UISlider *sliderMove = [[UISlider alloc] initWithFrame:CGRectMake(10, 225, 280, 20)];
        sliderMove.minimumValue = 1.0;
        sliderMove.maximumValue = 20.0;
        sliderMove.value = 5.0;
        [sliderMove addTarget:uiHandler action:@selector(moveChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderMove];
        
        UIButton *btnStart = [UIButton buttonWithType:UIButtonTypeCustom];
        btnStart.frame = CGRectMake(10, 265, 280, 40);
        btnStart.backgroundColor = [UIColor systemGreenColor];
        btnStart.layer.cornerRadius = 8;
        [btnStart setTitle:@"KÍCH HOẠT TUYẾN ĐƯỜNG GPX" forState:UIControlStateNormal];
        btnStart.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [btnStart addTarget:uiHandler action:@selector(startSimulation:) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnStart];
        
        UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeCustom];
        btnClose.frame = CGRectMake(10, 315, 280, 35);
        btnClose.backgroundColor = [UIColor darkGrayColor];
        btnClose.layer.cornerRadius = 8;
        [btnClose setTitle:@"ĐÓNG CỬA SỔ CONTROL" forState:UIControlStateNormal];
        btnClose.titleLabel.font = [UIFont systemFontOfSize:11];
        [btnClose addTarget:uiHandler action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnClose];
        
        [keyWindow addSubview:menuView];
    });
}

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

%ctor {
    initFloatingUI();
}

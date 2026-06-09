#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

// --- KHAI BÁO BIẾN TOÀN CỤC ---
static BOOL isFakeGPXActive = NO;
static NSMutableArray *gpxPoints = nil; 
static NSInteger currentPointIndex = 0;
static double simulationSpeed = 1.0;   
static double movementSpeedKmh = 5.0;  

static CLLocationCoordinate2D currentFakeCoordinate;
static UIButton *floatingButton = nil;
static UIView *menuView = nil;
static UILabel *statusLabel = nil; 

// --- 🌐 THUẬT TOÁN ĐỔI WGS-84 SANG VN-2000 BÌNH THUẬN (MÚI 3°, KTT 108.5°) ---
CLLocationCoordinate2D convertWGS84ToVN2000BinhThuan(double lat, double lon) {
    double lon0 = 108.5 * M_PI / 180.0; // Kinh tuyến trục Bình Thuận: 108 độ 30 phút
    double latRad = lat * M_PI / 180.0;
    double lonRad = lon * M_PI / 180.0;
    
    // Hằng số Elipsoid VN-2000 / WGS-84
    double a = 6378137.0; 
    double f = 1.0 / 298.257223563;
    double b = a * (1.0 - f);
    double e2 = (a*a - b*b) / (a*a);
    double ee2 = (a*a - b*b) / (b*b);
    double k0 = 0.9999; // Hệ số biến dạng múi chiếu 3 độ
    
    double dLon = lonRad - lon0;
    
    // Tính toán các tham số hình học Gauss-Kruger
    double N = a / sqrt(1.0 - e2 * sin(latRad) * sin(latRad));
    double T = tan(latRad) * tan(latRad);
    double C = ee2 * cos(latRad) * cos(latRad);
    double A = dLon * cos(latRad);
    
    // Tính độ dài cung kinh tuyến M
    double M = a * ((1.0 - e2/4.0 - 3.0*e2*e2/64.0 - 5.0*e2*e2*e2/256.0) * latRad
                    - (3.0*e2/8.0 + 3.0*e2*e2/32.0 + 45.0*e2*e2*e2/1024.0) * sin(2.0*latRad)
                    + (15.0*e2*e2/256.0 + 45.0*e2*e2*e2/1024.0) * sin(4.0*latRad)
                    - (35.0*e2*e2*e2/3072.0) * sin(6.0*latRad));
    
    // Tính tọa độ phẳng X (m) và Y (m)
    double x_vn2000 = k0 * (M + N * tan(latRad) * (A*A/2.0 + (5.0 - T + 9.0*C + 4.0*C*C) * A*A*A*A/24.0
                    + (61.0 - 58.0*T + T*T + 600.0*C - 330.0*ee2) * A*A*A*A*A*A/720.0));
    
    double y_vn2000 = k0 * N * (A + (1.0 - T + C) * A*A*A/6.0
                    + (5.0 - 18.0*T + T*T + 72.0*C - 58.0*ee2) * A*A*A*A*A/120.0);
    
    // Cộng hằng số dời trục dịch đông (False Easting) quy định hệ tọa độ VN-2000 múi 3°
    y_vn2000 += 500000.0; 
    
    // Trả về cấu trúc chứa giá trị mét X và Y (được lồng ghép giả lập vào cấu trúc coordinate)
    CLLocationCoordinate2D vn2000Point;
    vn2000Point.latitude = x_vn2000;  // Trục X (mét)
    vn2000Point.longitude = y_vn2000; // Trục Y (mét)
    return vn2000Point;
}

// --- 3. HÀM ĐỌC PHÂN TÍCH FILE GPX TOÀN CỤC ---
void parseGPXString(NSString *gpxString) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    
    NSError *error = nil;
    NSRegularExpression *latRegex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\"" options:0 error:&error];
    NSArray *latMatches = [latRegex matchesInString:gpxString options:0 range:NSMakeRange(0, gpxString.length)];
    
    NSRegularExpression *lonRegex = [NSRegularExpression regularExpressionWithPattern:@"lon=\"([^\"]+)\"" options:0 error:&error];
    NSArray *lonMatches = [lonRegex matchesInString:gpxString options:0 range:NSMakeRange(0, gpxString.length)];
    
    NSInteger count = MIN(latMatches.count, lonMatches.count);
    
    for (NSInteger i = 0; i < count; i++) {
        NSTextCheckingResult *latMatch = latMatches[i];
        NSTextCheckingResult *lonMatch = lonMatches[i];
        
        double rawLat = [[gpxString substringWithRange:[latMatch rangeAtIndex:1]] doubleValue];
        double rawLon = [[gpxString substringWithRange:[lonMatch rangeAtIndex:1]] doubleValue];
        
        // TIẾN HÀNH ĐỔI HỆ TOẠ ĐỘ: Ép tệp GPX WGS-84 sang hệ mét phẳng VN-2000 của Bình Thuận
        CLLocationCoordinate2D converted = convertWGS84ToVN2000BinhThuan(rawLat, rawLon);
        
        CLLocation *location = [[CLLocation alloc] initWithLatitude:converted.latitude longitude:converted.longitude];
        [gpxPoints addObject:location];
    }
}

// --- 4. HÀM CẬP NHẬT MÔ PHỎNG DI CHUYỂN ---
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

// --- 5. GIAO DIỆN VÀ XỬ LÝ SỰ KIỆN CHỌN FILE ---
@interface OmniControllerView : UIView <UIDocumentPickerDelegate>
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)toggleMenu;
- (void)speedChanged:(UISlider *)sender;
- (void)moveChanged:(UISlider *)sender;
- (void)startSimulation:(UIButton *)sender;
- (void)openFilePicker;
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

- (void)openFilePicker {
    UTType *gpxType = [UTType typeWithFilenameExtension:@"gpx"];
    if (!gpxType) gpxType = UTTypeData;
    
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[gpxType] asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    
    UIViewController *rootVC = [UIApplication sharedApplication].windows.firstObject.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = urls.firstObject;
    if (!selectedFileURL) return;
    
    NSError *error = nil;
    [selectedFileURL startAccessingSecurityScopedResource];
    NSString *gpxContent = [NSString stringWithContentsOfURL:selectedFileURL encoding:NSUTF8StringEncoding error:&error];
    [selectedFileURL stopAccessingSecurityScopedResource];
    
    if (!error && gpxContent) {
        parseGPXString(gpxContent);
        if (gpxPoints.count > 0) {
            statusLabel.text = [NSString stringWithFormat:@"📁 Tệp: %@ (%lu điểm)", selectedFileURL.lastPathComponent, (unsigned long)gpxPoints.count];
            statusLabel.textColor = [UIColor systemGreenColor];
        } else {
            statusLabel.text = @"❌ Không tìm thấy tọa độ trkpt hợp lệ!";
            statusLabel.textColor = [UIColor systemOrangeColor];
        }
    } else {
        statusLabel.text = @"❌ Không đọc được dữ liệu file!";
        statusLabel.textColor = [UIColor systemRedColor];
    }
}

- (void)startSimulation:(UIButton *)sender {
    if (isFakeGPXActive) {
        isFakeGPXActive = NO;
        [sender setTitle:@"KÍCH HOẠT TUYẾN ĐƯỜNG" forState:UIControlStateNormal];
        sender.backgroundColor = [UIColor systemGreenColor];
    } else {
        if (gpxPoints.count > 0) {
            isFakeGPXActive = YES;
            [sender setTitle:@"ĐANG CHẠY MÔ PHỎNG - BẤM ĐỂ DỪNG" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemRedColor];
            updateSimulation();
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lưu ý" message:@"Vui lòng nạp tệp .gpx hợp lệ trước!" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].windows.firstObject.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    }
}
@end

static OmniControllerView *uiHandler = nil;

void initFloatingUI() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) { keyWindow = window; break; }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (!keyWindow) return;

        uiHandler = [[OmniControllerView alloc] initWithFrame:CGRectZero];

        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 150, 55, 55);
        floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.65 blue:0.9 alpha:0.9];
        floatingButton.layer.cornerRadius = 27.5;
        [floatingButton setTitle:@"🌐" forState:UIControlStateNormal];
        floatingButton.layer.shadowOpacity = 0.4;
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:uiHandler action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:panGesture];
        [floatingButton addTarget:uiHandler action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:floatingButton];
        
        menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 290, 320)];
        menuView.center = keyWindow.center;
        menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.96];
        menuView.layer.cornerRadius = 14;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.65 blue:0.9 alpha:0.3].CGColor;
        menuView.hidden = YES;
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 12, 270, 20)];
        titleLabel.text = @"OMNI GPS - FMS BINH THUAN";
        titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
        titleLabel.font = [UIFont boldSystemFontOfSize:13];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:titleLabel];
        
        UIButton *btnSelectFile = [UIButton buttonWithType:UIButtonTypeCustom];
        btnSelectFile.frame = CGRectMake(15, 45, 260, 42);
        btnSelectFile.backgroundColor = [UIColor colorWithRed:0.2 green:0.25 blue:0.35 alpha:1.0];
        btnSelectFile.layer.cornerRadius = 8;
        btnSelectFile.layer.borderWidth = 1;
        btnSelectFile.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.3].CGColor;
        [btnSelectFile setTitle:@"📁 CHỌN FILE .GPX TỪ MÁY" forState:UIControlStateNormal];
        btnSelectFile.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [btnSelectFile setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [btnSelectFile addTarget:uiHandler action:@selector(openFilePicker) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnSelectFile];
        
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, 260, 20)];
        statusLabel.text = @"Trạng thái: Chưa có tệp nào được chọn";
        statusLabel.textColor = [UIColor lightGrayColor];
        statusLabel.font = [UIFont systemFontOfSize:10];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:statusLabel];
        
        UILabel *lblSpeed = [[UILabel alloc] initWithFrame:CGRectMake(15, 125, 260, 15)];
        lblSpeed.text = @"Tốc độ thời gian (0.1x - 10x): 1.0x";
        lblSpeed.textColor = [UIColor whiteColor];
        lblSpeed.font = [UIFont systemFontOfSize:11];
        lblSpeed.tag = 801;
        [menuView addSubview:lblSpeed];
        
        UISlider *sliderSpeed = [[UISlider alloc] initWithFrame:CGRectMake(15, 142, 260, 20)];
        sliderSpeed.minimumValue = 0.1;
        sliderSpeed.maximumValue = 10.0;
        sliderSpeed.value = 1.0;
        [sliderSpeed addTarget:uiHandler action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderSpeed];
        
        UILabel *lblMove = [[UILabel alloc] initWithFrame:CGRectMake(15, 172, 260, 15)];
        lblMove.text = @"Tốc độ di chuyển: 5.0 km/h";
        lblMove.textColor = [UIColor whiteColor];
        lblMove.font = [UIFont systemFontOfSize:11];
        lblMove.tag = 701;
        [menuView addSubview:lblMove];
        
        UISlider *sliderMove = [[UISlider alloc] initWithFrame:CGRectMake(15, 189, 260, 20)];
        sliderMove.minimumValue = 1.0;
        sliderMove.maximumValue = 20.0;
        sliderMove.value = 5.0;
        [sliderMove addTarget:uiHandler action:@selector(moveChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderMove];
        
        UIButton *btnStart = [UIButton buttonWithType:UIButtonTypeCustom];
        btnStart.frame = CGRectMake(15, 225, 260, 40);
        btnStart.backgroundColor = [UIColor systemGreenColor];
        btnStart.layer.cornerRadius = 8;
        [btnStart setTitle:@"KÍCH HOẠT TUYẾN ĐƯỜNG" forState:UIControlStateNormal];
        btnStart.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [btnStart addTarget:uiHandler action:@selector(startSimulation:) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnStart];
        
        UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeCustom];
        btnClose.frame = CGRectMake(15, 275, 260, 32);
        btnClose.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        btnClose.layer.cornerRadius = 6;
        [btnClose setTitle:@"ẨN MENU ĐIỀU KHIỂN" forState:UIControlStateNormal];
        btnClose.titleLabel.font = [UIFont systemFontOfSize:11];
        [btnClose addTarget:uiHandler action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnClose];
        
        [keyWindow addSubview:menuView];
    });
}

// --- 6. HOOK ĐỊNH VỊ CORE-LOCATION ---
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

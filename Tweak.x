#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

// --- 1. KHAI BÁO BIẾN TOÀN CỤC ---
static BOOL isFakeGPXActive = NO;
static NSMutableArray *gpxPoints = nil; // Mảng lưu trữ danh sách tọa độ "tĩnh" lấy từ file
static NSInteger currentPointIndex = 0; // Biến đếm vị trí điểm đang đứng trên tuyến đường
static double simulationSpeed = 1.0;   // Hệ số tua thời gian (0.1x - 10x)
static double movementSpeedKmh = 5.0;  // Tốc độ di chuyển mô phỏng (1km/h - 20km/h)

static CLLocation *currentFakeLocation = nil; // Đối tượng vị trí "động" để bơm vào app FMS
static UIButton *floatingButton = nil;
static UIView *menuView = nil;
static UILabel *statusLabel = nil; 

// --- HÀM TỰ TÍNH TOÁN HƯỚNG XOAY MŨI TÊN (BEARING/COURSE) ---
double calculateCourse(double lat1, double lon1, double lat2, double lon2) {
    double lat1Rad = lat1 * M_PI / 180.0;
    double lat2Rad = lat2 * M_PI / 180.0;
    double dLonRad = (lon2 - lon1) * M_PI / 180.0;
    
    double y = sin(dLonRad) * cos(lat2Rad);
    double x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLonRad);
    double bearingRad = atan2(y, x);
    double bearingDeg = bearingRad * 180.0 / M_PI;
    
    if (bearingDeg < 0) {
        bearingDeg += 360.0;
    }
    return bearingDeg;
}

// --- 2. BỘ GIẢI MÃ ĐỌC DỮ LIỆU TĨNH TỪ TỆP TIN ---
void parseSpatialFile(NSString *fileContent) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    
    // Đọc file cấu trúc GeoJSON (.geojson)
    if ([fileContent containsString:@"\"type\""] && [fileContent containsString:@"\"coordinates\""]) {
        NSData *jsonData = [fileContent dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonError = nil;
        NSDictionary *geoJSONObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        
        if (!jsonError && geoJSONObject) {
            NSDictionary *geometry = geoJSONObject[@"geometry"];
            if (geometry && [geometry[@"type"] isEqualToString:@"LineString"]) {
                NSArray *coordinates = geometry[@"coordinates"];
                for (NSArray *point in coordinates) {
                    if (point.count >= 2) {
                        double lon = [point[0] doubleValue];
                        double lat = [point[1] doubleValue];
                        // Nếu file không lưu độ cao, mặc định bù độ cao nền Bình Thuận là 50 mét
                        double ele = (point.count >= 3 && [point[2] doubleValue] > 0) ? [point[2] doubleValue] : 50.0;
                        
                        CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                                                        altitude:ele
                                                              horizontalAccuracy:1.0
                                                                verticalAccuracy:1.0
                                                                       timestamp:[NSDate date]];
                        [gpxPoints addObject:loc];
                    }
                }
            }
        }
    }
    
    // Đọc file cấu trúc GPX truyền thống (.gpx)
    if (gpxPoints.count == 0) {
        NSError *error = nil;
        NSRegularExpression *trkptRegex = [NSRegularExpression regularExpressionWithPattern:@"<trkpt[^>]*>([\\s\\S]*?)</trkpt>" options:0 error:&error];
        NSArray *trkptMatches = [trkptRegex matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        
        NSRegularExpression *latRegex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\"" options:0 error:&error];
        NSRegularExpression *lonRegex = [NSRegularExpression regularExpressionWithPattern:@"lon=\"([^\"]+)\"" options:0 error:&error];
        NSRegularExpression *eleRegex = [NSRegularExpression regularExpressionWithPattern:@"<ele>([^<]+)</ele>" options:0 error:&error];
        
        for (NSTextCheckingResult *match in trkptMatches) {
            NSString *trkptBlock = [fileContent substringWithRange:match.range];
            
            NSTextCheckingResult *latM = [latRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            NSTextCheckingResult *lonM = [lonRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            NSTextCheckingResult *eleM = [eleRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            
            if (latM && lonM) {
                double lat = [[trkptBlock substringWithRange:[latM rangeAtIndex:1]] doubleValue];
                double lon = [[trkptBlock substringWithRange:[lonM rangeAtIndex:1]] doubleValue];
                double ele = eleM ? [[trkptBlock substringWithRange:[eleM rangeAtIndex:1]] doubleValue] : 50.0;
                
                CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                                                altitude:ele
                                                      horizontalAccuracy:1.0
                                                        verticalAccuracy:1.0
                                                               timestamp:[NSDate date]];
                [gpxPoints addObject:loc];
            }
        }
    }
}

// --- 3. HÀM ĐIỀU KHIỂN THỜI GIAN ĐỂ TẠO SỰ DI CHUYỂN ĐỘNG ---
void updateSimulation() {
    if (!isFakeGPXActive || !gpxPoints || gpxPoints.count == 0) return;
    
    // Bốc điểm tọa độ tĩnh hiện tại trong mảng ra xử lý
    CLLocation *currentPoint = gpxPoints[currentPointIndex];
    
    // Lập trình tự động tính toán hướng xoay đầu mũi tên dựa trên điểm sắp tới
    double calculatedCourse = 0.0;
    if (currentPointIndex < gpxPoints.count - 1) {
        CLLocation *nextPoint = gpxPoints[currentPointIndex + 1];
        calculatedCourse = calculateCourse(currentPoint.coordinate.latitude, currentPoint.coordinate.longitude,
                                           nextPoint.coordinate.latitude, nextPoint.coordinate.longitude);
    } else if (gpxPoints.count > 1) {
        CLLocation *prevPoint = gpxPoints[currentPointIndex - 1];
        calculatedCourse = calculateCourse(prevPoint.coordinate.latitude, prevPoint.coordinate.longitude,
                                           currentPoint.coordinate.latitude, currentPoint.coordinate.longitude);
    }
    
    double speedMs = movementSpeedKmh / 3.6; // Đổi vận tốc km/h sang m/s chuẩn Apple
    
    // Đúc gói vị trí động hoàn chỉnh để chuyển cho hàm Hook che mắt app FMS
    currentFakeLocation = [[CLLocation alloc] initWithCoordinate:currentPoint.coordinate
                                                        altitude:currentPoint.altitude
                                              horizontalAccuracy:1.0  
                                                verticalAccuracy:1.0  
                                                          course:calculatedCourse 
                                                           speed:speedMs  
                                                       timestamp:[NSDate date]];
    
    // Tăng chỉ số để vòng lặp sau tự động bước sang điểm tiếp theo
    currentPointIndex++;
    if (currentPointIndex >= gpxPoints.count) {
        currentPointIndex = 0; // Chạy hết tuyến đường thì tự động quay lại điểm xuất phát
    }
    
    // Công thức tính toán nhịp thời gian delay dựa trên tốc độ chọn trên thanh gạt
    double interval = (3.6 / movementSpeedKmh) / simulationSpeed;
    if (interval < 0.1) interval = 0.1;
    
    // PHÁT LỆNH DI CHUYỂN: Ép hàm điều khiển tự lặp lại sau một khoảng nhịp thời gian
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        updateSimulation();
    });
}

// --- 4. GIAO DIỆN ĐIỀU KHIỂN MENU NÚT NỔI ---
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
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData, UTTypeText] asCopy:YES];
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
    NSString *fileContent = [NSString stringWithContentsOfURL:selectedFileURL encoding:NSUTF8StringEncoding error:&error];
    [selectedFileURL stopAccessingSecurityScopedResource];
    
    if (!error && fileContent) {
        parseSpatialFile(fileContent);
        if (gpxPoints.count > 0) {
            statusLabel.text = [NSString stringWithFormat:@"📁 Tệp: %@ (%lu điểm)", selectedFileURL.lastPathComponent, (unsigned long)gpxPoints.count];
            statusLabel.textColor = [UIColor systemGreenColor];
        } else {
            statusLabel.text = @"❌ Cấu trúc tệp không hợp lệ!";
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
            updateSimulation(); // Bắt đầu ra lệnh kích hoạt luồng điều khiển thời gian di chuyển
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lưu ý" message:@"Vui lòng nạp tệp lộ trình trước!" preferredStyle:UIAlertControllerStyleAlert];
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
        titleLabel.text = @"OMNI GPS - PROFESSIONAL SYSTEM";
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
        [btnSelectFile setTitle:@"📁 CHỌN TỆP (GPX / GEOJSON)" forState:UIControlStateNormal];
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

// --- 5. HOOK BẺ GÃY HỆ THỐNG ĐỊNH VỊ CORE-LOCATION ---
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.coordinate;
    }
    return %orig;
}
- (CLLocationDistance)altitude {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.altitude;
    }
    return %orig;
}
- (CLLocationDirection)course {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.course;
    }
    return %orig;
}
- (CLLocationSpeed)speed {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.speed;
    }
    return %orig;
}
- (CLLocationAccuracy)horizontalAccuracy {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.horizontalAccuracy;
    }
    return %orig;
}
- (CLLocationAccuracy)verticalAccuracy {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation.verticalAccuracy;
    }
    return %orig;
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    if (isFakeGPXActive && currentFakeLocation) {
        return currentFakeLocation;
    }
    return %orig;
}
%end

%ctor {
    initFloatingUI();
}

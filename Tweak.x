#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

// --- 1. KHAI BÁO BIẾN TOÀN CỤC VÀ TRẠNG THÁI ---
typedef NS_ENUM(NSInteger, OmniSimulationState) {
    OmniStateIdle,       
    OmniStatePlaying,    
    OmniStatePaused      
};

static OmniSimulationState currentState = OmniStateIdle;
static NSMutableArray *gpxPoints = nil; 
static NSInteger currentPointIndex = 0; 
static double simulationSpeed = 1.0;   
static double movementSpeedKmh = 5.0;  

static CLLocation *currentFakeLocation = nil; 
static UIButton *floatingButton = nil;
static UIView *menuView = nil;
static UILabel *statusLabel = nil; 

static UIButton *btnPlayPause = nil; 
static UIButton *btnStop = nil;      

static dispatch_queue_t simulationQueue = nil;

// --- HÀM TOÁN HỌC TÍNH HƯỚNG XOAY MŨI TÊN ---
double calculateCourse(double lat1, double lon1, double lat2, double lon2) {
    double lat1Rad = lat1 * M_PI / 180.0;
    double lat2Rad = lat2 * M_PI / 180.0;
    double dLonRad = (lon2 - lon1) * M_PI / 180.0;
    double y = sin(dLonRad) * cos(lat2Rad);
    double x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLonRad);
    double bearingDeg = atan2(y, x) * 180.0 / M_PI;
    return (bearingDeg < 0) ? (bearingDeg + 360.0) : bearingDeg;
}

// --- 2. BỘ GIẢI MÃ ĐỌC DỮ LIỆU TĨNH TỪ TỆP TIN ---
void parseSpatialFile(NSString *fileContent) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    currentFakeLocation = nil;
    currentState = OmniStateIdle;
    
    // Đọc file cấu trúc GeoJSON (.geojson)
    if ([fileContent containsString:@"\"type\""] && [fileContent containsString:@"\"coordinates\""]) {
        NSData *jsonData = [fileContent dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *geoJSONObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (geoJSONObject) {
            NSDictionary *geometry = geoJSONObject[@"geometry"];
            if (geometry && [geometry[@"type"] isEqualToString:@"LineString"]) {
                NSArray *coordinates = geometry[@"coordinates"];
                for (NSArray *point in coordinates) {
                    if (point.count >= 2) {
                        double lon = [point[0] doubleValue];
                        double lat = [point[1] doubleValue];
                        double ele = (point.count >= 3 && [point[2] doubleValue] > 0) ? [point[2] doubleValue] : 50.0;
                        CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon) altitude:ele horizontalAccuracy:1.0 verticalAccuracy:1.0 timestamp:[NSDate date]];
                        [gpxPoints addObject:loc];
                    }
                }
            }
        }
    }
    
    // Đọc file cấu trúc GPX truyền thống (.gpx)
    if (gpxPoints.count == 0) {
        NSRegularExpression *trkptRegex = [NSRegularExpression regularExpressionWithPattern:@"<trkpt[^>]*>([\\s\\S]*?)</trkpt>" options:0 error:nil];
        NSArray *trkptMatches = [trkptRegex matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        NSRegularExpression *latRegex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\"" options:0 error:nil];
        NSRegularExpression *lonRegex = [NSRegularExpression regularExpressionWithPattern:@"lon=\"([^\"]+)\"" options:0 error:nil];
        NSRegularExpression *eleRegex = [NSRegularExpression regularExpressionWithPattern:@"<ele>([^<]+)</ele>" options:0 error:nil];
        
        for (NSTextCheckingResult *match in trkptMatches) {
            NSString *trkptBlock = [fileContent substringWithRange:match.range];
            NSTextCheckingResult *latM = [latRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            NSTextCheckingResult *lonM = [lonRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            NSTextCheckingResult *eleM = [eleRegex firstMatchInString:trkptBlock options:0 range:NSMakeRange(0, trkptBlock.length)];
            
            if (latM && lonM) {
                double lat = [[trkptBlock substringWithRange:[latM rangeAtIndex:1]] doubleValue];
                double lon = [[trkptBlock substringWithRange:[lonM rangeAtIndex:1]] doubleValue];
                double ele = eleM ? [[trkptBlock substringWithRange:[eleM rangeAtIndex:1]] doubleValue] : 50.0;
                CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon) altitude:ele horizontalAccuracy:1.0 verticalAccuracy:1.0 timestamp:[NSDate date]];
                [gpxPoints addObject:loc];
            }
        }
    }

    if (gpxPoints.count > 0) {
        CLLocation *firstPoint = gpxPoints[0];
        currentFakeLocation = [[CLLocation alloc] initWithCoordinate:firstPoint.coordinate altitude:firstPoint.altitude horizontalAccuracy:1.0 verticalAccuracy:1.0 course:0.0 speed:0.0 timestamp:[NSDate date]];
    }
}

// --- 3. HÀM ĐIỀU KHIỂN THỜI GIAN CHẠY NGẦM ---
void updateSimulation() {
    if (currentState != OmniStatePlaying || !gpxPoints || gpxPoints.count == 0) return;
    
    dispatch_async(simulationQueue, ^{
        if (currentPointIndex >= gpxPoints.count) {
            currentPointIndex = 0; 
        }
        
        CLLocation *currentPoint = gpxPoints[currentPointIndex];
        double calculatedCourse = 0.0;
        if (currentPointIndex < gpxPoints.count - 1) {
            CLLocation *nextPoint = gpxPoints[currentPointIndex + 1];
            calculatedCourse = calculateCourse(currentPoint.coordinate.latitude, currentPoint.coordinate.longitude, nextPoint.coordinate.latitude, nextPoint.coordinate.longitude);
        }
        
        double speedMs = movementSpeedKmh / 3.6;
        
        currentFakeLocation = [[CLLocation alloc] initWithCoordinate:currentPoint.coordinate altitude:currentPoint.altitude horizontalAccuracy:1.0 verticalAccuracy:1.0 course:calculatedCourse speed:speedMs timestamp:[NSDate date]];
        
        currentPointIndex++;
        
        double interval = (3.6 / movementSpeedKmh) / simulationSpeed;
        if (interval < 1.0) interval = 1.0; 
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), simulationQueue, ^{
            if (currentState == OmniStatePlaying) {
                updateSimulation();
            }
        });
    });
}

// --- 4. GIAO DIỆN ĐIỀU KHIỂN NÚT NỔI CHUYÊN NGHIỆP ---
@interface OmniControllerView : UIView <UIDocumentPickerDelegate>
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)toggleMenu;
- (void)speedChanged:(UISlider *)sender;
- (void)moveChanged:(UISlider *)sender;
- (void)playPausePressed:(UIButton *)sender;
- (void)stopPressed:(UIButton *)sender;
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
    while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
    [rootVC presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFileURL = urls.firstObject;
    if (!selectedFileURL) return;
    
    [selectedFileURL startAccessingSecurityScopedResource];
    NSString *fileContent = [NSString stringWithContentsOfURL:selectedFileURL encoding:NSUTF8StringEncoding error:nil];
    [selectedFileURL stopAccessingSecurityScopedResource];
    
    if (fileContent) {
        parseSpatialFile(fileContent);
        
        // AN TOÀN ĐỒ HỌA: Ép các lệnh vẽ và sửa nút bấm phải chạy trên Main Thread để chống đơ máy
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gpxPoints.count > 0) {
                statusLabel.text = [NSString stringWithFormat:@"📁 Đã ghim điểm đầu (%lu điểm)", (unsigned long)gpxPoints.count];
                statusLabel.textColor = [UIColor systemGreenColor];
                
                [btnPlayPause setTitle:@"▶️ BẮT ĐẦU DI CHUYỂN" forState:UIControlStateNormal];
                btnPlayPause.backgroundColor = [UIColor systemGreenColor];
                btnPlayPause.enabled = YES;
                btnStop.enabled = YES;
            } else {
                statusLabel.text = @"❌ Cấu trúc tệp không đúng!";
                statusLabel.textColor = [UIColor systemOrangeColor];
            }
        });
    }
}

- (void)playPausePressed:(UIButton *)sender {
    if (gpxPoints.count == 0) return;
    
    if (currentState == OmniStateIdle || currentState == OmniStatePaused) {
        currentState = OmniStatePlaying;
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setTitle:@"⏸️ TẠM DỪNG LỘ TRÌNH" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemOrangeColor];
        });
        updateSimulation();
    } else if (currentState == OmniStatePlaying) {
        currentState = OmniStatePaused;
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setTitle:@"▶️ TIẾP TỤC DI CHUYỂN" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemGreenColor];
        });
    }
}

- (void)stopPressed:(UIButton *)sender {
    if (gpxPoints.count == 0) return;
    
    currentState = OmniStateIdle;
    currentPointIndex = 0;
    
    CLLocation *firstPoint = gpxPoints[0];
    currentFakeLocation = [[CLLocation alloc] initWithCoordinate:firstPoint.coordinate altitude:firstPoint.altitude horizontalAccuracy:1.0 verticalAccuracy:1.0 course:0.0 speed:0.0 timestamp:[NSDate date]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [btnPlayPause setTitle:@"▶️ BẮT ĐẦU DI CHUYỂN" forState:UIControlStateNormal];
        btnPlayPause.backgroundColor = [UIColor systemGreenColor];
        statusLabel.text = [NSString stringWithFormat:@"📁 Đã reset về điểm đầu (%lu điểm)", (unsigned long)gpxPoints.count];
        statusLabel.textColor = [UIColor systemGreenColor];
    });
}
@end

static OmniControllerView *uiHandler = nil;

void initFloatingUI() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) { if (window.isKeyWindow) { keyWindow = window; break; } }
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
        
        menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 290, 345)];
        menuView.center = keyWindow.center;
        menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.96];
        menuView.layer.cornerRadius = 14;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.65 blue:0.9 alpha:0.3].CGColor;
        menuView.hidden = YES;
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 12, 270, 20)];
        titleLabel.text = @"OMNI GPS - TẠT ĐƯỜNG LÂM NGHIỆP";
        titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
        titleLabel.font = [UIFont boldSystemFontOfSize:12];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:titleLabel];
        
        UIButton *btnSelectFile = [UIButton buttonWithType:UIButtonTypeCustom];
        btnSelectFile.frame = CGRectMake(15, 42, 260, 38);
        btnSelectFile.backgroundColor = [UIColor colorWithRed:0.2 green:0.25 blue:0.35 alpha:1.0];
        btnSelectFile.layer.cornerRadius = 8;
        [btnSelectFile setTitle:@"📁 NẠP TỆP LỘ TRÌNH (GPX/GEOJSON)" forState:UIControlStateNormal];
        btnSelectFile.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [btnSelectFile addTarget:uiHandler action:@selector(openFilePicker) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnSelectFile];
        
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 88, 260, 15)];
        statusLabel.text = @"Trạng thái: Chưa có tệp dữ liệu";
        statusLabel.textColor = [UIColor lightGrayColor];
        statusLabel.font = [UIFont systemFontOfSize:10];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:statusLabel];
        
        UILabel *lblMove = [[UILabel alloc] initWithFrame:CGRectMake(15, 110, 260, 15)];
        lblMove.text = @"Tốc độ di chuyển: 5.0 km/h";
        lblMove.textColor = [UIColor whiteColor];
        lblMove.font = [UIFont systemFontOfSize:11];
        lblMove.tag = 701;
        [menuView addSubview:lblMove];
        
        UISlider *sliderMove = [[UISlider alloc] initWithFrame:CGRectMake(15, 125, 260, 20)];
        sliderMove.minimumValue = 5.0;
        sliderMove.maximumValue = 20.0;
        sliderMove.value = 5.0;
        [sliderMove addTarget:uiHandler action:@selector(moveChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderMove];

        UILabel *lblSpeed = [[UILabel alloc] initWithFrame:CGRectMake(15, 152, 260, 15)];
        lblSpeed.text = @"Tốc độ thời gian (0.1x - 10x): 1.0x";
        lblSpeed.textColor = [UIColor whiteColor];
        lblSpeed.font = [UIFont systemFontOfSize:11];
        lblSpeed.tag = 801;
        [menuView addSubview:lblSpeed];
        
        UISlider *sliderSpeed = [[UISlider alloc] initWithFrame:CGRectMake(15, 167, 260, 20)];
        sliderSpeed.minimumValue = 0.1;
        sliderSpeed.maximumValue = 10.0;
        sliderSpeed.value = 1.0;
        [sliderSpeed addTarget:uiHandler action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sliderSpeed];
        
        btnPlayPause = [UIButton buttonWithType:UIButtonTypeCustom];
        btnPlayPause.frame = CGRectMake(15, 202, 260, 40);
        btnPlayPause.backgroundColor = [UIColor grayColor];
        btnPlayPause.layer.cornerRadius = 8;
        [btnPlayPause setTitle:@"▶️ BẮT ĐẦU DI CHUYỂN" forState:UIControlStateNormal];
        btnPlayPause.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        btnPlayPause.enabled = NO;
        [btnPlayPause addTarget:uiHandler action:@selector(playPausePressed:) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnPlayPause];

        btnStop = [UIButton buttonWithType:UIButtonTypeCustom];
        btnStop.frame = CGRectMake(15, 252, 260, 38);
        btnStop.backgroundColor = [UIColor colorWithRed:0.35 green:0.15 blue:0.15 alpha:1.0];
        btnStop.layer.cornerRadius = 8;
        btnStop.layer.borderWidth = 1;
        btnStop.layer.borderColor = [UIColor systemRedColor].CGColor;
        [btnStop setTitle:@"⏹️ DỪNG HẲN & VỀ ĐIỂM ĐẦU" forState:UIControlStateNormal];
        btnStop.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        btnStop.enabled = NO;
        [btnStop addTarget:uiHandler action:@selector(stopPressed:) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnStop];
        
        UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeCustom];
        btnClose.frame = CGRectMake(15, 302, 260, 30);
        btnClose.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        btnClose.layer.cornerRadius = 6;
        [btnClose setTitle:@"ẨN MENU ĐIỀU KHIỂN" forState:UIControlStateNormal];
        btnClose.titleLabel.font = [UIFont systemFontOfSize:11];
        [btnClose addTarget:uiHandler action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:btnClose];
        
        [keyWindow addSubview:menuView];
    });
}

// --- 5. HOOK ĐỊNH VỊ CHUYÊN NGHIỆP ---
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    if (currentFakeLocation) return currentFakeLocation.coordinate;
    return %orig;
}
- (CLLocationDistance)altitude {
    if (currentFakeLocation) return currentFakeLocation.altitude;
    return %orig;
}
- (CLLocationDirection)course {
    if (currentFakeLocation) return currentFakeLocation.course;
    return %orig;
}
- (CLLocationSpeed)speed {
    if (currentFakeLocation) return currentFakeLocation.speed;
    return %orig;
}
- (CLLocationAccuracy)horizontalAccuracy {
    if (currentFakeLocation) return 1.0; 
    return %orig;
}
- (CLLocationAccuracy)verticalAccuracy {
    if (currentFakeLocation) return 1.0;
    return %orig;
}
%end

%hook CLLocationManager
- (CLLocation *)location {
    if (currentFakeLocation) return currentFakeLocation;
    return %orig;
}
%end

%ctor {
    simulationQueue = dispatch_queue_create("com.omni.simulation.queue", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(simulationQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    initFloatingUI();
}

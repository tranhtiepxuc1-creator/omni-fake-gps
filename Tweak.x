// --- HÀM ĐỌC PHÂN TÍCH FILE GPX THÔNG MINH (SỬA LỖI LỆCH TỌA ĐỘ) ---
void parseGPXString(NSString *gpxString) {
    if (!gpxPoints) gpxPoints = [[NSMutableArray alloc] init];
    [gpxPoints removeAllObjects];
    currentPointIndex = 0;
    
    // Sử dụng hai bộ quét độc lập để không bị phụ thuộc vào thứ tự đứng trước/sau của lat và lon
    NSError *error = nil;
    NSRegularExpression *latRegex = [NSRegularExpression regularExpressionWithPattern:@"lat=\"([^\"]+)\"" options:0 error:&error];
    NSRegularExpression *lonRegex = [NSRegularExpression regularExpressionWithPattern:@"lon=\"([^\"]+)\"" options:0 error:&error];
    
    // Tách văn bản thành từng dòng trkpt để xử lý chính xác
    NSRegularExpression *lineRegex = [NSRegularExpression regularExpressionWithPattern:@"<trkpt[^>]*>" options:0 error:&error];
    NSArray *matches = [lineRegex matchesInString:gpxString options:0 range:NSMakeRange(0, gpxString.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSString *line = [gpxString substringWithRange:match.range];
        
        NSTextCheckingResult *latMatch = [latRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSTextCheckingResult *lonMatch = [lonRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        
        if (latMatch && lonMatch) {
            NSString *latStr = [line substringWithRange:[latMatch rangeAtIndex:1]];
            NSString *lonStr = [line substringWithRange:[lonMatch rangeAtIndex:1]];
            
            // Ép kiểu số thực chính xác tuyệt đối
            CLLocation *location = [[CLLocation alloc] initWithLatitude:[latStr doubleValue] longitude:[lonStr doubleValue]];
            [gpxPoints addObject:location];
        }
    }
    NSLog(@"[OMNI-GPS] Đã nạp thành công %lu tọa độ chuẩn từ tệp GPX của bạn!", (unsigned long)gpxPoints.count);
}

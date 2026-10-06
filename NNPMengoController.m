#import "NNPMengoController.h"
#import "NNPMengoTicket.h"
#import "NNPMengoSensorMode.h"
#import "NNPMengoTouchMonitor.h"
#import "NNPDiagnostics.h"
#import "NNPAODPresentation.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#include <math.h>

@interface NNPMengoOverlay : UIView
@property(nonatomic) CGRect entryRegion;
@property(nonatomic) BOOL ticketOpen;
@end
@implementation NNPMengoOverlay
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return (self.ticketOpen || CGRectContainsPoint(self.entryRegion, point)) && [super pointInside:point withEvent:event];
}
@end
@interface NNPMengoRedirectGuard : NSObject <NSURLSessionTaskDelegate>
@end
@implementation NNPMengoRedirectGuard
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(nil); }
@end

static NSDictionary *NNPMengoSession(void) {
    static NSString *cachedPath;
    NSDictionary *session = cachedPath ? [NSDictionary dictionaryWithContentsOfFile:cachedPath] : nil;
    if (session) return session;
    NSString *base = @"/var/mobile/Containers/Data/Application";
    for (NSString *container in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil]) {
        NSString *path = [[base stringByAppendingPathComponent:container]
            stringByAppendingPathComponent:@"Library/Application Support/NotchNowPlaying/mengo-session.plist"];
        session = [NSDictionary dictionaryWithContentsOfFile:path];
        if (session) { cachedPath = path; return session; }
    }
    return nil;
}

@interface NNPMengoController ()
@property(nonatomic, strong) NNPMengoOverlay *overlay;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIButton *entry;
@property(nonatomic, strong) UILabel *credentialLabel;
@property(nonatomic, strong) NSURLSession *credentialSession;
@property(nonatomic, strong) NSURLSessionDataTask *credentialTask;
@property(nonatomic, strong) NSTimer *credentialTimer;
@property(nonatomic) NSUInteger credentialGeneration;
@property(nonatomic) NSTimeInterval credentialVersion;
@property(nonatomic) NSTimeInterval credentialAttempt;
@property(nonatomic) NSTimeInterval credentialChecked;
@property(nonatomic) NNPMengoCredentialStatus credentialStatus;
@property(nonatomic, strong) UIImageView *codeView;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UILabel *countdown;
@property(nonatomic, strong) NSTimer *countdownTimer;
@property(nonatomic) NSTimeInterval closeDeadline;
@property(nonatomic) NSTimeInterval refreshDeadline;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, strong) NSTimer *closeTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL active;
@property(nonatomic, strong) NNPMengoSensorMode *sensorMode;
@property(nonatomic, strong) NNPMengoTouchMonitor *monitor;
@property(nonatomic) BOOL monitorTracking;
@property(nonatomic) BOOL monitorContactActive;
@property(nonatomic) CGPoint monitorStart;
@property(nonatomic) CGRect monitorRegion;
@end
@implementation NNPMengoController
- (void)setHostView:(UIView *)host active:(BOOL)active {
    active = active && host.window != nil;
    BOOL becameActive = active && !self.active;
    self.active = active;
    if (active && !self.sensorMode) self.sensorMode = [NNPMengoSensorMode new];
    [self.sensorMode setActive:active];
    if (active && !self.monitor) {
        self.monitor = [NNPMengoTouchMonitor new];
        __weak typeof(self) weakSelf = self;
        self.monitor.contact = ^(CGPoint normalized, BOOL down) { [weakSelf monitorContact:normalized down:down]; };
    }
    [self.monitor setActive:active];
    if (!active) { self.monitorTracking = NO; self.monitorContactActive = NO; }
    NNPDiagnosticSetBool(@"MengoFullTouchAssertionActive", NO);
    NNPDiagnosticSetBool(@"MengoEntryVisible", active);
    if (!active) NNPDiagnosticSetBool(@"MengoEntryAttachedToAOD", NO);
    if (!active) {
        self.credentialGeneration++;
        [self.credentialTimer invalidate]; self.credentialTimer = nil;
        if (self.credentialTask) self.credentialAttempt = 0;
        [self.credentialTask cancel]; self.credentialTask = nil;
        [self.credentialSession invalidateAndCancel]; self.credentialSession = nil;
        [self close];
        [self.overlay removeFromSuperview];
        self.overlay = nil;
        self.panel = nil; self.entry = nil; self.codeView = nil; self.status = nil; self.countdown = nil;
        self.credentialLabel = nil;
        return;
    }
    if (!self.overlay || self.overlay.superview != host) {
        [self close]; [self.overlay removeFromSuperview];
        self.overlay = [[NNPMengoOverlay alloc] initWithFrame:host.bounds];
        self.overlay.backgroundColor = UIColor.clearColor;
        self.overlay.opaque = NO;
        self.overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:self.overlay];
        self.entry = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.entry setImage:[UIImage systemImageNamed:@"qrcode"] forState:UIControlStateNormal];
        self.entry.tintColor = [UIColor colorWithWhite:0.75 alpha:1];
        self.entry.accessibilityLabel = @"MeN Go 乘車碼";
        [self.entry addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        [self.overlay addSubview:self.entry];
        self.credentialLabel = [UILabel new];
        self.credentialLabel.font = [UIFont systemFontOfSize:10];
        self.credentialLabel.textAlignment = NSTextAlignmentRight;
        self.credentialLabel.numberOfLines = 2;
        self.credentialLabel.isAccessibilityElement = YES;
        [self.overlay addSubview:self.credentialLabel];
        self.panel = [UIView new]; self.panel.backgroundColor = UIColor.blackColor;
        self.panel.accessibilityViewIsModal = YES;
        self.panel.hidden = YES; [self.overlay addSubview:self.panel];
        self.codeView = [UIImageView new]; self.codeView.contentMode = UIViewContentModeScaleAspectFit;
        self.codeView.backgroundColor = UIColor.whiteColor;
        self.codeView.layer.magnificationFilter = kCAFilterNearest;
        self.codeView.layer.minificationFilter = kCAFilterNearest;
        self.codeView.accessibilityLabel = @"MeN Go 動態乘車碼";
        self.codeView.isAccessibilityElement = YES;
        self.codeView.hidden = YES; [self.panel addSubview:self.codeView];
        self.status = [UILabel new]; self.status.textColor = UIColor.whiteColor;
        self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 3;
        self.status.font = [UIFont systemFontOfSize:16]; [self.panel addSubview:self.status];
        self.countdown = [UILabel new]; self.countdown.textColor = [UIColor colorWithWhite:0.85 alpha:1];
        self.countdown.textAlignment = NSTextAlignmentCenter;
        self.countdown.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        [self.panel addSubview:self.countdown];
        UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem]; back.tag = 1;
        [back setTitle:@"關閉" forState:UIControlStateNormal]; back.tintColor = UIColor.whiteColor;
        [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:back];
        UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem]; refresh.tag = 2;
        [refresh setTitle:@"重新取得" forState:UIControlStateNormal]; refresh.tintColor = UIColor.whiteColor;
        [refresh addTarget:self action:@selector(fetch) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:refresh];
    }
    self.overlay.frame = host.bounds;
    CGFloat width = CGRectGetWidth(self.overlay.bounds), height = CGRectGetHeight(self.overlay.bounds);
    self.entry.frame = CGRectMake(width - 76, height - 132, 52, 52);
    self.credentialLabel.frame = CGRectMake(width - 144, height - 78, 120, 30);
    self.overlay.entryRegion = self.entry.frame;
    self.panel.frame = self.overlay.bounds;
    CGFloat size = MIN(240, MIN(width - 64, height - 260));
    self.codeView.frame = CGRectMake((width - size) / 2, (height - size) / 2 - 20, size, size);
    self.status.frame = CGRectMake(24, CGRectGetMinY(self.codeView.frame) - 90, width - 48, 72);
    self.countdown.frame = CGRectMake(24, CGRectGetMaxY(self.codeView.frame) + 2, width - 48, 20);
    [self.panel viewWithTag:1].frame = CGRectMake(width / 2 - 114, CGRectGetMaxY(self.codeView.frame) + 24, 100, 48);
    [self.panel viewWithTag:2].frame = CGRectMake(width / 2 + 14, CGRectGetMaxY(self.codeView.frame) + 24, 100, 48);
    self.overlay.hidden = NO;
    [host bringSubviewToFront:self.overlay];
    NNPDiagnosticSetBool(@"MengoEntryAttachedToAOD", self.overlay.superview == host);
    NNPDiagnosticSetString(@"MengoEntryFrame", NSStringFromCGRect(self.entry.frame));
    CGRect inWindow = [self.entry convertRect:self.entry.bounds toView:self.entry.window];
    NNPDiagnosticSetString(@"MengoEntryScreenFrame", NSStringFromCGRect([self.entry.window convertRect:inWindow toWindow:nil]));
    NNPDiagnosticSetString(@"MengoHostBounds", NSStringFromCGRect(host.bounds));
    NNPDiagnosticSetString(@"MengoScreenBounds", NSStringFromCGRect(UIScreen.mainScreen.bounds));
    NNPDiagnosticSetString(@"MengoNativeScreenBounds", NSStringFromCGRect(UIScreen.mainScreen.nativeBounds));
    NNPDiagnosticSetDouble(@"MengoScreenScale", UIScreen.mainScreen.scale);
    if (becameActive) [self checkCredentialIfNeeded];
    if (!self.credentialLabel.text.length) [self updateCredentialLabel];
    if (!self.credentialTimer) {
        __weak typeof(self) weakSelf = self;
        self.credentialTimer = [NSTimer timerWithTimeInterval:1800 repeats:YES block:^(NSTimer *timer) {
            [weakSelf checkCredentialIfNeeded];
        }];
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - self.credentialAttempt;
        if (self.credentialAttempt > 0 && age >= 0)
            self.credentialTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:MAX(30, 1800 - age)];
        self.credentialTimer.tolerance = 60;
        [NSRunLoop.mainRunLoop addTimer:self.credentialTimer forMode:NSRunLoopCommonModes];
    }
}
- (void)updateCredentialLabel {
    NSString *text;
    UIColor *color = [UIColor colorWithWhite:0.65 alpha:1];
    if (self.credentialTask) text = @"正在檢查登入…";
    else if (self.credentialStatus == NNPMengoCredentialMissing) text = @"請先同步 MeN Go 登入";
    else if (self.credentialStatus == NNPMengoCredentialRejected) {
        text = @"需重新登入 MeN Go";
        color = [UIColor colorWithRed:0.85 green:0.4 blue:0.35 alpha:1];
    } else if (self.credentialStatus == NNPMengoCredentialValid) {
        NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"HH:mm";
        text = [NSString stringWithFormat:@"登入有效 · %@", [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:self.credentialChecked]]];
    } else {
        text = @"登入狀態未確認";
        color = [UIColor colorWithRed:0.8 green:0.65 blue:0.3 alpha:1];
    }
    self.credentialLabel.text = text;
    self.credentialLabel.textColor = color;
    self.entry.accessibilityValue = text;
    NNPDiagnosticSetString(@"MengoCredentialCaption", text);
    NNPDiagnosticSetInteger(@"MengoCredentialStatus", self.credentialStatus);
    NNPDiagnosticSetDouble(@"MengoCredentialCheckedTimestamp", self.credentialChecked);
}
- (void)checkCredentialIfNeeded {
    if (!self.active || self.credentialTask) return;
    NSDictionary *auth = NNPMengoSession();
    NSString *token = [auth[@"token"] isKindOfClass:NSString.class] ? auth[@"token"] : nil;
    NSString *agent = [auth[@"agent"] isKindOfClass:NSString.class] ? auth[@"agent"] : nil;
    NSTimeInterval version = [auth[@"updated"] isKindOfClass:NSNumber.class] ? [auth[@"updated"] doubleValue] : 0;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!token.length || token.length > 16384 || !agent.length || agent.length > 512 ||
        [agent rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        self.credentialStatus = NNPMengoCredentialMissing;
        self.credentialVersion = 0; self.credentialChecked = 0; self.credentialAttempt = 0;
        [self updateCredentialLabel];
        return;
    }
    if (version != self.credentialVersion) {
        self.credentialVersion = version; self.credentialAttempt = 0;
        self.credentialChecked = 0; self.credentialStatus = NNPMengoCredentialUnknown;
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"NNPMengoCredentialCheck"];
        if ([saved[@"version"] doubleValue] == version) {
            self.credentialChecked = [saved[@"checked"] doubleValue];
            self.credentialStatus = [saved[@"state"] integerValue];
            self.credentialAttempt = [saved[@"attempted"] doubleValue];
        }
    }
    NSTimeInterval age = now - self.credentialAttempt;
    NSTimeInterval interval = self.credentialStatus == NNPMengoCredentialUnknown ? 300 : 1800;
    if (self.credentialAttempt > 0 && age >= 0 && age < interval) return;
    self.credentialAttempt = now;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20;
    config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
    self.credentialSession = [NSURLSession sessionWithConfiguration:config delegate:[NNPMengoRedirectGuard new] delegateQueue:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://men-go.tw/Platform/Htmlv2/LoginCheck"]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    request.HTTPMethod = @"POST"; request.HTTPBody = NNPMengoFormBody(token);
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:agent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"null" forHTTPHeaderField:@"Origin"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    NSUInteger generation = ++self.credentialGeneration;
    __weak typeof(self) weakSelf = self;
    self.credentialTask = [self.credentialSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPMengoCredentialStatus state = !error && [response isKindOfClass:NSHTTPURLResponse.class] &&
            [(NSHTTPURLResponse *)response statusCode] == 200 ? NNPMengoLoginCheckStatus(data) : NNPMengoCredentialUnknown;
        dispatch_async(dispatch_get_main_queue(), ^{
            NNPMengoController *owner = weakSelf;
            if (!owner || generation != owner.credentialGeneration || !owner.active) return;
            owner.credentialTask = nil;
            [owner.credentialSession finishTasksAndInvalidate]; owner.credentialSession = nil;
            // A network failure cannot undo a known rejection of this credential.
            if (state != NNPMengoCredentialUnknown || owner.credentialStatus != NNPMengoCredentialRejected)
                owner.credentialStatus = state;
            if (state != NNPMengoCredentialUnknown) {
                owner.credentialChecked = NSDate.date.timeIntervalSince1970;
            }
            [NSUserDefaults.standardUserDefaults setObject:@{@"version": @(version), @"checked": @(owner.credentialChecked),
                @"attempted": @(owner.credentialAttempt), @"state": @(owner.credentialStatus)} forKey:@"NNPMengoCredentialCheck"];
            [owner updateCredentialLabel];
        });
    }];
    [self.credentialTask resume];
    [self updateCredentialLabel];
}
- (void)monitorContact:(CGPoint)normalized down:(BOOL)down {
    if (!self.active || !self.overlay.window || !self.overlay.superview) return;
    CGRect screen = UIScreen.mainScreen.bounds;
    CGPoint screenPoint = CGPointMake(normalized.x * CGRectGetWidth(screen), normalized.y * CGRectGetHeight(screen));
    UIWindow *window = self.overlay.window;
    CGPoint point = [window convertPoint:screenPoint fromWindow:nil];
    if (down) {
        self.monitorContactActive = YES;
        self.monitorRegion = [self interactiveRectInView:window];
        self.monitorTracking = CGRectContainsPoint(self.monitorRegion, point);
        self.monitorStart = point;
        NNPDiagnosticSetBool(@"MengoMonitorMatched", self.monitorTracking);
    } else {
        if (!self.monitorContactActive) return;
        self.monitorContactActive = NO;
        BOOL beganInside = self.monitorTracking;
        BOOL stillTap = hypot(point.x - self.monitorStart.x, point.y - self.monitorStart.y) < 18;
        BOOL tap = self.monitorTracking && CGRectContainsPoint(self.monitorRegion, point) &&
            hypot(point.x - self.monitorStart.x, point.y - self.monitorStart.y) < 18;
        self.monitorTracking = NO;
        if (tap) [self handleTapAtPoint:point inView:window];
        else if (!beganInside && stillTap && !self.overlay.ticketOpen && self.outsideTap) self.outsideTap();
    }
}
- (void)open {
    if (!self.active || self.overlay.ticketOpen) return;
    self.overlay.ticketOpen = YES; self.panel.hidden = NO;
    if (self.presentationChanged) self.presentationChanged(YES);
    NNPDiagnosticSetBool(@"MengoTicketOpen", YES);
    self.closeDeadline = NSProcessInfo.processInfo.systemUptime + 90;
    __weak typeof(self) weakSelf = self;
    self.countdownTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf updateCountdown]; }];
    self.countdownTimer.tolerance = 0.1;
    [NSRunLoop.mainRunLoop addTimer:self.countdownTimer forMode:NSRunLoopCommonModes];
    [self updateCountdown];
    self.closeTimer = [NSTimer timerWithTimeInterval:90 repeats:NO block:^(NSTimer *timer) { [weakSelf close]; }];
    [NSRunLoop.mainRunLoop addTimer:self.closeTimer forMode:NSRunLoopCommonModes];
    [self fetch];
}
- (CGRect)interactiveRectInView:(UIView *)view {
    if (!self.active || !self.overlay.superview || self.overlay.hidden) return CGRectNull;
    UIView *target = self.overlay.ticketOpen ? self.panel : self.entry;
    return [target convertRect:target.bounds toView:view];
}
- (BOOL)handleTapAtPoint:(CGPoint)point inView:(UIView *)view {
    if (!self.active || !self.overlay.superview || self.overlay.hidden) return NO;
    if (!self.overlay.ticketOpen) {
        if (!CGRectContainsPoint([self.entry convertRect:self.entry.bounds toView:view], point)) return NO;
        NNPDiagnosticSetString(@"MengoLastTouchAction", @"open");
        [self open];
        return YES;
    }
    UIView *back = [self.panel viewWithTag:1], *refresh = [self.panel viewWithTag:2];
    if (CGRectContainsPoint([back convertRect:back.bounds toView:view], point)) {
        NNPDiagnosticSetString(@"MengoLastTouchAction", @"close"); [self close];
    } else if (CGRectContainsPoint([refresh convertRect:refresh.bounds toView:view], point)) {
        NNPDiagnosticSetString(@"MengoLastTouchAction", @"refresh"); [self fetch];
    }
    return CGRectContainsPoint([self.overlay convertRect:self.overlay.bounds toView:view], point);
}
- (void)updateCountdown {
    if (!self.overlay.ticketOpen) return;
    double now = NSProcessInfo.processInfo.systemUptime;
    NSInteger closeSeconds = MAX(0, (NSInteger)ceil(self.closeDeadline - now));
    if (self.refreshDeadline > 0) {
        NSInteger updateSeconds = MAX(0, (NSInteger)ceil(self.refreshDeadline - now));
        self.countdown.text = [NSString stringWithFormat:@"%ld 秒後更新 · %ld 秒後關閉", (long)updateSeconds, (long)closeSeconds];
    } else self.countdown.text = [NSString stringWithFormat:@"%ld 秒後關閉", (long)closeSeconds];
}
- (void)close {
    BOOL wasOpen = self.overlay.ticketOpen;
    self.generation++;
    [self.task cancel]; self.task = nil;
    [self.session invalidateAndCancel]; self.session = nil;
    [self.refreshTimer invalidate]; self.refreshTimer = nil;
    [self.closeTimer invalidate]; self.closeTimer = nil;
    [self.countdownTimer invalidate]; self.countdownTimer = nil;
    self.refreshDeadline = 0; self.closeDeadline = 0; self.countdown.text = @"";
    self.codeView.image = nil; self.codeView.hidden = YES;
    self.panel.hidden = YES; self.overlay.ticketOpen = NO;
    if (wasOpen && self.presentationChanged) self.presentationChanged(NO);
    NNPDiagnosticSetBool(@"MengoTicketOpen", NO);
    NNPDiagnosticSetBool(@"MengoRequestActive", NO);
    NNPDiagnosticSetBool(@"MengoTicketImageAvailable", NO);
}
- (void)restPixelsAtOffset:(CGPoint)pixels {
    if (!self.overlay || self.overlay.hidden) return;
    NNPAODRestPixels(self.overlay.layer);
    NNPAODApplyPixelShift(self.overlay.layer, pixels);
    NNPDiagnosticSetString(@"MengoLayerPixelShift", NSStringFromCGAffineTransform(CATransform3DGetAffineTransform(self.overlay.layer.sublayerTransform)));
    NNPDiagnosticSetInteger(@"MengoPixelShiftX", (NSInteger)pixels.x);
    NNPDiagnosticSetInteger(@"MengoPixelShiftY", (NSInteger)pixels.y);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CALayer *presentation = weakSelf.overlay.layer.presentationLayer;
        NNPDiagnosticSetBool(@"MengoPixelRestObserved", presentation && presentation.opacity < 0.01);
    });
}
- (void)fetch {
    if (!self.active || !self.overlay.ticketOpen || self.task) return;
    [self.refreshTimer invalidate]; self.refreshTimer = nil;
    self.codeView.image = nil; self.codeView.hidden = YES;
    self.refreshDeadline = 0; [self updateCountdown];
    self.status.text = @"正在取得乘車碼…";
    NSDictionary *auth = NNPMengoSession();
    NSString *token = [auth[@"token"] isKindOfClass:NSString.class] ? auth[@"token"] : nil;
    NSString *endpoint = auth[@"endpoint"];
    NSString *agent = [auth[@"agent"] isKindOfClass:NSString.class] ? auth[@"agent"] : nil;
    if (!token.length || token.length > 16384 ||
        !agent.length || agent.length > 512 || [agent rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
        (![endpoint isEqual:@"QRCode"] && ![endpoint isEqual:@"MQRCode"])) {
        self.status.text = @"請先開啟 MeN Go\n登入並顯示一次乘車碼";
        NNPDiagnosticSetBool(@"MengoSessionAvailable", NO);
        return;
    }
    NNPDiagnosticSetBool(@"MengoSessionAvailable", YES);
    if (!self.session) {
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20;
        config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:[NNPMengoRedirectGuard new] delegateQueue:nil];
    }
    NSURL *url = [NSURL URLWithString:[@"https://men-go.tw/Platform/Htmlv2/" stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    request.HTTPMethod = @"POST"; request.HTTPBody = NNPMengoFormBody(token);
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:agent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"null" forHTTPHeaderField:@"Origin"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    NSUInteger generation = ++self.generation;
    __weak typeof(self) weakSelf = self;
    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *message;
        NSData *bytes = !error && [response isKindOfClass:NSHTTPURLResponse.class] &&
            [(NSHTTPURLResponse *)response statusCode] == 200 ? NNPMengoImageData(data, &message) : nil;
        UIImage *image;
        if (bytes) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)bytes, NULL);
            NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
            double width = [properties[(id)kCGImagePropertyPixelWidth] doubleValue];
            double height = [properties[(id)kCGImagePropertyPixelHeight] doubleValue];
            if (width > 0 && height > 0 && width <= 2048 && height <= 2048) image = [UIImage imageWithData:bytes];
            if (source) CFRelease(source);
        }
        BOOL readable = NO;
        if (image && bytes) {
            CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
            CIImage *qr = [CIImage imageWithData:bytes];
            for (CIQRCodeFeature *feature in (qr ? [detector featuresInImage:qr] : @[])) {
                if ([feature isKindOfClass:CIQRCodeFeature.class] &&
                    (feature.messageString.length || feature.symbolDescriptor.errorCorrectedPayload.length)) { readable = YES; break; }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NNPMengoController *owner = weakSelf;
            if (!owner || generation != owner.generation || !owner.active || !owner.overlay.ticketOpen) return;
            owner.task = nil;
            if ([message isEqualToString:@"請開啟 MeN Go 重新登入"]) {
                owner.credentialStatus = NNPMengoCredentialRejected;
                owner.credentialChecked = NSDate.date.timeIntervalSince1970;
                [NSUserDefaults.standardUserDefaults setObject:@{@"version": @(owner.credentialVersion),
                    @"checked": @(owner.credentialChecked), @"attempted": @(owner.credentialAttempt),
                    @"state": @(NNPMengoCredentialRejected)} forKey:@"NNPMengoCredentialCheck"];
                [owner updateCredentialLabel];
            }
            NNPDiagnosticSetBool(@"MengoRequestActive", NO);
            NNPDiagnosticSetBool(@"MengoTicketImageAvailable", image != nil);
            NNPDiagnosticSetBool(@"MengoQRCodeReadable", readable);
            NNPDiagnosticSetBool(@"MengoTicketExitOnly", [message containsString:@"僅可出站"]);
            if (image) NNPDiagnosticSetDouble(@"MengoLastSuccessfulFetchTimestamp", NSDate.date.timeIntervalSince1970);
            if (!image) { owner.status.text = message ?: @"無法取得乘車碼\n請確認網路或點選重新取得"; return; }
            owner.codeView.image = image; owner.codeView.hidden = NO;
            owner.status.text = message ?: (readable ? @"MeN Go 乘車碼\n請將 QR Code 對準讀碼機" : @"MeN Go 乘車碼\nQR 解析未確認，請至 App 核對");
            owner.refreshDeadline = NSProcessInfo.processInfo.systemUptime + 60;
            [owner updateCountdown];
            // The app refreshes at 300 s; use a shorter display age, never reuse
            // an earlier image on reopen or keep it after a failed renewal.
            owner.refreshTimer = [NSTimer timerWithTimeInterval:60 repeats:NO block:^(NSTimer *timer) { [weakSelf fetch]; }];
            [NSRunLoop.mainRunLoop addTimer:owner.refreshTimer forMode:NSRunLoopCommonModes];
        });
    }];
    NNPDiagnosticSetBool(@"MengoRequestActive", YES);
    [self.task resume];
}
- (void)dealloc {
    [self.credentialTimer invalidate];
    [self.credentialTask cancel]; [self.credentialSession invalidateAndCancel];
    [self.countdownTimer invalidate];
    [_monitor setActive:NO];
    [_sensorMode setActive:NO];
    [self.task cancel]; [self.session invalidateAndCancel];
    [self.refreshTimer invalidate]; [self.closeTimer invalidate];
    [self.overlay removeFromSuperview];
}
@end

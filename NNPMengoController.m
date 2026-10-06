#import "NNPMengoController.h"
#import "NNPMengoTicket.h"
#import "NNPMengoSensorMode.h"
#import "NNPDiagnostics.h"
#import "NNPAODPresentation.h"
#import <ImageIO/ImageIO.h>

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
@property(nonatomic, strong) UIImageView *codeView;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, strong) NSTimer *closeTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL active;
@property(nonatomic, strong) NNPMengoSensorMode *sensorMode;
@end
@implementation NNPMengoController
- (void)setHostView:(UIView *)host active:(BOOL)active {
    active = active && host.window != nil;
    self.active = active;
    if (active && !self.sensorMode) self.sensorMode = [NNPMengoSensorMode new];
    [self.sensorMode setActive:active];
    NNPDiagnosticSetBool(@"MengoFullTouchAssertionActive", NO);
    NNPDiagnosticSetBool(@"MengoEntryVisible", active);
    if (!active) NNPDiagnosticSetBool(@"MengoEntryAttachedToAOD", NO);
    if (!active) {
        [self close];
        [self.overlay removeFromSuperview];
        self.overlay = nil;
        self.panel = nil; self.entry = nil; self.codeView = nil; self.status = nil;
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
    self.overlay.entryRegion = self.entry.frame;
    self.panel.frame = self.overlay.bounds;
    CGFloat size = MIN(240, MIN(width - 64, height - 260));
    self.codeView.frame = CGRectMake((width - size) / 2, (height - size) / 2 - 20, size, size);
    self.status.frame = CGRectMake(24, CGRectGetMinY(self.codeView.frame) - 90, width - 48, 72);
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
}
- (void)open {
    if (!self.active || self.overlay.ticketOpen) return;
    self.overlay.ticketOpen = YES; self.panel.hidden = NO;
    if (self.presentationChanged) self.presentationChanged(YES);
    NNPDiagnosticSetBool(@"MengoTicketOpen", YES);
    __weak typeof(self) weakSelf = self;
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
- (void)close {
    BOOL wasOpen = self.overlay.ticketOpen;
    self.generation++;
    [self.task cancel]; self.task = nil;
    [self.session invalidateAndCancel]; self.session = nil;
    [self.refreshTimer invalidate]; self.refreshTimer = nil;
    [self.closeTimer invalidate]; self.closeTimer = nil;
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
}
- (void)fetch {
    if (!self.active || !self.overlay.ticketOpen || self.task) return;
    [self.refreshTimer invalidate]; self.refreshTimer = nil;
    self.codeView.image = nil; self.codeView.hidden = YES;
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
        dispatch_async(dispatch_get_main_queue(), ^{
            NNPMengoController *owner = weakSelf;
            if (!owner || generation != owner.generation || !owner.active || !owner.overlay.ticketOpen) return;
            owner.task = nil;
            NNPDiagnosticSetBool(@"MengoRequestActive", NO);
            NNPDiagnosticSetBool(@"MengoTicketImageAvailable", image != nil);
            if (!image) { owner.status.text = message ?: @"無法取得乘車碼\n請確認網路或點選重新取得"; return; }
            owner.codeView.image = image; owner.codeView.hidden = NO;
            owner.status.text = @"MeN Go 乘車碼\n請將 QR Code 對準讀碼機";
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
    [_sensorMode setActive:NO];
    [self.task cancel]; [self.session invalidateAndCancel];
    [self.refreshTimer invalidate]; [self.closeTimer invalidate];
    [self.overlay removeFromSuperview];
}
@end

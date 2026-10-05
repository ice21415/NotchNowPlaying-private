#import "NNPNextArtwork.h"
#import "NNPCoverURL.h"
#import <ImageIO/ImageIO.h>
@interface NNPNextArtwork ()
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, copy) NSString *URL;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *cache;
@property(nonatomic) NSUInteger generation;
@end
@implementation NNPNextArtwork
- (void)setURL:(NSString *)URL active:(BOOL)active onChange:(dispatch_block_t)onChange {
    NSString *nextURL = active ? NNPCoverURLString(URL) : @"";
    if ([self.URL isEqualToString:nextURL]) return;
    [self.task cancel]; self.task = nil;
    NSUInteger generation = ++self.generation;
    self.URL = nextURL;
    self.image = [self.cache objectForKey:nextURL];
    if (!nextURL.length || self.image) return;
    if (!self.cache) {
        self.cache = [NSCache new];
        self.cache.countLimit = 8;
        self.cache.totalCostLimit = 512 * 1024;
    }
    if (!self.session) {
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 12;
        configuration.timeoutIntervalForResource = 15;
        configuration.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:512 * 1024 diskCapacity:0 diskPath:nil];
        self.session = [NSURLSession sessionWithConfiguration:configuration];
    }
    __weak typeof(self) weakSelf = self;
    self.task = [self.session dataTaskWithURL:[NSURL URLWithString:nextURL] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = nil;
        if (!error && [(NSHTTPURLResponse *)response statusCode] == 200 && data.length > 0 && data.length <= 2 * 1024 * 1024) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (source) {
                NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @96,
                    (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES};
                CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
                if (thumbnail) { image = [UIImage imageWithCGImage:thumbnail scale:3 orientation:UIImageOrientationUp]; CGImageRelease(thumbnail); }
                CFRelease(source);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.generation) return;
            strongSelf.task = nil;
            if (!image) return;
            strongSelf.image = image;
            [strongSelf.cache setObject:image forKey:nextURL cost:96 * 96 * 4];
            if (onChange) onChange();
        });
    }];
    [self.task resume];
}
- (void)dealloc { [_task cancel]; [_session invalidateAndCancel]; }
@end

#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#include <stdio.h>
int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        CFTypeRef (*create)(CFAllocatorRef) = dlsym(handle, "IOHIDEventSystemClientCreate");
        CFArrayRef (*services)(CFTypeRef) = dlsym(handle, "IOHIDEventSystemClientCopyServices");
        CFTypeRef (*property)(CFTypeRef, CFStringRef) = dlsym(handle, "IOHIDServiceClientCopyProperty");
        CFTypeRef (*event)(CFTypeRef, uint32_t, CFTypeRef, uint32_t) = dlsym(handle, "IOHIDServiceClientCopyEvent");
        double (*value)(CFTypeRef, uint32_t) = dlsym(handle, "IOHIDEventGetFloatValue");
        if (!create || !services || !property || !event || !value) return 2;
        CFTypeRef client = create(kCFAllocatorDefault);
        if (!client) return 3;
        CFArrayRef list = services(client);
        if (!list) { CFRelease(client); return 4; }
        NSMutableArray *rows = [NSMutableArray array];
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            CFTypeRef service = CFArrayGetValueAtIndex(list, i);
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"Product", @"PrimaryUsagePage", @"PrimaryUsage"]) {
                id result = CFBridgingRelease(property(service, (__bridge CFStringRef)key));
                if (result) row[key] = result;
            }
            for (uint32_t type = 12; type <= 14; type++) {
                CFTypeRef sample = event(service, type, NULL, 0);
                if (!sample) continue;
                row[[NSString stringWithFormat:@"event%u", type]] = @[
                    @(value(sample, type << 16)), @(value(sample, (type << 16) + 1)),
                    @(value(sample, (type << 16) + 2))];
                CFRelease(sample);
            }
            if ([row[@"PrimaryUsagePage"] integerValue] == 65280 &&
                [@[@3, @4, @8, @9] containsObject:row[@"PrimaryUsage"]]) [rows addObject:row];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
        CFRelease(list); CFRelease(client);
        puts("starting CoreMotion");
        @try {
        CMMotionManager *motion = [CMMotionManager new];
        printf("accelerometerAvailable=%d\n", motion.accelerometerAvailable);
        motion.accelerometerUpdateInterval = 0.5;
        [motion startAccelerometerUpdates];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
        CMAccelerometerData *sample = motion.accelerometerData;
        if (sample) printf("accel=%.3f,%.3f,%.3f\n", sample.acceleration.x, sample.acceleration.y, sample.acceleration.z);
        else puts("accelerometerData=missing");
        [motion stopAccelerometerUpdates];
        } @catch (NSException *exception) {
            printf("motion exception=%s\n", exception.description.UTF8String);
            return 5;
        }
    }
    return 0;
}

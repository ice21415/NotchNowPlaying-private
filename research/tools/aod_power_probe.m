#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <notify.h>

// Read-only battery registry sampler. No sensor activation or battery writes.
typedef CFMutableDictionaryRef (*Matching)(const char *);
typedef uint32_t (*GetService)(uint32_t, CFDictionaryRef);
typedef int (*Properties)(uint32_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
typedef int (*ReleaseObject)(uint32_t);
static id JSONSafe(id value) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (id key in value) result[[key description]] = JSONSafe(value[key]);
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in value) [result addObject:JSONSafe(item)];
        return result;
    }
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    return [value description] ?: NSNull.null;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 3 && !strcmp(argv[1], "--notify")) return notify_post(argv[2]);
        unsigned count = argc > 1 ? (unsigned)strtoul(argv[1], NULL, 10) : 1;
        unsigned interval = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 30;
        if (!count || count > 1200 || interval < 5 || interval > 300) return 2;
        FILE *output = argc > 3 ? fopen(argv[3], "wx") : stdout;
        if (!output) { perror("output"); return 2; }
        void *lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        Matching matching = lib ? (Matching)dlsym(lib, "IOServiceMatching") : NULL;
        GetService getService = lib ? (GetService)dlsym(lib, "IOServiceGetMatchingService") : NULL;
        Properties properties = lib ? (Properties)dlsym(lib, "IORegistryEntryCreateCFProperties") : NULL;
        ReleaseObject releaseObject = lib ? (ReleaseObject)dlsym(lib, "IOObjectRelease") : NULL;
        if (!matching || !getService || !properties || !releaseObject) { fprintf(stderr, "IOKit API unavailable\n"); return 3; }
        uint32_t service = getService(0, matching("AppleSmartBattery"));
        if (!service) service = getService(0, matching("IOPMPowerSource"));
        if (!service) { fprintf(stderr, "Battery service unavailable\n"); return 4; }
        for (unsigned index = 0; index < count; ++index) {
            @autoreleasepool {
                CFMutableDictionaryRef raw = NULL;
                int status = properties(service, &raw, kCFAllocatorDefault, 0);
                if (status || !raw) { fprintf(stderr, "Battery read failed: %d\n", status); releaseObject(service); return 5; }
                NSDictionary *battery = CFBridgingRelease(raw);
                NSMutableDictionary *record = [NSMutableDictionary dictionary];
                record[@"unix_time"] = @([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970);
                record[@"sample"] = @(index);
                if (count == 1) record[@"battery"] = JSONSafe(battery);
                else for (NSString *key in @[@"InstantAmperage", @"Amperage", @"Voltage", @"Temperature", @"CurrentCapacity", @"MaxCapacity", @"AppleRawCurrentCapacity", @"AppleRawMaxCapacity", @"IsCharging", @"ExternalConnected", @"UpdateTime", @"PowerTelemetryData"]) {
                    if (battery[key]) record[key] = JSONSafe(battery[key]);
                }
                NSError *error = nil;
                NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:&error];
                if (!json) { fprintf(stderr, "%s\n", error.description.UTF8String); return 6; }
                fwrite(json.bytes, 1, json.length, output); fputc('\n', output); fflush(output);
            }
            if (index + 1 < count) sleep(interval);
        }
        releaseObject(service);
        if (output != stdout) fclose(output);
        return 0;
    }
}

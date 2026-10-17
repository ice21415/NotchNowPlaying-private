// Dumps the AppleSmartBattery IORegistry properties (capacity, voltage, amperage, ...) for power research.
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <stdio.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
extern const mach_port_t kIOMasterPortDefault;
CFMutableDictionaryRef IOServiceMatching(const char *name);
io_service_t IOServiceGetMatchingService(mach_port_t masterPort, CFDictionaryRef matching);
kern_return_t IORegistryEntryCreateCFProperties(io_service_t entry, CFMutableDictionaryRef *properties,
                                                CFAllocatorRef allocator, uint32_t options);
kern_return_t IOObjectRelease(io_object_t object);

static void print_value(CFStringRef key, CFTypeRef value) {
    char k[128];
    CFStringGetCString(key, k, sizeof(k), kCFStringEncodingUTF8);
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        long long n = 0;
        CFNumberGetValue(value, kCFNumberLongLongType, &n);
        printf("%-34s %lld\n", k, n);
    } else if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        printf("%-34s %s\n", k, CFBooleanGetValue(value) ? "true" : "false");
    } else if (CFGetTypeID(value) == CFStringGetTypeID()) {
        char s[256];
        CFStringGetCString(value, s, sizeof(s), kCFStringEncodingUTF8);
        printf("%-34s \"%s\"\n", k, s);
    } else if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        CFStringRef text = CFCopyDescription(value);
        char s[4096];
        if (CFStringGetCString(text, s, sizeof(s), kCFStringEncodingUTF8)) printf("%-34s %s
", k, s);
        CFRelease(text);
    } else {
        printf("%-34s <type %lu>\n", k, (unsigned long)CFGetTypeID(value));
    }
}

int main(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) { fprintf(stderr, "AppleSmartBattery not found\n"); return 1; }
    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS || !props) {
        fprintf(stderr, "cannot read properties\n");
        IOObjectRelease(service);
        return 2;
    }
    CFIndex count = CFDictionaryGetCount(props);
    const void **keys = malloc(sizeof(void *) * (size_t)count);
    const void **values = malloc(sizeof(void *) * (size_t)count);
    CFDictionaryGetKeysAndValues(props, keys, values);
    for (CFIndex i = 0; i < count; i++) print_value(keys[i], values[i]);
    free(keys); free(values);
    CFRelease(props);
    IOObjectRelease(service);
    return 0;
}

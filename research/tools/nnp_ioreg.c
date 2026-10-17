// Dumps IORegistry properties of every service matching the given class names (a minimal ioreg for jailbroken iOS).
// Usage: nnp_ioreg Class [Class ...]
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <stdio.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_iterator_t;
extern const mach_port_t kIOMasterPortDefault;
CFMutableDictionaryRef IOServiceMatching(const char *name);
kern_return_t IOServiceGetMatchingServices(mach_port_t masterPort, CFDictionaryRef matching, io_iterator_t *existing);
io_object_t IOIteratorNext(io_iterator_t iterator);
kern_return_t IORegistryEntryCreateCFProperties(io_service_t entry, CFMutableDictionaryRef *properties,
                                                CFAllocatorRef allocator, uint32_t options);
kern_return_t IOObjectRelease(io_object_t object);

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        io_iterator_t iterator = 0;
        if (IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(argv[i]), &iterator) != KERN_SUCCESS) {
            fprintf(stderr, "no services for %s\n", argv[i]);
            continue;
        }
        io_service_t service;
        while ((service = IOIteratorNext(iterator))) {
            CFMutableDictionaryRef props = NULL;
            if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
                CFStringRef text = CFCopyDescription(props);
                char *buffer = malloc((size_t)CFStringGetMaximumSizeForEncoding(CFStringGetLength(text), kCFStringEncodingUTF8) + 1);
                if (buffer && CFStringGetCString(text, buffer, CFStringGetMaximumSizeForEncoding(CFStringGetLength(text), kCFStringEncodingUTF8) + 1, kCFStringEncodingUTF8))
                    printf("== %s ==\n%s\n", argv[i], buffer);
                free(buffer);
                CFRelease(text);
                CFRelease(props);
            }
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
    }
    return 0;
}

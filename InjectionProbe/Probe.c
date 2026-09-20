#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);
__attribute__((used)) static void *const NNPProbeSubstrateAnchor = (void *)&MSHookFunction;

static void NNPProbeWrite(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    struct timeval now;
    gettimeofday(&now, NULL);
    char line[160];
    int length = snprintf(line, sizeof(line), "[%lld.%03d] pid=%d CONSTRUCTOR_REACHED\n", (long long)now.tv_sec, (int)(now.tv_usec / 1000), getpid());
    if (length > 0) write(fd, line, (size_t)length);
    close(fd);
}

__attribute__((constructor)) static void NNPInjectionProbeConstructor(void) {
    NNPProbeWrite("/var/mobile/Library/Preferences/NNPInjectionProbe.log");
    CFPreferencesSetAppValue(CFSTR("ConstructorReached"), CFSTR("YES"), CFSTR("com.user.nnpinjectionprobe"));
    CFPreferencesAppSynchronize(CFSTR("com.user.nnpinjectionprobe"));
}

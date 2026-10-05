#import "NNPSnapshotCache.h"
@implementation NNPSnapshotCache {
    NSDictionary *(^_loader)(void);
    NSDictionary *_snapshot;
    NSTimeInterval _lastRead;
    NSTimeInterval _interval;
    BOOL _dirty;
}
- (instancetype)initWithLoader:(NSDictionary *(^)(void))loader recoveryInterval:(NSTimeInterval)interval {
    if ((self = [super init])) {
        _loader = [loader copy];
        _interval = MAX(1.0, interval);
        _dirty = YES;
    }
    return self;
}
- (NSDictionary *)snapshotAtTime:(NSTimeInterval)now {
    if (_dirty || !_snapshot || now < _lastRead || now - _lastRead >= _interval) {
        NSDictionary *value = _loader ? _loader() : nil;
        _snapshot = [value isKindOfClass:NSDictionary.class] ? [value copy] : @{};
        _lastRead = now;
        _dirty = NO;
    }
    return _snapshot;
}
- (void)invalidate { _dirty = YES; }
@end

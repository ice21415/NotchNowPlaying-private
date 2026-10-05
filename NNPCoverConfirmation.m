#import "NNPCoverConfirmation.h"
@implementation NNPCoverConfirmation {
    NSTimer *_timer;
    BOOL _confirmed, _candidate;
    NSUInteger _generation;
}
- (void)update:(BOOL)covered {
    if (_timer && _candidate == covered) return;
    [_timer invalidate]; _timer = nil;
    NSUInteger generation = ++_generation;
    if (covered == _confirmed) return;
    _candidate = covered;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:covered ? 0.8 : 0.25 repeats:NO
        block:^(__unused NSTimer *timer) {
            NNPCoverConfirmation *owner = weakSelf;
            if (!owner || generation != owner->_generation) return;
            owner->_timer = nil;
            owner->_confirmed = covered;
            if (owner.onChange) owner.onChange(covered);
        }];
}
- (void)reset {
    ++_generation;
    [_timer invalidate]; _timer = nil;
    _confirmed = _candidate = NO;
}
- (void)dealloc { [_timer invalidate]; }
@end

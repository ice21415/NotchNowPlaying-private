#import <UIKit/UIKit.h>
#import "NNPController.h"

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NNPController sharedController] install];
    });
}

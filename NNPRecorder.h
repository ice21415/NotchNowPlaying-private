#import <Foundation/Foundation.h>

// Research recorder (preference ResearchRecorder): appends timestamped display events and a 10 Hz state
// snapshot (only when it changes) to /var/mobile/Library/Caches/nnp-recorder.log so a visible glitch can be
// matched against what SpringBoard was doing at that moment.
FOUNDATION_EXPORT BOOL NNPRecorderEnabled(void);
FOUNDATION_EXPORT void NNPRecorderLog(NSString *message);
FOUNDATION_EXPORT void NNPRecorderStart(NSString *(^snapshot)(void));

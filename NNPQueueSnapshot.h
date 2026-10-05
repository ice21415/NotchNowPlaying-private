#import <Foundation/Foundation.h>
static inline NSString *NNPQueueText(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static inline BOOL NNPQueueSnapshotMatches(NSDictionary *snapshot, NSString *URI, NSString *title, NSString *artist, NSTimeInterval now) {
    if (![snapshot isKindOfClass:NSDictionary.class]) return NO;
    id timestamp = snapshot[@"timestamp"];
    if (![timestamp isKindOfClass:NSNumber.class]) return NO;
    NSTimeInterval age = now - [timestamp doubleValue];
    if (age < -5 || age > 21600) return NO;
    NSString *currentURI = NNPQueueText(snapshot[@"currentURI"]);
    NSString *mediaURI = [[NNPQueueText(URI) componentsSeparatedByString:@"#"] firstObject];
    if (currentURI.length && mediaURI.length) return [currentURI isEqualToString:mediaURI];
    return title.length && artist.length &&
        [title isEqualToString:NNPQueueText(snapshot[@"currentTitle"])] &&
        [artist isEqualToString:NNPQueueText(snapshot[@"currentArtist"])];
}

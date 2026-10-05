#import <Foundation/Foundation.h>
static inline NSString *NNPCoverURLString(id value) {
    if ([value isKindOfClass:NSURL.class]) value = [value absoluteString];
    if (![value isKindOfClass:NSString.class] || [value length] > 512) return @"";
    NSURL *URL = [NSURL URLWithString:value];
    if ([URL.scheme.lowercaseString isEqualToString:@"https"] &&
        [URL.host.lowercaseString isEqualToString:@"i.scdn.co"] &&
        [URL.path hasPrefix:@"/image/"] && !URL.user.length && !URL.password.length)
        return URL.absoluteString;
    if ([value hasPrefix:@"spotify:image:"]) {
        NSString *identifier = [value substringFromIndex:[@"spotify:image:" length]];
        NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        if (identifier.length == 40 && [identifier rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound)
            return [@"https://i.scdn.co/image/" stringByAppendingString:identifier];
    }
    return @"";
}

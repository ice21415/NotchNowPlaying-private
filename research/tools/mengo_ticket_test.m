#import <Foundation/Foundation.h>
#import "../../NNPMengoTicket.h"
#include <assert.h>

static NSData *Response(id inner) {
    return [NSJSONSerialization dataWithJSONObject:@{@"ok": @YES, @"data": inner} options:0 error:nil];
}
int main(void) {
    @autoreleasepool {
        NSString *body = [[NSString alloc] initWithData:NNPMengoFormBody(@"a+b&c=d %") encoding:NSUTF8StringEncoding];
        assert([body isEqual:@"token=a%2Bb%26c%3Dd%20%25"]);
        NSData *bytes = [@"valid-test-image-bytes" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *inner = @{@"QRCode": [bytes base64EncodedStringWithOptions:0], @"Ticket": @{@"IsExpired": @NO}};
        NSString *message = @"old";
        assert([NNPMengoImageData(Response(inner), &message) isEqual:bytes]);
        assert(!message);
        NSString *encoded = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:inner options:0 error:nil] encoding:NSUTF8StringEncoding];
        assert([NNPMengoImageData(Response(encoded), NULL) isEqual:bytes]);
        NSMutableDictionary *expired = [inner mutableCopy]; expired[@"IsExpired"] = @YES;
        assert([NNPMengoImageData(Response(expired), &message) isEqual:bytes] && [message containsString:@"僅可出站"]);
        expired[@"IsExpired"] = @NO; expired[@"Ticket"] = @{@"IsExpired": @YES};
        assert([NNPMengoImageData(Response(expired), NULL) isEqual:bytes]);
        NSDictionary *badAuth = @{@"ok": @NO, @"toekn_error": @YES};
        assert(!NNPMengoImageData([NSJSONSerialization dataWithJSONObject:badAuth options:0 error:nil], &message));
        assert([message containsString:@"登入"]);
        assert(!NNPMengoImageData(Response(@{@"QRCode": @"invalid-base64!"}), NULL));
        assert(!NNPMengoImageData(Response(@{@"QRCode": @123}), NULL));
        assert(!NNPMengoImageData(Response(NSNull.null), NULL));
        assert(!NNPMengoImageData([@"[]" dataUsingEncoding:NSUTF8StringEncoding], NULL));
        assert(!NNPMengoImageData([@"{\"ok\":null,\"token_error\":[]}" dataUsingEncoding:NSUTF8StringEncoding], NULL));
        assert(!NNPMengoImageData([NSMutableData dataWithLength:4 * 1024 * 1024], NULL));
        puts("MeN Go response and credential encoding tests passed");
    }
    return 0;
}

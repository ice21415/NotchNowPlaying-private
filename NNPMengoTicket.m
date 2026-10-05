#import "NNPMengoTicket.h"
static BOOL NNPMengoBool(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

NSData *NNPMengoFormBody(NSString *token) {
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [token stringByAddingPercentEncodingWithAllowedCharacters:safe];
    return [[@"token=" stringByAppendingString:encoded ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
}
NSData *NNPMengoImageData(NSData *response, NSString **message) {
    if (message) *message = @"乘車碼取得失敗，請稍後重試";
    if (!response.length || response.length > 3 * 1024 * 1024) return nil;
    id outer = [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
    if (![outer isKindOfClass:NSDictionary.class]) return nil;
    if (NNPMengoBool(outer[@"toekn_error"]) || NNPMengoBool(outer[@"token_error"])) {
        if (message) *message = @"請開啟 MeN Go 重新登入";
        return nil;
    }
    if (!NNPMengoBool(outer[@"ok"])) return nil;
    id inner = outer[@"data"];
    if ([inner isKindOfClass:NSString.class])
        inner = [NSJSONSerialization JSONObjectWithData:[inner dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![inner isKindOfClass:NSDictionary.class]) return nil;
    id ticket = inner[@"Ticket"];
    if (NNPMengoBool(inner[@"IsExpired"]) ||
        ([ticket isKindOfClass:NSDictionary.class] && NNPMengoBool(ticket[@"IsExpired"]))) {
        if (message) *message = @"票券已到期，請至 MeN Go 確認";
        return nil;
    }
    NSString *base64 = [inner[@"QRCode"] isKindOfClass:NSString.class] ? inner[@"QRCode"] : nil;
    if (!base64.length || base64.length > 2 * 1024 * 1024) return nil;
    NSData *image = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (image.length < 8 || image.length > 1024 * 1024) return nil;
    if (message) *message = nil;
    return image;
}

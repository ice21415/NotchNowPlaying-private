#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>

// Runs only in MeN Go. The login credential stays in its protected container;
// no credential, ticket image or server response is written to diagnostics.
@interface NNPMengoBridge : NSObject <WKScriptMessageHandler>
@end
@implementation NNPMengoBridge
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.mainFrame || ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    NSString *token = [body[@"token"] isKindOfClass:NSString.class] ? body[@"token"] : nil;
    if (!token || token.length > 16384) return;
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/NotchNowPlaying"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"mengo-session.plist"];
    if (!token.length) { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; return; }
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *endpoint = [body[@"endpoint"] isEqual:@"MQRCode"] ? @"MQRCode" :
        ([body[@"endpoint"] isEqual:@"QRCode"] ? @"QRCode" : old[@"endpoint"]);
    NSString *agent = [body[@"agent"] isKindOfClass:NSString.class] ? body[@"agent"] : nil;
    if (!agent.length || agent.length > 512 || [agent rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return;
    if ([old[@"token"] isEqual:token] && [old[@"endpoint"] isEqual:endpoint ?: @""] && [old[@"agent"] isEqual:agent]) return;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:
        @{ @"token": token, @"endpoint": endpoint ?: @"", @"agent": agent, @"updated": @(NSDate.date.timeIntervalSince1970) }
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if ([data writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil])
        chmod(path.fileSystemRepresentation, 0600);
}
@end

static const char NNPMengoInstalledKey = 0;
%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKUserContentController *content = configuration.userContentController;
    if (content && !objc_getAssociatedObject(content, &NNPMengoInstalledKey)) {
        NNPMengoBridge *bridge = [NNPMengoBridge new];
        [content addScriptMessageHandler:bridge name:@"nnpMengoSession"];
        objc_setAssociatedObject(content, &NNPMengoInstalledKey, bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *script = @"(function(){'use strict';if(window.__nnpMengoBridge)return;window.__nnpMengoBridge=true;"
            "var endpoint='';function send(){try{window.webkit.messageHandlers.nnpMengoSession.postMessage({token:localStorage.getItem('ek_login_token')||'',endpoint:endpoint,agent:navigator.userAgent});}catch(e){}}"
            "var set=Storage.prototype.setItem,remove=Storage.prototype.removeItem,clear=Storage.prototype.clear;"
            "Storage.prototype.setItem=function(k,v){var r=set.apply(this,arguments);if(this===localStorage&&k==='ek_login_token')send();return r;};"
            "Storage.prototype.removeItem=function(k){var r=remove.apply(this,arguments);if(this===localStorage&&k==='ek_login_token')send();return r;};"
            "Storage.prototype.clear=function(){var r=clear.apply(this,arguments);if(this===localStorage)send();return r;};"
            "var open=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){var s=String(u),match=s.match(/\\/Platform\\/Htmlv2\\/(MQRCode|QRCode)(?:[?#]|$)/);"
            "if(match&&(/^https:\\/\\/men-go\\.tw\\//.test(s)||s.charAt(0)==='/')){endpoint=match[1];send();}return open.apply(this,arguments);};"
            "send();window.addEventListener('pageshow',send);})();";
        [content addUserScript:[[WKUserScript alloc] initWithSource:script
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    }
    return %orig(frame, configuration);
}
%end

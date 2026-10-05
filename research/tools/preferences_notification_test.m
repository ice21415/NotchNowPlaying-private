// Use the actual notification handler and a fake loader; no device preferences
// or real user defaults are read or written by this test.
#import "../../NNPPreferences.m"
#include <assert.h>
void NNPDiagnosticSetBool(__unused NSString *key, __unused BOOL value) {}
void NNPDiagnosticSetInteger(__unused NSString *key, __unused NSInteger value) {}
void NNPDiagnosticSetDouble(__unused NSString *key, __unused double value) {}
@interface NNPTestPreferences : NNPPreferences
@property(nonatomic) NSUInteger settingsReloads;
@end
@implementation NNPTestPreferences
- (void)reload { self.settingsReloads++; [self reloadSpotifyLyricsSnapshot]; }
@end
static void Drain(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
int main(void) {
    @autoreleasepool {
        __block NSUInteger reads = 0, dataEvents = 0, settingsEvents = 0;
        __block NSDictionary *source = @{@"SpotifyLyricsText": @"first"};
        NNPTestPreferences *preferences = [NNPTestPreferences new];
        preferences.snapshotCache = [[NNPSnapshotCache alloc] initWithLoader:^{ reads++; return source; } recoveryInterval:30];
        [preferences reloadSpotifyLyricsSnapshot];
        id dataToken = [NSNotificationCenter.defaultCenter addObserverForName:NNPSpotifyDataDidChangeNotification object:preferences queue:nil usingBlock:^(__unused NSNotification *note) { dataEvents++; }];
        id settingsToken = [NSNotificationCenter.defaultCenter addObserverForName:NNPPreferencesDidChangeNotification object:preferences queue:nil usingBlock:^(__unused NSNotification *note) { settingsEvents++; }];
        for (NSUInteger i = 0; i < 20; i++) [preferences reloadSpotifyLyricsSnapshot];
        assert(reads == 1);
        source = @{@"SpotifyLyricsText": @"updated", @"SpotifyQueueSnapshot": @{@"nextTitle": @"next"}};
        for (NSUInteger i = 0; i < 10; i++)
            NNPPreferencesCallback(NULL, (__bridge void *)preferences, (__bridge CFStringRef)NNPSpotifyDataDidChangeNotification, NULL, NULL);
        Drain();
        assert(reads == 2 && dataEvents == 1 && settingsEvents == 0 && preferences.settingsReloads == 0);
        assert([preferences.spotifyLyricsText isEqualToString:@"updated"]);
        assert([preferences.spotifyQueueSnapshot[@"nextTitle"] isEqualToString:@"next"]);
        [preferences queueChangeForSettings:NO];
        [preferences queueChangeForSettings:YES];
        Drain();
        assert(reads == 3 && dataEvents == 1 && settingsEvents == 1 && preferences.settingsReloads == 1);
        // Older Spotify producers used the settings channel: keep compatibility.
        NNPPreferencesCallback(NULL, (__bridge void *)preferences, (__bridge CFStringRef)NNPPreferencesDidChangeNotification, NULL, NULL);
        Drain();
        assert(reads == 4 && settingsEvents == 2 && preferences.settingsReloads == 2);
        [NSNotificationCenter.defaultCenter removeObserver:dataToken];
        [NSNotificationCenter.defaultCenter removeObserver:settingsToken];
        puts("Actual preference notification coalescing and data/settings separation passed");
    }
}
